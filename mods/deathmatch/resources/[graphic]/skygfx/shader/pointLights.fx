// The two nearest submitted fire lights illuminate the receiving surface.
float4 FireLights[2];
float4 FireColors[2];
float3 GetFireLighting(float3 position) {
    float3 a = position - FireLights[0].xyz;
    float3 b = position - FireLights[1].xyz;
    return FireColors[0].rgb * saturate(1 - dot(a,a) * FireLights[0].w)
         + FireColors[1].rgb * saturate(1 - dot(b,b) * FireLights[1].w);
}
