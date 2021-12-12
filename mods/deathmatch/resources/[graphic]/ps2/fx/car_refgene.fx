//
// car_refgene.fx
// author: Ren712/AngerMAN
//

float bumpSize = 1;

float2 uvMul = float2(1,1);
float2 uvMov = float2(0,0.25);

float bumpIntensity = 0.25;

float minZviewAngleFade = -0.6;
float brightnessFactor = 0.20;
float sNormZ = 3;
float sAdd = 0.1;  
float sMul = 1.1; 
float sCutoff : CUTOFF = 0.16;
float sPower : POWER  = 2; 
float sNorFac = 1;
float gShatt = false;

float3 sSkyColorTop = float3(0,0,0);
float3 sSkyColorBott = float3(0,0,0);
float sSkyLightIntensity = 0;

//------------------------------------------------------------------------------------------
// Car paint settings
//------------------------------------------------------------------------------------------
texture sReflectionTexture;
texture sRandomTexture;

//------------------------------------------------------------------------------------------
// Include some common stuff
//------------------------------------------------------------------------------------------
int gFogEnable  < string renderState="FOGENABLE"; >;
float4 gFogColor < string renderState="FOGCOLOR"; >;
float gFogStart  < string renderState="FOGSTART"; >;
float gFogEnd < string renderState="FOGEND"; >;
#define GENERATE_NORMALS // Uncomment for normals to be generated
#include "mta-helper.fx"

//------------------------------------------------------------------------------------------
// Samplers for the textures
//------------------------------------------------------------------------------------------
sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

sampler3D RandomSampler = sampler_state
{
    Texture = (sRandomTexture); 
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Point;
};

sampler2D ReflectionSampler = sampler_state
{
    Texture = (sReflectionTexture);	
    AddressU = Mirror;
    AddressV = Mirror;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
    float4 Position : POSITION; 
    float3 Normal : NORMAL0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 View : TEXCOORD1;
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//------------------------------------------------------------------------------------------
struct PSInput
{
    float4 Position : POSITION;
    float4 Diffuse : COLOR0;
    float4 Specular : COLOR1;
    float3 SparkleTex : TEXCOORD1;
    float NormalZ : TEXCOORD2;
    float3 View : TEXCOORD3;
    float4 WorldPos : TEXCOORD4;
    float3 Normal : TEXCOORD5;
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
	
    float4 worldPos = mul ( VS.Position, gWorld );
    float4 viewPos  = mul ( worldPos, gView );
    PS.WorldPos = float4(worldPos.xyz, viewPos.z / viewPos.w);
    PS.Position  = mul ( viewPos, gProjection );
	
    PS.View = gCameraPosition - worldPos.xyz;
 
    float3 Normal = normalize( mul(VS.Normal, (float3x3)gWorld) );
    PS.Normal = Normal;

    PS.SparkleTex.x = fmod( VS.Position.x, 10 ) * 16 * bumpSize;
    PS.SparkleTex.y = fmod( VS.Position.y, 10 ) * 16 * bumpSize;
    PS.SparkleTex.z = fmod( VS.Position.z, 10 ) * 16 * bumpSize;

    // Calc lighting
    PS.Diffuse = MTACalcGTAVehicleDiffuse( Normal, VS.Diffuse );
    // Normal Z vector for sky light 
    float skyTopmask = pow(Normal.z,5);
    PS.Specular.rgb = (skyTopmask * sSkyColorTop + saturate(Normal.z-skyTopmask)* sSkyColorBott );
    PS.Specular.rgb *= gGlobalAmbient.xyz;
    PS.Specular.a = pow(Normal.z,sNormZ);
    PS.NormalZ = PS.Specular.a;
    if (gCameraDirection.z < minZviewAngleFade) PS.Specular.a = PS.NormalZ * (1 - saturate((-1 / minZviewAngleFade ) * (minZviewAngleFade - gCameraDirection.z)));	
    return PS;
}

//------------------------------------------------------------------------------------------
// GetUV from WorldPos
//------------------------------------------------------------------------------------------
float3 GetUV(float3 position, float4x4 ViewProjection)
{
    float4 pVP = mul(float4(position, 1.0f), ViewProjection);
    pVP.xy = float2(0.5f, 0.5f) + float2(0.5f, -0.5f) * ((pVP.xy / pVP.w) * uvMul) + uvMov;
    return float3(pVP.xy, pVP.z / pVP.w);
}

//------------------------------------------------------------------------------------------
// MTAApplyFog
//------------------------------------------------------------------------------------------ 
float MTAApplyFogAlpha( float texel, float3 worldPos )
{
    if ( !gFogEnable )
        return texel;
 
    float DistanceFromCamera = distance( gCameraPosition, worldPos );
    float FogAmount = ( DistanceFromCamera - gFogStart )/( gFogEnd - gFogStart );
    texel = lerp(texel, 0, saturate( FogAmount ) );
    return texel;
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//  1. Read from PS structure
//  2. Process
//  3. Return pixel color
//------------------------------------------------------------------------------------------
float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Some settings for something or another
    float microflakePerturbation = 1.00;

    float3 vFlakesNormal = tex3D(RandomSampler, PS.SparkleTex).rgb;
    vFlakesNormal = 2 * vFlakesNormal - 1.0;

    // lerp between scene and material world normal
    vFlakesNormal = bumpIntensity * vFlakesNormal;
    float3 worldNormal = normalize(refract(PS.Normal, vFlakesNormal, 1));
	
    // reflection direction
    float3 vView = normalize(PS.View);
    float3 reflectDir = normalize(reflect(-vView, worldNormal));
    // cast rays
    float3 currentRay = PS.WorldPos.xyz + reflectDir * sNorFac;
    float farClip = gProjection[3][2] / (1 - gProjection[2][2]);
	
    currentRay += 2 * gWorld[2].xyz * (1.0 + (PS.WorldPos.w / farClip));
    float3 nuv = GetUV(currentRay , gViewProjection);

    // Sample environment map using this reflection vector:
    float4 envMap = tex2D( ReflectionSampler, nuv.xy );

    float lum = (envMap.r + envMap.g + envMap.b)/3;
    float adj = saturate( lum - sCutoff );
    adj = adj / (1.01 - sCutoff);
    envMap += sAdd+1.0; 
    envMap = (envMap * adj);
    envMap = pow(envMap, sPower+2); 
    envMap *= sMul;

    // Brighten the environment map sampling result:
    envMap.rgb *= brightnessFactor;	
	
    envMap.a =1;	
    float4 first = float4((envMap.rgb+ 0.5 * PS.Specular.rgb * sSkyLightIntensity),PS.Specular.a);
    float4 second = float4(1.1 * (PS.Specular.rgb),1.1 * sSkyLightIntensity * PS.NormalZ);

    envMap = lerp(first,second,1-PS.Specular.a);
	
    float4 Color = envMap;
    Color.a *=PS.NormalZ;

    if (!gShatt) if (PS.Diffuse.a >=0.8) Color.rgba=0;  
        else Color.a *= 0.65;
    Color.a *= PS.Diffuse.a;
	
    Color.a = MTAApplyFogAlpha( Color.a, PS.WorldPos.xyz );
	
    return Color;
}

float4 PixelShaderFunctionSM2(PSInput PS) : COLOR0
{
    // Some settings for something or another
    float microflakePerturbation = 1.00;

    float3 vFlakesNormal = tex3D(RandomSampler, PS.SparkleTex).rgb;
    vFlakesNormal = 2 * vFlakesNormal - 1.0;

    // lerp between scene and material world normal
    vFlakesNormal = bumpIntensity * vFlakesNormal;
    float3 worldNormal = normalize(refract(PS.Normal, vFlakesNormal, 1));
	
    // reflection direction
    float3 vView = normalize(PS.View);
    float3 reflectDir = normalize(reflect(-vView, worldNormal));
    // cast rays
    float3 currentRay = PS.WorldPos.xyz + reflectDir * sNorFac;
    float farClip = gProjection[3][2] / (1 - gProjection[2][2]);
	
    currentRay += 2 * gWorld[2].xyz * (1.0 + (PS.WorldPos.w / farClip));
    float3 nuv = GetUV(currentRay , gViewProjection);

    // Sample environment map using this reflection vector:
    float4 envMap = tex2D( ReflectionSampler, nuv.xy );

    float lum = (envMap.r + envMap.g + envMap.b)/3;
    float adj = saturate( lum - sCutoff );
    adj = adj / (1.01 - sCutoff);
    envMap += sAdd+1.0; 
    envMap = (envMap * adj);
    envMap = pow(envMap, sPower+2); 
    envMap *= sMul;

    // Brighten the environment map sampling result:
    envMap.rgb *= brightnessFactor;	
	
    envMap.a =1;	
    float4 first = float4((envMap.rgb+ 0.5 * PS.Specular.rgb * sSkyLightIntensity),PS.Specular.a);

    envMap = first;
	
    float4 Color = envMap;
    Color.a *=PS.NormalZ;

    if (!gShatt) if (PS.Diffuse.a >=0.8) Color.rgba=0;  
        else Color.a *= 0.65;
    Color.a *= PS.Diffuse.a;
	
    return Color;
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique car_reflect_generic_layer
{
    pass P0
    {
        DepthBias = -0.0003;
        AlphaRef = 1;
        AlphaBlendEnable = TRUE;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

technique car_reflect_generic_layer_fallback
{
    pass P0
    {
        DepthBias = -0.0003;
        AlphaRef = 1;
        AlphaBlendEnable = TRUE;
        VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunctionSM2();
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
