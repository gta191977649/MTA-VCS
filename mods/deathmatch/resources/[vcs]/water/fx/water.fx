//-- Declare the texture. These are set using dxSetShaderValue( shader, "Tex0", texture )
texture waterTxd;

sampler txd = sampler_state
{
    Texture = (waterTxd);
};


struct PSInput
{
    float4 Diffuse  : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    return tex2D(txd, PS.TexCoord) * PS.Diffuse;
}


technique simple
{
    pass P0
    {
        PixelShader  = compile ps_2_0 PixelShaderFunction();
        Texture[0] = waterTxd;
   

        //-- Leave the rest of the states to the default settings
    }
}