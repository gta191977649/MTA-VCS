#define GENERATE_NORMALS
#include "mta-helper.fx"

float3 sunPos = float3(1, 0, 0);
float4 sunColor = float4(1, 1, 1, 1);
float4 ambientColor = float4(1, 1, 1, 1);
float textureSize = 256.0;
float bias = -0.0002;

float ambientIntensity = 1.0;
float shadowStrength = 0.7;
float specularSize = 32;
float lightShiningPower = 0.4;
float normalStrength = 1;
float bumpMapFactor = 0.2;


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
	float lightIntensity : TEXCOORD6;
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
	float4 carColor = MTACalcGTAVehicleDiffuse2(output.worldNormal, smwColor, output.lightDirection);
	
	float4 dynamicLightColor = (smwColor + float4(shadowStrength, shadowStrength, shadowStrength, 1)) / 2;
	output.Color = carColor * dynamicLightColor;

    return output;
}

float4 PixelShaderFunction(VertexShaderOutput input) : COLOR0
{
	
	float4 mainColor = tex2D(MainSampler, input.TexCoord);
	float4 shadowBrightness = saturate(input.Color);
	
	float3 normalMap = bumpMapFactor * MTACalcNormalMap(MainSampler, input.TexCoord.xy, mainColor, textureSize) - bumpMapFactor / 2;  
    normalMap = normalize(normalMap.x * input.Tangent + normalMap.y * input.Binormal + input.worldNormal);
	
	float4 specularLight1 = MTACalculateSpecular(gCameraPosition, input.lightDirection, normalMap, specularSize);
	specularLight1 *= mainColor;
	float4 specularLight2 = specularLight1 * mainColor.g * mainColor.g;
	float4 finalSpecular = (specularLight1 / 2 + specularLight2 * 2) / 2;
	finalSpecular.rgb *= sunColor.rgb;
	
	float lightAwayDot = -dot(input.lightDirection, input.worldNormal);
	
	float4 dynamicLightColor = mainColor * shadowBrightness;
	    
	if (lightAwayDot < bias) finalSpecular = finalSpecular / 8;
		
	dynamicLightColor.rgb *= ambientColor.rgb * ambientIntensity;
	dynamicLightColor.rgb += finalSpecular.rgb * lightShiningPower;
	
	dynamicLightColor.rgb *= 2;
	
    return dynamicLightColor;
}

technique DynamicLightVehicle
{
    pass Pass0
    {
		AlphaBlendEnable = TRUE;
        AlphaRef = 1;
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