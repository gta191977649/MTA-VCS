
texture gTexture;

sampler Sampler0 = sampler_state {
	Texture = (gTexture);
	AddressU = Border;
	AddressV = Border;
	BorderColor = 0;
	MinFilter = Linear;
	MagFilter = Linear;
};

struct PSInput {
	float4 Diffuse : COLOR0;
	float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR {
	// GTA draws four mirrored quads. Their UV direction identifies the
	// quadrant of the complete PS2 sprite that belongs in each quad.
	float2 slope = float2(ddx(PS.TexCoord.x), ddy(PS.TexCoord.y));
	float2 uv = PS.TexCoord - 1.0 / 1024.0;
	float2 distanceFromCenter = (uv - 1.0) * 0.5 * sign(slope);
	float2 texelsPerPixel = max(abs(slope), 0.00001);
	float2 aspect = max(texelsPerPixel.x, texelsPerPixel.y) / texelsPerPixel;
	return saturate(tex2D(Sampler0, 0.5 + distanceFromCenter * aspect) * PS.Diffuse);
}

technique crosshair {
	pass P0 {
		PixelShader = compile ps_3_0 PixelShaderFunction();
	}
}
