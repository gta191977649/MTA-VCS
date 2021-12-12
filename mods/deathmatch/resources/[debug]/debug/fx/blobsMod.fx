//
// blobsMod.fx
// http://glslsandbox.com/e#25468.0
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
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
float3 sim(float3 p,float s);
float2 rot(float2 p,float r);
float2 rotsim(float2 p,float s);
float2 zoom(float2 p,float f);

float2 makeSymmetry(float2 p){
   float2 ret=p;
   ret=rotsim(ret,sin(gTime*0.9)*2.0+3.0);
   ret.x=abs(ret.x);
   return ret;
}

float makePoint(float x,float y,float fx,float fy,float sx,float sy,float t){
   float xx=x+tan(t*fx)*sy;
   float yy=y-tan(t*fy)*sy;
   float a=0.5/sqrt(abs(abs(x*xx)+abs(yy*y)));
   float b=0.5/sqrt(abs(x*xx+yy*y));
   return a*b;
}

float3 sim(float3 p,float s){
   float3 ret=p;
   ret=p+s/2.0;
   ret=frac(ret/s)*s-s/40.0;
   return ret;
}

float2 rot(float2 p,float r){
   float2 ret;
   ret.x=p.x*sin(r)*cos(r)-p.y*cos(r);
   ret.y=p.x*cos(r)+p.y*sin(r);
   return ret;
}

float2 rotsim(float2 p,float s){
   float2 ret=p;
   ret=rot(p,-PI/(s*2.0));
   ret=rot(p,floor(atan2(ret.x,ret.y)/PI*s)*(PI/s));
   return ret;
}

float2 zoom(float2 p,float f){
    return float2(p.x*f,p.y*f);
}

float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;

    position=rot(position,sin(timer+length(position))*1.0);
    position=zoom(position,sin(timer*2.0)*0.5+0.8);

    position=position*2.0;
   
    float x=position.x;
    float y=position.y;
   
    float t=timer*0.5;

    float a=
        makePoint(x,y,3.3,2.9,0.3,0.3,t);
    a=a+makePoint(x,y,1.9,2.0,0.4,0.4,t);
    a=a+makePoint(x,y,0.8,0.7,0.4,0.5,t);
    a=a+makePoint(x,y,2.3,0.1,0.6,0.3,t);
    a=a+makePoint(x,y,0.8,1.7,0.5,0.4,t);
    a=a+makePoint(x,y,0.3,1.0,0.4,0.4,t);
    a=a+makePoint(x,y,1.4,1.7,0.4,0.5,t);
    a=a+makePoint(x,y,1.3,2.1,0.6,0.3,t);
    a=a+makePoint(x,y,1.8,1.7,0.5,0.4,t);   
    
    float b=
        makePoint(x,y,1.2,1.9,0.3,0.3,t);
    b=b+makePoint(x,y,0.7,2.7,0.4,0.4,t);
    b=b+makePoint(x,y,1.4,0.6,0.4,0.5,t);
    b=b+makePoint(x,y,2.6,0.4,0.6,0.3,t);
    b=b+makePoint(x,y,0.7,1.4,0.5,0.4,t);
    b=b+makePoint(x,y,0.7,1.7,0.4,0.4,t);
    b=b+makePoint(x,y,0.8,0.5,0.4,0.5,t);
    b=b+makePoint(x,y,1.4,0.9,0.6,0.3,t);
    b=b+makePoint(x,y,0.7,1.3,0.5,0.4,t);
    
    float c=
        makePoint(x,y,3.7,0.3,0.3,0.3,t);
    c=c+makePoint(x,y,1.9,1.3,0.4,0.4,t);
    c=c+makePoint(x,y,0.8,0.9,0.4,0.5,t);
    c=c+makePoint(x,y,1.2,1.7,0.6,0.3,t);
    c=c+makePoint(x,y,0.3,0.6,0.5,0.4,t);
    c=c+makePoint(x,y,0.3,0.3,0.4,0.4,t);
    c=c+makePoint(x,y,1.4,0.8,0.4,0.5,t);
    c=c+makePoint(x,y,0.2,0.6,0.6,0.3,t);
    c=c+makePoint(x,y,1.3,0.5,0.5,0.4,t);
   
    float3 d=float3(a,b,c)/31.0;
	
    return float4(d.x,d.y,d.z,1.0);
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique blobsMod
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
