// 
// file: primitive3D_projectedTexture2vec.fx
// version: v1.6
// author: Ren712
//

//--------------------------------------------------------------------------------------
// Settings
//--------------------------------------------------------------------------------------
texture sTexture;
float4 sLightColor = float4(0,0,0,0);
bool sLightBillboard = false;
float3 sLightPosition = float3(0,0,0);
float3 sLightPositionOffset = float3(0,0,0);
float sLightAttenuation = 1;
float sLightNearClip = 0;
float2 sPicSize = float2(1,1);
float sLightAttenuationPowerFw = 2;
float sLightAttenuationPowerBk = 2;
float3 sLightUp = float3(0,0,1);
float3 sLightForward = float3(0,1,0);

float2 gDistFade = float2(250,150);

float2 sHalfPixel = float2(0.000625,0.00083);
float2 sPixelSize = float2(0.00125,0.00166);

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
int gCapsMaxAnisotropy < string deviceCaps="MaxAnisotropy"; >;
int CUSTOMFLAGS < string skipUnusedParameters = "yes"; >;

//--------------------------------------------------------------------------------------
// Sampler 
//--------------------------------------------------------------------------------------
sampler SamplerTexture = sampler_state
{
    Texture = (sTexture);
    AddressU = Border;
    AddressV = Border;
    MipFilter = Linear;
    MaxAnisotropy = gCapsMaxAnisotropy;
    MinFilter = Anisotropic;
    BorderColor = float4(0,0,0,0);
};

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
    float3 LightPosition : TEXCOORD5;
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
// Create world matrix with world position and euler rotation
//--------------------------------------------------------------------------------------
float4x4 createWorldMatrixVec( float3 pos, float3 fwVec, float3 upVec )
{
    float3 zaxis = normalize( fwVec );    // The "forward" vector.
    float3 xaxis = normalize( cross( -upVec, zaxis ));// The "right" vector.
    float3 yaxis = cross( xaxis, zaxis );     // The "up" vector.
				
    float4x4 eleMatrix = {
        float4(xaxis, 0), float4(yaxis, 0), float4(zaxis, 0), float4(pos.x,pos.y,pos.z, 1),
    };
    return eleMatrix;
}

//--------------------------------------------------------------------------------------
// Create view matrix with world position and euler rotation
//-------------------------------------------------------------------------------------- 
float4x4 createViewMatrixEuler( float3 pos, float3 rot )
{
    float3 zaxis = float3(cos(rot.z) * sin(rot.y) + cos(rot.y) * sin(rot.z) * sin(rot.x), sin(rot.z) * sin(rot.y) - 
                cos(rot.z) * cos(rot.y) * sin(rot.x), cos(rot.x) * cos(rot.y));    // The "forward" vector.
    float3 xaxis = float3(cos(rot.z) * cos(rot.y) - sin(rot.z) * sin(rot.x) * sin(rot.y), 
                cos(rot.y) * sin(rot.z) + cos(rot.z) * sin(rot.x) * sin(rot.y), -cos(rot.x) * sin(rot.y));// The "right" vector.
    float3 yaxis = float3(-cos(rot.x) * sin(rot.z), cos(rot.z) * cos(rot.x), sin(rot.x)); // The "up" vector.

    // Create a 4x4 view matrix from the right, up, forward and eye position vectors
    float4x4 viewMatrix = {
        float4(      xaxis.x,            yaxis.x,            zaxis.x,       0 ),
        float4(      xaxis.y,            yaxis.y,            zaxis.y,       0 ),
        float4(      xaxis.z,            yaxis.z,            zaxis.z,       0 ),
        float4(-dot( xaxis, pos ), -dot( yaxis, pos ), -dot( zaxis, pos ),  1 )
    };
    return viewMatrix;
}

//--------------------------------------------------------------------------------------
// Create view matrix 
//-------------------------------------------------------------------------------------- 
float4x4 createViewMatrixVec( float3 pos, float3 fwVec, float3 upVec )
{
    float3 zaxis = normalize( fwVec );    // The "forward" vector.
    float3 xaxis = normalize( cross( -upVec, zaxis ));// The "right" vector.
    float3 yaxis = cross( xaxis, zaxis );     // The "up" vector.

    // Create a 4x4 view matrix from the right, up, forward and eye position vectors
    float4x4 viewMatrix = {
        float4(      xaxis.x,            yaxis.x,            zaxis.x,       0 ),
        float4(      xaxis.y,            yaxis.y,            zaxis.y,       0 ),
        float4(      xaxis.z,            yaxis.z,            zaxis.z,       0 ),
        float4(-dot( xaxis, pos ), -dot( yaxis, pos ), -dot( zaxis, pos ),  1 )
    };
    return viewMatrix;
}

//--------------------------------------------------------------------------------------
//-- Use the last scene projecion matrix to transform linear depth to logarithmic
//--------------------------------------------------------------------------------------
float InvLinearize(float posZ)
{
    return (gProjection[3][2] / posZ) + gProjection[2][2];
}

//--------------------------------------------------------------------------------------
//-- getPositionFromElementOffset
//--------------------------------------------------------------------------------------
float3 getPositionFromElementOffset(float4x4 thisMatrix,float3 offset)
{
    return float3(offset.x * thisMatrix[0][0] + offset.y * thisMatrix[1][0] + offset.z * thisMatrix[2][0] + thisMatrix[3][0],
        offset.x * thisMatrix[0][1] + offset.y * thisMatrix[1][1] + offset.z * thisMatrix[2][1] + thisMatrix[3][1],
        offset.x * thisMatrix[0][2] + offset.y * thisMatrix[1][2] + offset.z * thisMatrix[2][2] + thisMatrix[3][2]);                     
}

//--------------------------------------------------------------------------------------
// Vertex Shader 
//--------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;
	
	float3 lightPosition = sLightPosition;
	
    float lightAttenuation = max(sLightAttenuation, max(sPicSize.x, sPicSize.y));
	
    // switch between quad/cone	
    if (sLightBillboard == false)
    {
        // get size
        VS.Position.y += 0.5;
        VS.Position.y = saturate(VS.Position.y + sLightNearClip);
        VS.Position.y *= sLightAttenuation;
        VS.Position.xz *= sPicSize;
		VS.Position.xzy = VS.Position.xzy + sLightPositionOffset.xzy;
    }
    else VS.Position.xy *= lightAttenuation * 2.5;

    // flip texCoords.x
    VS.TexCoord.x = 1 - VS.TexCoord.x;

    // create WorldMatrix for the quad
    float4x4 sWorld = createWorldMatrixVec(lightPosition, sLightForward, sLightUp);
    lightPosition = getPositionFromElementOffset(sWorld, sLightPositionOffset);	
	
    // get clip planes
    float nearClip = - gProjection[3][2] / gProjection[2][2];
    float farClip = gProjection[3][2] / (1 - gProjection[2][2]);
	
    // set altered projection matrix to prevent clipping parts of the material when small farClipDistance
    float4x4 sProjection = gProjection;
    float objDist = distance(gViewInverse[3].xyz, lightPosition) + lightAttenuation / 2;
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
        float depthBias = max(0, InvLinearize(vPos.z) - InvLinearize(vPos.z - 2 * lightAttenuation));
        PS.Position.z -= depthBias * PS.Position.w;
    }
	
    // fade object
    float DistFromCam = vPos.z / vPos.w;
    float2 DistFade = float2(max(0.3, min(gDistFade.x, farClip ) - lightAttenuation), max(0, min(gDistFade.y, gFogStart) - lightAttenuation));
    PS.DistFade = saturate((DistFromCam - DistFade.x)/(DistFade.y - DistFade.x));

    // pass texCoords and vertex color to PS
    PS.TexCoord = VS.TexCoord;
    PS.Diffuse =  sLightColor;
	
    // set texCoords for projective texture
    float projectedX = (0.5 * (PS.Position.w + PS.Position.x));
    float projectedY = (0.5 * (PS.Position.w - PS.Position.y));
    PS.ProjCoord.xyz = float3(projectedX, projectedY, PS.Position.w);
	
    // Get distance from plane
    PS.ProjCoord.w = dot(gViewInverse[2].xyz, lightPosition - gViewInverse[3].xyz) + 2 * lightAttenuation;
	
    // calculations for perspective-correct position recontruction
    float2 uvToViewADD = - 1 / float2(gProjection[0][0], gProjection[1][1]);	
    float2 uvToViewMUL = -2.0 * uvToViewADD.xy;
    PS.UvToView = float4(uvToViewMUL, uvToViewADD);
    PS.LightPosition = lightPosition;
	
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
	
	float3 lightPosition = PS.LightPosition;
    float3 lightDir = -normalize(sLightUp);
	
    // get logarithmic and linear scene depth
    float bufferValue = FetchDepthBufferValue(TexProj);
    float linearDepth = Linearize(bufferValue);
	
    // disregard calculations when depth value is close to 1 and beyound light radius
    if (bufferValue > 0.99999f) return 0;
    if ((linearDepth - PS.ProjCoord.w) > 0) return 0;
	
    // retrieve world position from scene depth
    float3 viewPos = GetPositionFromDepth(TexProj.xy, PS.UvToView);
    float3 worldPos = mul(float4(viewPos.xyz, 1),  gViewInverse).xyz;
	
    // recreate world normal from depth
    float3 viewNormal = GetNormalFromDepth(TexProj.xy, PS.UvToView);
    float3 worldNormal = mul(viewNormal, (float3x3)gViewInverse);
	
    // compute the distance from light and surface
    float lightAttenuation = sLightAttenuation * 0.5;
    float3 lightPos = lightPosition - lightDir * (lightAttenuation + lightAttenuation * sLightNearClip);
    float planarDist = dot(lightDir, worldPos.xyz - lightPos);
    float fSDistance = abs(planarDist);
	
    float lightAttenuationPower = planarDist > 0 ? sLightAttenuationPowerFw : sLightAttenuationPowerBk;
	
    // compute the attenuation
    lightAttenuation = lightAttenuation * ( 1 - sLightNearClip);
    float fAttenuation = 1 - saturate(fSDistance / lightAttenuation);
    fAttenuation = pow(fAttenuation, lightAttenuationPower);

    // compute NdotL
    float NdotL = saturate(max(0.0f, dot( worldNormal , lightDir)));

    // apply diffuse color
    float4 finalColor = PS.Diffuse;
	
    // apply attenuation
    finalColor.a *= NdotL * saturate(fAttenuation);
	
    // add projective texture
    float4x4 sProjView = createViewMatrixVec(lightPosition, sLightForward, lightDir);
    float4 projPos = mul(float4(worldPos, 1), sProjView);
	float2 texCoord = projPos.xz;
    texCoord /= sPicSize;
	
    if (abs(texCoord.x) > 0.5f || abs(texCoord.y) > 0.5f) discard;
    texCoord.xy += float2(0.5f, 0.5f);
    texCoord.y = 1.0f - texCoord.y;
	
    float4 texel = tex2D(SamplerTexture, texCoord);
    finalColor *= texel;
	
    // apply distance fade
    finalColor.a *= saturate(PS.DistFade);	

    return saturate(finalColor);
}

float4 PixelShaderFunctionTest(PSInput PS) : COLOR0
{
    return PS.Diffuse;
}

float4 PixelShaderFunctionNoDB(PSInput PS) : COLOR0
{
    return 0;
}

//--------------------------------------------------------------------------------------
// Choose CullMode
//--------------------------------------------------------------------------------------
int ChooseCullMode()
{
    if (sLightBillboard == false) 
    {
        if ((length(gViewInverse[3].xyz - sLightPosition) - max(sLightAttenuation, max(sPicSize.x, sPicSize.y)) * 1.5) < 0) return 2;
        else return 3;
    }
    else return 2;
}

//--------------------------------------------------------------------------------------
// Choose ZEnable
//--------------------------------------------------------------------------------------
bool ChooseZEnable()
{
    if ((length(gViewInverse[3].xyz - sLightPosition) - max(sLightAttenuation, max(sPicSize.x, sPicSize.y)) * 1.5) < 0) return false;
    else return true;
}

//--------------------------------------------------------------------------------------
// Techniques
//--------------------------------------------------------------------------------------
technique dxDrawPrimitive3DProjectedTexture2
{
  pass P0
  {
    ZEnable = ChooseZEnable();
    ZWriteEnable = false;
    CullMode = ChooseCullMode();
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
  
/*
  pass P1
  {
    ZEnable = ChooseZEnable();
    ZWriteEnable = false;
    CullMode = ChooseCullMode();
    ShadeMode = Gouraud;
    AlphaBlendEnable = true;
    SrcBlend = SrcAlpha;
    DestBlend = InvSrcAlpha;
    AlphaTestEnable = true;
    AlphaRef = 1;
    AlphaFunc = GreaterEqual;
    Lighting = false;
    FogEnable = false;
    DepthBias = -0.0001f;
    FillMode = 2;
    VertexShader = compile vs_3_0 VertexShaderFunction();
    PixelShader  = compile ps_3_0 PixelShaderFunctionTest();
  }
  
*/

}

technique dxDrawPrimitive3DProjectedTexture2_fallback
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
