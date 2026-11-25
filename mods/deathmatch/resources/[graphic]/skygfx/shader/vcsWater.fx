texture SurfaceTexture;

sampler SurfaceSampler = sampler_state {
    Texture = (SurfaceTexture);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

#ifdef VCS_BOAT_FOAM

float4x4 ViewProjection : VIEWPROJECTION;
float FoamGain = 1;
struct FoamVertex {
    float4 position : POSITION0;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};
FoamVertex foamVertex(FoamVertex input) {
    input.position = mul(float4(input.position.xyz,1), ViewProjection);
    return input;
}
float4 foamPixel(float2 uv : TEXCOORD0, float4 color : COLOR0) : COLOR0 {
    float4 raster = tex2D(SurfaceSampler, uv);
    return float4(color.rgb * raster.rgb, color.a * saturate(raster.a * FoamGain));
}
technique vcs_boat_foam {
    pass P0 {
        AlphaBlendEnable = true;
#ifdef VCS_SPLASH_ONE
        SrcBlend = ONE;
#else
        SrcBlend = SRCALPHA;
#endif
#ifdef VCS_SPLASH_ADDITIVE
        DestBlend = ONE;
#else
        DestBlend = INVSRCALPHA;
#endif
        BlendOp = ADD;
        AlphaTestEnable = false;
        CullMode = NONE;
        FogEnable = false;
#if defined(PARTICLE_OVERLAY) || defined(PARTICLE_SCREEN)
        ZEnable = false;
#else
        ZEnable = true;
#endif
        ZFunc = LESSEQUAL;
        ZWriteEnable = false;
#ifdef PARTICLE_SCREEN
        VertexShader = NULL;
#else
        VertexShader = compile vs_2_0 foamVertex();
#endif
        PixelShader = compile ps_2_0 foamPixel();
    }
}

#elif defined(VCS_WAKE)

// SA submits another strip at a sea-level constant, even on raised custom water.
// SkyGfx renders the wake on the water mesh instead.
technique vcs_wake {
    pass P0 {
        ColorWriteEnable = 0;
        ZWriteEnable = false;
    }
}

#elif defined(VCS_WAVE_GRID)

float WavePhase;
float NoiseFrame;
float WaterWind;
texture WaveNoiseTexture;

sampler WaveNoiseSampler = sampler_state {
    Texture = (WaveNoiseTexture);
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

static const float Tau = 6.28318530718;

float waveHeight(float2 index) {
    // SLUS-21590 0x11a690: 17 vertices, the last row and column repeat the first.
    index = 16.0 * frac(index / 16.0);
    float swell = (0.9 * WaterWind + 0.05) * sin(WavePhase + index.x * (Tau / 17.0));
    float cross = (0.9 * WaterWind + 0.1) * sin(WavePhase)
        * sin(index.x * (Tau / 34.0)) * sin(index.y * (Tau / 34.0));
    float diagonal = index.y - index.x + 17.0;
    float ripple = (0.1 * WaterWind + 0.075) * cos(WavePhase + diagonal * (Tau / 8.0))
        * (1.0 - 4.0 * frac(diagonal * 0.5));
    return swell + cross + ripple;
}

float4 noiseGrid(float2 index, float frame) {
    // 0x40fcc8 blends three bilinear random grids with weights 1, 1/2, 1/4.
    // The atlas bakes their 64 keyframes with the original RNG from 0x408058.
    float2 tile = float2(8.0 * frac(frame / 8.0), floor(frame / 8.0));
    float2 uv = (tile * 16.0 + index + 0.5) / 128.0;
    return (tex2Dlod(WaveNoiseSampler, float4(uv, 0.0, 0.0)) - 0.5) * 4.0;
}

float4 waveGridPixel(float2 pixel : VPOS) : COLOR0 {
    // MTA's textureless dxDrawImage has no usable UVs.
    float2 index = floor(pixel);
    float frame = floor(NoiseFrame);
    float nextFrame = 64.0 * frac((frame + 1.0) / 64.0);
    float4 noise = lerp(noiseGrid(index, frame), noiseGrid(index, nextFrame), frac(NoiseFrame));
    // At the first row and column the game uses the duplicated endpoint as the preceding height.
    float2 difference = float2(
        waveHeight(index + float2(1, 0)) - waveHeight(max(index - float2(1, 0), 0.0)),
        waveHeight(index + float2(0, 1)) - waveHeight(max(index - float2(0, 1), 0.0)));
    float3 normal = normalize(float3(-difference * 0.25, 1.0));
    normal = normalize(normal + float3(0.2 * noise.xy, 0.0));
    // Encode signed data in the small RGBA render target. Each texel is a grid vertex.
    return 0.5 + float4(normal.xy * 0.5, noise.zw * 0.25);
}

technique vcs_wave_grid {
    pass P0 {
        PixelShader = compile ps_3_0 waveGridPixel();
    }
}

#else

float4x4 World : WORLD;
float4x4 View : VIEW;
float4x4 WorldViewProjection : WORLDVIEWPROJECTION;

float3 WaterColor = float3(0.4, 0.5, 0.5);
float3 FogColor = 0;
float2 FogRange = float2(0, 2000);
float WaterScroll;
float InverseWaterOpacity = 1.0;
texture ReflectionTexture;
texture WaveGridTexture;
sampler WaveGridSampler = sampler_state {
    Texture = (WaveGridTexture);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
};

sampler ReflectionSampler = sampler_state {
    Texture = (ReflectionTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
};

struct WaterVertex {
    float4 position : POSITION;
    float4 color : COLOR0;
};

struct WaterPixel {
    float4 position : POSITION;
    float2 tile : TEXCOORD0;
    float3 depthAlphaFog : TEXCOORD1;
};

WaterPixel waterVertex(WaterVertex input) {
    WaterPixel output;
    output.position = mul(input.position, WorldViewProjection);
    float3 world = mul(input.position, World).xyz;
    // Recomp 0x27120c uses 32 m repeats and 0x2717f8 starts the grid at -2448.
    output.tile = (world.xy + 16.0) / 32.0;
    float fog = saturate((output.position.w - FogRange.x) / max(FogRange.y - FogRange.x, 1.0));
    output.depthAlphaFog = float3(output.position.w, input.color.a, fog);
    return output;
}

float4 sampleWaveGrid(float2 uv) {
    float2 cell = uv * 16.0;
    float2 lattice = floor(cell);
    float2 weight = cell - lattice;
    // Match the PS2 strip's diagonal. The first tap interpolates along
    // an edge and the second tap reads the opposite vertex.
    float upper = step(1.0, weight.x + weight.y);
    float direction = 1.0 - 2.0 * upper;
    lattice += upper;
    weight = lerp(weight, 1.0 - weight, upper);
    float2 edge = lattice + float2(direction * weight.x / max(1.0 - weight.y, 0.0001), 0.0);
    float2 vertex = lattice + float2(0.0, direction);
    float4 alongEdge = tex2Dlod(WaveGridSampler, float4((edge + 0.5) / 16.0, 0.0, 0.0));
    float4 opposite = tex2Dlod(WaveGridSampler, float4((vertex + 0.5) / 16.0, 0.0, 0.0));
    return lerp(alongEdge, opposite, weight.y);
}

float4 waterPixel(WaterPixel input) : COLOR0 {
    float viewDepth = input.depthAlphaFog.x;
    float2 surfaceUV = input.tile + WaterScroll;
    float reflection = 0.0;
    [branch] if (viewDepth < 90.0) {
        float4 grid = sampleWaveGrid(input.tile);
        float detailFade = saturate((90.0 - viewDepth) / 80.0);
        surfaceUV += (grid.zw - 0.5) * (4.0 * 0.0125 * detailFade);
        float2 normalXY = grid.xy * 2.0 - 1.0;
        float3 normal = float3(normalXY, sqrt(saturate(1.0 - dot(normalXY, normalXY))));
        float2 projected = mul(float4(normal, 0.0), View).xy;
        // VU1 overlay 0x2d0e08 maps the view-space normal to the gray reflection
        // raster. The GS adds it with the 96/128 to 0 fade at view depths 10–90.
        float2 reflectionUV = projected * float2(0.5, -0.5) + 0.5;
        float environment = tex2Dlod(ReflectionSampler, float4(reflectionUV, 0.0, 0.0)).r;
        // Match the PS2 reflection contrast on SA's water mesh while keeping
        // the additive distance fade. Bright texels need the strongest compression.
        static const float ReflectionKnee = 32.0 / 255.0;
        float contrast = environment - ReflectionKnee;
        environment = ReflectionKnee + contrast * 0.60 - max(contrast, 0.0) * 0.39;
        reflection = environment * ((96.0 / 128.0) * detailFade);
    }
    float base = tex2D(SurfaceSampler, surfaceUV).r;
    // VCS adds the reflection after blending the base. Counter the combined
    // native layer opacity so folding it into the same draw keeps that energy.
    float3 surface = lerp(WaterColor * base, FogColor, input.depthAlphaFog.z)
        + reflection * InverseWaterOpacity;
    float alpha = input.depthAlphaFog.y;
    return float4(saturate(surface), alpha);
}

// Reuse the native water draw's displaced vertices and clip-space depth for the foam pass.
texture WakeCoverage;
texture WakeRaster;
float3 WakeOrigin;
float2 WakeScroll;
float WakeActive = 0;
sampler WakeMask = sampler_state {
    Texture = (WakeCoverage); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Linear; MagFilter = Linear; MipFilter = None;
};
sampler WakePattern = sampler_state {
    Texture = (WakeRaster); AddressU = Wrap; AddressV = Wrap;
    MinFilter = Linear; MagFilter = Linear; MipFilter = Linear;
};
struct WakePixel {
    float4 position : POSITION;
    float3 world : TEXCOORD0;
};
WakePixel wakeMeshVertex(WaterVertex input) {
    WakePixel o;
    o.position = mul(input.position, WorldViewProjection);
    o.world = mul(input.position, World).xyz;
    return o;
}
float4 wakeMeshPixel(WakePixel input) : COLOR0 {
    clip(WakeActive - 0.5);
    float2 uv = (input.world.xy - WakeOrigin.xy) / 192.0;
    float2 mask = tex2D(WakeMask,uv).rg;
    float level = WakeOrigin.z + (mask.g * 255.0 - 128.0) * 0.25;
    float4 foam = tex2D(WakePattern,input.world.xy * 0.25 + WakeScroll);
    clip(min(uv,1.0-uv));
    clip(1.0-abs(input.world.z-level));
    return float4(saturate(WaterColor + 64.0/255.0)*foam.rgb,mask.r*foam.a);
}

technique vcs_water {
    pass P0 {
        FogEnable = false;
        VertexShader = compile vs_2_0 waterVertex();
        PixelShader = compile ps_3_0 waterPixel();
    }
    pass SurfaceFoam {
        FogEnable = false;
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZEnable = true;
        ZFunc = LESSEQUAL;
        ZWriteEnable = false;
        AlphaTestEnable = false;
        VertexShader = compile vs_2_0 wakeMeshVertex();
        PixelShader = compile ps_3_0 wakeMeshPixel();
    }
}

#endif
