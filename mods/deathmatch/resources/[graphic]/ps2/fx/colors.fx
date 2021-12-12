//
// colors.fx
// author: Ren712/AngerMAN
//

//---------------------------------------------------------------------
// Settings
//---------------------------------------------------------------------
float3 Tripspeed = float3( 1, 1, 1 );
float pendulumSpeed = 0;
float pendulumChoke = 1;
float strenght = 1;
texture sTex0 : TEX0;
texture sTex1 : TEX1;

//---------------------------------------------------------------------
// Include some common stuff
//---------------------------------------------------------------------
float gTime : TIME;

//---------------------------------------------------------------------
// Static data
//---------------------------------------------------------------------
static const float PI = 3.141592653589793f;

//---------------------------------------------------------------------
// Samplers
//---------------------------------------------------------------------
sampler2D Sampler0 = sampler_state
{
    Texture         = (sTex0);
    MinFilter       = Linear;
    MagFilter       = Linear;
    MipFilter       = Linear;
    AddressU        = Mirror;
    AddressV        = Mirror;
};

sampler1D ColorCorr = sampler_state
{
    Texture         = (sTex1);
    MinFilter       = Linear;
    MagFilter       = Linear;
    MipFilter       = Linear;
    AddressU        = Mirror;
    AddressV        = Mirror;
};
//------------------------------------------------------------------------------------------
// PixelShaderFunction
//  1. Read from PS structure
//  2. Process
//  3. Return pixel color
//------------------------------------------------------------------------------------------

float4 PixelShaderFunction(float2 TexCoord:TEXCOORD0) : COLOR0
{
    float4 Color = tex2D( Sampler0, TexCoord );
	
    float pendulumTimer = fmod( gTime * pendulumSpeed, 1 );
    float pendulum = saturate( abs(( cos( pendulumTimer * 2 * PI )+ 1 )/ 2 ));
    pendulum = saturate( pendulum * pendulumChoke + ( 1 - pendulumChoke ));
    float3 OutColor;
    OutColor.r = tex1D( ColorCorr, Color.r + pendulum * Tripspeed.r ).r;
    OutColor.g = tex1D( ColorCorr, Color.g + pendulum * Tripspeed.g ).g;
    OutColor.b = tex1D( ColorCorr, Color.b + pendulum * Tripspeed.b ).b;
    OutColor.rgb = lerp( Color, OutColor.rgb, saturate( strenght ));
    return float4( OutColor, 1 );
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique colors
{
    pass P0
    {
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
