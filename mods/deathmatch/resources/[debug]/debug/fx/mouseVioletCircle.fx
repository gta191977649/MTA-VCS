//
// mouseVioletCircle.fx
// http://glslsandbox.com/e#28578.0
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(1,1);
float2 sCenter = float2(0.5,0.5);
float2 sMouse = float2(0.25,0.25);

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
float dist(float2 v1, float2 v2) {
    float2 v = v1-v2;
    return sqrt(v.x*v.x+v.y*v.y);
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

    float4 color = float4(0.5,0.,1.,1.);
    float2 pixel = position;
	
    float r = dist(pixel, float2(0,0));
    float angle = atan2(pixel[0], pixel[1]);
    angle /= PI;

    float pR = 25.*sin(2.*PI*timer / 100.0) * cos(2.*PI*timer / 250.0) + 5.;
    float pA = 5.;
	
    color *= (cos(r*PI*2.0*pR + timer*2.5)*0.5+2.)/sqrt(abs(r)*4.0) * (cos(r*PI*2.0*pR - timer*2.5)*0.5+2.)/sqrt(abs(r)*4.0);
    color *= (cos(angle*PI*2.0*pA + timer*2.5)*0.5+2.) * (cos(angle*PI*2.0*pA - timer*2.5)*0.5+2.);
    //color *= cos(2.0*PI*pixel.x / 0.1 + timer*10.0) + 2.;
    //color *= cos(2.0*PI*pixel.y / 0.1 + timer*5.0) + 2.;
    float d = dist(mouse - float2(0.5, 0.5),pixel)*100.0;
	
    color += float4(0, 1.0/d, 0, 0);
    color *= 0.5/(d);
    //color /= 1.0/d;

    return float4(color.rgb,1);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique mouseVioletCircle
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
