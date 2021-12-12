//
// colFractals.fx
// http://glslsandbox.com/e#29615.0
// glsl to hlsl translation by Ren712

// Created by inigo quilez - iq/2013 // glslsandbox mod by Robert Schütze - trirop/2015
// License Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported License.

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);
float2 sMouse = float2(0.5,0.5);

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
float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;

    // Translate mouse
    float2 center = 0.5 + (sCenter - 0.5);	
	float2 mouse = sMouse;
    mouse -= 0.5;
    mouse -= center - 0.5;
    mouse *= float2(sTexSize.x/sTexSize.y,1) / sScale;
    mouse += 0.5;
    mouse = float2(mouse.x, 1 - mouse.y);
	
    float2 p = position;
    float4 dmin = 1000.0;
    float2 z = (-1.0 + 2.0 * p)*float2(1.7, 1.0);
    for( int i=0; i<64; i++ )
        {
        z = (mouse - float2(0.5, 0.5)) * 1.6 + float2(z.x * z.x-z.y * z.y,2.0 * z.x * z.y);
        dmin = min(dmin, float4(abs(0.0 + z.y + 0.5 * sin(z.x)), abs(1.0 + z.x + 0.5 * sin(z.y)), dot(z, z),length(frac(z) - 0.5)));
        }	
    float3 color = float3(dmin.w, dmin.w, dmin.w);
    color = lerp( color, float3(1.00,0.80,0.60),     min(1.0,pow(dmin.x*0.25,0.20)));
    color = lerp( color, float3(0.72,0.70,0.60),     min(1.0,pow(dmin.y*0.50,0.50)));
    color = lerp( color, float3(1.00,1.00,1.00), 1.0-min(1.0,pow(dmin.z*1.00,0.15)));
    color = 1.25 * color * color;
    return float4(color * (0.5 + 0.5 * pow(16.0 * p.x * (1.0 - p.x) * p.y * (1.0 - p.y), 0.15)), 1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique colFractals
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