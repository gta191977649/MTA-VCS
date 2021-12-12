//
// colNeckl.fx
// http://glslsandbox.com/e#29248.1
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);
float2 sMouse = float2(0.25,0.25);

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
const float dotsnb = 30.0; // Number of dots

float3 hsv2rgb (float3 hsv) { // from HSV to RGB color vector
    hsv.yz = clamp (hsv.yz, 0.0, 1.0);
    return hsv.z * (1.0 + 0.63 * hsv.y * (cos (2.0 * 3.14159 * (hsv.x + float3 (0.0, 2.0 / 3.0, 1.0 / 3.0))) - 1.0));
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
    float mx = max(sTexSize.x, sTexSize.y);
    float2 scrs = float2(1,1); //sTexSize/mx;
    float2 uv = position + 0.5;
	
    float2 pos  = float2(0.0, 0.0); // Position of the dots
    float3 col = float3(0.0, 0.0, 0.0); // Color of the dots
    float radius = 0.15; // Radius of the circle
    float intensity = 1.0/500.0; // Light intensity
	
    for(float i = 0.0 ; i<dotsnb ; i++){	
        pos = float2(radius*cos(2.0*PI*i/dotsnb+timer*(3.0)/3.0),
            radius*sin(2.0*PI*i/dotsnb+timer*(2.0)/3.0));
        col += hsv2rgb(float3(i/dotsnb, distance(uv,scrs/2.0 + pos)*(1.0/intensity), intensity/distance(uv,scrs/2.0 + pos)));
    }
	
	return float4(col, 1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique colNeckl
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