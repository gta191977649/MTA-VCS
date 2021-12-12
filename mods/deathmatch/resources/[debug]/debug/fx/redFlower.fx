//
// redFlower.fx
// http://glslsandbox.com/e#28732.0
// glsl to hlsl translation by Ren712

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
#define WIDTH 0.01

float ring(float2 p, float r)
{
    return 1.-clamp(dot(abs(length(p)-r), sTexSize.x * WIDTH), 0., 1.);
}

float2x2 rmat(float t)
{
    float c = cos(t);
    float s = sin(t);   
    return float2x2(c,s,-s,c);
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
    // Translate mouse
    float2 center = 0.5 + (sCenter - 0.5);	
    float2 mouse = sMouse;
    mouse -= 0.5;
    mouse -= center - 0.5;
    mouse *= float2(sTexSize.x/sTexSize.y,1) / sScale;
    mouse += 0.5;
    mouse = float2(mouse.x, 1 - mouse.y);
	
    float2 uv,p,m;
    uv = position + 0.5;
    p 	= (uv * 2.0 - 1.0);
    m  = (mouse * 2.0 - 2.0);
		
    float r = 0.0;
	
    for(int i = 0; i < 8; i++)
    {
        r += ring(p / float2(-m.y, m.x), abs(m.y)/abs(m.x));
        p = mul(p, rmat(float(7-i)*5.*atan(1.)));
    }
	
    return float4(float3(r+r-r*r,0.0,r-r*r),1);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique redFlower
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