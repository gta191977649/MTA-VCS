
#include "transform.fx"

texture gTilesTexture;
float2 gTilesScale = 1.0;
float gTilesRot = 0.0;

texture gArtificialHorizonTexture;
float gArtificialHorizonRatio = 0.0;

texture gRingPlaneTexture;
float gRingPlaneScale = 1.0;
float gRingPlaneRot = 0.0;

texture gMaskTexture;
texture gBorderTexture;
bool gPlane = false;

float3x3 calcTilesTextureTransform() {

    return mul(mul(mul(
        tmove(float2(-0.5, -0.5)),
        tscale(gTilesScale)),
        trot(gTilesRot)),
        tmove(float2(0.5, 0.5)));
}

float3x3 calcRingPlaneTextureTransform() {

    return mul(mul(mul(
        tmove(float2(-0.5, -0.5)),
        tscale(float2(gTilesScale.x / gTilesScale.y * gRingPlaneScale, gRingPlaneScale))),
        trot(gRingPlaneRot)),
        tmove(float2(0.5, 0.5)));
}

float3x3 calcArtificialHorizonTransform() {

	return tmove(float2(0.0, - gArtificialHorizonRatio));
}

technique radar
{
    pass P0
    {
        TextureFactor = 0;

        // map tiles
        Texture[0] = gTilesTexture;
        TextureTransformFlags[0] = Count2;
        TextureTransform[0] = calcTilesTextureTransform();
        ColorOp[0] = SelectArg1;
        ColorArg1[0] = Texture;
        AlphaOp[0] = SelectArg1;
        AlphaArg1[0] = Texture;

        // artificial horizon
        Texture[1] = gArtificialHorizonTexture;
        AddressU[1] = Clamp;
        AddressV[1] = Clamp;
        TexCoordIndex[1] = 0;
        TextureTransformFlags[1] = Count2;
        TextureTransform[1] = calcArtificialHorizonTransform();
        // BLENDTEXTUREALPHA    = 13
        // SELECTARG2           = 3
        ColorOp[1] = gPlane ? 13 : 3;
        ColorArg1[1] = Texture;
        ColorArg2[1] = Current;
        // ADDSMOOTH            = 11
        // SELECTARG2           = 3
        AlphaOp[1] = gPlane ? 11 : 3;
        AlphaArg1[1] = Texture;
        AlphaArg2[1] = Current;

        // ring plane
        Texture[2] = gRingPlaneTexture;
        AddressU[2] = Clamp;
        AddressV[2] = Clamp;
        TexCoordIndex[2] = 0;
        TextureTransformFlags[2] = Count2;
        TextureTransform[2] = calcRingPlaneTextureTransform();
        // BLENDTEXTUREALPHA    = 13
        // SELECTARG2           = 3
        ColorOp[2] = gPlane ? 13 : 3;
        ColorArg1[2] = Texture;
        ColorArg2[2] = Current;
        // ADDSMOOTH            = 11
        // SELECTARG2           = 3
        AlphaOp[2] = gPlane ? 11 : 3;
        AlphaArg1[2] = Texture;
        AlphaArg2[2] = Current;

        // mask
        Texture[3] = gMaskTexture;
        TexCoordIndex[3] = 0;
        ColorOp[3] = BlendTextureAlpha;
        ColorArg1[3] = Current;
        ColorArg2[3] = TFactor;
        AlphaOp[3] = Modulate;
        AlphaArg1[3] = Current;
        AlphaArg2[3] = Texture;

        // border
        Texture[4] = gBorderTexture;
        TexCoordIndex[4] = 0;
        ColorOp[4] = BlendTextureAlpha;
        ColorArg1[4] = Texture;
        ColorArg2[4] = Current;
        AlphaOp[4] = Add;
        AlphaArg1[4] = Texture;
        AlphaArg2[4] = Current;

        // paint
        ColorOp[5] = Modulate;
        ColorArg1[5] = Current;
        ColorArg2[5] = Diffuse;
        AlphaOp[5] = Modulate;
        AlphaArg1[5] = Current;
        AlphaArg2[5] = Diffuse;
    }
}
