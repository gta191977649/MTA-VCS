//
// file: img_refract_MRT_NoDB.fx
// version: v1.5
// author: Ren712
//

//--------------------------------------------------------------------------------------
// Settings
//--------------------------------------------------------------------------------------
float sZPosition = 0;
float3 sElementRotation = float3(0,0,0);
float2 sScrSize = float2(800,600);
float2 sElementSize = float2(1,1);
float2 sElementLow = float2(1,1);
bool bIsDetailed = true;
bool sFogEnable = false;
int fCullMode = 1;

float4 sWaterColor = float4(90 / 255.0, 170 / 255.0, 170 / 255.0, 240 / 255.0 );

bool sRefBleedFix = true;

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
texture sMaskTexture;
texture sWaveTexture;
texture sRandomTexture;
texture sProjectiveTexture;

//--------------------------------------------------------------------------------------
// Variables set by MTA
//--------------------------------------------------------------------------------------
float4x4 gProjectionMainScene : PROJECTION_MAIN_SCENE;
float4x4 gViewMainScene : VIEW_MAIN_SCENE;
float4 gFogColor < string renderState="FOGCOLOR"; >;
float gFogStart < string renderState="FOGSTART"; >;
float gFogEnd < string renderState="FOGEND"; >;
int gCapsMaxAnisotropy < string deviceCaps="MaxAnisotropy"; >;
int CUSTOMFLAGS < string skipUnusedParameters = "yes"; >;
float gTime : TIME;

//--------------------------------------------------------------------------------------
// Sampler 
//--------------------------------------------------------------------------------------
sampler2D SamplerMask = sampler_state
{
    Texture = (sMaskTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
};

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

sampler2D SamplerScreen = sampler_state
{
    Texture = (sProjectiveTexture);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Mirror;
    AddressV = Mirror;
};

//--------------------------------------------------------------------------------------
// Structures
//--------------------------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
    float2 TexCoord : TEXCOORD0;
    float4 Diffuse : COLOR0;
};

struct PSInput
{
    float4 Position : POSITION0;
    float4 TexProj : TEXCOORD0;
    float3 WorldPos : TEXCOORD1;
    float3 Normal : TEXCOORD2;
    float3 Tangent : TEXCOORD3;
    float3 Binormal : TEXCOORD4;
    float4 SparkleTex : TEXCOORD5;
    float3 CameraPosition : TEXCOORD6;
    float3 CameraDirection : TEXCOORD7;	
    float4 Diffuse : COLOR0;
};

//--------------------------------------------------------------------------------------
// Create world matrix with world position and euler rotation
//--------------------------------------------------------------------------------------
float4x4 createWorldMatrixEuler(float3 pos, float3 rot)
{
    float4x4 eleMatrix = {
        float4(cos(rot.z) * cos(rot.y) - sin(rot.z) * sin(rot.x) * sin(rot.y), 
                cos(rot.y) * sin(rot.z) + cos(rot.z) * sin(rot.x) * sin(rot.y), -cos(rot.x) * sin(rot.y), 0),
        float4(-cos(rot.x) * sin(rot.z), cos(rot.z) * cos(rot.x), sin(rot.x), 0),
        float4(cos(rot.z) * sin(rot.y) + cos(rot.y) * sin(rot.z) * sin(rot.x), sin(rot.z) * sin(rot.y) - 
                cos(rot.z) * cos(rot.y) * sin(rot.x), cos(rot.x) * cos(rot.y), 0),
        float4(pos.x,pos.y,pos.z, 1),
    };
    return eleMatrix;
}

//--------------------------------------------------------------------------------------
// Create world matrix with world position and vector
//--------------------------------------------------------------------------------------
float4x4 createWorldMatrixVector( float3 pos, float3 dir )
{
    float3 zaxis = normalize( dir );    // The "forward" vector.
    float3 xaxis = normalize( cross( float3(0, 0, -1 ), zaxis ));// The "right" vector.
    float3 yaxis = cross( xaxis, zaxis );     // The "up" vector.

    // Create a 4x4 world matrix from the right, up, forward and eye position vectors
    float4x4 worldMatrix = {
        float4(      xaxis.x,            xaxis.y,            xaxis.z,       0 ),
        float4(      yaxis.x,            yaxis.y,            yaxis.z,       0 ),
        float4(      zaxis.x,            zaxis.y,            zaxis.z,       0 ),
        float4(	     pos.x,              pos.y,              pos.z,         1 )
    };
    
    return worldMatrix;
}

//--------------------------------------------------------------------------------------
// Inverse matrix
//--------------------------------------------------------------------------------------
float4x4 inverseMatrix(float4x4 input)
{
     #define minor(a,b,c) determinant(float3x3(input.a, input.b, input.c))
     
     float4x4 cofactors = float4x4(
          minor(_22_23_24, _32_33_34, _42_43_44), 
         -minor(_21_23_24, _31_33_34, _41_43_44),
          minor(_21_22_24, _31_32_34, _41_42_44),
         -minor(_21_22_23, _31_32_33, _41_42_43),
         
         -minor(_12_13_14, _32_33_34, _42_43_44),
          minor(_11_13_14, _31_33_34, _41_43_44),
         -minor(_11_12_14, _31_32_34, _41_42_44),
          minor(_11_12_13, _31_32_33, _41_42_43),
         
          minor(_12_13_14, _22_23_24, _42_43_44),
         -minor(_11_13_14, _21_23_24, _41_43_44),
          minor(_11_12_14, _21_22_24, _41_42_44),
         -minor(_11_12_13, _21_22_23, _41_42_43),
         
         -minor(_12_13_14, _22_23_24, _32_33_34),
          minor(_11_13_14, _21_23_24, _31_33_34),
         -minor(_11_12_14, _21_22_24, _31_32_34),
          minor(_11_12_13, _21_22_23, _31_32_33)
     );
     #undef minor
     return transpose(cofactors) / determinant(input);
}

//---------------------------------------------------------------------------------------
// MTAUnlerp
//---------------------------------------------------------------------------------------
float MTAUnlerp( float from, float to, float pos )
{
    if ( from == to )
        return 1.0;
    else
        return ( pos - from ) / ( to - from );
}

//--------------------------------------------------------------------------------------
// Vertex Shader 
//--------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // is detail or stretched
    float2 elementSize = sElementSize;
    if (!bIsDetailed) elementSize = sElementLow;

    // set proper position and scale of the quad
    VS.Position.xy /= float2(sScrSize.x, sScrSize.y);
    VS.Position.xy =  0.5 - VS.Position.xy;
    VS.Position.xy = float2(VS.Position.x,-VS.Position.y);
    VS.Position.xy = VS.Position.yx;
    VS.Position.xy *= elementSize.xy;

    // retrieve cameraPosition and cameraDirection from inverted ViewMatrix	
    float4x4 sViewInverse = inverseMatrix(gViewMainScene);
    PS.CameraPosition = sViewInverse[3].xyz;

    // set texCoord to get always the same size
    VS.TexCoord.xy += float2(-PS.CameraPosition.y, PS.CameraPosition.x) / elementSize;
	
    // create WorldMatrix for the quad	
    float4x4 sWorld = createWorldMatrixEuler(float3(PS.CameraPosition.xy, sZPosition), sElementRotation);
	
    // create Normal, Binormal and Tangent vectors	
    float3 VSNormal = float3(0,0,1);
    float3 Tangent; 
    float3 Binormal; 
    float3 c1 = cross(VSNormal, float3(0.0, 0.0, 1.0)); 
    float3 c2 = cross(VSNormal, float3(0.0, 1.0, 0.0)); 
    if (length(c1) > length(c2)) Tangent = c1;	
        else Tangent = c2;	
    Binormal = normalize(cross(VSNormal, Tangent));

    // calculate screen position of the vertex
    float4 wPos = mul(float4( VS.Position, 1), sWorld);
    float4 vPos = mul(wPos, gViewMainScene);
    PS.Position = mul(vPos, gProjectionMainScene);
    PS.TexProj.w = vPos.z / vPos.w;

    // set information for world Position and world Normal, Binormal and Tangent
    PS.WorldPos = mul(float4(VS.Position,1), sWorld).xyz;
    PS.Normal = mul(VSNormal, (float3x3)sWorld);
    PS.Tangent = mul(Tangent, (float3x3)sWorld);
    PS.Binormal = mul(Binormal, (float3x3)sWorld); 

    // set texCoords for projective texture
    float projectedX = (0.5 * (PS.Position.w + PS.Position.x));
    float projectedY = (0.5 * (PS.Position.w - PS.Position.y));
    PS.TexProj.xyz = float3(projectedX, projectedY, PS.Position.w);
    // Scroll noise texture
    float2 uvpos1 = 0;
    float2 uvpos2 = 0;

    uvpos1.x = sin(gTime/5) * 0.25;
    uvpos1.y = fmod(gTime/40,1);

    uvpos2.x = fmod(gTime/70,1);
    uvpos2.y = sin((1.6 + gTime)/10) * 0.25;
	
    // pass texCoords to PS
    VS.TexCoord.xy *= (elementSize / 24.0f);

    // pass sparkleTex to PS	
    PS.SparkleTex.x = VS.TexCoord.x * 0.5 + uvpos1.x ;
    PS.SparkleTex.y = VS.TexCoord.y * 0.5 + uvpos1.y ;
    PS.SparkleTex.z = VS.TexCoord.x * 1 + uvpos2.x ;
    PS.SparkleTex.w = VS.TexCoord.y * 1 + uvpos2.y ;
	
    // Convert regular water color to what we want
    float4 waterColorBase = float4(90 / 255.0, 170 / 255.0, 170 / 255.0, 240 / 255.0 );
    float4 conv           = float4(30 / 255.0,  58 / 255.0,  58 / 255.0, 200 / 255.0 );
    PS.Diffuse = saturate( sWaterColor * conv / waterColorBase );
	
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
// MTAApplyFade
//------------------------------------------------------------------------------------------
float MTAApplyFade(float3 worldPos, float3 cameraPos)
{
    if (!sFogEnable) 
        return 1;
    float DistanceFromCamera = distance(cameraPos, worldPos);
    float fogStart = min(sElementLow.x / 2, gFogStart);
    float fogEnd = min(sElementLow.x / 2, gFogEnd);
    float FogAmount = (DistanceFromCamera - fogStart)/(fogEnd - fogStart);
    return saturate(FogAmount);
}

//--------------------------------------------------------------------------------------
// Pixel shaders 
//--------------------------------------------------------------------------------------
float4 PixelShaderFunctionSM3NoDB(PSInput PS) : COLOR0
{
    // slice if needed
    float2 distFromCam = float2( distance(PS.CameraPosition.x, PS.WorldPos.x), distance(PS.CameraPosition.y, PS.WorldPos.y));
    if (((distFromCam.x < sElementSize.x * 0.5) && (distFromCam.y < sElementSize.y * 0.5)) && !bIsDetailed) return 0;

    // include fog fading effect
    float3 applyFade = saturate(1 - MTAApplyFade(PS.WorldPos, PS.CameraPosition));

    // sample normal texture and calculate bump normals 
    float3 vFlakesNormal = tex2D(SamplerNormal, PS.SparkleTex.xy).rgb;
    float3 vFlakesNormal2 = tex2D(SamplerNormal, PS.SparkleTex.zw).rgb;

    float3 NormalTex = (vFlakesNormal + vFlakesNormal2 )/2;
    NormalTex.xyz = normalize((NormalTex.xyz * 2.0) - 1.0);
	
    NormalTex *= nStrength;
    float3 Normal = normalize(NormalTex.x * normalize(PS.Tangent) + NormalTex.y * normalize(PS.Binormal) + NormalTex.z * normalize(PS.Normal));
    Normal = normalize(Normal);
    NormalTex *= nRefIntens;

    // sample wave map using this reflection method
    float3 vView = normalize( PS.CameraPosition - PS.WorldPos.xyz );
    float fNdotV = saturate(dot(PS.Normal, vView));
    float3 vReflection = 2 * PS.Normal * fNdotV - vView;
    vReflection += Normal;
    float4 envMap = texCUBE(SamplerWave, -vReflection);
    float envGray = (envMap.r + envMap.g + envMap.b)/1.5;
    envMap.rgb = float3(envGray,envGray,envGray);
    envMap.rgb = envMap.rgb * envMap.a * PS.Diffuse.rgb;
	
    // calculate specular light
    float3 lightDir = normalize(sLightDir);
    float3 specLighting = applyLiSpecular(sSunColorTop.rgb, sSunColorBott.rgb, Normal, lightDir, vView, sSpecularPower);	
    specLighting = specLighting * envGray * sSpecularBrightness;
	
    // get projective texture coords
    float2 TexProj = PS.TexProj.xy / PS.TexProj.z;
    TexProj += float2(0.0006, 0.0006);	
	
    // sample projective screen texture
    float4 refractionColor = tex2D(SamplerScreen, TexProj.xy + NormalTex.xy * applyFade);
	
    // lerp between screen and color texture
    float4 finalColor = 1;
    finalColor.rgb = lerp(refractionColor.rgb, envMap.rgb, PS.Diffuse.a * applyFade);
    finalColor.rgb = saturate(finalColor.rgb);
	
    // add spelular lighting to finalColor
    finalColor.rgb += specLighting * sVisibility * applyFade;

    // get world texture mask and apply to the refracted water
    float waterMask = tex2D(SamplerMask, TexProj.xy).r;
    finalColor.a *= waterMask;
	
    return saturate(finalColor);
}

//--------------------------------------------------------------------------------------
// Techniques
//--------------------------------------------------------------------------------------
technique dxDrawImage4D_ref_PS3_MRT_NoDB
{
  pass P0
  {
    ZEnable = true;
    ZFunc = LessEqual;
    ZWriteEnable = true;
    CullMode = fCullMode;
    ShadeMode = Gouraud;
    AlphaBlendEnable = true;
    SrcBlend = SrcAlpha;
    DestBlend = InvSrcAlpha;
    AlphaTestEnable = true;
    AlphaRef = 1;
    AlphaFunc = GreaterEqual;
    Lighting = false;
    FogEnable = false;
    VertexShader = compile vs_3_0 VertexShaderFunction();
    PixelShader  = compile ps_3_0 PixelShaderFunctionSM3NoDB();
  }
} 

technique fallback
{
    pass P0
    {
    }
}
