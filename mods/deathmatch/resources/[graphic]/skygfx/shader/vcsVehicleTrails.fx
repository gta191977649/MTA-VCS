// The PS2 streak pass uses untextured vertex RGB, ONE/ONE blending and no depth.
// Use explicit shaders: MTA's untextured primitive batch can inherit shader state.
float4x4 WorldViewProjection : WORLDVIEWPROJECTION;

struct TrailVertex {
    float4 position : POSITION0;
    float4 color : COLOR0;
};

TrailVertex trailVertex(TrailVertex input) {
    input.position = mul(float4(input.position.xyz, 1), WorldViewProjection);
    return input;
}

float4 trailPixel(float4 color : COLOR0) : COLOR0 {
    return color;
}

technique vcs_vehicle_trails {
    pass P0 {
        AlphaBlendEnable = true;
        SrcBlend = ONE;
        DestBlend = ONE;
        BlendOp = ADD;
        AlphaTestEnable = false;
        ColorWriteEnable = 7;
        CullMode = NONE;
        FogEnable = false;
        ZEnable = false;
        ZWriteEnable = false;
        VertexShader = compile vs_2_0 trailVertex();
        PixelShader = compile ps_2_0 trailPixel();
    }
}
