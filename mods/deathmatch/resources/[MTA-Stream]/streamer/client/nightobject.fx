sampler Sampler0 = sampler_state
{
    Texture = (gTexture0);
};

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
	return float4(1,0,0,1) ;
}
technique worldfiff
{
    pass P0
    {
        //VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader  = compile ps_2_0 PixelShaderFunction();
    }
}
