//
// coolWaves.fx
// http://glslsandbox.com/e#28415.0
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(1,1);
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
float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;
	
    const float sa = 0.1;
    const float sf = 50.0;
    const float cf = 0.66;
    float tf = 4.0 * timer;

    float3 color = float3(0.0 , 0.0, 0.0);
		
    float rx = sin(tf + sf * position.x);
    float ry = abs( position.y - (sa * rx + 0.5) );
    color.r = cf * (1.0 - sqrt(ry));
	
    float gx = sin(tf - sf * position.x);
    float gy = abs( position.y - (sa * gx + 0.5) );
    color.g = cf * (1.0 - sqrt(gy));
	
    float bx = rx + gx;
    float by = abs( position.y - (sa * bx + 0.5) );
    color.b = (1.0 - sqrt(by));
	
    return float4( color.rgb, 1.0 );
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique coolWaves
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
