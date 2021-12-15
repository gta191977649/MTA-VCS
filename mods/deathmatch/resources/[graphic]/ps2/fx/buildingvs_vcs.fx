//CREDIT VCS PC EDITION TEAM

//#define surfAmb (surfProps.x)
#include "mta-helper.fx"

#define surfAmb 0.6
#define ambient gGlobalAmbient

sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

struct VS_INPUT
{
	float4 Position		: POSITION;
	float2 TexCoord		: TEXCOORD0;
	float4 Color		: COLOR0;
};

struct VS_OUTPUT {
	float4 Position		: POSITION;
	float2 Texcoord0	: TEXCOORD0;
	float4 Color		: COLOR0;
};

matrix Identity =
{
    { 1, 0, 0, 0 },
    { 0, 1, 0, 0 },
    { 0, 0, 1, 0 },
    { 0, 0, 0, 1 }
};

VS_OUTPUT main(in VS_INPUT IN)
{
	VS_OUTPUT OUT;

	OUT.Position = mul(IN.Position, gWorldViewProjection);
	OUT.Texcoord0 = mul(Identity, float4(IN.TexCoord, 0.0, 1.0)).xy;

	OUT.Color = IN.Color*IN.Color;
	OUT.Color.rgb += ambient*surfAmb * 128.0/255.0;

	return OUT;
}
technique worldfiff
{
    pass P0
    {
        VertexShader = compile vs_2_0 main();
        
    }
}