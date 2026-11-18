
float4x4 gWorldViewProjection : WORLDVIEWPROJECTION;
texture gTexture0           < string textureState="0,Texture"; >;


float gBlendTarget = 0.5;                       // Blend with this alpha and above
float2 texelSize = (1.0 / 256.0, 1.0 / 256.0);
float gDiscard = 0.5;                           // What is the max alpha we should keep? Discard below

sampler2D gTextureSampler = sampler_state
{
    Texture = (gTexture0);
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
    AddressU = Wrap;
    AddressV = Wrap;
};


// Vertex shader input structure
struct VSInput
{
    float3 Position : POSITION;
    float2 TexCoord : TEXCOORD0;
    float4 Diffuse : COLOR0;
};

// Vertex shader output structure
struct VSOutput
{
    float4 Position : POSITION;
    float2 TexCoord : TEXCOORD0;
    float4 Diffuse : COLOR0;
};

// Vertex shader
VSOutput VertexShaderFunction(VSInput input)
{
    VSOutput output;
    output.Position = mul(float4(input.Position, 1.0), gWorldViewProjection);
    output.TexCoord = input.TexCoord;
    output.Diffuse = input.Diffuse;
    return output;
}


float4 PixelShaderFunction(VSOutput input) : COLOR0
{

    float4 texColor = tex2D(gTextureSampler, input.TexCoord);
    

    if (texColor.a <= gDiscard)
    {
        discard;
    }
    
    float4 blendColor = texColor;

    if (texColor.a < 1)
    {

        float sampleCount = 1.0;
        
        for (int x = -1; x <= 1; x++)
        {
            for (int y = -1; y <= 1; y++)
            {
                if (x == 0 && y == 0) continue;
                float2 offset = float2(x, y) * texelSize;
                float4 neighbor = tex2D(gTextureSampler, input.TexCoord + offset);
                if (neighbor.a > gBlendTarget)
                {
                    blendColor += neighbor;
                    sampleCount += 1.0;
                }
            }
        }
        

        blendColor /= sampleCount;
        blendColor.a = 1.0; 
    }

    return blendColor * input.Diffuse;
}

technique semiFlattenAlpha
{
    pass P0
    {

        CullMode = None;

        VertexShader = compile vs_2_0 VertexShaderFunction();
        PixelShader = compile ps_2_0 PixelShaderFunction();
    }
}