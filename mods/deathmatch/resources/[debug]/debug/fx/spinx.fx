//
// spinx.fx
// http://glslsandbox.com/e#28746.0
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
#define WIDTH 0.25

float pointz(float2 p)
{
	return 1.0-clamp(dot(length(p)-WIDTH/32.0, sTexSize.x * WIDTH), 0.0, 1.0);	
}

float ring(float2 p, float r)
{
	return 1.0-clamp(dot(abs(length(p)-r), sTexSize.x * WIDTH), 0.0, 1.0);
}

float linez(float2 p, float2 a, float2 b)
{
    if (a.x == b.x) return 0;
    if (a.y == b.y) return 0;
    float d = distance(a, b);
    float2  n = normalize(b - a);
    float2  l = float2(0.0,0.0);
    p -= a;
    d *= -.5;
    l.x = abs(dot(p, float2(-n.y, n.x)));
    l.y = abs(dot(p, n.xy)+d)+d;
    l = max(l, 0.0);
	
    return  1.0-clamp(dot(sTexSize * WIDTH, l), 0., 1.);
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
	
    float2 uv = position;
    float2 p 	= (uv * 2. - 1.);
    float2 m  = (mouse * 2. - 1.);

    float l = 0.0;
    float r = 0.0;
    float d = 0.0;
	
    r += ring(p, 0.5);
    for(int i = 0; i < 8; i++)
    {
        l += linez(p, float2(0.0,0.0), m) + linez(p - 0.5 * normalize(m),float2(0.0,0.0), float2(-m.y, m.x));
        r += ring(p / float2(-m.y, m.x), abs(m.y)/abs(m.x));
        d += pointz(p) + pointz(p-m) + pointz(p-0.5 * normalize(m)) + pointz(p - 0.5 * normalize(m) - float2(-m.y, m.x));
        p = mul(p, rmat(float(7-i)*3.0*atan(1.0)));
    }
	
    float colg = d + l + r;
	return float4(colg,colg,colg,1);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique spinx
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