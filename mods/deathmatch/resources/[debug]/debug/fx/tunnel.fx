//
// tunnel.fx
// http://glslsandbox.com/e#25682.3
// glsl to hlsl translation by Ren712

// Nice little tunnel...  any idea ?  -Harley

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
float2 Scale = float2(0.002,0.002);
float Saturation = 0.8; // 0 - 1;

float3 lungth(float2 x,float3 c){
    return float3(length(x+c.r),length(x+c.g),length(c.b));
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
    float th = atan2(position.y, position.x) / (1.0 * 3.1415926); // x, y ?
    float dd = length(position) + 0.005;
    float d = 0.5 / dd + timer;
	
    float2 x = position * sTexSize;
    float3 c2=float3(0,0,0);
    x=x*Scale*sTexSize/sTexSize.x;
    x+=sin(x.yx*sqrt(float2(1,9)))/10.0;
    c2=lungth(sin(x*sqrt(float2(3,43))),float3(5,6,7)*Saturation * d);
    x+=sin(x.yx*sqrt(float2(73,5)))/5.0;
    c2=2.*lungth(sin(timer+x*sqrt(float2(33.,23.))),c2/9.0);
    x+=sin(x.yx*sqrt(float2(93,7)))/3.0;
    c2=lungth(sin(x*sqrt(float2(3.,1.))),c2/2.0);
    c2=.5+.5*sin(c2*8.);
	
    float3 uv = float3(th + d, th - d, th + sin(d) * 0.45);
    float a = 0.5 + cos(uv.x * 3.1415926 * 2.0) * 0.5;
    float b = 0.5 + cos(uv.y * 3.1415926 * 2.0) * 0.5;
    float c = 0.5 + cos(uv.z * 3.1415926 * 6.0) * 0.5;
    float3 color = 	lerp(float3(0.1, 0.5, 0.5), float3(0.1, 0.1, 0.2),  pow(a, 0.2)) * 3.;
    color += lerp(float3(0.1, 0.2, 1.0), float3(0.1, 0.1, 0.2),  pow(b, 0.1)) * 0.75;
    color += lerp(c2, float3(0.1, 0.2, 0.2),  pow(c, 0.1)) * 0.75;

	return float4( (color * dd), 1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique tunnel
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