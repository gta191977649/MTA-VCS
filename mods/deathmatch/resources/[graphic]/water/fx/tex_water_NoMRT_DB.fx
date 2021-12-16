//
// file: tex_water_NoMRT_DB.fx
// version: v1.0
// author: Ren712
//

//--------------------------------------------------------------------------------------
// Settings
//--------------------------------------------------------------------------------------
float2 sElementSize = float2(1,1);
float2 sElementLow = float2(1,1);

float4 sWaterColor = float4(90 / 255.0, 170 / 255.0, 170 / 255.0, 240 / 255.0 );

bool sRefEffectEnable = false;

float sSpecularBrightness = 1;
float3 sLightDir = float3(0,-0.5,-0.5);
float sSpecularPower = 4;
float sVisibility = 1;
float4 sSunColorTop = float4(1,1,1,1);
float4 sSunColorBott = float4(1,1,1,1);

float3 nStrength = float3(0.5,0.5,0.5);
float3 nRefIntens = float3(0.1,0.1,0.1);

//--------------------------------------------------------------------------------------
// Textures
//--------------------------------------------------------------------------------------
texture sWaveTexture;
texture sRandomTexture;

//--------------------------------------------------------------------------------------
// Variables set by MTA
//--------------------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gWorldView : WORLDVIEW;
float4x4 gProjection : PROJECTION;
float4x4 gViewProjection : VIEWPROJECTION;
float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
float3 gCameraPosition : CAMERAPOSITION;
float3 gCameraDirection : CAMERADIRECTION;
int gFogEnable < string renderState="FOGENABLE"; >;
float4 gFogColor < string renderState="FOGCOLOR"; >;
float gFogStart < string renderState="FOGSTART"; >;
float gFogEnd < string renderState="FOGEND"; >;
int gCapsMaxAnisotropy < string deviceCaps="MaxAnisotropy"; >;
int CUSTOMFLAGS < string skipUnusedParameters = "yes"; >;
float gTime : TIME;

//--------------------------------------------------------------------------------------
// Sampler 
//--------------------------------------------------------------------------------------
samplerCUBE SamplerWave = sampler_state
{
    Texture = (sWaveTexture);
    MagFilter = Linear;
    MinFilter = Linear;
    MipFilter = Linear;
    MIPMAPLODBIAS = 0.000000;
};

sampler2D SamplerNormal = sampler_state
{
    Texture = (sRandomTexture);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Wrap;
    AddressV = Wrap;
};

//---------------------------------------------------------------------
// Structure of data sent to the vertex shader
//---------------------------------------------------------------------
struct VSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
    float3 Normal : NORMAL0;
};

//---------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//---------------------------------------------------------------------
struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float3 WorldPos : TEXCOORD0;
    float4 SparkleTex : TEXCOORD1;
    float3 Normal : TEXCOORD2;
    float3 Binormal : TEXCOORD3;
    float3 Tangent : TEXCOORD4;
    float2 TexCoord : TEXCOORD5;
};

//------------------------------------------------------------------------------------------
// MTAUnlerp
// - Find a the relative position between 2 values
//------------------------------------------------------------------------------------------
float MTAUnlerp( float from, float to, float pos )
{
    if ( from == to )
        return 1.0;
    else
        return ( pos - from ) / ( to - from );
}

//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Calculate screen pos of vertex
    PS.Position = mul(VS.Position,gWorldViewProjection);

    // Convert regular water color to what we want
    float4 waterColorBase = float4(90 / 255.0, 170 / 255.0, 170 / 255.0, 240 / 255.0 );
    float4 conv           = float4(30 / 255.0,  58 / 255.0,  58 / 255.0, 200 / 255.0 );
    PS.Diffuse = saturate( sWaterColor * conv / waterColorBase );
	
    // create Normal, Binormal and Tangent vectors	
    float3 VSNormal = float3(0,0,1);
    float3 Tangent; 
    float3 Binormal; 
    float3 c1 = cross(VSNormal, float3(0.0, 0.0, 1.0)); 
    float3 c2 = cross(VSNormal, float3(0.0, 1.0, 0.0)); 
    if (length(c1) > length(c2)) Tangent = c1;	
        else Tangent = c2;	
    Binormal = normalize(cross(VSNormal, Tangent));
	
    // set information for surface normal and lighting calculation in PS	
    PS.WorldPos = mul(float4(VS.Position.xyz, 1), gWorld).xyz;
    PS.Normal = mul(VSNormal, (float3x3)gWorld);
    PS.Tangent = mul(Tangent, (float3x3)gWorld);
    PS.Binormal = mul(Binormal, (float3x3)gWorld); 

    // Scroll noise texture
    float2 uvpos1 = 0;
    float2 uvpos2 = 0;

    uvpos1.x = sin(gTime/5) * 0.25;
    uvpos1.y = fmod(gTime/40,1);

    uvpos2.x = fmod(gTime/70,1);
    uvpos2.y = sin((1.6 + gTime)/10) * 0.25;
	
    // Pass texCoord to PS
    PS.TexCoord = VS.TexCoord;

    float2 WorldPos =  float2(PS.WorldPos.y,-PS.WorldPos.x) * 0.125 * 0.125;
		
    PS.SparkleTex.x = WorldPos.x * 1 - uvpos1.x ;
    PS.SparkleTex.y = WorldPos.y * 1 - uvpos1.y ;
    PS.SparkleTex.z = WorldPos.x * 2 - uvpos2.x ;
    PS.SparkleTex.w = WorldPos.y * 2 - uvpos2.y ;
	
    return PS;
}

//------------------------------------------------------------------------------------------
// applyLiSpecular
//------------------------------------------------------------------------------------------
float3 applyLiSpecular(float3 color1, float3 color2, float3 normal, float3 lightDir, float3 sView, float specul) 
{	
    float3 h = normalize(sView - lightDir);
    float spec = pow(saturate(dot(h, normal)), specul);	
	
    float spec1 = saturate(pow(spec, specul));
    float spec2 = saturate(pow(spec, 2 * specul));
    float3 specular = spec1 * color1.rgb / 3 + spec2 * color2.rgb;
    return saturate( specular );
}

//------------------------------------------------------------------------------------------
// MTAApplyFog
//------------------------------------------------------------------------------------------
float3 MTAApplyFog( float3 texel, float3 worldPos )
{
    if ( !gFogEnable )
        return texel;
 
    float DistanceFromCamera = distance( gCameraPosition, worldPos );
    float FogAmount = ( DistanceFromCamera - gFogStart )/( gFogEnd - gFogStart );
    texel.rgb = lerp(texel.rgb, gFogColor.rgb, saturate( FogAmount ) );
    return texel;
}

//------------------------------------------------------------------------------------------
// MTAApplyFade
//------------------------------------------------------------------------------------------
float MTAApplyFade(float3 worldPos, float3 cameraPos)
{
    if (!gFogEnable) 
        return 1;
    float DistanceFromCamera = distance(cameraPos, worldPos);
    float fogStart = min(sElementLow.x / 2, gFogStart);
    float fogEnd = min(sElementLow.x / 2, gFogEnd);
    float FogAmount = (DistanceFromCamera - fogStart)/(fogEnd - fogStart);
    return saturate(FogAmount);
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
float4 PixelShaderFunctionSM3(PSInput PS) : COLOR0
{
    // sample normal texture and calculate bump normals 
    float3 vFlakesNormal = tex2D(SamplerNormal, PS.SparkleTex.xy).rgb;
    float3 vFlakesNormal2 = tex2D(SamplerNormal, PS.SparkleTex.zw).rgb;

    float3 NormalTex = (vFlakesNormal + vFlakesNormal2 )/2;
    NormalTex.xyz = normalize((NormalTex.xyz * 2.0) - 1.0);
	
    NormalTex *= nStrength;
    float3 Normal = normalize(NormalTex.x * normalize(PS.Tangent) + NormalTex.y * normalize(PS.Binormal) + NormalTex.z * normalize(PS.Normal));
    Normal = normalize(Normal);
    NormalTex *= nRefIntens;

    // Sample wave map using this reflection method
    float3 vView = normalize( gCameraPosition - PS.WorldPos.xyz );
    float fNdotV = saturate(dot(PS.Normal, vView));
    float3 vReflection = 2 * PS.Normal * fNdotV - vView;
    vReflection += Normal;
    float4 envMap = texCUBE(SamplerWave, -vReflection);
    float envGray = (envMap.r + envMap.g + envMap.b)/1.5;
    envMap.rgb = float3(envGray,envGray,envGray);
    envMap.rgb = envMap.rgb * envMap.a * PS.Diffuse.rgb;
    envMap.rgb = saturate(envMap.rgb);
	
    // calculate specular light
    float3 lightDir = normalize(sLightDir);
    float3 specLighting = applyLiSpecular(sSunColorTop.rgb, sSunColorBott.rgb, Normal, lightDir, vView, sSpecularPower);	
    specLighting = specLighting * envGray * sSpecularBrightness;

    // lerp between screen and color texture
    float applyFade = saturate(MTAApplyFade(PS.WorldPos, gCameraPosition));
	
    // Bodge in the water color
    float4 finalColorRef = float4(PS.Diffuse.rgb, PS.Diffuse.a);
    float4 finalColorNor = saturate(envMap * 0.1 + PS.Diffuse * 0.3);
    finalColorNor += envMap * PS.Diffuse;
    finalColorNor.a = saturate(finalColorNor.a * 2.5 * PS.Diffuse.a);

    float4 finalColor = 1;
    if (sRefEffectEnable) 
            {
              finalColor = lerp(finalColorRef, finalColorNor, applyFade);
            }			  
		else 
           { 
              finalColor = finalColorNor;
              finalColor.rgb = lerp(finalColor.rgb,PS.Diffuse.rgb,0.4);
			  float sFactor = saturate((specLighting.r + specLighting.g + specLighting.b)/3);
              // add spelular lighting to finalColor
              finalColor.rgba += float4(specLighting, sFactor) * sVisibility * (1 - applyFade) * 0.8;
           }
	

    // add fog effect that is absent in PS 3.0  
    finalColor.rgb = MTAApplyFog( finalColor.rgb, PS.WorldPos.xyz);	
    return saturate(finalColor);
}

float4 PixelShaderFunctionSM2(PSInput PS) : COLOR0
{
    // sample normal texture and calculate bump normals 
    float3 vFlakesNormal = tex2D(SamplerNormal, PS.SparkleTex.xy).rgb;
    float3 vFlakesNormal2 = tex2D(SamplerNormal, PS.SparkleTex.zw).rgb;

    float3 NormalTex = (vFlakesNormal + vFlakesNormal2 )/2;
    NormalTex.xyz = normalize((NormalTex.xyz * 2.0) - 1.0);
	
    NormalTex *= nStrength;
    float3 Normal = normalize(NormalTex.x * normalize(PS.Tangent) + NormalTex.y * normalize(PS.Binormal) + NormalTex.z * normalize(PS.Normal));
    Normal = normalize(Normal);
    NormalTex *= nRefIntens;

    // Sample wave map using this reflection method
    float3 vView = normalize( gCameraPosition - PS.WorldPos.xyz );
    float fNdotV = saturate(dot(PS.Normal, vView));
    float3 vReflection = 2 * PS.Normal * fNdotV - vView;
    vReflection += Normal;
    float4 envMap = texCUBE(SamplerWave, -vReflection);
    float envGray = (envMap.r + envMap.g + envMap.b)/1.5;
    envMap.rgb = float3(envGray,envGray,envGray);
    envMap.rgb = envMap.rgb * envMap.a * PS.Diffuse.rgb;
    envMap.rgb = saturate(envMap.rgb);

    // lerp between screen and color texture
    float applyFade = saturate(MTAApplyFade(PS.WorldPos, gCameraPosition));
	
    // Bodge in the water color
    float4 finalColorRef = float4(PS.Diffuse.rgb, PS.Diffuse.a);
    float4 finalColorNor = saturate(envMap * 0.1 + PS.Diffuse * 0.3);
    finalColorNor += envMap * PS.Diffuse;
    finalColorNor.a = saturate(finalColorNor.a * 2.5 * PS.Diffuse.a);

    float4 finalColor = 1;
    if (sRefEffectEnable) 
            {
              finalColor = lerp(finalColorRef, finalColorNor, applyFade);
            }			  
		else 
           { 
              finalColor = finalColorNor;
              finalColor.rgb = lerp(finalColor.rgb,PS.Diffuse.rgb,0.4);
           }

    return saturate(finalColor);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique water_PS3_NoMRT_DB
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunctionSM3();
    }
}

technique water_PS2_NoMRT_DB
{
    pass P0
    {
        VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunctionSM2();
    }
}

technique fallback
{
    pass P0
    {
    }
}
