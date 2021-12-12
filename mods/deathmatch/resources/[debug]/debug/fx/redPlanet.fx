//
// redPlanet.fx
// http://glslsandbox.com/e#22826.0
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
// Mahmud Yuldashev Red Planet mahmud9935@gmail.com

float noise2D(float2 uv)
{
    uv = frac(uv)*1e3;
    float2 f = frac(uv);
    uv = floor(uv);
    float v = uv.x+uv.y*1e3;
    float4 r = float4(v, v+1., v+1e3, v+1e3+1.);
    r = frac(1e5*sin(r*1e-2));
    f = f*f*(3.0-2.0*f);
    return (lerp(lerp(r.x, r.y, f.x), lerp(r.z, r.w, f.x), f.y));	
}

float fracal(float2 p) {
    float v = 0.5;
    v += noise2D(p*12.); v*=.54;
    v += noise2D(p*8.); v*=.54;
    v += noise2D(p*4.); v*=.54;
    v += noise2D(p*2.); v*=.54;
    v += noise2D(p*3.); v*=.54;
    v += noise2D(p*1.); v*=.54;
    return v;
}

float3 func( float2  p) {
    p = p*.1+0.6;
    float3 c = float3(.0, .0, .1);
    float2 d = float2(gTime*.0002, 0.);
    c = lerp(c, float3(.7, .2, .2)*0.9, pow(fracal(p*.15-d), 3.)*2.);
    c = lerp(c, float3(1.9, .6, .6)*0.8, pow(fracal(p.y*p*.10+d*2.)*1.3, 3.));
    c = lerp(c, float3(0.4, 0.9, 1.2)*0.7, pow(fracal(p.y*p*.05+d*3.)*1.2, 1.1));
    c = lerp(c, float3(1.0, 0.7, 0.7)*0.6, pow(fracal(p.y*p*.03+d*5.)*1.6, 1.9));
    return c;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{ 
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
    float2 p = position;
    float d = length(p);
    p *= (acos(d) - 1.57079632)/d;
    return float4(func(p)*max(1.-d*d*d, 0.), 1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique redPlanet
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
