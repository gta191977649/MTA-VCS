//
// gridWalk.fx
// http://glslsandbox.com/e#27027.2
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);

// effect speciffic
float3 color1 = float3(-1., 0., 0.9);
float3 color2 = float3(0.9, 0., 0.9); 

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
float2 mod2(float2 x, float2 y)
{
    return x - y * floor(x/y);
}

float linstep(float x0, float x1, float xn)
{
    return (xn - x0) / (x1 - x0);
}

float cdist(float2 v0, float2 v1)
{
    v0 = abs(v0 - v1);
    return max(v0.x, v0.y);
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;

    float2 cen = 0.5;
	
    float2 gruv = position - cen;
    gruv = float2(gruv.x * abs(1./gruv.y), abs(1./gruv.y));
    gruv.y += timer;
    gruv.x += sin(timer);


    float grid = 2. * cdist(float2(0.5,0.5), mod2(gruv,float2(1.0,1.0)));
		
    float gridmix = max(pow(grid,6.), smoothstep(0.93,0.96,grid) * 2.);

    float3 gridcol = (lerp(color1, color2, position.y*2.) + 1.2) * gridmix;
    gridcol *= linstep(0.1, 2.0, abs(position.y - cen.y));
  
    return float4(gridcol.rgb,1);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique gridWalk
{
    pass P0
    {
        VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunction();
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
