texture tex;
float4 rgb1 = float4(1,1,1,1);
float4 rgb2 = float4(1,1,1,1);

//horizontal,vertecal
float2 offset_x = 0;
float2 offset_y = 0;

sampler Sampler0 = sampler_state
{
    Texture = (tex);
};
struct PS_INPUT
{
	float2 texcoord0	: TEXCOORD0;
};

/* --------------------
The PS2 effect works like this: out = in*rgb1*2 + in*rgb2*2*alpha2*2. I.e. it does PS2 colour modulation and blending
*/
float4 main(PS_INPUT IN) : COLOR
{
    float2 txdCord = IN.texcoord0;
    txdCord.x = txdCord.x + offset_x;
    txdCord.y = txdCord.y + offset_y;

	//float4 c = tex2D(Sampler0, IN.texcoord0.xy);
	float4 c = tex2D(Sampler0, txdCord);

	c = c*rgb1*2 + c*rgb2*2*rgb2.a*2;
    c.a = 1.0f;
	return c;
}

technique colorfilter
{
    pass P0
    {
        PixelShader = compile ps_2_0 main();
    }
   
}