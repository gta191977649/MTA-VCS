#define GENERATE_NORMALS
#include "mta-helper.fx"

float3 sunPos = float3(1, 0, 0);
float4 sunColor = float4(1, 1, 1, 1);
float4 ambientColor = float4(1, 1, 1, 1);
float textureSize = 128.0;
float bias = -0.0002;

float ambientIntensity = 1.0;
float shadowStrength = 0.7;
float specularSize = 6;
float lightShiningPower = 1;
float normalStrength = 1;
float bumpMapFactor = 1.2;
float specularIntensity = 1;
float specularFadeStart = 30;
float specularFadeEnd = 150;
float fogStart = 90;
float fogEnd = 900;


sampler MainSampler = sampler_state
{
    Texture = (gTexture0);
};

struct VertexShaderInput
{
	float3 Position : POSITION0;
	float4 Color : COLOR0;
	float3 Normal : NORMAL0;
	float2 TexCoord : TEXCOORD0;
};

struct VertexShaderOutput
{
	float4 Position : POSITION0;
	float4 Color : COLOR0;
	float2 TexCoord : TEXCOORD0;
	float3 worldPosition : TEXCOORD1;
	float3 worldNormal : TEXCOORD2;
	float3 lightDirection : TEXCOORD3;
	float3 Binormal : TEXCOORD4;
	float3 Tangent : TEXCOORD5;
	float DistFade : TEXCOORD6;
	float lightIntensity : TEXCOORD7;
	float Depth : TEXCOORD8;
};

VertexShaderOutput VertexShaderFunction(VertexShaderInput input)
{
    VertexShaderOutput output;
	
    MTAFixUpNormal(input.Normal);

    output.Position = MTACalcScreenPosition(input.Position);
	output.worldNormal = MTACalcWorldNormal(input.Normal);
	output.worldPosition = MTACalcWorldPosition(input.Position);
	output.lightDirection = normalize(gCameraPosition - sunPos);
	
    float3 Tangent = input.Normal.yxz;
    Tangent.xz = input.TexCoord.xy;
    float3 Binormal = normalize(cross(Tangent, input.Normal));
    Tangent = normalize(cross(Binormal, input.Normal));

	output.Tangent = normalize(mul(Tangent, gWorldInverseTranspose).xyz);
    output.Binormal = normalize(mul(Binormal, gWorldInverseTranspose).xyz);

    output.lightIntensity = dot(output.worldNormal, -output.lightDirection);
	
	output.TexCoord = input.TexCoord;
	float4 originalColor = float4(input.Color.rgb, 1);
	float4 smwColor = float4(sunColor.rgb * output.lightIntensity, 1);
	output.Color = (smwColor + float4(shadowStrength, shadowStrength, shadowStrength, 1)) / 2;
	
    float DistanceFromCamera = MTACalcCameraDistance(gCameraPosition, output.worldPosition);
    output.DistFade = MTAUnlerp(specularFadeEnd, specularFadeStart, DistanceFromCamera);
	
	output.Depth = output.Position.z;

    return output;
}

float4 PixelShaderFunction(VertexShaderOutput input) : COLOR0
{
	
	float4 mainColor = tex2D(MainSampler, input.TexCoord);
	float4 shadowBrightness = saturate(input.Color);
	
	float3 normalMap = bumpMapFactor * MTACalcNormalMap(MainSampler, input.TexCoord.xy, mainColor, textureSize) - bumpMapFactor / 2;  
    normalMap = normalize(normalMap.x * input.Tangent + normalMap.y * input.Binormal + input.worldNormal);
	
    float3 lightRange1 = normalize(normalize(gCameraPosition - input.worldPosition) - input.lightDirection);
    float specularLight1 = pow(saturate(dot(lightRange1, input.worldNormal)), specularSize * 2) / 2;
	float4 specularColor1 = float4(sunColor.rgb * specularLight1, 1);
	specularColor1.rgb += pow(saturate(dot(lightRange1, normalMap)), specularSize / 2);
	specularColor1.rgb *= mainColor.g;
	specularColor1.rgb *= specularIntensity;
	
	float3 lightRange2 = normalize(normalize(gCameraPosition - input.worldPosition) - gLightDirection);
    float specularLight2 = pow(saturate(dot(lightRange2, input.worldNormal)), specularSize * 3) / 3;
	float4 specularColor2 = float4(sunColor.rgb * specularLight2, 1);
	specularColor2.rgb += pow(saturate(dot(lightRange2, normalMap)), specularSize / 3);
	specularColor2.rgb *= mainColor.r;
	specularColor2.rgb *= specularIntensity;
	
	float4 finalSpecular = (specularColor1 + specularColor2) / 2;
	finalSpecular *= sunColor;
	
	float lightAwayDot = -dot(input.lightDirection, input.worldNormal);
	
	float4 dynamicLightColor = mainColor * shadowBrightness;
	    
	if (lightAwayDot < bias) finalSpecular = finalSpecular / 8;
		
	dynamicLightColor.rgb *= ambientColor.rgb * ambientIntensity;
	
	float greyNess = MTAGetPixelGreyness(mainColor);
	dynamicLightColor.rgb += finalSpecular.rgb * greyNess * lightShiningPower * saturate(input.DistFade);
	
	float distanceFog = saturate((input.Depth - fogStart)/(fogEnd - fogStart));
	float4 finalColor = float4(lerp(dynamicLightColor.rgb, dynamicLightColor.rgb / 2, distanceFog), dynamicLightColor.a);
	
    return finalColor;
}

technique DynamicLight
{
    pass Pass0
    {
		AlphaBlendEnable = TRUE;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
    }
}

// Fallback
technique Fallback
{
    pass P0
    {
        // Just draw normally
    }
}