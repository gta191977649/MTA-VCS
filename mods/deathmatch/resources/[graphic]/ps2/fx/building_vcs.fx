//CREDIT VCS PC EDITION TEAM

//#define surfAmb (surfProps.x)
#include "mta-helper.fx"

#define surfAmb 0.5
#define ambient 1.0

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

VS_OUTPUT Vertex_Pipeline(in VS_INPUT IN)
{
	VS_OUTPUT PS;

	PS.Position = mul(IN.Position, gWorldViewProjection);
	PS.Texcoord0 = mul(Identity, float4(IN.TexCoord, 0.0, 1.0)).xy;

	PS.Color = IN.Color*IN.Color;
	PS.Color.rgb += ambient*surfAmb * 128.0/255.0;

	return PS;
}

float4 Pixel_Pipeline(VS_OUTPUT PS) : COLOR0
{
	float4 finalColor = tex2D(Sampler0, PS.Texcoord0.xy)*PS.Color * 255.0/128.0;
	return finalColor;
}


technique worldfiff
{
    pass P0
    {
        VertexShader = compile vs_2_0 Vertex_Pipeline();
    	PixelShader = compile ps_2_0 Pixel_Pipeline();
		AlphaBlendEnable = true;
		AlphaRef = 1;
    }
}