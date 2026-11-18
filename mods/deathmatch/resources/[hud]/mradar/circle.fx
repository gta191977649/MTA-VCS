
float fInnerRadius = 0.0;
float fOuterRadius = 0.5;
float fInnerFading = 0.005;
float fOuterFading = 0.005;

struct PSInput {
	float4 Diffuse : COLOR0;
	float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR {

	float len = length(PS.TexCoord.xy - 0.5);

	float ik = smoothstep(0, 1, (len - fInnerRadius + fInnerFading) / fInnerFading);
    float ok = smoothstep(0, 1, (fOuterRadius - len) / fOuterFading);

	return float4(PS.Diffuse.rgb, PS.Diffuse.a * min(ik, ok));
}

technique circle {
	pass P0 {
		PixelShader = compile ps_2_0 PixelShaderFunction();
	}
}