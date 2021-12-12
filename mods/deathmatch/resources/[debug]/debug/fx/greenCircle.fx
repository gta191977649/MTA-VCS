//
// greenCircle.fx
// http://glslsandbox.com/e#22795.0
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(2,2);
float2 sCenter = float2(0.5,0.5);

//------------------------------------------------------------------------------------------
// These parameters are set by MTA whenever a shader is drawn
//------------------------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gProjection : PROJECTION;
float gTime : TIME;
#define PI 3.1415926535897

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
float mod(float x, float y)
{
    return x - y * floor(x/y);
}

float atoms(float3 pos, float radius)
{
    return radius / pow(length(pos), 256.0);
}


float3 ball(float2 position, float3 colour, float sizec, float xc, float yc){
    return colour * (sizec / distance(position, float2(xc, yc)));
}

float3 grid(float2 position, float3 colour, float linesize, float xc, float yc){
    float xmod = mod(position.x, xc);
    float ymod = mod(position.y, yc);
    return xmod < linesize || ymod < linesize ? float3(0,0,0) : colour;
}

float3 circle(float2 position, float3 colour, float size, float linesize, float xc, float yc){
    float dist = distance(position, float2(xc, yc));
    return colour * clamp(-(abs(dist - size)*linesize * 100.0) + 0.9, 0.0, 2.0);
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;
	
    float3 red = float3(2, 1, 1);
    float3 green = float3(1, 2, 1);
    float3 blue = float3(1, 1, 2);
	
    float3 color = float3(0,0,0);
    color += circle(position, blue, 0.085, 0.6, 0.5, 0.5);

    color *= 1.0 - distance(position, float2(0.5, 0.5));
    color += ball(position, green, 0.01, sin(timer*4.0) / 12.0 + 0.5, cos(timer*4.0) / 12.0 + 0.5);
    color *= ball(position, green, 0.01, -sin(timer*-8.0) / 12.0 + 0.5, -cos(timer*-8.0) / 12.0 + 0.5) + 0.5;
    return float4(color, 1.0 );
}



//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique greenCircle
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
