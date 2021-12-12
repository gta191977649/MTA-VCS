//
// screenFlare.fx
// http://glslsandbox.com/e#28447.11
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sMouse = float2(0.5,0.5);
float2 sScale = float2(1,1);
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
float mod(float x, float y)
{
  return x - y * floor(x/y);
}

#define dist 0.02
#define intensity 1.5 / dist
#define pattern 20.0
#define tint float3(1,1,1)
#define chromaShift 1.0

/*//board pattern
float3 texUV(float2 uv){
    if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) return float3(0.0);
    float3 color = float3(0.0);
    color += mod(floor(uv.x * pattern), 2.0) * 0.3;
    color += mod(floor(uv.y * pattern), 2.0) * 0.3;
    color.rg *= uv;
    return color;
}
//*/

/////mouse circle
float3 texUV(float2 uv){
    if (uv.x == 0.0 || uv.y == 0.0 || uv.x == 1.0 || uv.y == 1.0) return float3(0,0,0);
    float d = distance(uv, sMouse) ;
    if (d < dist) return float3(((dist-d)/dist),((dist-d)/dist),((dist-d)/dist))*tint;
    return float3(0,0,0);
}
///

/*//moving circle
float3 texUV(float2 uv){
    if (uv.x == 0.0 || uv.y == 0.0 || uv.x == 1.0 || uv.y == 1.0) return float3(0.0);
    float s = time * 1.0; 
    float a = sin(time * 1.2) * 0.2 + 0.2;

    float d = distance(uv, 0.5+float2(cos(s)*a, sin(s)*a)) ;
    if (d < dist) return float3(0.2*((dist-d)/dist),0.4*((dist-d)/dist),0.8*((dist-d)/dist));
    return float3(0.0);
}
//*/

float3 flare(float px, float py, float pz, float cShift, float i, float2 uvx)
{
    float3 t=float3(0,0,0);
	
    //float3 lx = float3(.01,.01,.3);
    float x = length(uvx);
    uvx*=pow(4.0*x,py)*px+pz;
    t.r = texUV(clamp(uvx*(1.0+cShift*chromaShift)+0.5, 0.0, 1.0)).r;
    t.g = texUV(clamp(uvx+0.5, 0.0, 1.0)).g;
    t.b = texUV(clamp(uvx*(1.0-cShift*chromaShift)+0.5, 0.0, 1.0)).b;
    t = t*t;
    t *= clamp(.6-length(uvx), 0.0, 1.0);
    t *= clamp(length(uvx*20.0), 0.0, 1.0);
    t *= i;
    /*
    //t=t*lx;
    S=m.xy-.5;
    S*=1.75;
    t*=clamp(1.-dot(S,S), 0.0, 1.0);
    float n=max(t.x,max(t.y,t.z)),c=n/(1.+n);
    //c=pow(c,10.0);
    t.xyz*=c;
    //*/
    return t;
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{	
    // standard thing
    // Get TexCoord
    float2 position = PS.TexCoord + 0.5;
    float timer = gTime;

    // Translate mouse
    float2 center = 0.5 + (sCenter - 0.5);	
	float2 mouse = sMouse;
    mouse -= 0.5;
    mouse -= center - 0.5;
    mouse *= float2(sTexSize.x/sTexSize.y,1) / sScale;
    mouse += 0.5;
    mouse = float2(mouse.x, 1 - mouse.y);
	
    float2 uvx = position - 0.5;
	
    // effect start	
    float3 finalColor =float3(0,0,0);
    float tt = 1.0 / abs( distance(position, mouse) * intensity );
    float v = 1.0 / abs( length((mouse-position) * float2(0.03, 1.0)) * (intensity*10.0) );
	
    finalColor += texUV(position)*0.5;
    finalColor += float3(tt,tt,tt)*tint;
    finalColor += float3(v,v,v)*tint;
	
    finalColor += flare(0.00005, 16.0, 0.0, 0.2, 1.0,uvx);
    finalColor += flare(0.5, 2.0, 0.0, 0.1, 1.0,uvx);
    finalColor += flare(20.0, 1.0, 0.0, 0.05, 1.0,uvx);
    finalColor += flare(-10.0, 1.0, 0.0, 0.1, 1.0,uvx);
    finalColor += flare(-10.0, 2.0, 0.0, 0.05, 2.0,uvx);
    finalColor += flare(-1.0, 1.0, 0.0, 0.1, 2.0,uvx);
    finalColor += flare(-0.00005, 16.0, 0.0, 0.2, 2.0,uvx);
	
    //finalColor = float3(position, 0.0);
    //finalColor = float3(m, 0.0);
	
    return float4(finalColor.rgb, 1.0 );
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique screenFlare
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
