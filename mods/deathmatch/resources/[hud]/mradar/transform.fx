
float3x3 tmove(float2 pos) {

    return float3x3(1, 0, 0,
                    0, 1, 0,
                    pos.x, pos.y, 1);
}

float3x3 trot(float angle) {

    float s = sin(angle);
    float c = cos(angle);
    return float3x3(c, s, 0,
                    -s, c, 0,
                    0, 0, 1);
}

float3x3 tscale(float2 scale) {

    return float3x3(scale.x, 0, 0,
                    0, scale.y, 0,
                    0, 0, 1);
}