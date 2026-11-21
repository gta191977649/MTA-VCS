texture MarkerTexture;
float4x4 ViewProjection : VIEWPROJECTION;

sampler MarkerSampler = sampler_state {
    Texture = (MarkerTexture);
    AddressU = Wrap;
    AddressV = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

struct MarkerVertex {
    float4 position : POSITION0;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

MarkerVertex markerVertex(MarkerVertex input) {
    input.position = mul(float4(input.position.xyz, 1), ViewProjection);
    return input;
}

float4 markerPixel(float2 uv : TEXCOORD0, float4 color : COLOR0) : COLOR0 {
    return tex2D(MarkerSampler, uv) * color;
}

technique vcs_marker {
    pass P0 {
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
#ifdef VCS_MARKER_ADDITIVE
        DestBlend = ONE;
#else
        DestBlend = INVSRCALPHA;
#endif
        BlendOp = ADD;
        AlphaTestEnable = false;
        CullMode = NONE;
        FogEnable = false;
        ZEnable = true;
        ZFunc = LESSEQUAL;
        ZWriteEnable = false;
        VertexShader = compile vs_2_0 markerVertex();
        PixelShader = compile ps_2_0 markerPixel();
    }
}
