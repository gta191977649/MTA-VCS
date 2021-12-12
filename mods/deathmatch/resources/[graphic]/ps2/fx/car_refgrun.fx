//
// car_refgrun.fx
// author: Ren712/AngerMAN
//

float bumpSize = 1;

float2 uvMul = float2(1,1);
float2 uvMov = float2(0,0.25);

float bumpIntensity = 0.25;

float brightnessFactor = 0.20;
float transFactor = 0.55;
float alphaFactor = 0.75;

float minZviewAngleFade = 0.6;
float sNormZ = 3;
float sRefFlan = 0.2;
float sAdd = 0.1;  
float sMul = 1.1; 
float sCutoff : CUTOFF = 0.16;
float sPower : POWER  = 2;
float sNorFac = 1;

float gFilmDepth = 0.05; // 0-0.25
float gFilmIntensity = 0.005;
float3 sSkyColorTop = float3(0,0,0);
float3 sSkyColorBott = float3(0,0,0);
float sSkyLightIntensity = 0;

//------------------------------------------------------------------------------------------
// Car paint settings
//------------------------------------------------------------------------------------------
texture sReflectionTexture;
texture sRandomTexture;
texture sFringeTexture;

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

sampler2D gFringeMapSampler = sampler_state 
{
    Texture = (sFringeTexture);
    MinFilter = Linear;
    MipFilter = Linear;
    MagFilter = Linear;
    AddressU  = Clamp;
    AddressV  = Clamp;
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
    float3 Tangent : TEXCOORD1;
    float3 Binormal : TEXCOORD2;
    float3 Normal : TEXCOORD3;
    float3 View : TEXCOORD4;
    float3 SparkleTex : TEXCOORD5;
    float3 FilmDepth : TEXCOORD6;
    float4 WorldPos : TEXCOORD7;
};

//------------------------------------------------------------------------------------------
// Function to Index this texture - use in vertex or pixel shaders 
//------------------------------------------------------------------------------------------

float calc_view_depth(float NDotV,float Thickness)
{
    return (Thickness / NDotV);
}

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
	
    // Fake tangent and binormal
    float3 Tangent = VS.Normal.yxz;
    Tangent.xz = VS.TexCoord.xy;
    float3 Binormal =normalize( cross(Tangent, VS.Normal) );
    Tangent = normalize( cross(Binormal, VS.Normal) );

    // Transfer some stuff
    PS.Tangent = normalize(mul(Tangent, gWorldInverseTranspose).xyz);
    PS.Binormal = normalize(mul(Binormal, gWorldInverseTranspose).xyz);
    PS.Normal = normalize( mul(VS.Normal, (float3x3)gWorld) );
	
    PS.SparkleTex.x = fmod( VS.Position.x, 10 ) * 16 * bumpSize;
    PS.SparkleTex.y = fmod( VS.Position.y, 10 ) * 16 * bumpSize;
    PS.SparkleTex.z = fmod( VS.Position.z, 10 ) * 16 * bumpSize; 	
	
    // compute the view depth for the thin film
    float3 Nn = mul(VS.Normal,gWorldInverseTranspose).xyz;	
    float3 Vn = normalize(PS.View);
    float vdn = dot(Vn,Nn);
    float viewdepth = calc_view_depth(vdn,gFilmDepth.x);
    PS.FilmDepth.xy = viewdepth.xx;	
	
    // Calc lighting
    PS.Diffuse = MTACalcGTAVehicleDiffuse( PS.Normal, VS.Diffuse );

    // Normal Z vector for sky light 
    float skyTopmask = pow(PS.Normal.z,5);
    PS.Specular.rgb = (skyTopmask * sSkyColorTop + saturate(PS.Normal.z-skyTopmask)* sSkyColorBott );
    PS.Specular.rgb *= gGlobalAmbient.xyz;
    PS.Specular.a = pow(PS.Normal.z,sNormZ);
    PS.FilmDepth.z = saturate(PS.Specular.a);
    if (gCameraDirection.z < minZviewAngleFade) PS.Specular.a = PS.FilmDepth.z * (1 - saturate((-1 / minZviewAngleFade ) * (minZviewAngleFade - gCameraDirection.z)));
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
    //reflection variable here

    // Some settings for something or another
    float microflakePerturbation = 1.00;

    float3 vFlakesNormal = tex3D(RandomSampler, PS.SparkleTex).rgb;

    vFlakesNormal = 2 * vFlakesNormal - 1.0;
    float3 vNp2 = microflakePerturbation * (( vFlakesNormal + 1.0)/2) ;

    float3 vView = normalize(PS.View);
    float3 vNormal = normalize(PS.Normal);
    float3x3 mTangentToWorld = transpose( float3x3( PS.Tangent,PS.Binormal, PS.Normal ) );
    float3 vNormalWorld = normalize( mul( mTangentToWorld, vNormal ));
    float fNdotV = saturate(dot( vNormalWorld, vView ));

    // lerp between scene and material world normal
    vFlakesNormal = bumpIntensity * vFlakesNormal;
    float3 worldNormal = normalize(refract(PS.Normal, vFlakesNormal, 1));
	
    // reflection direction
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

    // Sample fringe map:
    float3 fringeCol = (float3)tex2D(gFringeMapSampler, PS.FilmDepth.xy)* PS.FilmDepth.z;

    // Brighten the environment map sampling result:
    envMap.rgb *= brightnessFactor;	 
	
    envMap.a =1;	
    float4 first = float4((envMap.rgb+ 0.5 * PS.Specular.rgb * sSkyLightIntensity),PS.Specular.a);
    float4 second = float4(1.2 * (PS.Specular.rgb),1.2 * sSkyLightIntensity * PS.FilmDepth.z);

    envMap = lerp(first,second,1 - PS.Specular.a);
    float fEnvContribution = 1.0 - 0.5 *fNdotV; 
    float4 finalColor = ((envMap)*(fEnvContribution));
    float4 Color = finalColor;
    Color += float4(fringeCol,gFilmIntensity* PS.FilmDepth.z) * gFilmIntensity;
    Color = saturate(Color);
    Color.a *= transFactor;
    Color.a *= PS.Diffuse.a;
	
    Color.a = MTAApplyFogAlpha( Color.a, PS.WorldPos.xyz );
	
    return saturate(Color);
}

float4 PixelShaderFunctionSM2(PSInput PS) : COLOR0
{
    //reflection variable here

    // Some settings for something or another
    float microflakePerturbation = 1.00;

    float3 vFlakesNormal = tex3D(RandomSampler, PS.SparkleTex).rgb;

    vFlakesNormal = 2 * vFlakesNormal - 1.0;
    float3 vView = normalize(PS.View);

    // lerp between scene and material world normal
    vFlakesNormal = bumpIntensity * vFlakesNormal;
    float3 worldNormal = normalize(refract(PS.Normal, vFlakesNormal, 1));
	
    // reflection direction
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

    // Sample fringe map:
    float3 fringeCol = (float3)tex2D(gFringeMapSampler, PS.FilmDepth.xy)* PS.FilmDepth.z;

    // Brighten the environment map sampling result:
    envMap.rgb *= brightnessFactor;	 
	
    envMap.a =1;	
    float4 first = float4((envMap.rgb+ 0.5 * PS.Specular.rgb * sSkyLightIntensity),PS.Specular.a);
    float4 second = float4(1.2 * (PS.Specular.rgb),1.2 * sSkyLightIntensity * PS.FilmDepth.z);

    envMap = first;
    float4 finalColor = envMap;
    float4 Color = finalColor;
    Color += float4(fringeCol,gFilmIntensity* PS.FilmDepth.z) * gFilmIntensity;
    Color = saturate(Color);
    Color.a *= transFactor;
    Color.a *= PS.Diffuse.a;
	
    return saturate(Color);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique car_reflect_paint_layer
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

technique car_reflect_paint_layer_fallback
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