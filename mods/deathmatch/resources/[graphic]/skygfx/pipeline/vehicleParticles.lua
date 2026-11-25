-- Vehicle particle producers from SLUS-21590. Wheel friction states are shared
-- by MTA and VCS: normal, spinning, sliding, locked (0..3).
VehicleParticles = {}
local profiles=setmetatable({},{__mode="k"})
local random,min,max=math.random,math.min,math.max
local groundVehicles={Automobile=true,["Monster Truck"]=true,Quad=true,Bike=true}
local wheelNames={"wheel_lf_dummy","wheel_lb_dummy","wheel_rf_dummy","wheel_rb_dummy"}
local bikeWheels={"wheel_front","wheel_rear"}
local surfaceKinds={}
local dustColors={grass={110,138,50,.02,.08},gravel={64,64,64,.04,.05},mud={64,32,16,.02,.04}}
local rotorColors={grass={10,10,3},gravel={10,8,7},mud={10,6,3},sand={10,10,7}}
local function range(a,b) return a+(b-a)*random() end
local function point(m,x,y,z)
    return m[4][1]+m[1][1]*x+m[2][1]*y+m[3][1]*z,
           m[4][2]+m[1][2]*x+m[2][2]*y+m[3][2]*z,
           m[4][3]+m[1][3]*x+m[2][3]*y+m[3][3]*z
end

local function surfaceKind(material)
    local kind=surfaceKinds[material]
    if not kind then
        kind=engineGetSurfaceProperties(material,"wheeleffect") or "disabled"
        if kind=="dust" then kind="mud" end
        surfaceKinds[material]=kind
    end
    return kind
end

local function profile(vehicle)
    local model=getElementModel(vehicle)
    local original=tonumber(getElementData(vehicle,"vcs_vehicle:originalModel",false)
        or getElementData(vehicle,"npchlc_traffic:originalModel",false))
    local p=profiles[vehicle]
    if p and p.model==model and p.original==original then return p end
    local kind=getVehicleType(vehicle)
    local d=VehicleParticleDummies[original]
    local ex,ey,ez,lx,ly,lz,flags,electric
    if d then
        ex,ey,ez,lx,ly,lz,flags,electric=unpack(d)
    else
        ex,ey,ez=getVehicleDummyPosition(vehicle,"exhaust")
        lx,ly,lz=getVehicleDummyPosition(vehicle,"engine")
        local handling=getVehicleHandling(vehicle)
        flags=0
        if handling then
            flags=handling.modelFlags
            electric=handling.engineType=="electric"
        end
    end
    local components=getVehicleComponents(vehicle) or {}
    local wheels={}
    for i,name in ipairs(kind=="Bike" and bikeWheels or wheelNames) do
        if components[name] then wheels[i]=name end
    end
    p={model=model,original=original,kind=kind,ex=ex,ey=ey,ez=ez,lx=lx,ly=ly,lz=lz,
       flags=flags,electric=electric,wheels=wheels,seed=random(0,255)}
    profiles[vehicle]=p
    return p
end

-- CAutomobile::PreRender 00141FE8; model-info +C0, handling flags +D0.
local function addExhaust(vehicle,p,m,driver,forwardSpeed,vx,vy)
    if not p.ex or (p.ex==0 and p.ey==0 and p.ez==0) or forwardSpeed>=130 or
            bitAnd(p.flags,0x1000)~=0 or not getVehicleEngineState(vehicle) then return end
    local gas=driver and getPedAnalogControlState(driver,"accelerate") or 0
    if (gas+1.1)*range(1,3)<=2 then return end
    if forwardSpeed<10 then
        local steer=driver and ((getPedAnalogControlState(driver,"vehicle_left") or 0)-
                                (getPedAnalogControlState(driver,"vehicle_right") or 0)) or 0
        local angle=math.rad(steer*35)
        local scale=range(-.06,-.03)
        vx=(m[2][1]*math.cos(angle)-m[1][1]*math.sin(angle))*scale
        vy=(m[2][2]*math.cos(angle)-m[1][2]*math.sin(angle))*scale
    end
    local x,y,z=point(m,p.ex,p.ey,p.ez)
    AddParticle(65,x,y,z,vx,vy,0)
    local dual=bitAnd(p.flags,0x2000)~=0
    local x2,y2,z2
    if dual then
        x2,y2,z2=point(m,-p.ex,p.ey,p.ez)
        AddParticle(65,x2,y2,z2,vx,vy,0)
    end
    if gas>.5 and (getVehicleCurrentGear(vehicle) or 0)<3 then
        if random(2)==1 then AddParticle(65,x,y,z,vx,vy,0)
        elseif dual then AddParticle(65,x2,y2,z2,vx,vy,0) end
    end
end

-- CAutomobile::AddDamagedVehicleParticles 00140B28.
local function addDamage(vehicle,p,m,frame,vx,vy,vz,speed)
    local health=getElementHealth(vehicle)
    if health>=650 or health<=1 or not p.lx or
       (getPedOccupiedVehicle(localPlayer)~=vehicle and frame%2~=0) then return end
    local lx,ly,lz=p.lx,p.ly,p.lz
    if p.kind~="Bike" and getVehicleDoorState(vehicle,0)>=2 then
        lx,ly=lx-.5,ly-.3
    else
        lx,ly=lx-.1,ly-.1
    end
    local x,y,z=point(m,lx,ly,lz)
    z=z+.15
    if p.electric and health<460 then
        local offset=range(0,.04)*(1-speed*2)
        local n=health<320 and bitAnd(random(0,255),10)+2 or bitAnd(random(0,255),5)+1
        for _=1,n do
            AddParticle(1,x,y,z,.85*vx+m[1][1]*offset,.85*vy+m[1][2]*offset,.85*vz+m[1][3]*offset+.001)
        end
        if bitAnd(frame,10)==0 then AddParticle(health<320 and 56 or 55,x,y,z,.8*vx,.8*vy,.8*vz,.1,nil,nil,nil,nil,0,0,0,1000) end
        return
    end
    if health<250 then return end
    vx,vy,vz=vx*.85,vy*.85,vz*.85
    if health<390 then
        local smoke=health<320 and 56 or 55
        if smoke==55 then
            for _=1,2 do AddParticle(33,x,y,z,.75*vx,.75*vy,.75*vz) end
        end
        local scale=smoke==56 and .8 or .85
        for _=1,2 do AddParticle(smoke,x,y,z,scale*vx,scale*vy,scale*vz) end
    elseif health<460 then
        for _=1,(frame%2==0 and 4 or 2) do AddParticle(33,x,y,z,.9*vx,.9*vy,.9*vz) end
    else
        local t=frame%256
        if t<10 or (t>=26 and t<70) or (t>=101 and t<160) or (t>=176 and t<200) or t>235 then return end
        for _=1,2 do AddParticle(33,x,y,z,vx,vy,vz+max(0,1-speed*1.6)*.05,.1,nil,nil,nil,nil,0,0,0,1000) end
    end
end

-- AddWheelDirtAndWater 001419D0 / bike 0033DCA0. Select VCS surface
-- responses through the SA material's wheel-effect property.
local function addWheelDirt(kind,frame,rain,x,y,z,vx,vy,speed,draw)
    if kind=="sand" then
        if frame%4<2 and (rain<=0 or range(rain,1.01)<=.5) then
            AddParticle(4,x,y,z,vx*.5,vy*.5,range(.02,.055),speed*2,170,165,140,255)
        end
        return false
    end
    if not draw then return false end
    local col=dustColors[kind]
    if col then
        for _=1,4 do
            AddParticle(3,x,y,z,vx*-.05,vy*-.05,range(.03,.06),col[4]+random()*col[5],col[1],col[2],col[3],255)
        end
        return kind=="gravel"
    end
    if rain>.01 then
        if frame%2==1 then AddParticle(39,x,y,z+.5,0,0,range(.005,.04),range(.1,.5)) end
        return false
    end
    return true
end

local function addWheels(vehicle,p,m,frame,rain,vx,vy,vz,speed,fwd)
    local damage={getVehicleWheelStates(vehicle)}
    for i,name in pairs(p.wheels) do
        local state=getVehicleWheelFrictionState(vehicle,i-1)
        if (state==1 or math.abs(fwd)>5) and isVehicleWheelOnGround(vehicle,i-1) then
            local x,y,z=getVehicleComponentPosition(vehicle,name,"world")
            if x then
                local hit,_,_,gz,_,nx,ny,nz,material=processLineOfSight(x,y,z+.25,x,y,z-1.3,true,false,false,true,false)
                if hit then
                    local kind=surfaceKind(material)
                    local rubber=addWheelDirt(kind,frame,rain,x,y,gz,vx,vy,speed,math.abs(fwd)<90)
                    if state==1 then
                        if rubber then
                            AddParticle(67,x,y,gz+.25,0,0,0)
                            AddParticle(67,x,y,gz+.25,0,0,.05)
                        end
                        AddParticle(66,x,y,gz+.25,0,0,0)
                    elseif state==2 or state==3 then AddParticle(66,x,y,gz+.25,0,0,0) end
                    if damage[i]==1 and speed>.1 and kind=="disabled" then
                        local dot=vx*nx+vy*ny+vz*nz
                        local sign=i<=2 and -.05 or .05
                        local ax=(vx-dot*nx+sign*m[1][1])*.25
                        local ay=(vy-dot*ny+sign*m[1][2])*.25
                        local az=(vz-dot*nz+sign*m[1][3])*.25
                        for _=1,(speed>.4 and 4 or (speed>.2 and 2 or 1)) do AddParticle(1,x,y,gz,ax,ay,az) end
                    end
                end
            end
        end
    end
end

-- CVehicle::HeliDustGenerate 003EF3B8. Each tick samples one ground sector
-- and emits the following adjacent points on the 32-segment ring.
local function heliDust(vehicle,m,frame)
    local rotor=math.abs(getVehicleRotorSpeed(vehicle) or 0)
    if rotor<=.1125 then return end
    local x,y,z=m[4][1],m[4][2],m[4][3]
    local ground=getGroundPosition(x,y,z+.5)
    local water=getWaterLevel(x,y,z,true)
    if water then ground=math.max(ground or -101,water) end
    if not ground then return end
    local height=z-ground
    local rc=getElementModel(vehicle)==501 or getElementModel(vehicle)==465
    local radius=(rc and 3 or 10)-height
    if radius<=0 then return end
    local offset=rc and .3 or 1
    x,y=x-height*m[3][1]*offset*.5,y-height*m[3][2]*offset*.5
    if rc then radius=3 end
    local n=min(9,math.ceil((rotor-.1125)*9*400/43))
    local index=(frame%8)*4
    local a=index*math.pi/16
    local px,py=x+radius*math.cos(a),y+radius*math.sin(a)
    local hit,_,_,gz,_,_,_,_,material=processLineOfSight(px,py,z+.5,px,py,ground-10,true,false,false,true,false)
    water=getWaterLevel(px,py,z,true)
    local wet=water and (not hit or water>gz)
    if not (wet or hit) then return end
    local level=wet and water or gz
    local color=not wet and rotorColors[surfaceKind(material)]
    for k=0,n-1 do
        a=(index+k)*math.pi/16
        local dx,dy=radius*math.cos(a),radius*math.sin(a)
        px,py=x+dx,y+dy
        local scale=rc and .07 or 1
        if wet and (n-k)%2==0 then
            local v=getTimeCycleValue("values")
            local r,g,b=48,48,60
            if v then r,g,b=(v[1]+.3*v[13])*.25,(v[2]+.3*v[14])*.25,(v[3]+.3*v[15])*.25 end
            AddParticle(44,px,py,level,.01*dx+range(-.1,.1),.01*dy+range(-.1,.1),.51,
                        radius*.3*scale,r,g,b,random(8,32),random(0,9),random(0,89),1)
        elseif wet then
            AddParticle(31,px,py,level,.01*dx,.01*dy,.01,radius*.25*scale,255,255,255,32)
        elseif z-level<20 then
            AddParticle(53,px,py,level,.01*dx,.01*dy,.01,rc and .04 or 0,
                        10,color and color[2] or 10,color and color[3] or 10,32)
        end
    end
end

function VehicleParticles.Update(vehicle,frame,rain)
    if isVehicleBlown(vehicle) then return end
    local p=profile(vehicle)
    if not groundVehicles[p.kind] and p.kind~="Helicopter" then return end
    local m=getElementMatrix(vehicle)
    if not m then return end
    if p.kind=="Helicopter" then heliDust(vehicle,m,frame) return end
    local driver=getVehicleController(vehicle)
    local vx,vy,vz=getElementVelocity(vehicle)
    local speed=math.sqrt(vx*vx+vy*vy+vz*vz)
    local fwd=180*(vx*m[2][1]+vy*m[2][2]+vz*m[2][3])
    addExhaust(vehicle,p,m,driver,fwd,vx,vy)
    addDamage(vehicle,p,m,frame+p.seed,vx,vy,vz,speed)
    if speed>.025 or driver then addWheels(vehicle,p,m,frame,rain,vx,vy,vz,speed,fwd) end
end

-- CAutomobile::VehicleDamage (00136C10) checks damage impulse before
-- dispatching body impacts to dmgDrawCarCollidingParticles (00136868).
local function collision(other,impulse,_,x,y,z,nx,ny,nz)
    if not x or not impulse or not isElementStreamedIn(source) or
       getElementDimension(source)~=getElementDimension(localPlayer) or getElementInterior(source)~=getCameraInterior() then return end
    local otherType=isElement(other) and getElementType(other)
    if otherType=="player" or otherType=="ped" or isVehicleBlown(source) then return end
    local model=getElementModel(source)
    local minImpulse=(model==465 or model==501) and 1 or 25
    if impulse<=minImpulse then return end
    if (not otherType or otherType=="building" or otherType=="object") and nz then
        local up=getElementMatrix(source)[3]
        if nx*up[1]+ny*up[2]+nz*up[3]>.6 then return end
    end
    local factor=math.floor(impulse/20)
    for _=1,(factor+4)%32 do AddParticle(1,x,y,z,range(-.1,.1),range(-.1,.1),.006) end
    for _=1,min(15,factor+2) do AddParticle(61,x+range(-1.2,1.2),y+range(-1.2,1.2),z,0,0,0,.5) end
    local r,g,b=getVehicleColor(source,true)
    for _=1,min(10,math.floor(impulse/50)+1) do
        AddParticle(62,x,y,z,range(-.25,.25),range(-.25,.25),range(.1,.25),range(.02,.08),
                    r,g,b,255,random(-40,39),0,random(0,3))
    end
end
function VehicleParticles.start()
    addEventHandler("onClientVehicleCollision",root,collision)
end
function VehicleParticles.stop()
    removeEventHandler("onClientVehicleCollision",root,collision)
    profiles=setmetatable({},{__mode="k"})
end
