//
// RTinput_world.fx
//

//------------------------------------------------------------------------------------------
// Settings
//------------------------------------------------------------------------------------------
bool sDisableNormals = false;

//------------------------------------------------------------------------------------------
// Include some common stuff
//------------------------------------------------------------------------------------------
//#define GENERATE_NORMALS      // Uncomment for normals to be generated
#include "mta-helper.fx"
#define surfAmb 0.35
#define ambient 1.0
//------------------------------------------------------------------------------------------
// Render targets
//------------------------------------------------------------------------------------------
texture colorRT < string renderTarget = "yes"; >;
texture normalRT < string renderTarget = "yes"; >;

//------------------------------------------------------------------------------------------
// Sampler for the main texture
//------------------------------------------------------------------------------------------
sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
  float4 Position : POSITION0;
  float4 Diffuse : COLOR0;
  float3 Normal : NORMAL0;
  float2 TexCoord : TEXCOORD0;
  float2 TexCoord1 : TEXCOORD1;
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//------------------------------------------------------------------------------------------
struct PSInput
{
  float4 Position : POSITION0;
  float4 Diffuse : COLOR0;
  float2 TexCoord : TEXCOORD0;
  float4 Normal : TEXCOORD1;
  float2 Depth : TEXCOORD2;
}; 

matrix Identity =
{
    { 1, 0, 0, 0 },
    { 0, 1, 0, 0 },
    { 0, 0, 1, 0 },
    { 0, 0, 0, 1 }
};
//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Pass through tex coord (Did in vcs)
    //PS.TexCoord = VS.TexCoord;
	
    float4 Normal;
    if ((gDeclNormal != 1) || (sDisableNormals)) Normal = float4(0,0,0,0);
        else Normal = float4(mul(VS.Normal, (float3x3)gWorld), 1);
    PS.Normal = Normal; 
	
    // Calculate screen pos of vertex	
    float4 worldPos = mul(float4(VS.Position.xyz,1) , gWorld);	
    float4 viewPos = mul(worldPos, gView);
    float4 projPos = mul(viewPos, gProjection);
    PS.Position = projPos;
	
    // Pass depth
    PS.Depth = float2(viewPos.z, viewPos.w);

    // Calculate GTA lighting for Buildings
    PS.Diffuse = MTACalcGTABuildingDiffuse(VS.Diffuse);

    //Process VCS Building Pipeline
	PS.TexCoord = mul(Identity, float4(VS.TexCoord, 0.0, 1.0)).xy;
	PS.Diffuse = PS.Diffuse*PS.Diffuse;
	PS.Diffuse.rgb += ambient*surfAmb * 128.0/255.0;

    
    return PS;
}

//------------------------------------------------------------------------------------------
// Structure of color data sent to the renderer ( from the pixel shader  )
//------------------------------------------------------------------------------------------
struct Pixel
{
    float4 World : COLOR0;      // Render target #0
    float4 Color : COLOR1;      // Render target #1
    float4 Normal : COLOR2;      // Render target #2
};

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
Pixel PixelShaderFunction(PSInput PS)
{
    Pixel output;
	
    // Get texture pixel
    float4 texel = tex2D(Sampler0, PS.TexCoord);

    // Apply diffuse lighting
    float4 finalColor = texel * PS.Diffuse * 255.0/128.0;
    finalColor.rgb = MTAApplyFog(finalColor.rgb, PS.Depth.x / PS.Depth.y);
    
    //finalColor = tex2D(Sampler0, PS.Texcoord0.xy)*PS.Diffuse * 255.0/128.0;

    //output.World = saturate(finalColor);
    output.World = finalColor;
	
    // Compare with current pixel depth
    // Color render target
    output.Color.rgb = texel.rgb;
    output.Color.a = texel.a * PS.Diffuse.a;
		
    // Normal render target
	float3 Normal = normalize(PS.Normal.xyz);
    if ((PS.Normal.w == 0) || (sDisableNormals)) 
        output.Normal = float4(dot(PS.Diffuse.xyz,float3(0.299,0.587,0.114)),0,0.211,1);
        else output.Normal = float4((Normal.xy * 0.5) + 0.5, Normal.z <0 ? 0.411 : 0.589, 1);



    return output;
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique RTinput_world
{
    pass P0
    {

        SRGBWriteEnable = false;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
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