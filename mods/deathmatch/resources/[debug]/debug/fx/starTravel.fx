//
// starTravel.fx
// http://glslsandbox.com/e#28499.0
// glsl to hlsl translation by Ren712

//------------------------------------------------------------------------------------------
// Shader settings
//------------------------------------------------------------------------------------------
float2 sTexSize = float2(800,600);
float2 sScale = float2(1,1);
float2 sCenter = float2(0.5,0.5);
float2 mouse = float2(0.0,0.0);

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

float3 mod3(float3 x, float3 y)
{
    return x - y * floor(x/y);
}

#define iterations 14
#define formuparam2 0.79
 
#define volsteps 5
#define stepsize 0.290
 
#define zoom 0.900
#define tile   0.850
#define speed2  0.10
 
#define brightness 0.003
#define darkmatter 0.400
#define distfading 0.560
#define saturation 0.800


#define transverseSpeed zoom*2.0
#define cloud 0.11 


float field(float3 p) {
	
    float strength = 7. + .03 * log(1.e-6 + frac(sin(gTime) * 4373.11));
    float accum = 0.;
    float prev = 0.;
    float tw = 0.;


    for (int i = 0; i < 6; ++i) {
        float mag = dot(p, p);
        p = abs(p) / mag + float3(-.5, -.8 + 0.1*sin(gTime*0.7 + 2.0), -1.1+0.3*cos(gTime*0.3));
        float w = exp(-float(i) / 7.);
        accum += w * exp(-strength * pow(abs(mag - prev), 2.3));
        tw += w;
        prev = mag;
    }
    return max(0., 5. * accum / tw - .7);
}


float4 PixelShaderFunction(PSInput PS) : COLOR0
{
    // Get TexCoord
    float2 position = PS.TexCoord;
    float timer = gTime;

    //float2 uv2 = 2. * gl_FragCoord.xy / resolution.xy - 1.;
    float2 uvs = position * sTexSize.xy / max(sTexSize.x, sTexSize.y);
	
    float time2 = timer;
       
    float speed = speed2;
    speed = -0.02 * cos(time2*0.02 + 3.1415926/4.0);
    float formuparam = formuparam2;

    //get coords and direction
    float2 uv = uvs;
       
    //mouse rotation
    float a_xz = 0.9;
    float a_yz = -.6;
    //float a_xy = 0.9 + timer*0.04; // altered by Ren
    float a_xy = 0.9;	
	
    float2x2 rot_xz = float2x2(cos(a_xz),sin(a_xz),-sin(a_xz),cos(a_xz));
    float2x2 rot_yz = float2x2(cos(a_yz),sin(a_yz),-sin(a_yz),cos(a_yz));
    float2x2 rot_xy = float2x2(cos(a_xy),sin(a_xy),-sin(a_xy),cos(a_xy));

    float v2 =1.0;

    float3 dir=float3(uv*zoom,1.);
 
    float3 from=float3(0.0, 0.0,0.0);
    from.x -= 5.0*(mouse.x-0.5);
    from.y -= 5.0*(mouse.y-0.5);
               
    float3 forward = float3(0.,0.,1.);
    from.x += transverseSpeed*(1.0)*cos(0.01*timer) + 0.001*timer;
    from.y += transverseSpeed*(1.0)*sin(0.01*timer) +0.001*timer;
	
    from.z += 0.003*timer;
    dir.xy = mul(dir.xy,rot_xy);
    forward.xy = mul(forward.xy,rot_xy);

    dir.xz = mul(dir.xz,rot_xz);
    forward.xz = mul(forward.xz,rot_xz);

    dir.yz = mul(dir.yz,rot_yz);
    forward.yz = mul(forward.yz,rot_yz);

    from.xy = mul(from.xy,-rot_xy);
    from.xz =mul(from.xz,rot_xz);
    from.yz = mul(from.yz,rot_yz);

    //zoom
    float zooom = (time2-3311.)*speed;
    from += forward* zooom;
    float sampleShift = mod( zooom, stepsize );
	 
    float zoffset = -sampleShift;
    sampleShift /= stepsize; // make from 0 to 1

    //volumetric rendering
    float s=0.24;
    float s3 = s + stepsize/2.0;
    float3 v=float3(0,0,0);
    float t3 = 0.0;
	
    float3 outCol = float3(0,0,0);
    for (int r=0; r<volsteps; r++) {
        float3 p2=from+(s+zoffset)*dir;// + float3(0.,0.,zoffset);
        float3 p3=from+(s3+zoffset)*dir;// + float3(0.,0.,zoffset);
		
        p2 = abs(float3(tile,tile,tile)-mod3(p2,float3(tile*2,tile*2,tile*2))); // tiling fold
        p3 = abs(float3(tile,tile,tile)-mod3(p3,float3(tile*2,tile*2,tile*2))); // tiling fold
		
        #ifdef cloud
        t3 = field(p3);
        #endif
		
        float pa,a=pa=0.;
        for (int i=0; i<iterations; i++) {
            p2=abs(p2)/dot(p2,p2)-formuparam; // the magic formula
            //p=abs(p)/max(dot(p,p),0.005)-formuparam; // another interesting way to reduce noise
            float D = abs(length(p2)-pa); // absolute sum of average change
            a += i > 7 ? min( 12., D) : D;
            pa=length(p2);
        }
		
        //float dm=max(0.,darkmatter-a*a*.001); //dark matter
        a*=a*a; // add contrast
        //if (r>3) fade*=1.-dm; // dark matter, don't render near
        // brightens stuff up a bit
        float s1 = s+zoffset;
        // need closed form expression for this, now that we shift samples
        float fade = pow(distfading,max(0.,float(r)-sampleShift));
		
		
        //t3 += fade;
		
        v+=fade;
        //outCol -= fade;

        // fade out samples as they approach the camera
        if( r == 0 )
            fade *= (1. - (sampleShift));
            // fade in samples as they approach from the distance
        if( r == volsteps-1 )
            fade *= sampleShift;
        v+=float3(s1,s1*s1,s1*s1*s1*s1)*a*brightness*fade; // coloring based on distance

        outCol += lerp(.4, 1., v2) * float3(1.8 * t3 * t3 * t3, 1.4 * t3 * t3, t3) * fade;
	
        s+=stepsize;
        s3 += stepsize;
        
    }
    
    float lenV = length(v);		
    v = lerp(float3(lenV,lenV,lenV),v,saturation); //color adjust

    float4 forCol2 = float4(v*.01,1.);
	
    #ifdef cloud
        outCol *= cloud;
    #endif
	
    outCol.b *= 1.8;
    outCol.r *= 0.05;
    outCol.b = 0.5*lerp(outCol.g, outCol.b, 0.8);
    outCol.g = 0.0;

//	outCol.bg = lerp(outCol.gb, outCol.bg, 0.5*(cos(time*0.01) + 1.0));

    return float4(forCol2 + float4(outCol, 1.0));
}

//------------------------------------------------------------------------------------------
// Techniques
//------------------------------------------------------------------------------------------
technique starTravel
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
