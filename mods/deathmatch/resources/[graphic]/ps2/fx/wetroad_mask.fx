float4 gColor = float4(1,1,1,1); 
bool bIsGTADiffuse = true; 
  
//--------------------------------------------------------------------- 
// Include some common stuff 
//--------------------------------------------------------------------- 
#include "mta-helper.fx" 
  

  
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
  float2 TexCoord : TEXCOORD0; 
}; 
  
  

//------------------------------------------------------------------------------------------ 
// PixelShaderFunction 
//  1. Read from PS structure 
//  2. Process 
//  3. Return pixel color 
//------------------------------------------------------------------------------------------ 
float4 PixelShaderFunction(PSInput PS) : COLOR0 
{ 
    // Get texture pixel 
  
    // Apply diffuse lighting 
    //float4 finalColor = texel * PS.Diffuse; 
  
    return float4(0,0,0,0); 
} 
  
  
//------------------------------------------------------------------------------------------ 
// Techniques 
//------------------------------------------------------------------------------------------ 
technique colorize 
{ 
    pass P0 
    { 
        PixelShader = compile ps_2_0 PixelShaderFunction(); 
        AlphaBlendEnable = true;
    } 
} 
  
technique fallback 
{
    pass P0
    {
    }

}