#ifdef ORIGINAL_TEXTURE
texture CoronaTexture < string textureState="0,Texture"; >;
#else
texture CoronaTexture;
#endif

sampler CoronaSampler = sampler_state {
    Texture = (CoronaTexture);
    AddressU = Clamp;
    AddressV = Clamp;
};

float4 roundCorona(float2 uv : TEXCOORD0, float4 diffuse : COLOR0) : COLOR0 {
    // Native Im2D vertices are already transformed. Infer the actual raster
    // size of each UV axis and bring the longer axis down to the shorter one.
    float2 uvDx = ddx(uv);
    float2 uvDy = ddy(uv);
    float2 pixelRate = max(sqrt(uvDx*uvDx + uvDy*uvDy), 0.00001);
    float2 scale = max(pixelRate.x, pixelRate.y) / pixelRate;
    float2 corrected = (uv - 0.5) * scale + 0.5;
    clip(min(corrected, 1.0 - corrected));
    return tex2D(CoronaSampler, corrected) * diffuse;
}

technique round_corona {
    pass Sprite {
        PixelShader = compile ps_3_0 roundCorona();
    }
}
