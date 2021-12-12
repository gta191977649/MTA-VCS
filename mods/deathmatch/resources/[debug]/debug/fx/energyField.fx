//
// energyField.fx
// By: Brandon Fogerty 
// http://glslsandbox.com/e#25448.3
// glsl to hlsl translation by Ren712

// bfogerty at gmail dot com 
// xdpixel.com
// Special thanks to Inigo Quilez for noise!

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(0.5,0.5);
float2 sCenter = float2(0.5,0.5);

//------------------------------------------------------------------------------------------
// These parameters are set by MTA whenever a shader is drawn
//------------------------------------------------------------------------------------------
float4x4 gWorld : WORLD;
float4x4 gView : VIEW;
float4x4 gProjection : PROJECTION;
float gTime : TIME;
#define PI 3.1415926535897

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
float hash( float n ) { return frac(sin(n)*753.5453123); }

// Slight modification of iq's noise function.
float noise( float2 x )
{
    float2 p = floor(x);
    float2 f = frac(x);
    f = f*f*(3.0-2.0*f);
    
    float n = p.x + p.y*157.0;
    return lerp(
                    lerp( hash(n+  0.0), hash(n+  1.0),f.x),
                    lerp( hash(n+157.0), hash(n+158.0),f.x),
            f.y);
}

float fbm(float2 p, float3 a)
{
     float v = 0.0;
     v += noise(p*a.x)*.5;
     v += noise(p*a.y)*.25;
     v += noise(p*a.z)*.125;
     return v;
}

float3 drawLines( float2 uv, float3 fbmOffset, float3 color1, float3 color2, float timer )
{
    float timeVal = timer * 0.1;
    float3 finalColor = float3( 0.0,0.0,0.0 );
    for( int i=0; i < 3; ++i )
    {
        float indexAsFloat = float(i);
        float amp = 40.0 + (indexAsFloat*5.0);
        float period = 2.0 + (indexAsFloat+2.0);
        float thickness = lerp( 0.9, 1.0, noise(uv*10.0) );
        float t = abs( 0.9 / (sin(uv.x + fbm( uv + timeVal * period, fbmOffset )) * amp) * thickness );
        
        finalColor +=  t * color1;
    }
    
    for( int j=0; j < 5; ++j )
    {
        float indexAsFloat = float(j);
        float amp = 40.0 + (indexAsFloat*7.0);
        float period = 2.0 + (indexAsFloat+8.0);
        float thickness = lerp( 0.7, 1.0, noise(uv*10.0) );
        float t = abs( 0.8 / (sin(uv.x + fbm( uv + timeVal * period, fbmOffset )) * amp) * thickness );
        
        finalColor +=  t * color2 * 0.6;
    }
    
    return finalColor;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;
	
	// correction
    position.xy = position.yx;
   
    float3 lineColor1 = float3( 2.3, 0.5, .5 );
    float3 lineColor2 = float3( 0.3, 0.5, 2.5 );

    // main effect	
    float3 finalColor = float3(0,0,0);
	
    float t = sin( timer ) * 0.5 + 0.5;
    float pulse = lerp( 0.10, 0.20, t);
    
    finalColor += drawLines( position, float3( 1.0, 20.0, 30.0), lineColor1, lineColor2, timer ) * pulse;
    finalColor += drawLines( position, float3( 1.0, 2.0, 4.0), lineColor1, lineColor2, timer );
	
    return float4(finalColor.rgb,1);

}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique energyField
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
