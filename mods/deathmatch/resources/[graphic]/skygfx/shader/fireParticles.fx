// SA fire, fire_car and flamethrower share particle rasters with smoke and jets.
// The fire primitives use red/orange vertex colours. Neutral smoke and blue
// thrust keep their stage-zero texture and the original batch's blend state.
#include "mta-helper.fx"
texture ParticleAtlas;
float4 FlameUV;
float FireGreenRatio;
float4 Sources[4];
sampler Native = sampler_state { Texture = (gTexture0); };
sampler Atlas = sampler_state { Texture = (ParticleAtlas); AddressU = Clamp; AddressV = Clamp; };

struct FireVertex {
    float4 position : POSITION;
    float4 color : COLOR0;
    float2 uv : TEXCOORD0;
};
struct FirePixel {
    float4 position : POSITION;
    float4 color : COLOR0;
    float2 uv : TEXCOORD0;
    float covered : TEXCOORD1;
    float3 world : TEXCOORD2;
};

float covers(float3 world, float4 source) {
    float3 delta = world - source.xyz;
    return source.w - dot(delta,delta);
}
FirePixel fireVertex(FireVertex v) {
    FirePixel o;
    o.position = mul(v.position,gWorldViewProjection);
    o.color = v.color;
    o.uv = v.uv;
    float3 world = mul(v.position,gWorld).xyz;
    o.world = world;
    o.covered = max(max(covers(world,Sources[0]),covers(world,Sources[1])),
                    max(covers(world,Sources[2]),covers(world,Sources[3])));
    return o;
}
// CFire emits several rising CARFLAME particles before the first expires.
// A native billboard supplies one quad. Composite the overlapping PS2
// sprites across its full height so successive billboards overlap.
float3 carFlame(float2 uv, float2 centre, float2 extent) {
    float2 p = (uv - centre) / extent + 0.5;
    float2 edge = saturate(12 * min(p,1-p));
    return tex2D(Atlas,lerp(FlameUV.xy,FlameUV.zw,saturate(p))).rgb * edge.x * edge.y;
}
float isFlame(float3 color) {
    // effects.fxp fire and fire_car use (255,150,0) on wjet6.
    // Native brightness and timecycle tint shift the authored green value.
    // The blue jet on the same raster keeps the native pass.
    const float quantum = 1.0/255;
    if (FireGreenRatio >= 0)
        return step(.025,color.r) * step(color.b,color.r*.10 + quantum) *
               step(abs(color.g - color.r*FireGreenRatio),color.r*.20 + quantum);
    // molotov_flame on sphere ramps (255,255,128) to (255,0,0).
    return step(1-.5*quantum,color.r) * step(.025,color.g) *
           step(abs(color.b - color.g*(128.0/255)),quantum);
}
float4 nativePixel(FirePixel i) : COLOR0 {
#ifdef NATIVE_EXPLOSION
    clip(-i.covered);
#else
    clip(.5 - isFlame(i.color.rgb));
#endif
    return tex2D(Native,i.uv)*i.color;
}
float4 flameColor(FirePixel i, float covered) {
    clip(isFlame(i.color.rgb) - .5);
    clip(-covered);
    // Unowned native ground fires (including incidental spread) still need a
    // flame. Use the original VCS CARFLAME raster and its configured colour.
    float3 base = carFlame(i.uv,float2(.50,.60),float2(.87,.84));
    // Several freshly emitted particles overlap at the source. Above it,
    // the individual, dimmer red tips remain visible.
    float3 flame = base * 2 + carFlame(i.uv,float2(.51,.46),float2(.76,.77))
                 + carFlame(i.uv,float2(.48,.30),float2(.55,.59));
    return float4(flame * float3(1,74.0/255,30.0/255) * i.color.r * i.color.a,1);
}
float4 firePixel(FirePixel i) : COLOR0 {
#ifdef BILLBOARD_CENTRE
    // The native FX batch contains many quads. Test each quad's centre so
    // a nearby managed source cannot slice a horizontal band out of a flame.
    float2 u = ddx(i.uv), v = ddy(i.uv), toCentre = .5 - i.uv;
    float det = u.x*v.y - u.y*v.x;
    float2 offset = float2(toCentre.x*v.y-toCentre.y*v.x, u.x*toCentre.y-u.y*toCentre.x);
    float3 centre = i.world + (ddx(i.world)*offset.x + ddy(i.world)*offset.y) /
                    (abs(det)>1e-12 ? det : 1);
    float covered = max(max(covers(centre,Sources[0]),covers(centre,Sources[1])),
                        max(covers(centre,Sources[2]),covers(centre,Sources[3])));
    return flameColor(i,covered);
#else
    return flameColor(i,i.covered);
#endif
}
technique FireParticles {
    pass P0 {
        VertexShader = compile vs_2_0 fireVertex();
        PixelShader = compile ps_2_0 nativePixel();
    }
#ifndef NATIVE_EXPLOSION
    pass Flame {
        AlphaBlendEnable = true;
        SrcBlend = ONE;
        DestBlend = ONE;
        BlendOp = ADD;
        ZWriteEnable = false;
#ifdef BILLBOARD_CENTRE
        VertexShader = compile vs_3_0 fireVertex();
        PixelShader = compile ps_3_0 firePixel();
#else
        VertexShader = compile vs_2_0 fireVertex();
        PixelShader = compile ps_2_0 firePixel();
#endif
    }
#endif
}
