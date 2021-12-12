#include "mta-helper.fx"
float Time;
float Intensity = 1.0;
float4 WorldDiffuse = float4(1, 1, 1, 1);
bool Vehicle = false;
sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

struct VSInput
{
    float3 Position : POSITION;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 Normal   : NORMAL0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
    PS.Position = mul(float4(VS.Position, 1), gWorldViewProjection);
    float3 WorldNormal = MTACalcWorldNormal(VS.Normal);
    PS.Diffuse = (Vehicle ? MTACalcGTAVehicleDiffuse(WorldNormal, VS.Diffuse) : MTACalcGTABuildingDiffuse(VS.Diffuse));
    PS.TexCoord = VS.TexCoord;
    return PS;
}


float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 finalColor = tex2D(Sampler0, PS.TexCoord);
    finalColor = finalColor * PS.Diffuse * WorldDiffuse * Intensity;
    return finalColor;
}

technique worldfiff
{
    pass P0
    {
        //VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunction();
    }
}

technique fallback {
    pass P0 {
	
    }
}
