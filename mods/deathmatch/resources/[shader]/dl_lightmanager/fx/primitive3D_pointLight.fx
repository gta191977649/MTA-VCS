// 
// file: primitive3D_pointLight.fx
// version: v1.6
// author: Ren712
//

//--------------------------------------------------------------------------------------
// Settings
//--------------------------------------------------------------------------------------
float3 sLightPosition = float3(0,0,0);
float4 sLightColor = float4(0,0,0,0);
float sLightAttenuation = 1;
float sLightAttenuationPower = 2;
bool sLightBillboard = false;

float2 gDistFade = float2(250,150);
bool gUseNormals = true;

float2 sHalfPixel = float2(0.000625,0.00083);
float2 sPixelSize = float2(0.00125,0.00166);

float sTexBlend = 1;

//--------------------------------------------------------------------------------------
// Textures
//--------------------------------------------------------------------------------------
texture colorRT;
texture normalRT;

//--------------------------------------------------------------------------------------
// Variables set by MTA
//--------------------------------------------------------------------------------------
texture gDepthBuffer : DEPTHBUFFER;
float4x4 gProjection : PROJECTION;
float4x4 gView : VIEW;
float4x4 gViewInverse : VIEWINVERSE;
int gFogEnable < string renderState="FOGENABLE"; >;
float4 gFogColor < string renderState="FOGCOLOR"; >;
float gFogStart < string renderState="FOGSTART"; >;
float gFogEnd < string renderState="FOGEND"; >;
static const float PI = 3.14159265f;
int CUSTOMFLAGS < string skipUnusedParameters = "yes"; >;

//--------------------------------------------------------------------------------------
// Sampler 
//--------------------------------------------------------------------------------------
sampler SamplerDepth = sampler_state
{
    Texture = (gDepthBuffer);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    MaxMipLevel = 0;
    MipMapLodBias = 0;
};

sampler SamplerColor = sampler_state
{
    Texture = (colorRT);
    AddressU = Mirror;
    AddressV = Mirror;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = None;
    MaxMipLevel = 0;
    MipMapLodBias = 0;
};

sampler SamplerNormal = sampler_state
{
    Texture = (normalRT);
    AddressU = Clamp;
    AddressV = Clamp;
    MinFilter = Point;
    MagFilter = Point;
    MipFilter = None;
    MaxMipLevel = 0;
    MipMapLodBias = 0;
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
    float2 TexCoord : TEXCOORD0;
    float DistFade : TEXCOORD1;
    float4 ProjCoord : TEXCOORD2;
    float3 WorldPos : TEXCOORD3;
    float4 UvToView : TEXCOORD4;
    float4 Diffuse : COLOR0;
};

//--------------------------------------------------------------------------------------
// Create world matrix with world position and euler rotation
//--------------------------------------------------------------------------------------
float4x4 createWorldMatrix(float3 pos, float3 rot)
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
//-- Use the last scene projecion matrix to transform linear depth to logarithmic
//--------------------------------------------------------------------------------------
float InvLinearize(float posZ)
{
    return (gProjection[3][2] / posZ) + gProjection[2][2];
}

//--------------------------------------------------------------------------------------
// Vertex Shader 
//--------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
	
    // scale the sphere
    if (sLightBillboard == false) 
    {
        // correct radius depending on tesselation
        float sphRadius = 1 / cos(0.523598775);
	
        // shape the sphere
        VS.Position.xyz = VS.Position.xyz * length(2 * sLightAttenuation * sphRadius);
    }
    else VS.Position.xy *= sLightAttenuation * 2.5; 

    // flip texCoords.x
    VS.TexCoord.x = 1 - VS.TexCoord.x;

    // create WorldMatrix for the quad
    float4x4 sWorld = createWorldMatrix(sLightPosition, float3(0,0,0));
	
    // get clip planes
    float nearClip = - gProjection[3][2] / gProjection[2][2];
    float farClip = gProjection[3][2] / (1 - gProjection[2][2]);
	
    // set altered projection matrix to prevent clipping parts of the material when small farClipDistance
    float4x4 sProjection = gProjection;
    float objDist = distance(gViewInverse[3].xyz, sLightPosition) + sLightAttenuation / 2;
    float farPlaneAlt = max(farClip, objDist);
    sProjection[2].z = farPlaneAlt/(farPlaneAlt - nearClip);
    sProjection[3].z =  - sProjection[2].z * nearClip;
	
    // calculate screen position of the vertex
    float4 wPos = mul(float4( VS.Position, 1), sWorld);
	
    float4 vPos = 0;
    float4x4 sWorldView = mul(sWorld, gView);
    if (sLightBillboard == false) vPos = mul(wPos, gView);
       else vPos = float4(VS.Position.xyz + sWorldView[3].xyz, 1);
    PS.Position = mul(vPos, gProjection);
	
    if (sLightBillboard == true)
    {
        float depthBias = max(0, InvLinearize(vPos.z) - InvLinearize(vPos.z - 2 * sLightAttenuation));
        PS.Position.z -= depthBias * PS.Position.w;
    }
	
    // fade object
    float DistFromCam = vPos.z / vPos.w;
    float2 DistFade = float2(max(0.3, min(gDistFade.x, farClip ) - sLightAttenuation * 0.5), max(0, min(gDistFade.y, gFogStart) - sLightAttenuation * 0.5));
    PS.DistFade = saturate((DistFromCam - DistFade.x)/(DistFade.y - DistFade.x));

    // pass texCoords and vertex color to PS
    PS.TexCoord = VS.TexCoord;
    PS.Diffuse =  sLightColor;
	
    // set texCoords for projective texture
    float projectedX = (0.5 * (PS.Position.w + PS.Position.x));
    float projectedY = (0.5 * (PS.Position.w - PS.Position.y));
    PS.ProjCoord.xyz = float3(projectedX, projectedY, PS.Position.w);

    // Get distance from plane
    PS.ProjCoord.w = dot(gViewInverse[2].xyz, sLightPosition - gViewInverse[3].xyz) + 2 * sLightAttenuation;
	
    // calculations for perspective-correct position recontruction
    float2 uvToViewADD = - 1 / float2(gProjection[0][0], gProjection[1][1]);	
    float2 uvToViewMUL = -2.0 * uvToViewADD.xy;
    PS.UvToView = float4(uvToViewMUL, uvToViewADD);
	
    return PS;
}

PSInput VertexShaderFunctionNoDB(VSInput VS)
{
    PSInput PS = (PSInput)0;
	
    // set proper size to the quad
    VS.Position.xy *= sLightAttenuation * 2.5;
	
    // flip texCoords.x
    VS.TexCoord.x = 1 - VS.TexCoord.x;

    // create WorldMatrix for the quad
    float4x4 sWorld = createWorldMatrix(sLightPosition, float3(0,0,0));
	
    // calculate screen position of the vertex
    float4x4 sWorldView = mul(sWorld, gView);
    float4 vPos = float4(VS.Position.xyz + sWorldView[3].xyz, 1);
    PS.WorldPos = VS.Position.xyz + sWorld[3].xyz;	
    PS.Position = mul(float4(vPos.xyz, 1), gProjection);

    // get clip values
    float nearClip = - gProjection[3][2] / gProjection[2][2];
    float farClip = (gProjection[3][2] / (1 - gProjection[2][2]));	
	
    // fade object
    float DistFromCam = vPos.z / vPos.w;
    float2 DistFade = float2(max(0.3, min(gDistFade.x, farClip ) - sLightAttenuation * 0.5), max(0, min(gDistFade.y, gFogStart) - sLightAttenuation * 0.5));
    PS.DistFade = saturate((DistFromCam - DistFade.x)/(DistFade.y - DistFade.x));

    // pass texCoords and vertex color to PS
    PS.TexCoord = VS.TexCoord;
    PS.Diffuse =  sLightColor;
	
    return PS;
}

//--------------------------------------------------------------------------------------
//-- Get value from the depth buffer
//-- Uses define set at compile time to handle RAWZ special case (which will use up a few more slots)
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
//-- Use the last scene projecion matrix to linearize the depth value a bit more
//--------------------------------------------------------------------------------------
float Linearize(float posZ)
{
    return gProjection[3][2] / (posZ - gProjection[2][2]);
}

//--------------------------------------------------------------------------------------
// GetPositionFromDepth
//--------------------------------------------------------------------------------------
float3 GetPositionFromDepth(float2 coords, float4 uvToView)
{
    return float3(coords.x * uvToView.x + uvToView.z, (1 - coords.y) * uvToView.y + uvToView.w, 1.0) 
        * Linearize(FetchDepthBufferValue(coords.xy));
}

//--------------------------------------------------------------------------------------
// GetPositionFromDepthMatrix
//--------------------------------------------------------------------------------------
float3 GetPositionFromDepthMatrix(float2 coords, float4x4 g_matInvProjection)
{
    float4 vProjectedPos = float4(coords.x * 2 - 1, (1 - coords.y) * 2 - 1, FetchDepthBufferValue(coords), 1.0f);
    float4 vPositionVS = mul(vProjectedPos, g_matInvProjection);  
    return vPositionVS.xyz / vPositionVS.w;  
}

//--------------------------------------------------------------------------------------
// More accurate than GetNormalFromDepth
//--------------------------------------------------------------------------------------
float3 GetNormalFromDepthMatrix(float2 coords, float4x4 g_matInvProjection)
{
    float3 offs = float3(sPixelSize.xy, 0);

    float3 f = GetPositionFromDepthMatrix(coords.xy, g_matInvProjection);
    float3 d_dx1 = - f + GetPositionFromDepthMatrix(coords.xy + offs.xz, g_matInvProjection);
    float3 d_dx2 =   f - GetPositionFromDepthMatrix(coords.xy - offs.xz, g_matInvProjection);
    float3 d_dy1 = - f + GetPositionFromDepthMatrix(coords.xy + offs.zy, g_matInvProjection);
    float3 d_dy2 =   f - GetPositionFromDepthMatrix(coords.xy - offs.zy, g_matInvProjection);

    d_dx1 = lerp(d_dx1, d_dx2, abs(d_dx1.z) > abs(d_dx2.z));
    d_dy1 = lerp(d_dy1, d_dy2, abs(d_dy1.z) > abs(d_dy2.z));

    return (- normalize(cross(d_dy1, d_dx1)));
}

//--------------------------------------------------------------------------------------
//  Calculates normals based on partial depth buffer derivatives.
//--------------------------------------------------------------------------------------
float3 GetNormalFromDepth(float2 coords, float4 uvToView)
{
    float3 offs = float3(sPixelSize.xy, 0);

    float3 f = GetPositionFromDepth(coords.xy, uvToView);
    float3 d_dx1 = - f + GetPositionFromDepth(coords.xy + offs.xz, uvToView);
    float3 d_dx2 =   f - GetPositionFromDepth(coords.xy - offs.xz, uvToView);
    float3 d_dy1 = - f + GetPositionFromDepth(coords.xy + offs.zy, uvToView);
    float3 d_dy2 =   f - GetPositionFromDepth(coords.xy - offs.zy, uvToView);

    d_dx1 = lerp(d_dx1, d_dx2, abs(d_dx1.z) > abs(d_dx2.z));
    d_dy1 = lerp(d_dy1, d_dy2, abs(d_dy1.z) > abs(d_dy2.z));

    return (- normalize(cross(d_dy1, d_dx1)));
}

//--------------------------------------------------------------------------------------
// Pixel shaders 
//--------------------------------------------------------------------------------------
float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // get projective texture coords
    float2 TexProj = PS.ProjCoord.xy / PS.ProjCoord.z;
    TexProj += sHalfPixel.xy;
	
    // get logarithmic and linear scene depth
    float bufferValue = FetchDepthBufferValue(TexProj);
    float linearDepth = Linearize(bufferValue);
	
    // disregard calculations when depth value is close to 1 and beyound light radius
    if (bufferValue > 0.99999f) return 0;
    if ((linearDepth - PS.ProjCoord.w) > 0) return 0;
	
    // retrieve world position from scene depth
    float3 viewPos = GetPositionFromDepth(TexProj.xy, PS.UvToView);
    float3 worldPos = mul(float4(viewPos.xyz, 1),  gViewInverse).xyz;
	
    // get world normal from normalRT
    float3 texNormal = tex2D(SamplerNormal, TexProj.xy).xyz;
    
    float3 worldNormal = float3((texNormal.xy - 0.5) * 2, 0);
    worldNormal.z =  1 - length(worldNormal.xy);
    worldNormal.z = fmod(texNormal.z, 0.2) > 0.1 ? worldNormal.z : -worldNormal.z;
	
    worldNormal = normalize(worldNormal);		
	
    // compute the distance attenuation factor
    float fDistance = distance(sLightPosition, worldPos);
	
    // compute the direction to the light
    float3 vLight = normalize(sLightPosition - worldPos);
	
    // compute the attenuation
    float fAttenuation = 1 - saturate(fDistance / sLightAttenuation);
    fAttenuation = pow(fAttenuation, sLightAttenuationPower);

    // compute NdotL
    float NdotL = 1;
    if (texNormal.z > 0.5999f) NdotL = saturate(max(0.0f, dot( worldNormal , vLight)));
	
    // get texture color from colorRT
    float4 texColor = tex2D(SamplerColor, TexProj.xy);
    texColor.rgb = texColor.rgb * sTexBlend + (1 - sTexBlend);
    texColor.rgb *= texColor.a;
	
    // apply diffuse color
    float4 finalColor = texColor * PS.Diffuse;
	
    // apply attenuation
    finalColor.rgb *= saturate(fAttenuation);
    if (gUseNormals) finalColor.rgb *=  NdotL;
	
    // apply distance fade
    finalColor.a *= saturate(PS.DistFade);
	
    return saturate(finalColor);
}

float4 PixelShaderFunctionNoDB(PSInput PS) : COLOR0
{
    // compute the distance attenuation factor
    float fDistance = distance(sLightPosition, PS.WorldPos);

    // compute the attenuation
    float fAttenuation = 1 - saturate(fDistance / sLightAttenuation);
    fAttenuation = pow(fAttenuation, sLightAttenuationPower);
	
    // apply diffuse color
    float4 finalColor = PS.Diffuse;
	
    // apply attenuation
    finalColor.rgb *= saturate(fAttenuation);
	
    // apply distance fade
    finalColor.a *= saturate(PS.DistFade);

    return saturate(finalColor);
}

float4 PixelShaderFunction1(PSInput PS) : COLOR0
{
    // apply diffuse color
    float4 finalColor = PS.Diffuse;

    return saturate(finalColor);
}

//--------------------------------------------------------------------------------------
// Choose CullMode
//--------------------------------------------------------------------------------------
int ChooseCullMode()
{
    if (sLightBillboard == false) 
    {
        if ((length(gViewInverse[3].xyz - sLightPosition) - sLightAttenuation * 1.5) < 0) return 3;
        else return 2;
    }
    else return 2;
}

//--------------------------------------------------------------------------------------
// Choose ZEnable
//--------------------------------------------------------------------------------------
bool ChooseZEnable()
{
    if ((length(gViewInverse[3].xyz - sLightPosition) - sLightAttenuation * 2) < 0) return false;
    else return true;
}

//--------------------------------------------------------------------------------------
// Techniques
//--------------------------------------------------------------------------------------
technique dxDrawPrimitive3DPointLight
{
  pass P0
  {
    ZEnable = ChooseZEnable();
    ZWriteEnable = false;
    CullMode = ChooseCullMode();
    ShadeMode = Gouraud;
    AlphaBlendEnable = true;
    SrcBlend = SrcAlpha;
    DestBlend = One;
    AlphaTestEnable = true;
    AlphaRef = 1;
    AlphaFunc = GreaterEqual;
    Lighting = false;
    FogEnable = false;
    VertexShader = compile vs_3_0 VertexShaderFunction();
    PixelShader  = compile ps_3_0 PixelShaderFunction();
  }
/*
  pass P1
  {
    ZEnable = ChooseZEnable();
    ZWriteEnable = false;
    CullMode = ChooseCullMode();
    ShadeMode = Gouraud;
    AlphaBlendEnable = true;
    SrcBlend = SrcAlpha;
    DestBlend = One;
    AlphaTestEnable = true;
    AlphaRef = 1;
    AlphaFunc = GreaterEqual;
    Lighting = false;
    FogEnable = false;
	FillMode = 2;
    VertexShader = compile vs_3_0 VertexShaderFunction();
    PixelShader  = compile ps_3_0 PixelShaderFunction1();
  }
*/
}

technique dxDrawPrimitive3DPointLight_fallback
{
  pass P0
  {
    ZEnable = true;
    ZFunc = LessEqual;
    ZWriteEnable = false;
    CullMode = 2;
    ShadeMode = Gouraud;
    AlphaBlendEnable = true;
    SrcBlend = SrcAlpha;
    DestBlend = One;
    AlphaTestEnable = true;
    AlphaRef = 1;
    AlphaFunc = GreaterEqual;
    Lighting = false;
    FogEnable = false;
    VertexShader = compile vs_2_0 VertexShaderFunctionNoDB();
    PixelShader  = compile ps_2_0 PixelShaderFunctionNoDB();
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
