//
// merryXMass.fx
// http://glslsandbox.com/e#29681.0
// glsl to hlsl translation by Ren712

// Merry Christmas Everyone!
// By: Brandon Fogerty
// bfogerty at gmail dot com

// "Mary will bear a son, and you shall call his name Jesus, 
//  for he will save his people from their sins." - An Angel of God To Joseph (Matthew 1:21)

// "“Glory to God in the highest, and on earth peace among those with whom He is pleased!” - Luke 2:14

// "But he was pierced for our transgressions,
//  he was crushed for our iniquities;
//  the punishment that brought us peace was on him,
//  and by his wounds we are healed." - Isaiah 53:5-6 


/*
One of the criminals who were hanged railed at him, saying, 
“Are you not the Christ? Save yourself and us!”
But the other rebuked him, saying, 
“Do you not fear God, since you are under the same sentence of condemnation?
And we indeed justly, for we are receiving the due reward of our deeds; 
but this man has done nothing wrong.” 
And he said, “Jesus, remember me when you come into your kingdom.” 
And he said to him, “Truly, I say to you, today you will be with me in Paradise.” - Luke 23:39-43
*/

// Special Thanks to my Beautiful Wife, Naomi, for the design!

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);

#define GloryGlowColor				float3(0.26, 0.16, 0.06)
#define VerticalBarWidth			0.09
#define VerticalBarHeight			0.9
#define HorizontalBarWidth			0.7
#define HorizontalBarHeight			0.07
#define HorizontalBarVerticalOffset		0.4

#define ChristsCrossColor			float3( 1.0, 1.0, 1.0 )
#define UnrepentantThiefsCrossColor		float3( 0.45, 0.45, 0.45 )
#define RepentantThiefsCrossColor		float3( 0.90, 0.90, 0.90 )

#define CrossGlowScale				0.02
#define CrossGloryGlowMin			0.035
#define CrossGloryGlowMax			5.00

//------------------------------------------------------------------------------------------
// These parameters are set by MTA whenever a shader is drawn
//------------------------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gProjection : PROJECTION;
float gTime : TIME;
#define PI 3.14159265359

//------------------------------------------------------------------------------------------
// Structure of data sent to the vertex shader
//------------------------------------------------------------------------------------------
struct VSInput
{
    float3 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord : TEXCOORD0;
};

//------------------------------------------------------------------------------------------
// Structure of data sent to the pixel shader ( from the vertex shader )
//------------------------------------------------------------------------------------------
struct PSInput
{
    float4 Position : POSITION0;
    float4 Diffuse : COLOR0;
    float2 TexCoord: TEXCOORD0;
};

//------------------------------------------------------------------------------------------
// VertexShaderFunction
//------------------------------------------------------------------------------------------
PSInput VertexShaderFunction(VSInput VS)
{
    PSInput PS = (PSInput)0;

    // Calculate screen pos of vertex
    float4 posWorld = mul(float4(VS.Position.xyz,1), gWorld);
    float4 posWorldView = mul(posWorld, gView);
    PS.Position = mul(posWorldView, gProjection);
	
    // Pass through color and tex coord
    PS.Diffuse = VS.Diffuse;

    // Translate TexCoord
    float2 position = float2(VS.TexCoord.x,1 - VS.TexCoord.y);
    float2 center = 0.5 + (sCenter - 0.5);
    position += float2(1 - center.x, center.y) - 0.5;
    position = (position - 0.5) * float2(sTexSize.x/sTexSize.y,1) / sScale + 0.5;
    position -= 0.5;
    PS.TexCoord = position;

    return PS;
}

//------------------------------------------------------------------------------------------
// PixelShaderFunction
//------------------------------------------------------------------------------------------
float hash( float x )
{
    return frac( sin( x ) * 43758.5453 );
}

float noise( float2 uv )  // Thanks Inigo Quilez
{
    float3 x = float3( uv.xy, 0.0 );
    
    float3 p = floor( x );
    float3 f = frac( x );
    
    f = f * f * (3.0 - 2.0 * f);
    
    float offset = 57.0;
    
    float n = dot( p, float3(1.0, offset, offset*2.0) );
    
    return lerp(	lerp(	lerp( hash( n + 0.0 ), hash( n + 1.0 ), f.x ),
        				lerp( hash( n + offset), hash( n + offset+1.0), f.x ), f.y ),
				lerp(	lerp( hash( n + offset*2.0), hash( n + offset*2.0+1.0), f.x),
                    	lerp( hash( n + offset*3.0), hash( n + offset*3.0+1.0), f.x), f.y), f.z);
}

float snoise( float2 uv )
{
    return noise( uv ) * 2.0 - 1.0;
}


float perlinNoise( float2 uv )
{   
    float n = noise( uv * 1.0 ) * 128.0 +
              noise( uv * 2.0 ) * 64.0 +
              noise( uv * 4.0 ) * 32.0 +
              noise( uv * 8.0 ) * 16.0 +
              noise( uv * 16.0 ) * 8.0 +
              noise( uv * 32.0 ) * 4.0 +
              noise( uv * 64.0 ) * 2.0 +
              noise( uv * 128.0 ) * 1.0;
    
    float noiseVal = n / ( 1.0 + 2.0 + 4.0 + 8.0 + 16.0 + 32.0 + 64.0 + 128.0 );
    noiseVal = abs(noiseVal * 2.0 - 1.0);
    
    return 	noiseVal;
}

float fBm( float2 uv, float lacunarity, float gain )
{
    float sum = 0.0;
    float amp = 1.0;
    
    for( int i = 0; i < 10; ++i )
    {
        sum += ( perlinNoise( uv ) ) * amp;
        amp *= gain;
        uv *= lacunarity;
    }
    
    return sum;
}

float pulse( float value, float minValue, float maxValue )
{
    float t = step( minValue, value ) - step( maxValue, value );
    return t;
}

float3 cross( float2 uv, float verticalBarWidth, float verticalBarHeight, float horizontalBarWidth, float horizontalBarHeight, 
              float horizontalBarVerticalOffset, float2 position, float scale, float3 color )
{
    verticalBarWidth *= scale;
    verticalBarHeight *= scale;
    horizontalBarWidth *= scale;
    horizontalBarHeight *= scale;
    horizontalBarVerticalOffset *= scale;
	
    float verticleBar = pulse( uv.x, -verticalBarWidth + position.x, verticalBarWidth + position.x );
    verticleBar *= pulse( uv.y, -verticalBarHeight + position.y, verticalBarHeight + position.y );
    float horizontalBar = pulse( uv.x, -horizontalBarWidth + position.x, horizontalBarWidth + position.x );
    horizontalBar *= pulse( uv.y, -horizontalBarHeight  + horizontalBarVerticalOffset + position.y, horizontalBarHeight + horizontalBarVerticalOffset + position.y );
    float intensity = clamp(verticleBar + horizontalBar, 0.0, 1.0);
    float3 finalColor = (color * intensity);
    return  finalColor;
}

float3 gloryGlow( float2 uv, float3 glowColor, float minGlow, float maxGlow, float noiseFactor, float speed )
{
    float t = sin( gTime ) * 0.50 + 0.50;
    float glowAmount = lerp( minGlow, maxGlow, t );
    float2 glowUV = uv + float2( 0.0, 0.0 );
    float glowPulse = sin( glowUV.x * glowAmount );
    float3 color = glowColor * abs( 1.0 / glowPulse ) * noiseFactor;
    return color;
}

float3 beam( float2 uv, float3 glowColor, float noiseFactor, float offset, float speed )
{
    float t = sin( gTime * speed ) * 0.50 + 0.50;
    float glowAmount = lerp( 0.20, 1.0, t );
    float2 glowUV = uv + float2( 0.0, 0.0 );
    float glowPulse = sin( glowUV.x * glowAmount );
    float t2 = sin( gTime * 0.50 ) * 0.50 + 0.50;
    float lengthOfBeam = lerp( -1.0, 0.70, 1.0 - t2 );
    glowUV = uv + float2( -1.24 - sin(offset + gTime + uv.y * speed) * 0.10, 0.0 );
    glowPulse = sin( glowUV.x * 0.7  );
    float glowFactor = (( abs( 0.2 / glowPulse  ) * noiseFactor)) * (sin(uv.y + lengthOfBeam) * 1.0);
    float3 color = clamp( glowColor *  glowFactor, 0.0, 1.50);
    return color;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
	float2 uv = position;
	
    float3 finalColor = float3( 0.0, 0.0, 0.0 );
	
    float noiseFactor = fBm( uv * 1.0, 2.0, 0.9 );
	
    finalColor += gloryGlow( uv, GloryGlowColor, CrossGloryGlowMin, CrossGloryGlowMax, noiseFactor, 1.0 );
	
    float3 beamColor = float3( 0.0, 0.0, 0.0 );
    beamColor += beam( uv, float3( 0.03, 0.03, 0.13), noiseFactor, 0.0, 2.4 );
    beamColor += beam( uv, float3( 0.03, 0.13, 0.03), noiseFactor, 0.2, 3.5 );
    beamColor += beam( uv, float3( 0.13, 0.13, 0.03), noiseFactor, 1.4, 4.6 );
    beamColor += beam( uv, float3( 0.13, 0.03, 0.03), noiseFactor, 4.0, 6.7 );
    beamColor += beam( uv, float3( 0.13, 0.03, 0.13), noiseFactor, 6.7, 8.7 );
	
    float t = sin( gTime + (uv.y / 2.0) ) * 0.5 + 0.5;
    finalColor += (beamColor * t);
	
    finalColor += cross( uv, 
                    VerticalBarWidth, 
                    VerticalBarHeight, 
                    HorizontalBarWidth + 0.05, 
                    HorizontalBarHeight, 
                    HorizontalBarVerticalOffset,
                    float2( 0.0, 0.0 ),
                    1.0,
                    ChristsCrossColor );
	
    finalColor += cross( uv, 
                    VerticalBarWidth, 
                    VerticalBarHeight, 
                    HorizontalBarWidth, 
                    HorizontalBarHeight, 
                    HorizontalBarVerticalOffset,
                    float2( -1.2, -0.5 ),
                    0.2,
                    UnrepentantThiefsCrossColor );
	
    finalColor += cross( uv, 
                    VerticalBarWidth, 
                    VerticalBarHeight, 
                    HorizontalBarWidth, 
                    HorizontalBarHeight, 
                    HorizontalBarVerticalOffset,
                    float2( 1.2, -0.5 ),
                    0.2,
                    RepentantThiefsCrossColor );
	
    finalColor *= lerp( 0.7, 1.0, uv.y );
    finalColor *= lerp( 0.7, 1.0, -abs(uv.x));
	
    return float4( finalColor, 1.0 );
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique merryXMass
{
    pass P0
    {
        VertexShader = compile vs_3_0 VertexShaderFunction();
        PixelShader  = compile ps_3_0 PixelShaderFunction();
    }
}

// Fallback
technique fallback
{
    pass P0
    {
        // Just draw normally
    }
}