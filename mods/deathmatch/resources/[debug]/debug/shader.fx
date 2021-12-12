texture gTexture;
float4 gColor = float4(1,1,1,1); 
bool bIsGTADiffuse = true; 
  
//--------------------------------------------------------------------- 
// Include some common stuff 
//--------------------------------------------------------------------- 
#include "mta-helper.fx" 
  
//--------------------------------------------------------------------- 
// Sampler for the main texture 
//--------------------------------------------------------------------- 
sampler Sampler0 = sampler_state 
{ 
    Texture = (gTexture0); 
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
  float2 TexCoord : TEXCOORD0; 
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
    PS.Position = MTACalcScreenPosition ( VS.Position ); 
  
    // Pass through tex coord 
    PS.TexCoord = VS.TexCoord; 
  
    // Calculate GTA lighting for buildings 
    float4 Diffuse = MTACalcGTABuildingDiffuse( VS.Diffuse ); 
    PS.Diffuse = 0; 
    if (bIsGTADiffuse) PS.Diffuse = Diffuse; 
    else PS.Diffuse = float4(1,1,1,Diffuse.a); 
    PS.Diffuse *= gColor; 
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
    // Get texture pixel 
    float4 texel = tex2D(Sampler0, PS.TexCoord); 
  
    // Apply diffuse lighting 
    float4 finalColor = texel * PS.Diffuse; 
  
    return finalColor; 
} 
  
  
//------------------------------------------------------------------------------------------ 
// Techniques 
//------------------------------------------------------------------------------------------ 
technique colorize 
{ 
    pass P0 
    { 
        VertexShader = compile vs_2_0 VertexShaderFunction(); 
        PixelShader = compile ps_2_0 PixelShaderFunction(); 
        Texture[0] = gTexture;
        AlphaBlendEnable = true;
    } 
} 
  
technique fallback 
{
    pass P0
    {
        Texture[0] = gTexture;
    }

}