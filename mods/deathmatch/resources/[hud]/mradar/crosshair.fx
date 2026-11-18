
texture gTexture;
float2 fViewportRatio;

sampler Sampler0 = sampler_state {
	Texture = (gTexture);
    MipMapLodBias = -1;
};

struct PSInput {
	float4 Diffuse : COLOR0;
	float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR {

	return saturate(tex2D(Sampler0, (PS.TexCoord - 1) * fViewportRatio + 1) * PS.Diffuse);
}

technique crosshair {
	pass P0 {
		PixelShader = compile ps_2_0 PixelShaderFunction();
	}
}