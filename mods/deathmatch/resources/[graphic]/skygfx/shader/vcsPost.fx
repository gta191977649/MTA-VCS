texture Scene;
sampler SceneSampler = sampler_state {
    Texture = (Scene); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Linear; MagFilter = Linear; MipFilter = None;
};

#if defined(VCS_THRESHOLD)
float Threshold;
#ifdef VCS_SKY_MASK
float2 SceneSize;
float2 SceneTexel;
texture SceneDepth : DEPTHBUFFER;
sampler ScenePointSampler = sampler_state {
    Texture = (Scene); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Point; MagFilter = Point; MipFilter = None;
};
sampler DepthSampler = sampler_state {
    Texture = (SceneDepth); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Point; MagFilter = Point; MipFilter = None;
};

float sceneDepth(float2 uv) {
    float4 depth = tex2D(DepthSampler, uv);
#if IS_DEPTHBUFFER_RAWZ
    // Point sampling returns the three normalized depth bytes exactly.
    float value = dot(depth.arg, float3(65536.0, 256.0, 1.0) / 65793.0);
#else
    float value = depth.r;
#endif
    return value;
}

float3 sampleSkyMaskedScene(float2 uv) {
    float3 scene = tex2D(ScenePointSampler, uv).rgb;
    float cyan = saturate((min(scene.g, scene.b) - scene.r - 0.125) * 4.0);
    return lerp(scene, scene.rrr, sceneDepth(uv) >= 0.999999 ? cyan : 0.0);
}
#endif

float4 thresholdPixel(float2 uv : TEXCOORD0) : COLOR0 {
#ifdef VCS_SKY_MASK
    // Match each color to its own depth before bilinear filtering.
    // A single depth tap can classify a mixed sky/pole sample as geometry.
    float2 pixel = uv * SceneSize - 0.5;
    float2 weight = frac(pixel);
    float2 a = (pixel - weight + 0.5) * SceneTexel;
    float2 b = a + SceneTexel;
    float3 top = lerp(sampleSkyMaskedScene(a), sampleSkyMaskedScene(float2(b.x, a.y)), weight.x);
    float3 bottom = lerp(sampleSkyMaskedScene(float2(a.x, b.y)), sampleSkyMaskedScene(b), weight.x);
    float3 scene = lerp(top, bottom, weight.y);
#else
    float3 scene = tex2D(SceneSampler, uv).rgb;
#endif
    return float4(saturate(scene - Threshold), 1);
}
technique vcs_threshold {
    pass P0 { PixelShader = compile ps_2_0 thresholdPixel(); }
}
#elif defined(VCS_BLUR)
float2 Step;
float4 blurPixel(float2 uv : TEXCOORD0) : COLOR0 {
#if defined(VCS_DIAGONAL)
    float2 a = float2(-Step.x, -Step.y);
    float2 b = float2( Step.x, -Step.y);
    float2 c = float2(-Step.x,  Step.y);
    float2 d = float2( Step.x,  Step.y);
#else
    float2 a = float2(-Step.x, 0);
    float2 b = float2( Step.x, 0);
    float2 c = float2(0, -Step.y);
    float2 d = float2(0,  Step.y);
#endif
    float3 color = tex2D(SceneSampler, uv + a).rgb + tex2D(SceneSampler, uv + b).rgb
                 + tex2D(SceneSampler, uv + c).rgb + tex2D(SceneSampler, uv + d).rgb;
    // VCSPC's index buffer also draws three strips connecting adjacent quads.
    color += tex2D(SceneSampler, uv + lerp(b, a, uv.x)).rgb;
    color += tex2D(SceneSampler, uv + lerp(c, b, uv.x)).rgb;
    color += tex2D(SceneSampler, uv + lerp(d, c, uv.x)).rgb;
    return float4(color * (36.0 / 255.0), 1);
}
technique vcs_blur {
    pass P0 { PixelShader = compile ps_2_0 blurPixel(); }
}
#else
texture Bloom;
texture History;
sampler BloomSampler = sampler_state {
    Texture = (Bloom); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Linear; MagFilter = Linear; MipFilter = None;
};
sampler HistorySampler = sampler_state {
    Texture = (History); AddressU = Clamp; AddressV = Clamp;
    MinFilter = Linear; MagFilter = Linear; MipFilter = None;
};
float2 SmearOffset;
float SmearWeight;
float3 TrailsColor;
float BloomWeight;
float HistoryWeight;

float3 sceneWithBloom(float2 uv) {
    return saturate(tex2D(SceneSampler, uv).rgb + tex2D(BloomSampler, uv).rgb * BloomWeight);
}

float4 composePixel(float2 uv : TEXCOORD0) : COLOR0 {
    float3 scene = sceneWithBloom(uv);
    // The shifted quads are clipped at the edges of the framebuffer.
    float2 source = uv - SmearOffset;
    float2 covered = step(0.0, source) * step(source, 1.0);
    float3 localColor = lerp(scene, sceneWithBloom(float2(source.x, uv.y)), SmearWeight * covered.x);
    localColor = lerp(localColor, sceneWithBloom(source), SmearWeight * covered.x * covered.y);
    localColor = lerp(localColor, sceneWithBloom(float2(uv.x, source.y)), SmearWeight * covered.y);
    localColor = saturate(localColor + scene * TrailsColor);
    float3 history = tex2D(HistorySampler, uv).rgb;
    return float4(lerp(localColor, history, HistoryWeight), 1);
}

technique vcs_compose {
    pass P0 { PixelShader = compile ps_2_0 composePixel(); }
}
#endif
