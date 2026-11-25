-- Original US PS2 CFire::ProcessFire, CExplosion::Update and
-- CWeapon::GenerateFlameThrowerParticles. Particle velocities use 20 ms steps.
local fires, weapons, burningPeds = {}, {}, {}
local gfx = exports.skygfx
local step = 1000/30
local skyResource=getResourceFromName("skygfx")
local coronaResource=getResourceFromName("custom_coronas")
local function skyRunning() return skyResource and getResourceState(skyResource)=="running" end
local function coronasRunning() return coronaResource and getResourceState(coronaResource)=="running" end
local function particle(...) return gfx:AddParticle(...) end

local function release(f)
    if f.sound and skyRunning() then gfx:StopFireSound(f.sound) end
    f.sound = nil
    if f.corona and coronasRunning() then exports.custom_coronas:destroyCorona(f.corona) end
    f.corona = nil
end

addEvent("fire:start",true)
addEventHandler("fire:start",resourceRoot,function(id,kind,host,x,y,z,size,age,strength,interior,dimension,slot)
    if fires[id] then return end
    local now = getTickCount()
    if kind=="ped" and isElement(host) then burningPeds[host]=id end
    fires[id] = {kind=kind,host=host,x=x,y=y,z=z,size=size,started=now-age,strength=strength,
        interior=interior,dimension=dimension,slot=slot,nextEmit=now,step=math.floor(age/step)}
end,false)
addEvent("fire:stop",true)
addEventHandler("fire:stop",resourceRoot,function(id)
    local f=fires[id]
    if not f then return end
    if f.host and burningPeds[f.host]==id then burningPeds[f.host]=nil end
    release(f)
    fires[id]=nil
end,false)

local function filterNativeBurn(_,weapon)
    if weapon==37 and burningPeds[source] then cancelEvent() end
end
addEventHandler("onClientPedDamage",root,filterNativeBurn)
addEventHandler("onClientPlayerDamage",root,filterNativeBurn)

local function position(f)
    if not f.host then
        if f.kind=="molotov" and not f.groundZ then
            local hit,_,_,surface=processLineOfSight(f.x,f.y,f.z+2,f.x,f.y,f.z-8,true,false,false,true,false)
            if hit then f.groundZ=surface end
        end
        return f.x,f.y,f.groundZ or f.z
    end
    if not isElement(f.host) or not isElementStreamedIn(f.host) then return end
    local x,y,z = getElementPosition(f.host)
    local kind = getElementType(f.host)
    if kind == "vehicle" and f.kind ~= "wreck" then
        local model = tonumber(getElementData(f.host,"vcs_vehicle:originalModel",false))
        local dx,dy,dz
        if model == 198 then dx,dy,dz=0,-1,0
        elseif model == 222 then dx,dy,dz=0,2.7,1
        elseif getVehicleType(f.host)=="Bike" then dx,dy,dz=0,-0.5,1
        else dx,dy,dz=getVehicleDummyPosition(f.host,"engine") end
        local m=getElementMatrix(f.host)
        if dx and m then
            x=x+dx*m[1][1]+dy*m[2][1]+dz*m[3][1]
            y=y+dx*m[1][2]+dy*m[2][2]+dz*m[3][2]
            z=z+dx*m[1][3]+dy*m[2][3]+dz*m[3][3]+0.15
        end
    elseif kind == "ped" or kind == "player" then z=z-1 end
    return x,y,z
end

local random=math.random
local function processFire(f,x,y,z,t)
    if t < f.nextEmit then return end
    local interval = f.strength < 0.3 and 400 or f.strength < 0.7 and 200 or 80
    f.nextEmit=t+interval
    particle(27,x,y,z,0,0,f.size*(0.0125+random()*0.0875),f.size)
    particle(57,x,y,z,0,0,0,0.3)
end

-- CAutomobile::ProcessControl, 0013ECA4..0013EE48.
local function processEngineFire(f,x,y,z)
    particle(27,x,y,z,0,0,0.01125+random()*0.07875,0.63)
    particle(57,x+(random()-0.5)*1.125,y+(random()-0.5)*1.125,z+0.5625+random()*1.6875,0,0,0,0)
    particle(56,x,y,z,0,0,0,0.5)
end

local function processWreck(f,x,y,z,t)
    if t-f.started < 750 then
        if t>=f.nextEmit then
            for i=1,random(1,2) do particle(40,x,y,z,0,0,0,3.5) end
            f.nextEmit=t+125+random(0,127)
        end
    elseif f.step%2==1 then
        particle(56,x,y,z,0,0,0,0.5+random()*0.3)
        particle(56,x,y,z+1,0,0,0.11,0.5+random()*1.5)
    end
end

local function processMolotov(f,x,y,z)
    local n=f.step
    if n<10 then
        local radius=n*0.55
        for i=1,math.floor(radius)*30 do
            local angle=random(0,255)*0.02453125
            particle(13,x+radius*math.sin(angle),y+radius*math.cos(angle),z,0,0,0,0.4,
                255,255,0,30,random(-3,2),random(-180,179))
        end
        if n==7 then
            for i=1,10 do
                local dx,dy=(random()-0.5)*0.06,(random()-0.5)*0.06
                particle(13,x,y,z+1.7,dx,dy,0.03-math.sqrt(dx*dx+dy*dy),1.8,255,255,0,30)
            end
        end
    elseif n*step<3000 then
        for i=1,4 do particle(57,x,y,z+0.01,0,0,0) end
    end
end

addEvent("fire:water",true)
addEventHandler("fire:water",resourceRoot,function(id,strength)
    local f=fires[id]
    if not f then return end
    f.strength=strength
    if not f.visible or not skyRunning() then return end
    if f.sound then gfx:ReportWaterExtinguish(f.sound,strength) end
    local x,y,z=position(f)
    if not x then return end
    x,y,z=x+random(-128,127)*0.015,y+random(-128,127)*0.015,z+random(0,255)*0.005
    particle(28,x,y,z,0,0,0.1,1.2,210,210,240,90)
    particle(28,x,y,z,0,0,0.05,1.4,210,210,240,90)
    particle(28,x+random(-128,127)*0.015,y+random(-128,127)*0.015,z+random(0,255)*0.005,
        0,0,0.15,1,210,210,240,90)
end,false)

local function updateFire(f,now,interior,dimension,cx,cy,cz,enabled)
    local x,y,z
    if enabled and f.dimension==dimension and f.interior==interior then x,y,z=position(f) end
    f.visible=x and (x-cx)^2+(y-cy)^2+(z-cz)^2<200*200
    local frame=math.floor((now-f.started)/step)
    if not f.visible then
        release(f)
        f.step=frame
        return
    end
    if f.kind=="wreck" then
        if coronasRunning() and now-f.started<750 and (x-cx)^2+(y-cy)^2+(z-cz)^2<80^2 then
            local bright=frame%2==1
            if not f.corona then f.corona=exports.custom_coronas:createCorona(x,y,z,8,128,0,0,255,true) end
            if f.corona then
                exports.custom_coronas:setCoronaPosition(f.corona,x,y,z)
                exports.custom_coronas:setCoronaColor(f.corona,bright and 200 or 128,bright and 100 or 0,0,255)
                exports.custom_coronas:setCoronaSize(f.corona,bright and 6 or 8)
            end
            if bright then gfx:AddLight(x,y,z,15,1,0,0) end
        elseif f.corona then
            if coronasRunning() then exports.custom_coronas:destroyCorona(f.corona) end
            f.corona=nil
        end
    elseif f.kind~="engine" then
        if f.lightFrame~=frame then f.lightFrame,f.light=frame,random(0,127)/128 end
        gfx:AddLight(x,y,z,12,f.light,f.light,0)
    end
    if not f.sound and f.kind~="wreck" then
        local soundKind="ground"
        local hostType=f.host and getElementType(f.host)
        if f.kind=="engine" then soundKind="vehicle"
        elseif f.kind=="object" then soundKind="building"
        elseif hostType=="ped" or hostType=="player" then soundKind="ped" end
        f.sound=gfx:PlayFireSound(soundKind,x,y,z,interior,dimension,f.slot,now-f.started)
    elseif f.sound and not gfx:MoveFireSound(f.sound,x,y,z) then f.sound=nil end
    -- Never replay an offscreen burst on stream-in or after a suspended client.
    f.step=math.max(f.step,frame-3)
    while f.step<frame do
        f.step=f.step+1
        local t=f.started+f.step*step
        f.strength=math.min(1,f.strength+step*0.0001)
        if f.kind=="engine" then processEngineFire(f,x,y,z)
        elseif f.kind=="wreck" then processWreck(f,x,y,z,t)
        else
            if f.kind=="molotov" then processMolotov(f,x,y,z) end
            processFire(f,x,y,z,t)
        end
    end
end

-- 002CA078 obtains a camera/target direction. Its unaimed branch uses half a
-- unit of forward velocity. 002C9D70 emits a stationary muzzle flame and five
-- successively slower flames beginning one direction vector ahead of it.
local function fireWeapon(ped,x,y,z,tx,ty,tz)
    if not x or not tx then return end
    local dx,dy,dz=tx-x,ty-y,tz-z
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    if length<0.001 then return end
    if ped==localPlayer then triggerServerEvent("fire:shot",resourceRoot,dx/length,dy/length,dz/length) end
    local speed=getPedControlState(ped,"aim_weapon") and ped==localPlayer and 1 or 0.5
    dx,dy,dz=dx*speed/length,dy*speed/length,dz*speed/length
    particle(74,x,y,z,0,0,0,0,nil,nil,nil,nil,0,random(0,358),0,100)
    x,y,z=x+dx,y+dy,z+dz
    for i=1,5 do
        dx,dy,dz=dx*0.9,dy*0.9,dz*0.9
        particle(74,x,y,z,dx,dy,dz,0,nil,nil,nil,nil,0,random(85,94),0,600)
    end
end

local function processWeapon(ped,now)
    local x,y,z=getPedWeaponMuzzlePosition(ped)
    if not x then
        if weapons[ped] then release(weapons[ped]) weapons[ped]=nil end
        return
    end
    local w=weapons[ped]
    local interior,dimension=getElementInterior(ped),getElementDimension(ped)
    if w and (w.interior~=interior or w.dimension~=dimension) then release(w) w=nil end
    if not w then
        gfx:PlayFireSound("flamethrowerStart",x,y,z,interior,dimension)
        w={sound=gfx:PlayFireSound("flamethrower",x,y,z,interior,dimension),nextEmit=now,interior=interior,dimension=dimension}
        weapons[ped]=w
    end
    if w.sound and not gfx:MoveFireSound(w.sound,x,y,z) then
        w.sound=gfx:PlayFireSound("flamethrower",x,y,z,getElementInterior(ped),getElementDimension(ped))
    end
    if now>=w.nextEmit then
        local tx,ty,tz=getPedTargetEnd(ped)
        if not tx then
            local m=getElementMatrix(ped)
            tx,ty,tz=x+m[2][1],y+m[2][2],z+m[2][3]
        end
        fireWeapon(ped,x,y,z,tx,ty,tz)
        w.nextEmit=now+100 -- GAME.DTZ weapon record 33, rate of fire at +0x0C
    end
end

local shooters={}
local function observe(ped)
    if getPedWeapon(ped)==37 then shooters[ped]=true else shooters[ped]=nil end
end
addEventHandler("onClientPlayerWeaponFire",root,function(weapon)
    if weapon==37 then shooters[source]=true end
end)
addEventHandler("onClientPedWeaponFire",root,function(weapon)
    if weapon==37 then shooters[source]=true end
end)
local function scanWeapons()
    observe(localPlayer)
    for _,kind in ipairs({"player","ped"}) do
        for _,ped in ipairs(getElementsByType(kind,root,true)) do observe(ped) end
    end
end
addEventHandler("onClientElementStreamOut",root,function()
    shooters[source]=nil
    if weapons[source] then release(weapons[source]) weapons[source]=nil end
end)
addEventHandler("onClientElementDestroy",root,function()
    burningPeds[source]=nil
    shooters[source]=nil
    if weapons[source] then release(weapons[source]) weapons[source]=nil end
end)

addEventHandler("onClientExplosion",root,function(x,y,z,kind)
    if not skyRunning() or not gfx:AreParticlesEnabled() or wasEventCancelled() then return end
    gfx:PlayFireSound(kind,x,y,z,getElementInterior(localPlayer),getElementDimension(localPlayer))
end,true,"low")

local function updateWaterCannon()
    local vehicle=getPedOccupiedVehicle(localPlayer)
    if not vehicle or getVehicleController(vehicle)~=localPlayer or not getPedControlState(localPlayer,"vehicle_fire") then return end
    local model=tonumber(getElementData(vehicle,"vcs_vehicle:originalModel",false))
    if model~=194 and getElementModel(vehicle)~=407 then return end
    local yaw,pitch=getVehicleTurretPosition(vehicle)
    if not yaw or not pitch then return end
    triggerServerEvent("fire:cannon",resourceRoot,yaw,pitch)
end

local nextScan,nextCannon=0,0
addEventHandler("onClientPreRender",root,function()
    local now=getTickCount()
    local enabled=skyRunning() and gfx:AreParticlesEnabled()
    local interior,dimension=getElementInterior(localPlayer),getElementDimension(localPlayer)
    local cx,cy,cz=getCameraMatrix()
    for _,f in pairs(fires) do updateFire(f,now,interior,dimension,cx,cy,cz,enabled) end
    if now>=nextCannon then updateWaterCannon() nextCannon=now+100 end
    if enabled and now>=nextScan then scanWeapons() nextScan=now+200 end
    for ped in pairs(shooters) do
        if enabled and getElementInterior(ped)==interior and getElementDimension(ped)==dimension
            and getPedWeapon(ped)==37 and getPedTotalAmmo(ped)>0 and not isPedDead(ped)
            and getPedControlState(ped,"fire") then processWeapon(ped,now)
        elseif weapons[ped] then release(weapons[ped]) weapons[ped]=nil end
    end
    for ped,w in pairs(weapons) do
        if not shooters[ped] then release(w) weapons[ped]=nil end
    end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    triggerServerEvent("fire:ready",resourceRoot)
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for _,f in pairs(fires) do release(f) end
    for _,w in pairs(weapons) do release(w) end
end)
