#include "mta-helper.fx"
#include "pointLights.fx"

float3 PrelightScale = float3(0.5, 0.5, 0.5);
float3 PrelightOffset = 0;
float3 FogColor = 0;
float2 FogRange = float2(0, 2000);

sampler WorldSampler = sampler_state {
    Texture = (gTexture0);
#ifdef VCS_WORLD_FOLIAGE
    MinFilter = Linear;
    MagFilter = Linear;
    MipFilter = Linear;
#endif
};

struct VertexIn {
    float4 position : POSITION;
    float2 uv : TEXCOORD0;
    float4 color : COLOR0;
};

struct VertexOut {
    float4 position : POSITION;
    float2 uv : TEXCOORD0;
    float fog : TEXCOORD1;
    float3 worldPosition : TEXCOORD2;
    float4 color : COLOR0;
};

VertexOut worldVertex(VertexIn input) {
    VertexOut output;
    output.position = mul(input.position, gWorldViewProjection);
    output.uv = input.uv;
    output.worldPosition = mul(input.position, gWorld).xyz;
#ifdef VCS_WORLD_PROP
    // The VCS converter bakes material tint into the expanded vertex colors.
    // The current D3D material state can belong to an earlier draw.
    float3 lit = clamp(input.color.rgb * 255.0 * PrelightScale + PrelightOffset, 0.0, 255.0);
#else
    // Recover the VIF RGB555 values from the DFF's expanded vertex colors.
    // VU1 clips and truncates the result before the GS interpolates it.
    float3 prelight = floor(input.color.rgb * 31.0 + 0.5) * 8.0;
    float3 lit = floor(clamp(prelight * PrelightScale + PrelightOffset, 0.0, 255.0));
#endif
    // RenderAtomicWithAlpha changes the material and enables native lighting
    // during fades. Unlit draws may retain a previous material, so use MTA's
    // render-state-aware building alpha rather than multiplying it blindly.
    output.color = float4(lit / 255.0, MTACalcGTABuildingDiffuse(input.color).a);
    output.fog = saturate((output.position.w - FogRange.x) / max(FogRange.y - FogRange.x, 1.0));
    return output;
}

float4 worldPixel(VertexOut input) : COLOR0 {
    float4 texel = tex2D(WorldSampler, input.uv);
    float3 surface = saturate(texel.rgb * (input.color.rgb * (255.0 / 128.0) + GetFireLighting(input.worldPosition)));
    float alpha = texel.a * input.color.a;
    return float4(lerp(surface, FogColor, input.fog), alpha);
}

// GTA owns alpha testing, blending (including additive materials), depth and
// culling for each draw. Only replace lighting and fog; preserve those states
// for opaque, transparent and distance-faded entities alike.
technique vcs_leeds {
    pass P0 {
        FogEnable = false;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
}
