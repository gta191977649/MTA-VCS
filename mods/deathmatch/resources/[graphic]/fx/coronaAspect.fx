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

#ifdef MOON_MASK
float2 MoonCenter;
bool MoonCenterValid = false;
#endif

float4 roundCorona(float2 uv : TEXCOORD0, float4 diffuse : COLOR0
#ifdef MOON_MASK
    , float2 pixel : VPOS
#endif
) : COLOR0 {
    // Native Im2D vertices are already transformed. Infer the actual raster
    // size of each UV axis and bring the longer axis down to the shorter one.
    float2 uvDx = ddx(uv);
    float2 uvDy = ddy(uv);
    float2 pixelRate = max(sqrt(uvDx*uvDx + uvDy*uvDy), 0.00001);
    float2 scale = max(pixelRate.x, pixelRate.y) / pixelRate;
    float2 center = 0.5;
#ifdef MOON_MASK
    if (!MoonCenterValid) return tex2D(CoronaSampler, uv) * diffuse;
    // The game offsets lunar each day. Find the disc's center in the
    // mask's UV space so its offset scales along with the moon.
    center = uv + uvDx * (MoonCenter.x - pixel.x) + uvDy * (MoonCenter.y - pixel.y);
#endif
    float2 corrected = (uv - center) * scale + center;
#ifndef MOON_MASK
    clip(min(corrected, 1.0 - corrected));
#endif
    return tex2D(CoronaSampler, corrected) * diffuse;
}

technique round_corona {
    pass Sprite {
        PixelShader = compile ps_3_0 roundCorona();
    }
}
