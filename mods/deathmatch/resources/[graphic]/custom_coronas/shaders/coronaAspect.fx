float2 CoronaViewport = float2(4.0, 3.0);

float3 coronaViewOffset(float3 offset, float4x4 projection) {
    float2 pixelScale = abs(float2(projection[0][0], projection[1][1])) * CoronaViewport;
    offset.x *= pixelScale.y / max(pixelScale.x, 0.00001);
    return offset;
}
