//
// verticalStrobes.fx
// http://glslsandbox.com/e#28666.1
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);

//------------------------------------------------------------------------------------------
// These parameters are set by MTA whenever a shader is drawn
//------------------------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gProjection : PROJECTION;
float gTime : TIME;
#define PI 3.14159265359

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//------------------------------------------------------------------------------------------
struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord: TEXCOORD0;
};

//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Calculate screen pos of vertex
    float4 posWorld = mul(float4(VS.Position.xyz,1), gWorld);
    float4 posWorldView = mul(posWorld, gView);
    PS.Position = mul(posWorldView, gProjection);
	
    // Pass through color and tex coord
    PS.Diffuse = VS.Diffuse;

    // Translate TexCoord
    float2 position = float2(VS.TexCoord.x,1 - VS.TexCoord.y);
    float2 center = 0.5 + (sCenter - 0.5);
    position += float2(1 - center.x, center.y) - 0.5;
    position = (position - 0.5) * float2(sTexSize.x/sTexSize.y,1) / sScale + 0.5;
    position -= 0.5;
    PS.TexCoord = position;

    return PS;
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
#define ITER 10
float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;

    float3 color;
    float2 pos;
    float _t;
	
    for(int i = 0; i < ITER; i++){
        _t = timer * 3.6;
        pos = float2(sin(_t), 0.0);
        color += (0.05 / float(ITER)) / length(position.xy - pos + float2(0, (float(i) / float(ITER) - 0.5) * 2.0)) *
			        float3(0, max(min(abs(tan(_t - PI / 2.0)), 5.0), 0.7), max(min(abs(tan(_t - PI / 2.0)), 5.0), 0.7));
		
        _t = timer * 1.8;
        pos = float2(sin(_t), 0.0);
        color += (0.04 / float(ITER)) / length(position.xy - pos + float2(0, (float(i) / float(ITER) - 0.5) * 2.0)) *
			        float3(max(min(abs(tan(_t - PI / 2.0)), 5.0), 0.7), max(min(abs(tan(_t - PI / 2.0)), 5.0), 0.7), 0);
		
        _t = timer * 1.2;
        pos = float2(sin(_t), 0.0);
        color += (0.04 / float(ITER)) / length(position.xy - pos + float2(0, (float(i) / float(ITER) - 0.5) * 2.0)) *
			        float3(max(min(abs(tan(_t - PI / 2.0)), 5.0), 0.7), 0, max(min(abs(tan(_t - PI / 2.0)), 20.0), 0.7));
    }
    return float4(color, 1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique verticalStrobes
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

// Fallback
technique fallback
{
    pass P0
    {
        // Just draw normally
    }
}
