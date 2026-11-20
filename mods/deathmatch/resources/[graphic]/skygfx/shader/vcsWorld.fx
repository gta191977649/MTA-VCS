#include "mta-helper.fx"

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
    float4 color : COLOR0;
};

VertexOut worldVertex(VertexIn input) {
    VertexOut output;
    output.position = mul(input.position, gWorldViewProjection);
    output.uv = input.uv;
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
    output.color = float4(lit / 255.0, input.color.a);
    output.fog = saturate((output.position.w - FogRange.x) / max(FogRange.y - FogRange.x, 1.0));
    return output;
}

float4 worldPixel(VertexOut input) : COLOR0 {
    float4 texel = tex2D(WorldSampler, input.uv);
    float3 surface = saturate(texel.rgb * input.color.rgb * (255.0 / 128.0));
    float alpha = texel.a * input.color.a;
#if !defined(VCS_VERTEX_ALPHA_ONLY) && !defined(VCS_WORLD_FOLIAGE) && !defined(VCS_WORLD_SOLID_PROP)
    // Timed and range-faded placements still carry instance opacity here.
    alpha *= gMaterialDiffuse.a;
#endif
#if defined(VCS_WORLD_FOLIAGE) || defined(VCS_WORLD_ALPHA) || defined(VCS_WORLD_SOLID_PROP)
    // GS GREATER 8, mapped from its 0..128 blend range to the decoded TXD.
    clip(alpha - (16.5 / 255.0));
#endif
    return float4(lerp(surface, FogColor, input.fog), alpha);
}

#ifdef VCS_WORLD_DECAL
technique vcs_leeds_decal {
    pass Shadow {
        FogEnable = false;
        AlphaTestEnable = false;
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZEnable = true;
        ZWriteEnable = false;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
}
#elif defined(VCS_WORLD_FOLIAGE) || defined(VCS_WORLD_SOLID_PROP)
technique vcs_prelit_prop {
    pass P0 {
        FogEnable = false;
        AlphaTestEnable = false;
        // GS ALPHA_1 = 0x44: (source - destination) * sourceAlpha + destination.
        // Opaque prop rasters use the same pass with full texture coverage.
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZEnable = true;
        ZFunc = LESSEQUAL;
        ZWriteEnable = true;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
}
#elif defined(VCS_WORLD_ALPHA) || defined(VCS_SHOP_PROP)
#ifdef VCS_SHOP_PROP
#define COVERAGE_ALPHA_REF 255
#else
#define COVERAGE_ALPHA_REF 128
#endif
technique vcs_leeds_alpha {
    pass Coverage {
        FogEnable = false;
        AlphaTestEnable = true;
        AlphaRef = COVERAGE_ALPHA_REF;
        AlphaFunc = GREATEREQUAL;
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZWriteEnable = true;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
    pass Fringe {
        FogEnable = false;
        AlphaTestEnable = true;
        AlphaRef = COVERAGE_ALPHA_REF;
        AlphaFunc = LESS;
        AlphaBlendEnable = true;
        SrcBlend = SRCALPHA;
        DestBlend = INVSRCALPHA;
        ZWriteEnable = false;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
}
#else
technique vcs_leeds {
    pass P0 {
        FogEnable = false;
        VertexShader = compile vs_2_0 worldVertex();
        PixelShader = compile ps_2_0 worldPixel();
    }
}
#endif
