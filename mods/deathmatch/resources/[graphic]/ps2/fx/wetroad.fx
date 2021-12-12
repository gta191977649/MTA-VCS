// wet roads
// by ren712, ccw, Sam@ke

#define GENERATE_NORMALS   
#include "mta-helper.fx"

float TextureSize = 2048.0; // higher amount gets better result in bump results
float bumpFactor = 0;
float shiftXValue = 0;
float shiftYValue = -0.03;
float zoomXValue = 1;
float zoomYValue = 0.8;
float reflectionStrength = 10;
float diffuseFactor = 1;

bool specularsEnabled = true;
float3 lightDirection = float3(500, -500, 450);
float3 sunColor = float3(0.95, 0.85, 0.8);
float specularPower = 1;
float specularBrightness = 1;
float specularStrength = 2;
float fadeStart = 10;
float fadeEnd = 65;
float wetLevel = 0.1;

texture screenSource;

sampler2D MainSampler = sampler_state{
    Texture = (gTexture0);
    AddressU = Wrap;
    AddressV = Wrap;
    AddressW = Wrap;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};


sampler2D ReflectionSampler = sampler_state{
    Texture = (screenSource);
    AddressU = Mirror;
    AddressV = Mirror;
    AddressW = Mirror;
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
};



// The Sobel filter extracts the first order derivates of the image,
// that is, the slope. The slope in X and Y directon allows us to
// given a heightmap evaluate the normal for each pixel. This is
// the same this as ATI's NormalMapGenerator application does,
// except this is in hardware.
//
// These are the filter kernels:
//
//  SobelX       SobelY
//  1  0 -1      1  2  1
//  2  0 -2      0  0  0
//  1  0 -1     -1 -2 -1

float3 calculateTextureNormals(float2 TexCoords, float4 color) {
   float off = 1.0 / TextureSize;

   // Take all neighbor samples
   float4 s00 = tex2D(MainSampler, TexCoords + float2(-off, -off));
   float4 s01 = tex2D(MainSampler, TexCoords + float2( 0,   -off));
   float4 s02 = tex2D(MainSampler, TexCoords + float2( off, -off));

   float4 s10 = tex2D(MainSampler, TexCoords + float2(-off,  0));
   float4 s12 = tex2D(MainSampler, TexCoords + float2( off,  0));

   float4 s20 = tex2D(MainSampler, TexCoords + float2(-off,  off));
   float4 s21 = tex2D(MainSampler, TexCoords + float2( 0,    off));
   float4 s22 = tex2D(MainSampler, TexCoords + float2( off,  off));

   // Slope in X direction
   float4 sobelX = s00 + 2 * s10 + s20 - s02 - 2 * s12 - s22;
   // Slope in Y direction
   float4 sobelY = s00 + 2 * s01 + s02 - s20 - 2 * s21 - s22;

   // Weight the slope in all channels, we use grayscale as height
   float sx = dot(sobelX, color);
   float sy = dot(sobelY, color);

   // Compose the normal
   float3 normal = normalize(float3(sx, sy, 1));

   // Pack [-1, 1] into [0, 1]
   return float3(normal * 0.5 + 0.5);
}


float4 calculateLuminance(float4 color) {
    float lum = (color.r + color.g + color.b) / 3;
    float adj = saturate(lum - 0.1);
    adj = adj / (1.01 - 0.3);
    color = color * adj;
    color += 0.17;
	color.rgb *= 1 + gCameraDirection.z;
	
	return color;
}


float3 getReflectionBumpCoords(float3 coords, float3 normals, float3 tangent, float3 binormal, float factor) {
	float3 newCoords = float3((coords.xy / coords.z), 0) ;
	newCoords += (normals.x * tangent + normals.y * binormal);	
	newCoords.xy += float2(shiftXValue * factor, shiftYValue * factor);
    newCoords.xy *= float2(zoomXValue, zoomYValue);
	
	return newCoords;
}


float2 fixReflectionCoords(float2 coords) {
	if (gCameraDirection.z < 0.1) {
		coords.y = 1 - coords.y;
		coords.y -= 0.2;
		coords.y += gCameraDirection.z * 2;
	} else {
		coords.y -= gCameraDirection.z * 2;
		coords.y += 0.2;
	}
	
	return coords;
}


float2 getFakeLightDot(float3 normals) {
	float3 fakeLightDir = normalize(float3(1.0f, 1.0, 0.8f));   
    fakeLightDir.xy = gCameraDirection.xy;
	
	return dot(normals, fakeLightDir);
}


float3 addSpecularLight(float3 normal, float3 normalWorld, float3 lightDir, float3 worldPos, float specul, float intensity, float distance) {
    float3 h = normalize(normalize(gCameraPosition - worldPos) - lightDir);
    float specLighting = pow(saturate(dot(h, normal)), specul);

    float lightAwayDot = -dot(normalize(lightDir), normalWorld);
	
    if (lightAwayDot < 0) specLighting = 0;
		
	return saturate(specLighting) * saturate(distance) * intensity * 0.07; 
}


struct VertexShaderinput {
    float4 Position : POSITION0;
    float4 Color : COLOR0;
    float2 TexCoords : TEXCOORD0;
    float3 Normal : NORMAL0; 
};


struct VertexShaderOutput {
    float4 Position : POSITION0;
    float2 TexCoords : TEXCOORD0;
    float3 TexCoords_proj : TEXCOORD1;
    float4 Diffuse: TEXCOORD3;
    float DistFade: TEXCOORD4;
    float3 Normal : TEXCOORD2;
    float3 Binormal : TEXCOORD5;
    float3 Tangent : TEXCOORD6;
	float3 worldPosition : TEXCOORD7;
	float2 WorldCoords : TEXCOORD8;
};

//-----------------------------------------------------------------------------
//	VertexShader
//-----------------------------------------------------------------------------

VertexShaderOutput VertexShaderFunction(VertexShaderinput input) {
	VertexShaderOutput output;
	
	MTAFixUpNormal(input.Normal);
   
    output.Position = mul(input.Position, gWorldViewProjection);
    output.TexCoords = input.TexCoords;
    output.worldPosition = mul(float4(input.Position.xyz,1), gWorld).xyz;
  
    float4 Po = float4(input.Position.xyz,1.0);
    float4 pPos = mul(Po, gWorldViewProjection); 

    output.TexCoords_proj.x = 0.5 * (pPos.w + pPos.x);
    output.TexCoords_proj.y = 0.5 * (pPos.w - pPos.y);
    output.TexCoords_proj.z = pPos.w;
	
    // Fake tangent and binormal
    float3 Tangent = input.Normal.yxz;
    Tangent.xz = input.TexCoords.xy;
    float3 Binormal = normalize( cross(Tangent, input.Normal) );
    Tangent = normalize( cross(Binormal, input.Normal) );
    // first rows are the tangent and binormal scaled by the bump scale
	
    output.Tangent = normalize(mul(Tangent, gWorldInverseTranspose).xyz);
    output.Binormal = normalize(mul(Binormal, gWorldInverseTranspose).xyz);
    output.Normal = normalize( mul(input.Normal, (float3x3)gWorld) );
	
    float DistanceFromCamera = MTACalcCameraDistance( gCameraPosition, output.worldPosition );
    output.DistFade = MTAUnlerp(fadeEnd, fadeStart, DistanceFromCamera);
	
    output.Diffuse = MTACalcGTABuildingDiffuse( input.Color );
	output.WorldCoords = output.worldPosition.xy / 150;

    return output;
}

//-----------------------------------------------------------------------------
//	PixelShader
//-----------------------------------------------------------------------------

float4 PixelShaderFunction(VertexShaderOutput input) : COLOR0 {
	float4 mainColor = tex2D(MainSampler, input.TexCoords) * input.Diffuse;
	
	// ********************* COLOR WET ROADS **********************//
    float3 bumpNormals = calculateTextureNormals(input.TexCoords, mainColor) * 2.0 - 1.0;
	float newBumFactor = bumpFactor * 1.5;
    bumpNormals = normalize(float3(bumpNormals.x * newBumFactor, bumpNormals.y * newBumFactor, bumpNormals.z)); 

    float fakeLightRoads = getFakeLightDot(bumpNormals); 
	
    float3 reflectionCoordsWetRoad = getReflectionBumpCoords(input.TexCoords_proj, bumpNormals, input.Tangent, input.Binormal, 1);
    float4 wetRoadColorBase = tex2D(ReflectionSampler, fixReflectionCoords(reflectionCoordsWetRoad)) * (reflectionStrength) * 0.4;
	
	wetRoadColorBase = calculateLuminance(wetRoadColorBase);
	
	float4 wetRoadAmbient = saturate((mainColor) / 1.3); 
    float4 wetRoadDiffuse = (input.Diffuse * wetRoadColorBase) * diffuseFactor;

    float4 wetRoadColor = saturate(wetRoadAmbient * fakeLightRoads) + saturate(input.DistFade) * wetRoadDiffuse;  
	wetRoadColor.a = mainColor.a;
	// ********************* COLOR WET ROADS **********************//
	
	
	// ********************* Speculars  **********************//

    float3 specLighting = addSpecularLight(bumpNormals, input.Normal, lightDirection, input.worldPosition.xyz, specularPower, specularStrength, input.DistFade);
	// ********************* Speculars **********************//

	wetRoadColor.rgb += (specLighting * 1.5) * wetRoadColor.g * wetRoadColor.g;
	mainColor.rgb += (specLighting / 1.5) * mainColor.g * mainColor.g;
	
	float4 finalColor = (wetRoadColor * wetLevel) + (mainColor * (1 - wetLevel));
	
    return finalColor;
}


technique wetRoads {
	pass P0 {
		AlphaBlendEnable = false;
		AlphaRef = 1;
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader = compile ps_3_0 PixelShaderFunction();
	}
}

technique fallback {
    pass P0 {
	
    }
}
