-- CParticle::AddParticle (001E9078), Update (001E9C90), Render (001EAD88).
CParticle = {}
local systems, byName = ParticleSystems, {}
local materials, atlas = {}, nil
local count, lastTick, remainder = 0, nil, 0
local drawn, accepted, exhausted = 0, 0, 0
local period, step = 1000/30, 50/30
local floor, min, max, random = math.floor, math.min, math.max, math.random
local worldDimension, worldInterior
local function flag(value, mask) return bitAnd(value, mask) ~= 0 end
local function clamp(value, upper) return max(0,min(upper or 255,value)) end
local function jitter() return random(-10,9)*0.1 end
local function rate(amount, period)
    local n=amount/max(1,period)
    return n<0 and math.ceil(n) or floor(n)
end
for id=0,89 do
    local d=systems[id]
    byName[d.name]=d
    d.particles={}
    d.blend=flag(d.flags,4) and "alpha" or (flag(d.flags,128) and "soft" or "add")
    d.screen=flag(d.flags,1024)
    d.ground=flag(d.flags,1)
    d.bump=flag(d.flags,4096)
    d.drag=d.friction>1 and (d.friction/100)^step or 1
    d.dimRate=rate(d.intensityFade,d.intensityPeriod)
    d.fadeRate=rate(d.alphaFade,d.alphaPeriod)
end

function AreParticlesEnabled()
    return isElement(atlas) and isElement(materials.alpha) and isElement(materials.soft)
        and isElement(materials.add)
end

local function groundAt(x,y,z)
    local hit,_,_,height=processLineOfSight(x,y,z+.5,x,y,-100,true,true,false,true,false)
    if hit then return height end
end

local function currentWorld()
    local dimension,interior=getElementDimension(localPlayer),getCameraInterior()
    if dimension~=worldDimension or interior~=worldInterior then
        for id=0,89 do systems[id].particles={} end
        count,remainder,lastTick=0,0,nil
        worldDimension,worldInterior=dimension,interior
    end
end

local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end

function AddParticle(id,x,y,z,vx,vy,vz,size,r,g,b,a,spin,angle,frame,life,visibility)
    local d=systems[id] or byName[id]
    if not d or not AreParticlesEnabled() or not finite(x) or not finite(y) or not finite(z) then return false end
    vx,vy,vz=vx or 0,vy or 0,vz or 0
    if not finite(vx) or not finite(vy) or not finite(vz) or not finite(size or 0)
        or not finite(spin or 0) or not finite(angle or 0) or not finite(frame or 0)
        or not finite(life or 0) or not finite(visibility or 1) then return false end
    if r~=nil and not (finite(r) and finite(g) and finite(b) and finite(a or 255)) then return false end
    currentWorld()
    if count>=750 then exhausted=exhausted+1 return false end
    if d.rangeSq>0 and not d.screen then
        local cx,cy,cz=getCameraMatrix()
        if (x-cx)^2+(y-cy)^2+(z-cz)^2>d.rangeSq then return false end
    end
    local radius=d.size
    frame=frame and frame~=0 and floor(frame) or d.first
    spin=spin and spin~=0 and spin or d.spin
    spin=(random(2)==1 and -spin or spin)
    local hasColor=r~=nil and a~=0
    if not hasColor then
        local change=d.variation>0 and (1+random(-d.variation,d.variation-1)*.01) or 1
        r,g,b=clamp(d.r*change),clamp(d.g*change),clamp(d.b*change)
    end
    local vertical=flag(d.flags,32)
    if d.positionError~=0 then
        x,y=x+d.positionError*jitter(),y+d.positionError*jitter()
        if vertical then z=z+d.positionError*jitter() end
    end
    if d.velocityError~=0 then
        vx,vy=vx+d.velocityError*jitter(),vy+d.velocityError*jitter()
        if vertical then vz=vz+d.velocityError*jitter() end
    end
    local growth=d.growth
    if d.growthError~=0 and not flag(d.flags,8) then growth=growth+d.growthError*(1+jitter()) end
    if d.spinError>0 then spin=spin+random(-d.spinError,d.spinError-1) end
    life=life and life~=0 and life or d.life
    if d.lifeError~=0 then
        local e=jitter()
        life=life+d.life*e*(e>0 and d.lifeError or 1/d.lifeError)
    end
    local ground
    if d.ground or d.bump then
        ground=groundAt(x,y,z)
        if not ground or (d.ground and z<=ground) then return false end
    end
    local intensity,updates=d.intensity,0
    if d.id==40 or d.id==41 then
        local large=d.id==41
        intensity,updates=intensity-random(0,1)*30,random(0,7)
        radius=large and .8+random()*.6 or .3+random()*.5
        z=z+(random()-.5)*(large and .6 or .2)
    elseif d.id==9 then
        vz=vz*(random()*2.5+.5)
    elseif d.id==47 then
        z=z+d.positionError*jitter()*20
    end
    local p={x=x,y=y,z=z,vx=vx,vy=vy,vz=vz,size=size and size~=0 and size or radius,
        life=life,age=0,spin=spin,angle=angle or 0,frame=frame,updates=updates,
        intensity=intensity,alpha=d.alpha,growth=growth,r=r,g=g,b=b,ground=ground,
        fadeColor=not hasColor and d.colorTime>0,opacity=clamp(visibility or 1,1),
        boatAlpha=visibility~=nil and d.id==44}
    d.particles[#d.particles+1]=p
    if d.id==13 or d.id==27 or d.id==74 or (d.id>=40 and d.id<=43) then
        NativeFire.Register(d.id,x,y,z)
    end
    count,accepted=count+1,accepted+1
    return true
end

local function advance(d,p,wind)
    p.age=p.age+period
    if p.age>p.life or p.alpha==0 then return false end
    local dx,dy,dz=p.vx*step,p.vy*step,p.vz*step
    local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
    local oldZ=p.z
    p.x,p.y,p.z=p.x+dx,p.y+dy,p.z+dz
    if d.id==84 then
        local a=math.rad(p.angle)
        p.vx,p.vy,p.vz=.5*math.cos(a),math.cos(a),.25*math.sin(a)
        local cx,cy,cz=getCameraMatrix()
        if p.z>40 or (p.x-cx)^2+(p.y-cy)^2+(p.z-cz)^2<3600 then return false end
    end
    if d.wind~=0 and wind>0 and distance>0 then
        local f=-wind*.002*d.wind*step
        local wx,wy=f*(.75+random()*.5),f*(.75+random()*.5)
        p.vx,p.vy=p.vx+wx,p.vy+wy
        distance=max(distance,math.sqrt(wx*wx+wy*wy))
    end
    if d.screen and flag(d.flags,2048) and (p.x< -10 or p.x>650 or p.y< -10 or p.y>458) then return false end
    local splash=d.id==44 or d.id==45
    if splash then
        local water=getWaterLevel(p.x,p.y,p.z,true)
        if water and p.z+p.size<water then return false end
    end
    if p.fadeColor then
        local t=min(1,p.age/d.colorTime)
        p.r,p.g,p.b=d.r+(d.endR-d.r)*t,d.g+(d.endG-d.g)*t,d.b+(d.endB-d.b)*t
    end
    if not flag(d.flags,8) then
        if d.id==33 or d.id==65 then distance=distance*2 end
        local growth=p.growth>0 and p.growth*(1+distance) or p.growth
        if splash and p.size>1.2 and growth>0 then
            p.size,p.vz=p.size-growth,p.vz-.15
        else
            p.size=p.size+growth
        end
        if p.size<0 then return false end
    end
    p.vx,p.vy,p.vz=p.vx*d.drag,p.vy*d.drag,p.vz*d.drag
    if (d.gravity>0 and p.vz> -50*d.gravity) or (d.gravity<0 and p.vz< -5*d.gravity) then
        p.vz=p.vz-d.gravity*step
    end
    if d.ground and oldZ<p.ground then
        if d.id==34 or d.id==35 or (d.id==5 and random(2)==1) then
            AddParticle(random(2)==1 and 36 or 38,p.x,p.y,p.ground+.05,0,0,0)
        end
        if d.id==34 or d.id==35 or d.id==5 or d.id==6 or d.id==7 then return false end
    elseif d.bump and oldZ<p.ground then
        if d.id==69 or d.id==70 then
            AddParticle(71,p.x,p.y,p.ground+.05,random()*.04-.02,random()*.04-.02,
                random()*.05+.05,p.size,p.r,p.g,p.b,255,p.spin)
        elseif d.id==71 then
            AddParticle(72,p.x,p.y,p.ground+.05,0,0,random()*.03+.03,p.size,p.r,p.g,p.b,255)
        end
        return false
    elseif flag(d.flags,2) and dz<0 then
        local hit,_,_,height=processLineOfSight(p.x-dx,p.y-dy,oldZ,p.x,p.y,p.z,true,true,false,true,false)
        if hit then
            p.z=height
            if d.id==10 then
                p.vx,p.vy,p.vz=p.vx*.8,p.vy*.8,-.4*p.vz
                if p.vz<.005 then p.vz=0 end
            elseif d.id==54 then
                AddParticle(28,p.x,p.y,p.z,0,0,.05,.2)
                return false
            end
        end
    end
    p.intensity=clamp(p.intensity-d.dimRate)
    if d.fadeRate~=0 then p.alpha=clamp(p.alpha-d.fadeRate,d.id==58 and 100 or 255) end
    if d.animationPeriod~=0 then
        if p.updates>d.animationPeriod then
            p.updates=0
            p.frame=p.frame+1
            if p.frame>d.last then p.frame=flag(d.flags,64) and d.first or d.last end
        else
            p.updates=p.updates+1
        end
    end
    p.angle=p.angle+p.spin
    return p.alpha>0
end

local function simulate(wind)
    for id=0,89 do
        local d=systems[id]
        local list=d.particles
        local write=1
        for index=1,#list do
            local p=list[index]
            if advance(d,p,wind) then
                list[write]=p
                write=write+1
            else
                count=count-1
            end
        end
        for index=#list,write,-1 do list[index]=nil end
    end
end

local function submit(vertices,material)
    if #vertices==0 then return end
    if dxDrawMaterialPrimitive3D("trianglelist",material,"postfx",unpack(vertices)) then
        drawn=drawn+#vertices/6
    end
end

local function render()
    local cx,cy,cz,tx,ty,tz,roll=getCameraMatrix()
    local forward=Vector3(tx-cx,ty-cy,tz-cz)
    if forward.length<.00001 then return end
    forward=forward/forward.length
    local right=Vector3(forward.y,-forward.x,0)
    right=right.length<.00001 and Vector3(1,0,0) or right/right.length
    local up=right:cross(forward)
    local rotation=math.rad(roll or 0)
    local sx,sy=guiGetScreenSize()
    for id=0,89 do
        local d=systems[id]
        local material=d.screen and materials[d.blend.."Screen"]
            or ((id==37 or id==76) and materials[d.blend.."Overlay"] or materials[d.blend])
        local vertices={}
        for index=#d.particles,1,-1 do
            local p=d.particles[index]
            local uv=d.frames[(d.last==0 and 0 or p.frame)+1] or d.frames[1]
            local alpha=p.alpha*p.opacity
            local power=p.intensity/256*(d.blend=="add" and p.opacity or 1)
            if p.boatAlpha then power=power*p.alpha/255 end
            local color=tocolor(clamp(p.r*power),clamp(p.g*power),clamp(p.b*power),alpha)
            if d.screen then
                local fw=p.size*(63+d.stretchX*(.1+random()*.9)*p.frame)*sx/640
                local fh=p.size*(63+d.stretchY*(.1+random()*.9)*p.frame)*sy/448
                -- MTA's "add" mode uses ONE/INVSRCALPHA, which darkens the
                -- black background of PS2 additive rasters. Use the material's
                -- explicit particle blend state for screen sprites too.
                dxDrawImageSection(p.x*sx/640-fw,p.y*sy/448-fh,2*fw,2*fh,
                    uv[1]*1024-.5,uv[2]*1024-.5,(uv[3]-uv[1])*1024+1,(uv[4]-uv[2])*1024+1,
                    material,p.angle,0,0,color)
                drawn=drawn+1
            else
                local x,y,z=p.x,p.y,p.z
                local depth=(x-cx)*forward.x+(y-cy)*forward.y+(z-cz)*forward.z
                if depth>0 and not (id==74 and p.angle~=0 and p.alpha==255) then
                    -- 0039FC48 returns the 640x448 viewport's projected
                    -- unit size. Texture stretch is added in PS2 pixels.
                    local pixel=depth/448
                    local width=p.size*max(0,1+d.stretchX*pixel*(.1+random()*.9))
                    local height=p.size*max(0,1+d.stretchY*pixel*(.1+random()*.9))
                    local angle=rotation+math.rad(p.angle)
                    if flag(d.flags,16384) then
                        local distance=math.sqrt((x-cx)^2+(y-cy)^2+(z-cz)^2)
                        local fraction=math.sqrt((x-cx)^2+(y-cy)^2)/max(.001,distance)
                        width=width*math.cos(fraction*math.pi*.5)
                    end
                    if p.angle==0 then
                        if flag(d.flags,8) or flag(d.flags,16) then
                            local dx=p.vx*right.x+p.vy*right.y+p.vz*right.z
                            local dy=p.vx*up.x+p.vy*up.y+p.vz*up.z
                            local scale=flag(d.flags,8) and step or 1
                            height=height+d.trail*math.sqrt(dx*dx+dy*dy)*scale
                            if dx~=0 or dy~=0 then angle=rotation-math.atan2(dx,dy) end
                        elseif flag(d.flags,256) then
                            height=height+d.trail*math.abs(p.vz)*10
                        end
                        if id==35 then width=width*.05 end
                        if id==89 then width,z=.01,z+p.size end
                    end
                    local c,s=math.cos(angle),math.sin(angle)
                    local w=(right*c+up*s)*width
                    local h=(up*c-right*s)*height
                    local a={x-w.x+h.x,y-w.y+h.y,z-w.z+h.z,color,uv[1],uv[2]}
                    local b={x+w.x+h.x,y+w.y+h.y,z+w.z+h.z,color,uv[3],uv[2]}
                    local c1={x-w.x-h.x,y-w.y-h.y,z-w.z-h.z,color,uv[1],uv[4]}
                    local e={x+w.x-h.x,y+w.y-h.y,z+w.z-h.z,color,uv[3],uv[4]}
                    local n=#vertices
                    vertices[n+1],vertices[n+2],vertices[n+3]=a,b,c1
                    vertices[n+4],vertices[n+5],vertices[n+6]=c1,b,e
                    if n+6>=360 then submit(vertices,material) vertices={} end
                end
            end
        end
        submit(vertices,material)
    end
end

function CParticle.Render()
    if not AreParticlesEnabled() then return end
    currentWorld()
    local now=getTickCount()
    local elapsed=lastTick and (now-lastTick)%4294967296 or 0
    lastTick=now
    if elapsed>2000 then
        for id=0,89 do systems[id].particles={} end
        count,remainder=0,0
    end
    if isMainMenuActive() then return end
    remainder=remainder+min(elapsed,200)*getGameSpeed()
    local wind=getTimeCycleValue("wind") or 0
    while remainder>=period do
        ObjectParticles.Update()
        CExplosion.Update()
        if count>0 then simulate(wind) end
        remainder=remainder-period
    end
    drawn=0
    if count>0 then render() end
    CExplosion.Render()
end

function CParticle.GetMaterial(blend)
    return materials[blend]
end

-- US PS2 002C5C78 searches the BIRD_FRONT list in a 1.5-degree horizontal cone.
function CParticle.ShootBirds(x,y,z,forwardX,forwardY)
    local birds=systems[82].particles
    if #birds==0 then return end
    local threshold=math.cos(math.rad(1.5))*math.sqrt(forwardX*forwardX+forwardY*forwardY)
    for i=#birds,1,-1 do
        local p=birds[i]
        local dx,dy,dz=p.x-x,p.y-y,p.z-z
        local horizontal=dx*dx+dy*dy
        if horizontal+dz*dz<40000 and dx*forwardX+dy*forwardY>math.sqrt(horizontal)*threshold then
            for _=1,8 do
                if AddParticle(63,p.x,p.y,p.z,random()*6-3,random()*6-3,random()*6-3,
                    .3,p.r,p.g,p.b,255,random(20,39),0,random(0,3)) then
                    local feathers=systems[63].particles
                    feathers[#feathers].alpha=p.alpha
                end
            end
            table.remove(birds,i)
            count=count-1
        end
    end
end

function CParticle.GetStats()
    return {active=count,drawn=drawn,accepted=accepted,full=exhausted,capacity=750,
        spray=#systems[44].particles+#systems[45].particles}
end

function CParticle.Shutdown()
    NativeFire.Shutdown()
    for _,mat in pairs(materials) do if isElement(mat) then destroyElement(mat) end end
    if isElement(atlas) then destroyElement(atlas) end
    for id=0,89 do systems[id].particles={} end
    atlas,materials,lastTick=nil,{},nil
    count,remainder,drawn,accepted,exhausted=0,0,0,0,0
end

function CParticle.Initialise()
    CParticle.Shutdown()
    atlas=dxCreateTexture("txd/vcs-particles.png","argb",false,"clamp")
    if not atlas then return false end
    for _,blend in ipairs({"alpha","soft","add"}) do
        for overlay=0,2 do
            local macros={VCS_BOAT_FOAM="1"}
            if blend~="alpha" then macros.VCS_SPLASH_ADDITIVE="1" end
            if blend=="add" then macros.VCS_SPLASH_ONE="1" end
            if overlay==1 then macros.PARTICLE_OVERLAY="1" end
            if overlay==2 then macros.PARTICLE_SCREEN="1" end
            local material=dxCreateShader("shader/vcsWater.fx",macros)
            if not material then
                CParticle.Shutdown()
                return false
            end
            dxSetShaderValue(material,"SurfaceTexture",atlas)
            materials[blend..(overlay==2 and "Screen" or (overlay==1 and "Overlay" or ""))]=material
        end
    end
    NativeFire.Initialise(atlas)
    return true
end
