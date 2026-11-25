#include "mta-helper.fx"

#if defined(VCS_REFLECTION_MAP)
texture ReflectionScene;
texture CoronaStar;
float2 CoronaLeft;

sampler SceneSampler = sampler_state {
    Texture = (ReflectionScene);
    MinFilter = Linear;
    MagFilter = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};
sampler StarSampler = sampler_state {
    Texture = (CoronaStar);
    MinFilter = Linear;
    MagFilter = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

float3 mapCorona(float2 uv, float2 corner, float size) {
    // Only X wraps. GS clips the coronas against the top and bottom of the map.
    float2 spriteUv = uv - corner;
    spriteUv.x += 1 - step(0, spriteUv.x);
    spriteUv /= size;
    float inside = step(0, min(spriteUv.x, spriteUv.y)) * step(max(spriteUv.x, spriteUv.y), 1);
    return tex2D(StarSampler, saturate(spriteUv)).rgb * inside;
}

float4 reflectionMapPixel(float2 uv : TEXCOORD0) : COLOR0 {
    float3 scene = tex2D(SceneSampler, uv).rgb;
    // SLUS-21590 0x35c9e0, GS ALPHA = (Cs - 0) * 255/128 + Cd.
    float3 stars = mapCorona(uv, float2(CoronaLeft.x, 0), 89.0 / 128.0)
                 + mapCorona(uv, float2(CoronaLeft.y, 12.0 / 128.0), 38.0 / 128.0);
    return float4(saturate(scene + stars * (255.0 / 128.0)), 1);
}

technique vcs_reflection_map {
    pass Map {
        PixelShader = compile ps_2_0 reflectionMapPixel();
    }
}
#elif defined(VCS_SIREN_LENS)
float LensPhase;
sampler LensSampler = sampler_state {
    Texture = (gTexture0);
};

float4 lensPixel(float2 uv : TEXCOORD0, float4 diffuse : COLOR0) : COLOR0 {
    float4 lens = tex2D(LensSampler, uv);
    // The model's atlas supplies the red and blue sectors on BOTH sides.
    // Approximate the rotating native beacon's measured one-second sweep.
    float pulse = saturate(cos((gTime / 1.024 + LensPhase) * 6.2831853));
    return float4(saturate(lens.rgb * (diffuse.rgb + 2 * pulse * pulse)), lens.a * diffuse.a);
}

technique vcs_emergency_lens {
    pass Lens {
        PixelShader = compile ps_2_0 lensPixel();
    }
}
#elif defined(VCS_GLASS)
sampler GlassSampler = sampler_state {
    Texture = (gTexture0);
};

float4 glassPixel(float2 uv : TEXCOORD0, float4 diffuse : COLOR0) : COLOR0 {
    float4 glass = tex2D(GlassSampler, uv);
    // The texture carries the original opacity. Native vertex alpha can
    // reduce it for a fading vehicle or an open window.
    return float4(glass.rgb, min(glass.a, diffuse.a));
}

technique vcs_vehicle_glass {
    pass Glass {
        AlphaTestEnable = false;
        AlphaBlendEnable = true;
        SrcBlend = SrcAlpha;
        DestBlend = InvSrcAlpha;
        ZWriteEnable = false;
        SpecularEnable = false;
        PixelShader = compile ps_2_0 glassPixel();
    }
}
#else

texture Reflection;
#include "pointLights.fx"
float ReflectionWeight;
float3 FogColor;
float2 FogRange;

sampler BaseSampler = sampler_state {
    Texture = (gTexture0);
};
sampler ReflectionSampler = sampler_state {
    Texture = (Reflection);
    MinFilter = Linear;
    MagFilter = Linear;
    AddressU = Clamp;
    AddressV = Clamp;
};

struct VehicleVertex {
    float4 position : POSITION0;
    float3 normal : NORMAL0;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VehiclePixel {
    float4 position : POSITION0;
    float2 uv : TEXCOORD0;
    float2 reflectionUv : TEXCOORD1;
    float fog : TEXCOORD2;
    float4 color : COLOR0;
};

VehiclePixel vehicleVertex(VehicleVertex input) {
    VehiclePixel output;
    output.position = mul(input.position, gWorldViewProjection);
    output.uv = input.uv;
    float3 normal = normalize(mul(input.normal, (float3x3)gWorldInverseTranspose));
    float3 viewNormal = mul(normal, (float3x3)gView);
    output.reflectionUv = float2(viewNormal.x, -viewNormal.y) * 0.5 + 0.5;
    output.color = MTACalcGTAVehicleDiffuse(normal, input.color);
    output.color.rgb = saturate(output.color.rgb + GetFireLighting(mul(input.position, gWorld).xyz));
    output.color.a = gDiffuseMaterialSource == 0 ? gMaterialDiffuse.a : input.color.a;
    output.fog = saturate((output.position.w - FogRange.x) / max(FogRange.y - FogRange.x, 1));
    return output;
}

float4 vehiclePixel(VehiclePixel input) : COLOR0 {
    float4 base = tex2D(BaseSampler, input.uv) * input.color;
    float3 color = lerp(base.rgb, FogColor, input.fog);
    // GS context 2 redraws the mesh without fog: (Cs - Cd) * FIX + Cd.
    color = lerp(color, tex2D(ReflectionSampler, input.reflectionUv).rgb, ReflectionWeight);
    return float4(color, base.a);
}

technique vcs_vehicle_matfx {
    pass Environment {
        FogEnable = false;
        SpecularEnable = false;
        VertexShader = compile vs_2_0 vehicleVertex();
        PixelShader = compile ps_2_0 vehiclePixel();
    }
}
#endif
