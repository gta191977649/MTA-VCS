//
// RTinput_car_paint.fx
// Thanks goes to rifleh700 for his research to recreate exact gtasa vehicle processing.
//

//------------------------------------------------------------------------------------------
// Include some common stuff
//------------------------------------------------------------------------------------------
float4 gBlendFactor < string renderState="BLENDFACTOR"; >;
int gZWriteEnable < string renderState="ZWRITEENABLE"; >;
int gCullMode < string renderState="CULLMODE"; >;  
int gStage1ColorOp < string stageState="1,COLOROP"; >;
float4 gTextureFactor < string renderState="TEXTUREFACTOR"; >;
float4x4 gTransformTexture1 < string transformState="TEXTURE1"; >; 
#include "mta-helper.fx"

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

sampler Sampler1 = sampler_state
{
    Texture = (gTexture1);
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
  float3 Position : POSITION0;
  float3 Normal : NORMAL0;
  float4 Diffuse : COLOR0;
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
  float3 Specular : COLOR1;
  float2 TexCoord : TEXCOORD0;
  float3 Normal : TEXCOORD1;
  float3 TexCoord1 : TEXCOORD2;
  float2 Depth : TEXCOORD3;
};

//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Make sure normal is valid
    MTAFixUpNormal( VS.Normal );

    // Set information to do specular calculation
    float3 Normal = mul(VS.Normal, (float3x3)gWorld);
    PS.Normal = Normal.xyz;
    float3 ViewNormal = mul(VS.Normal, (float3x3)gWorldView);
	
    // Calculate screen pos of vertex	
    float4 worldPos = mul( float4(VS.Position.xyz,1) , gWorld );	
    float4 viewPos = mul( worldPos , gView );
    float4 projPos = mul( viewPos, gProjection);
    PS.Position = projPos;

    // Pass through tex coord
    PS.TexCoord = VS.TexCoord;
    PS.TexCoord1 = 0;
    if (gStage1ColorOp == 25) PS.TexCoord1 = mul(ViewNormal.xyz, (float3x3)gTransformTexture1);
    if (gStage1ColorOp == 14) PS.TexCoord1 = mul(float3(VS.TexCoord1.xy, 1), (float3x3)gTransformTexture1);
	
    // Pass depth
    PS.Depth = float2(viewPos.z, viewPos.w);

    // Calculate GTA lighting for Vehicles
    PS.Diffuse = MTACalcGTACompleteDiffuse( Normal, VS.Diffuse );
    PS.Specular.rgb = gMaterialSpecular.rgb * MTACalculateSpecular( gCameraDirection, gLight1Direction, Normal, min(127, gMaterialSpecPower)) * gLight1Specular.rgb;
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
    float4 texel = tex2D(Sampler0, PS.TexCoord.xy);

    // Apply diffuse lighting
    float4 finalColor = texel * PS.Diffuse;

    // Apply env reflection
    // BlendFactorAlpha = 14,
    if (gStage1ColorOp == 14) {
        float4 envTexel = tex2D(Sampler1, PS.TexCoord1.xy);
        finalColor.rgb = finalColor.rgb * (1 - gTextureFactor.a) + envTexel.rgb * gTextureFactor.a;
    }

    // Apply spherical reflection
    // MultiplyAdd = 25
    if (gStage1ColorOp == 25) {
        float4 sphTexel = tex2D(Sampler1, PS.TexCoord1.xy/PS.TexCoord1.z);
        finalColor.rgb += sphTexel.rgb * gTextureFactor.r;
    }
	
    // Apply specular
    if (gMaterialSpecPower != 0) finalColor.rgb += PS.Specular.rgb;
	
    finalColor = saturate(finalColor);

    finalColor.rgb = MTAApplyFog(finalColor.rgb, PS.Depth.x / PS.Depth.y);
    output.World = saturate(finalColor);
		
    // Color render target
    output.Color.rgb = finalColor.rgb * 0.85 + 0.15;
    output.Color.a = texel.a * PS.Diffuse.a;
		
    // Normal render target
    float3 Normal = normalize(PS.Normal);
    Normal = float3((Normal.xy * 0.5) + 0.5, Normal.z <0 ? 0.611 : 0.789);
    output.Normal = float4(Normal, 1);

    return output;
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique RTinput_car_paint
{
    pass P0
    {
        CullMode = ((gMaterialDiffuse.a < 0.9) && (gBlendFactor.a == 0)) ? 1 : gCullMode;
        ZWriteEnable = (gMaterialDiffuse.a < 0.9) ? 0 : gZWriteEnable;
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