texture Sprite;
#ifndef VCS_SUN_OPTICS
float4x4 ViewProjection : VIEWPROJECTION;
float4x4 Projection : PROJECTION;
float2 HalfExtent;
float CoreDepth;
float3 CoreColor;
#endif

sampler SpriteSampler = sampler_state {
    Texture = (Sprite);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
};

struct Vertex {
    float4 position : POSITION0;
    float2 uv : TEXCOORD0;
#ifdef VCS_SUN_OPTICS
    float4 color : COLOR0;
#endif
};

// GS MODULATE uses 128 as unity before blending. The source corona encodes
// the glow in RGB, with an opaque texture alpha.
float3 coronaLight(float2 uv, float3 color) {
    return saturate(tex2D(SpriteSampler, uv).rgb * color * (255.0 / 128.0));
}

#ifdef VCS_SUN_OPTICS
Vertex sunVertex(Vertex input) {
    input.position.w = 1.0;
    return input;
}

float4 sunPixel(float2 uv : TEXCOORD0, float4 color : COLOR0) : COLOR0 {
    return float4(coronaLight(uv, color.rgb) * color.a, 0);
}
#else
Vertex sunVertex(Vertex input) {
    Vertex result = input;
    result.position = mul(input.position, ViewProjection);
    float2 offset = (input.uv * 2.0 - 1.0) * HalfExtent;
    result.position.xy += float2(offset.x, -offset.y) * result.position.w;
    // The original core places its depth at 95% of the camera far plane.
    float4 depth = mul(float4(0, 0, CoreDepth, 1), Projection);
    result.position.z = result.position.w * (depth.z / depth.w);
    return result;
}

float4 sunPixel(float2 uv : TEXCOORD0) : COLOR0 {
    return float4(coronaLight(uv, CoreColor), 0);
}
#endif

technique vcs_sun {
    pass SpritePass {
        AlphaBlendEnable = true;
        SrcBlend = ONE;
        DestBlend = ONE;
        BlendOp = ADD;
        AlphaTestEnable = false;
        ColorWriteEnable = 7;
        CullMode = NONE;
        FogEnable = false;
#ifdef VCS_SUN_OPTICS
        ZEnable = false;
#else
        ZEnable = true;
        ZFunc = LESSEQUAL;
#endif
        ZWriteEnable = false;
        VertexShader = compile vs_2_0 sunVertex();
        PixelShader = compile ps_2_0 sunPixel();
    }
}
