//
// RTOutput_brightPass.fx
//

//---------------------------------------------------------------------
// brightPass settings
//---------------------------------------------------------------------
texture ColorRT;
texture NormalRT;
float sCutoff = 0.2;         // 0 - 1
float sPower = 1;            // 1 - 5
float sAdd = 0;            // 1 - 5
float sMult = 1;            // 1 - 5

//---------------------------------------------------------------------
// Include some common stuff
//---------------------------------------------------------------------
texture gDepthBuffer : DEPTHBUFFER;
float4x4 gProjectionMainScene : PROJECTION_MAIN_SCENE;
#include "mta-helper.fx"


//---------------------------------------------------------------------
// Sampler for the main texture
//---------------------------------------------------------------------
sampler Sampler0 = sampler_state
{
    Texture = (ColorRT);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Mirror;
    AddressV = Mirror;
};

sampler Sampler1 = sampler_state
{
    Texture = (NormalRT);
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
};

sampler SamplerDepth = sampler_state
{
    Texture = (gDepthBuffer);
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    AddressU = Clamp;
    AddressV = Clamp;
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
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Calculate screen pos of vertex
    PS.Position = MTACalcScreenPosition ( VS.Position );

    // Pass through color and tex coord
    PS.Diffuse = VS.Diffuse;
    PS.TexCoord = VS.TexCoord;

    return PS;
}


//--------------------------------------------------------------------------------------
// Get value from the depth buffer
// Uses define set at compile time to handle RAWZ special case (which will use up a few more slots)
//--------------------------------------------------------------------------------------
float FetchDepthBufferValue( float2 uv )
{
    float4 texel = tex2D(SamplerDepth, uv);
#if IS_DEPTHBUFFER_RAWZ
    float3 rawval = floor(255.0 * texel.arg + 0.5);
    float3 valueScaler = float3(0.996093809371817670572857294849, 0.0038909914428586627756752238080039, 1.5199185323666651467481343000015e-5);
    return dot(rawval, valueScaler / 255.0);
#else
    return texel.r;
#endif
}
 
//--------------------------------------------------------------------------------------
// Use the last scene projecion matrix to linearize the depth value a bit more
//--------------------------------------------------------------------------------------
float Linearize(float posZ)
{
    return gProjectionMainScene[3][2] / (posZ - gProjectionMainScene[2][2]);
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    float3 Mask = tex2D(Sampler1, PS.TexCoord.xy).rgb;
    float sMask = ((Mask.b < 0.35) && (Mask.b > 0.3)) ? Mask.r : 0;
    if (sMask == 0) return 0;
	
    float4 Color = 0;

	float4 texel = tex2D(Sampler0, PS.TexCoord);

    float lum = (texel.r + texel.g + texel.b)/3;

    float adj = saturate( lum - sCutoff );

    adj = adj / (1.01 - sCutoff);
    
    texel = texel * adj;
    texel = pow(texel, sPower);
    texel.rgb = saturate((texel.rgb + sAdd)* sMult * sMask);
	
    float fogLinDepth = Linearize(FetchDepthBufferValue(PS.TexCoord));
    float FogAmount = ( fogLinDepth - gFogStart )/( gFogEnd - gFogStart );
    texel.rgb = lerp(texel.rgb, 0, saturate( FogAmount ) );

    Color = texel * PS.Diffuse;

	Color.a = 1;
	return Color;
}


//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique RTOutput_brightpass
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
