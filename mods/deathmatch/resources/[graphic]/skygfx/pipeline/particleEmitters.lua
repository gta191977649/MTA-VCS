-- USA PS2 world, pedestrian and projectile callers of CParticle::AddParticle.
ParticleEmitters = {}
local running = false
local period = 1000 / 30
local frame, remainder, nextScan, lastWorld, drying = 0, 0, 0, nil, 0
local nearby, projectiles, swimmers = {}, {}, {}
local bird, ship = {}, {}
local function range(a,b) return a+(b-a)*math.random() end

local function sameWorld(element)
    return getElementDimension(element)==getElementDimension(localPlayer)
        and getElementInterior(element)==getCameraInterior()
end

local function clearScene()
    nearby, projectiles, swimmers, bird, ship = {}, {}, {}, {}, {}
    nextScan, drying = 0, 0
end

local function collect(cx,cy,cz,now)
    nearby={}
    local dimension,interior=getElementDimension(localPlayer),getCameraInterior()
    for _,kind in ipairs({"vehicle","player","ped"}) do
        for _,element in ipairs(getElementsWithinRange(cx,cy,cz,90,kind,interior,dimension)) do
            if isElementStreamedIn(element) then nearby[#nearby+1]=element end
        end
    end
    for _,projectile in ipairs(getElementsByType("projectile")) do
        if sameWorld(projectile) and not projectiles[projectile] then
            local kind=getProjectileType(projectile)
            if kind==17 or kind==19 or kind==20 then
                local x,y,z=getElementPosition(projectile)
                projectiles[projectile]={kind=kind,x=x,y=y,z=z}
            end
        end
    end
    nextScan=now+250
end

-- CProjectileInfo::Update 00181208 and AddParticlesAlongLine 001E8E70.
local function updateProjectiles()
    for projectile,p in pairs(projectiles) do
        if not isElement(projectile) or not sameWorld(projectile) then
            projectiles[projectile]=nil
        else
            local x,y,z=getElementPosition(projectile)
            if p.kind==17 then
                local remaining=getProjectileCounter(projectile)
                if remaining and remaining<19500 then
                    for _,dx in ipairs({.2,-.2,0}) do AddParticle(23,x,y,z,dx,0,0,0) end
                end
            else
                local dx,dy,dz=x-p.x,y-p.y,z-p.z
                local length=math.sqrt(dx*dx+dy*dy+dz*dz)
                if length<100 then
                    local count=math.max(1,math.floor(length/.7))
                    for i=0,count-1 do
                        local t=i/count
                        AddParticle(73,p.x+dx*t,p.y+dy*t,p.z+dz*t,0,0,0,0)
                    end
                end
            end
            p.x,p.y,p.z=x,y,z
        end
    end
end

-- CParticleObject::UpdateClose at 002294A8. The map contains eight small
-- tiki flames and a vertical fountain. The tenth model effect has no placement.
local function updateObjects(cx,cy,interior,dimension)
    for _,site in ipairs(ParticleObjectSites) do
        local kind,x,y,z,dx,dy,_,size,area,world=unpack(site)
        if area==interior and world==dimension and (cx-x)^2+(cy-y)^2<=10000 then
            if kind==3 and frame%2==0 and math.random(2)==1 then
                AddParticle(13,x,y,z,dx,dy,range(.0125,.1)*size,size)
                AddParticle(57,x+range(-.625,.625)*size,y+range(-.625,.625)*size,z+range(.625,2.5)*size,0,0,0,0)
            elseif kind==5 then
                for _,sign in ipairs({-1,1}) do
                    local offset=sign*.015
                    for i=1,4 do
                        AddParticle(26,x+offset,y,z,offset,0,.1+range(.004,.008),range(.001,.005),nil,nil,nil,nil,0,0,1,1000)
                    end
                end
            end
        end
    end
end

local function horizonPosition(x,y,minimum,maximum)
    local angle=math.rad(math.random(0,1023))
    local distance=range(minimum,maximum)
    return x+distance*(math.cos(angle)-math.sin(angle)),y+distance*(math.sin(angle)+math.cos(angle))
end

local function stationary(state,x,y,z,now,interval)
    if not state.x or math.abs(x-state.x)+math.abs(y-state.y)+math.abs(z-state.z)>1.5 then
        state.x,state.y,state.z,state.moved=x,y,z,now
    end
    if now-state.moved<=5000 or now-(state.last or 0)<=interval then return false end
    state.last=now
    return true
end

-- Horizon birds 0026FFF8, ships 002702C0 and insects 003E5B20.
local function updateHorizon(cx,cy,cz,now,hour)
    if hour>=7 and hour<20 then
        local weather=VCSWeather.new
        if (weather==0 or weather==4) and stationary(bird,cx,cy,cz,now,1000) then
            local x,y=horizonPosition(cx,cy,90,150)
            AddParticle(82,x,y,cz+range(10,30),range(-1,1),range(-1,1),0,0)
        end
    end
    if frame%10==0 and not isPedInVehicle(localPlayer) and bitAnd(math.random(0,65535),5)~=0 then
        local x,y=horizonPosition(cx,cy,90,150)
        AddParticle(84,x,y,cz+range(7.5,30),0,0,0,0)
    end
    local px,py,pz=getElementPosition(localPlayer)
    if stationary(ship,px,py,pz,now,4000) then
        local x,y=horizonPosition(px,py,450,750)
        local water=getWaterLevel(x,y,pz)
        local ground=getGroundPosition(x,y,pz+25)
        if water and (not ground or ground<water) then
            AddParticle(83,x,y,water+9.5,range(-.1,.1),0,0,0,nil,nil,nil,nil,0,0,math.random(0,7))
        end
    end
end

-- CWeather::RenderRainStreaks 003E47B8 and ground steam 003E4270.
local function updateWeather(cx,cy,cz,tx,ty,rain,hour)
    local storm=rain>0 and (VCSWeather.data.wind or 0)>1.1
    if rain>0 then
        drying=800
        for _=1,math.floor(rain*5) do
            for _,y in ipairs({math.random(0,88),math.random(89,223),0}) do
                AddParticle(85,math.random(0,639),y,0,0,range(30,40),0,range(.1,.75),
                    nil,nil,nil,nil,0,0,bitAnd(math.floor(rain),3))
            end
        end
    end
    if rain==0 and drying>0 then
        if hour<7 or hour>17 then drying=0 return end
        drying=drying-1
    elseif not storm then
        return
    end
    local ground=getGroundPosition(cx,cy,cz+1)
    if not ground then return end
    local heading=math.atan2(ty-cy,tx-cx)
    local drift=storm and -.002 or 0
    local z=ground+(storm and .1 or .2)
    local alpha=storm and 32 or 24
    for _=1,20 do
        local angle=math.random(2)==1 and heading+range(-.8,.8) or range(0,2*math.pi)
        local radius=range(-10,30)+math.random(0,255)/255
        AddParticle(32,cx+radius*math.cos(angle),cy+radius*math.sin(angle),z,drift,drift,.015,0,255,255,255,alpha)
    end
end

local function addFootParticles(left)
    if not sameWorld(source) or isPedInVehicle(source) then return end
    local x,y,z=getPedBonePosition(source,left and 44 or 54)
    if not x then return end
    local hit,hx,hy,hz,_,_,_,_,material=processLineOfSight(x,y,z+.4,x,y,z-.5,true,false,false,true,false,false,false,false,source)
    if not hit then return end
    local wet=VCSWeather.data and VCSWeather.data.wetRoads or 0
    local dx,dy=getElementVelocity(source)
    if wet>.01 then
        AddParticle(38,hx+range(-.1,.1),hy+range(-.1,.1),hz+.02,-dx*.05,-dy*.05,0,0,32,32,32,32,0,0,math.random(0,1))
    elseif engineGetSurfaceProperties(material,"wheeleffect")~="disabled" then
        AddParticle(51,hx+range(-.1,.1),hy+range(-.1,.1),hz+.02,0,0,0,0)
    end
end

local function updateSwimmer(ped,now)
    if not isElementInWater(ped) or isPedInVehicle(ped) then swimmers[ped]=nil return end
    local x,y,z=getElementPosition(ped)
    local level=getWaterLevel(x,y,z)
    if not level or math.abs(z-level)>1.4 then return end
    local state=swimmers[ped] or {}
    swimmers[ped]=state
    local m=getElementMatrix(ped)
    if not m then return end
    local vx,vy=getElementVelocity(ped)
    if vx*vx+vy*vy>.0001 then
        AddParticle(now%2==0 and 77 or 76,x-m[2][1],y-m[2][2],level,0,0,-.001,0)
    elseif bitAnd(math.floor(now/64),15)==0 then
        AddParticle(37,x,y,level,0,0,0,0)
    end
    for _,bone in ipairs({25,35,44,54}) do
        local bx,by,bz=getPedBonePosition(ped,bone)
        if bx then
            if state[bone]==false and bz<level-.1 then
                AddParticle(75,bx,by,level-.1,0,0,0,.3)
            end
            state[bone]=bz<level-.1
        end
    end
end

local function update(delta)
    if not AreParticlesEnabled() or isMainMenuActive() then return end
    local now=getTickCount()
    local cx,cy,cz,tx,ty=getCameraMatrix()
    local interior,dimension=getCameraInterior(),getElementDimension(localPlayer)
    local world=dimension*256+interior
    if lastWorld~=world then clearScene() lastWorld=world end
    if now>=nextScan then collect(cx,cy,cz,now) end
    remainder=remainder+math.min(delta,100)*getGameSpeed()
    local rain=math.max(0,getRainLevel() or 0)
    local hour,minute=getTime()
    while remainder>=period do
        frame=frame+1
        remainder=remainder-period
        updateProjectiles()
        updateObjects(cx,cy,interior,dimension)
        if interior==0 and not (VCSWeather.data and VCSWeather.data.indoors) then
            updateWeather(cx,cy,cz,tx,ty,rain,hour)
            updateHorizon(cx,cy,cz,now,hour)
            if hour==23 and minute%15==0 and (cx-557.029)^2+(cy+4)^2<10000 then
                AddParticle(44,557.029,-4,151.464,0,0,2.5,2,255,255,255,255,0,0,1)
            end
        end
        for _,e in ipairs(nearby) do
            if isElement(e) and isElementStreamedIn(e) and sameWorld(e) then
                if getElementType(e)=="vehicle" then VehicleParticles.Update(e,frame,rain)
                else updateSwimmer(e,now) end
            end
        end
    end
end

local function removeElement()
    projectiles[source],swimmers[source]=nil,nil
end

function ParticleEmitters.start()
    if running then return end
    running=true
    VehicleParticles.start()
    WeaponParticles.start()
    addEventHandler("onClientPreRender",root,update,true,"normal")
    addEventHandler("onClientPedStep",root,addFootParticles)
    addEventHandler("onClientElementDestroy",root,removeElement)
    addEventHandler("onClientElementStreamOut",root,removeElement)
end

function ParticleEmitters.stop()
    if not running then return end
    running=false
    VehicleParticles.stop()
    WeaponParticles.stop()
    removeEventHandler("onClientPreRender",root,update)
    removeEventHandler("onClientPedStep",root,addFootParticles)
    removeEventHandler("onClientElementDestroy",root,removeElement)
    removeEventHandler("onClientElementStreamOut",root,removeElement)
    clearScene()
    frame,remainder,lastWorld=0,0,nil
end
