//
// file: img_refract_MRT_DB.fx
// version: v1.5
// author: Ren712
//

//--------------------------------------------------------------------------------------
// Settings
//--------------------------------------------------------------------------------------
float2 sElementLow = float2(1,1);
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
texture gDepthBuffer : DEPTHBUFFER;
float4x4 gProjectionMainScene : PROJECTION_MAIN_SCENE;
float4x4 gViewMainScene : VIEW_MAIN_SCENE;
float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
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

sampler2D SamplerScreen = sampler_state
{
    Texture = (sProjectiveTexture);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Mirror;
    AddressV = Mirror;
};

sampler SamplerDepthTex = sampler_state
{
    Texture = (sMaskTexture);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
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

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
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
    float3 CameraDirection : TEXCOORD1;
    float3 CameraPosition : TEXCOORD2;
    float3 Normal : TEXCOORD3;
    float3 Tangent : TEXCOORD4;
    float3 Binormal : TEXCOORD5;
    float4 SparkleTex : TEXCOORD6;
};

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

//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // retrieve cameraPosition and cameraDirection from inverted ViewMatrix	
    float4x4 sViewInverse = inverseMatrix(gViewMainScene);
    PS.CameraDirection = sViewInverse[2].xyz;
    PS.CameraPosition = sViewInverse[3].xyz;
	
    // calculate projection inverse matrix
    float4x4 sProjectionInverse = inverseMatrix(gProjectionMainScene);

    // calculate screen position of the vertex
    PS.Position = mul(float4(VS.Position.xyz, 1), gWorldViewProjection);

    // pass texCoords and vertex color to PS
    PS.TexCoord = VS.TexCoord;
	
    // create Normal, Binormal and Tangent vectors	
    float3 VSNormal = float3(0,0,1);
    float3 Tangent; 
    float3 Binormal; 
    float3 c1 = cross(VSNormal, float3(0.0, 0.0, 1.0)); 
    float3 c2 = cross(VSNormal, float3(0.0, 1.0, 0.0)); 
    if (length(c1) > length(c2)) Tangent = c1;	
        else Tangent = c2;	
    PS.Normal = VSNormal;
    PS.Tangent = normalize(Tangent);
    PS.Binormal = normalize(cross(VSNormal, PS.Tangent)); 
	
    // Scroll noise texture
    float2 uvpos1 = 0;
    float2 uvpos2 = 0;

    uvpos1.x = sin(gTime/5) * 0.25;
    uvpos1.y = fmod(gTime/40,1);

    uvpos2.x = fmod(gTime/70,1);
    uvpos2.y = sin((1.6 + gTime)/10) * 0.25;

    // pass sparkleTex to PS	
    PS.SparkleTex = float4(uvpos1.x, uvpos1.y, uvpos2.x, uvpos2.y);
	
    // Convert regular water color to what we want
    float4 waterColorBase = float4(90 / 255.0, 170 / 255.0, 170 / 255.0, 240 / 255.0);
    float4 conv = float4(30 / 255.0,  58 / 255.0,  58 / 255.0, 200 / 255.0);
    PS.Diffuse = saturate(sWaterColor * conv / waterColorBase);

    return PS;
}

//------------------------------------------------------------------------------------------
//-- Function for converting depth to view-space position
//-- in deferred pixel shader pass.  vTexCoord is a texture
//-- coordinate for a full-screen quad, such that x=0 is the
//-- left of the screen, and y=0 is the top of the screen.
//------------------------------------------------------------------------------------------
float3 VSPositionFromDepthTex(float z, float2 vTexCoord, float4x4 g_matInvProjection)
{
    // Get x/w and y/w from the viewport position
    float x = vTexCoord.x * 2 - 1;
    float y = (1 - vTexCoord.y) * 2 - 1;
    float4 vProjectedPos = float4(x, y, z, 1.0f);
    // Transform by the inverse projection matrix
    float4 vPositionVS = mul(vProjectedPos, g_matInvProjection);  
    // Divide by w to get the view-space position
    return vPositionVS.xyz / vPositionVS.w;  
}

//------------------------------------------------------------------------------------------
// Pack Unit Float [0,1] into RGB24
//------------------------------------------------------------------------------------------
float3 UnitToColor24New(in float depth) 
{
    // Constants
    const float3 scale	= float3(1.0, 256.0, 65536.0);
    const float2 ogb	= float2(65536.0, 256.0) / 16777215.0;
    const float normal	= 256.0 / 255.0;
	
    // Avoid Precision Errors
    float3 unit	= (float3)depth;
    unit.gb	-= floor(unit.gb / ogb) * ogb;
	
    // Scale Up
    float3 color = unit * scale;
	
    // Use Fraction to emulate Modulo
    color = frac(color);
	
    // Normalize Range
    color *= normal;
	
    // Mask Noise
    color.rg -= color.gb / 256.0;

    return color;
}

//------------------------------------------------------------------------------------------
// Unpack RGB24 into Unit Float [0,1]
//------------------------------------------------------------------------------------------
float ColorToUnit24New(in float3 color) {
    const float3 scale = float3(65536.0, 256.0, 1.0) / 65793.0;
    return dot(color, scale);
}

//------------------------------------------------------------------------------------------
// Pack Unit float [nearClip,farClip] Unit Float [0,1]
//------------------------------------------------------------------------------------------
float DistToUnit(in float dist, in float nearClip, in float farClip) 
{
    float unit = (dist - nearClip) / (farClip - nearClip);
    return unit;
}

//------------------------------------------------------------------------------------------
// Pack Unit Float [0,1] to Unit float [nearClip,farClip]
//------------------------------------------------------------------------------------------
float UnitToDist(in float unit, in float nearClip, in float farClip) 
{
    float dist = (unit * (farClip - nearClip)) + nearClip;
    return dist;
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

//------------------------------------------------------------------------------------------
// Pixel shader
//------------------------------------------------------------------------------------------
float4 PixelShaderFunction(PSInput PS) : COLOR
{
    // calculate projection inverse and view inverse matrices
    float4x4 sProjectionInverse = inverseMatrix(gProjectionMainScene);
    float4x4 sViewInverse = inverseMatrix(gViewMainScene);
	
    float2 ProjCoord = PS.TexCoord;
	
    // get pixel depth from depth texture
    float3 depthColor = tex2D(SamplerDepthTex, ProjCoord).rgb;
    float texDepth = ColorToUnit24New(depthColor.rgb);
    float texLinDepth = Linearize(texDepth);
	
    if (texDepth < 0.0001) return 0;

    // get world position from depth texture
    float3 viewPos = VSPositionFromDepthTex(texDepth, ProjCoord, sProjectionInverse);
    float4 worldPos = mul(float4(viewPos, 1), sViewInverse);
	
    // create texture coords from world position
    float2 TexCoord =  float2(worldPos.y,-worldPos.x) * 0.125 * 0.125;

    // calculate wave texture coords
    float4 SparkleTex;
    SparkleTex.x = TexCoord.x * 1 + PS.SparkleTex.x;
    SparkleTex.y = TexCoord.y * 1 + PS.SparkleTex.y;
    SparkleTex.z = TexCoord.x * 2 + PS.SparkleTex.z;
    SparkleTex.w = TexCoord.y * 2 + PS.SparkleTex.w;

    // sample normal texture and calculate bump normals 
    float3 vFlakesNormal = tex2D(SamplerNormal, SparkleTex.xy).rgb;
    float3 vFlakesNormal2 = tex2D(SamplerNormal, SparkleTex.zw).rgb;

    float3 NormalTex = (vFlakesNormal + vFlakesNormal2 )/2;
    NormalTex.xyz = normalize((NormalTex.xyz * 2.0) - 1.0);
	
    NormalTex *= nStrength;
    float3 Normal = normalize(NormalTex.x * normalize(PS.Tangent) + NormalTex.y * normalize(PS.Binormal) + NormalTex.z * normalize(PS.Normal));
    Normal = normalize(Normal);
    NormalTex *= nRefIntens;
	
    // Sample wave map using this reflection method
    float3 vView = normalize( PS.CameraPosition - worldPos.xyz );
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

    // include fog fading effect
    float3 applyFade = saturate(1 - MTAApplyFade(worldPos, PS.CameraPosition));	
	
    // calculate bleed fix
    float depthAlt = Linearize(FetchDepthBufferValue(ProjCoord.xy + NormalTex.xy));
    float refMul =  1 - saturate(texLinDepth - depthAlt);
    if (sRefBleedFix) NormalTex *= refMul;
	
    // sample projective screen texture
    float4 refractionColor = tex2D(SamplerScreen, ProjCoord.xy + NormalTex.xy * applyFade);
	
    // lerp between screen and color texture
    float4 finalColor = 1;
    finalColor.rgb = lerp(refractionColor.rgb, envMap.rgb, PS.Diffuse.a * applyFade);
    finalColor.rgb = saturate(finalColor.rgb);
	
    // add spelular lighting to finalColor
    finalColor.rgb += specLighting * sVisibility * applyFade;

    // get world texture mask and apply to the refracted water
    float depthVal = FetchDepthBufferValue(ProjCoord.xy);
    if (texDepth >= depthVal) finalColor.a = 0;
	
    return saturate(finalColor);
}

//-----------------------------------------------------------------------------
//-- Techniques
//-----------------------------------------------------------------------------

technique dxDrawImage2D_ref_PS3_MRT_DB
{
  pass P0
  {
    ZEnable = false;
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
    PixelShader  = compile ps_3_0 PixelShaderFunction();
  }
}

technique fallback
{
  pass P0
  {
  }
}