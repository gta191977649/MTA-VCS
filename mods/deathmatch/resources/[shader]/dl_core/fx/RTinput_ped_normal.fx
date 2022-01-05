//
// RTinput_ped.fx
//

//------------------------------------------------------------------------------------------
// Settings
//------------------------------------------------------------------------------------------
static const float pi = 3.141592653589793f;
float fLerpNormal = 0.5;
float3 gTexColor = float3(1,1,1);
texture gTextureNormal;

//------------------------------------------------------------------------------------------
// Render targets
//------------------------------------------------------------------------------------------
texture colorRT < string renderTarget = "yes"; >;
texture normalRT < string renderTarget = "yes"; >;

//------------------------------------------------------------------------------------------
// Include some common stuff
//------------------------------------------------------------------------------------------
//#define GENERATE_NORMALS      // Uncomment for normals to be generated
#include "mta-helper.fx"

//------------------------------------------------------------------------------------------
// Sampler for the main texture
//------------------------------------------------------------------------------------------
sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

sampler SamplerNormal = sampler_state
{
    Texture = (gTextureNormal);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
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
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//------------------------------------------------------------------------------------------
struct PSInput
{
  float4 Position : POSITION0;
  float4 Diffuse : COLOR0;
  float2 TexCoord : TEXCOORD0;
  float3 Normal : TEXCOORD1;
  float3 WorldPos : TEXCOORD2;
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
    PS.Normal = mul(VS.Normal, (float3x3)gWorld);

    // Pass through tex coord
    PS.TexCoord = VS.TexCoord;

    // Calculate screen and world pos of vertex	
    PS.Position = mul( float4(VS.Position.xyz,1) , gWorldViewProjection);
    float4 worldPos = mul(float4(VS.Position, 1), gWorld);
    PS.WorldPos = worldPos.xyz;
	
    // Calculate view position and pass zw
    float4 viewPos = mul(worldPos, gView);
    PS.Depth = float2(viewPos.z, viewPos.w);	

    // Calculate GTA lighting for Vehicles
    PS.Diffuse = MTACalcGTABuildingDiffuse(VS.Diffuse);
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
// function to recreate tangent and bitangent using derivatives
//------------------------------------------------------------------------------------------
float3x3 cotangent_frame(float3 N, float3 p, float2 uv)
{
    // get edge vectors of the pixel triangle
    float3 dp1 = ddx( p );
    float3 dp2 = ddy( p );
    float2 duv1 = ddx( uv );
    float2 duv2 = ddy( uv );
 
    // solve the linear system
    float3 dp2perp = cross( dp2, N );
    float3 dp1perp = cross( N, dp1 );
    float3 T = dp2perp * duv1.x + dp1perp * duv2.x;
    float3 B = dp2perp * duv1.y + dp1perp * duv2.y;
 
    // construct a scale-invariant frame 
    float invmax = rsqrt( max( dot(T,T), dot(B,B) ) );
    return float3x3( -T * invmax, -B * invmax, N );
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
Pixel PixelShaderFunction(PSInput PS)
{
    Pixel output;
	
    // Get texture pixels
    float4 texel = tex2D(Sampler0, PS.TexCoord);
    texel.rgb = gTexColor * texel.rgb;
    float4 NormalTex = tex2D(SamplerNormal, PS.TexCoord);
	
    float3 VNormal = normalize(PS.Normal);
	
    // Get normal vector
    float3x3 tangentToWorldSpace = cotangent_frame(VNormal, PS.WorldPos - gCameraPosition, PS.TexCoord);
    NormalTex.xy = (NormalTex.xy * 2.0) - 1.0;
    float3 Normal = normalize(NormalTex.x * normalize(tangentToWorldSpace[0]) - NormalTex.y * 
        normalize(tangentToWorldSpace[1]) + (1 - length(NormalTex.xy)) * normalize(tangentToWorldSpace[2]));
    Normal = lerp(VNormal, normalize(Normal), fLerpNormal * texel.a);

    // Apply diffuse lighting
    float4 finalColor = texel * PS.Diffuse;
	
    // Apply per pixel directional lights
    finalColor.rgb += texel.rgb * MTACalcGTAPedSpecularLights(Normal, NormalTex.w).rgb * NormalTex.z;
	
    // Apply fog
    finalColor.rgb = MTAApplyFog(finalColor.rgb, PS.Depth.x / PS.Depth.y);

    output.World = saturate(finalColor);

    // Color render target
    output.Color.rgb = texel.rgb;
    output.Color.a = texel.a * PS.Diffuse.a;

   // Normal render target
   Normal = normalize(Normal);
   output.Normal = float4((Normal.xy * 0.5) + 0.5, Normal.z <0 ? 0.811 : 0.989, 1);
   
    return output;
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique RTinput_ped_normal
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