//
// esotropiaV.fx
// author: Ren712/AngerMAN
//

//---------------------------------------------------------------------
// Settings
//---------------------------------------------------------------------
float sBlur = 1;
texture sTex0 : TEX0;
float2 sTex0Size : TEX0SIZE;
float2 Prop = float2( 0.1, 0.1 );
float pendulumSpeed = 0.4;
float pendulumChoke = 1;
float strenght = 0;

//-----------------------------------------------------------------------------
// Include some common stuff
//-----------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gProjection : PROJECTION;
float gTime : TIME;

//-----------------------------------------------------------------------------
// Static data
//-----------------------------------------------------------------------------
static const float Kernel[13] = {-6, -5,     -4,     -3,     -2,     -1,     0,      1,      2,      3,      4,      5,      6};
static const float Weights[13] = {      0.002216,       0.008764,       0.026995,       0.064759,       0.120985,       0.176033,       0.199471,       0.176033,       0.120985,       0.064759,       0.026995,       0.008764,       0.002216};
static const float PI = 3.141592653589793f;

//---------------------------------------------------------------------
// Sampler for the main texture
//---------------------------------------------------------------------
sampler Sampler0 = sampler_state
{
    Texture         = (sTex0);
    MinFilter       = Linear;
    MagFilter       = Linear;
    MipFilter       = Linear;
    AddressU        = Mirror;
    AddressV        = Mirror;
};


//---------------------------------------------------------------------
// Structure of data sent to the vertex shader
//---------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

//---------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//---------------------------------------------------------------------
struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord: TEXCOORD0;
};


//------------------------------------------------------------------------------------------
// VertexShaderFunction
//  1. Read from VS structure
//  2. Process
//  3. Write to PS structure
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Calculate screen pos of vertex
	
    float4 posWorld = mul( float4( VS.Position, 1 ), gWorld );
    float4 posWorldView = mul( posWorld, gView );
    PS.Position = mul( posWorldView, gProjection );
	
    // Pass through color and tex coord
    PS.Diffuse = VS.Diffuse;
    PS.TexCoord = VS.TexCoord;

    return PS;
}


//------------------------------------------------------------------------------------------
// PixelShaderFunction
//  1. Read from PS structure
//  2. Process
//  3. Return pixel color
//------------------------------------------------------------------------------------------
float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float4 Color = 0;
    float4 preColor = tex2D( Sampler0, PS.TexCoord.xy ); 
	
    float pendulumTimer = fmod( gTime * pendulumSpeed , 1 );
    float pendulum = saturate( abs(( cos( pendulumTimer * 2 * PI ) + 1 ) /2 ));
    pendulum = saturate( pendulum * pendulumChoke + ( 1 - pendulumChoke ));
	
    float2 coord;
    float proport = Prop.x * pendulum;
    coord.x = PS.TexCoord.x;
    coord.x *= ( 1 / ( 1 + proport ));
    coord.x += proport;
    for(int i = 0; i < 4; ++i)
    {
        if ( fmod( i, 2 ) > 0 ) coord.x += proport; 
            else coord.x -= proport;
        coord.y = PS.TexCoord.y + ( Kernel[i] / sTex0Size.y ) * sBlur;
        Color += tex2D( Sampler0, coord.xy ) * 0.25;
    }

    float4 output = lerp( preColor, Color, saturate( strenght ));
    output = output * PS.Diffuse;
    output.a = 1;
    return output;  
}


//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique drunkV
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
