local effects, buckets = {}, {}
local sprayTexture
local updater, update
local stopping=false
local function updateTimer()
    if stopping then return end
    if next(effects) or next(buckets) then
        if not updater or not isTimer(updater) then updater=setTimer(update,150,0) end
    elseif updater and isTimer(updater) then
        killTimer(updater)
        updater=nil
    end
end
-- FIRETRK gives each burning occupant a separate 14–22 second script clock.
addEventHandler("onClientPedDamage",root,function(_,weapon)
    if weapon==37 and getElementData(source,"mission:fireVictim",false) then cancelEvent() end
end)
local function clearFire(marker)
    if isElement(effects[marker]) then destroyElement(effects[marker]) end
    effects[marker]=nil
end

local function clearBucket(element)
    buckets[element]=nil
    if sprayTexture and not next(buckets) then
        destroyElement(sprayTexture)
        sprayTexture=nil
    end
end

local function remove(element)
    clearFire(element)
    clearBucket(element)
    updateTimer()
end

local function register(element)
    if not isElementStreamedIn(element) then return end
    local kind=getElementType(element)
    if kind=="object" then
        if getElementData(element,"mission:airRescueCable",false)==7350 then
            buckets[element]=buckets[element] or false
        else clearBucket(element) end
    elseif kind=="marker" then
        if getElementData(element,"mission:fireTarget",false) then
            effects[element]=effects[element] or false
        else clearFire(element) end
    end
    updateTimer()
end
addEventHandler("onClientElementStreamIn",root,function() register(source) end)
addEventHandler("onClientElementStreamOut",root,function() remove(source) end)
addEventHandler("onClientElementDestroy",root,function() remove(source) end)
addEventHandler("onClientElementDataChange",root,function(key)
    if key=="mission:airRescueCable" or key=="mission:fireTarget" then register(source) end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,kind in ipairs({"marker","object"}) do
        for _,e in ipairs(getElementsByType(kind,root,true)) do register(e) end
    end
end)

local function drawFire(marker,effect,px,py,pz)
    local target=getElementData(marker,"mission:fireTarget",false)
    local entity=target and target[2]
    local host=isElement(entity) and entity or marker
    local x,y,z=getElementPosition(host)
    if not target or target[1]~=MissionRunToken or getElementDimension(marker)~=getElementDimension(localPlayer)
        or getDistanceBetweenPoints3D(x,y,z,px,py,pz)>190 then
        if isElement(effect) then destroyElement(effect) end
        effects[marker]=false
        return
    end
    if isElement(entity) and getElementType(entity)=="vehicle"
        and getElementData(entity,"mission:fireRoad",false)==MissionRunToken then
        local hit,_,_,surface,_,_,_,normalZ=processLineOfSight(x,y,z+8,x,y,z-9,true,false,false,true,false)
        if hit and normalZ and normalZ>0.55 then
            triggerServerEvent("mission:fireRoadReady",resourceRoot,MissionRunToken,entity,surface)
        end
    end
    if isElement(entity) and getElementType(entity)=="ped" then return end
    if isElement(effect) then
        setElementPosition(effect,x,y,z)
    else
        effect=createEffect("fire_med",x,y,z,0,0,0,190,false)
        if effect then
            setElementInterior(effect,getElementInterior(marker))
            setElementDimension(effect,getElementDimension(marker))
            effects[marker]=effect
        end
    end
end

local function sendControls()
    if not MissionRunToken then return end
    local v=getPedOccupiedVehicle(localPlayer)
    if not v or getPedOccupiedVehicleSeat(localPlayer)~=0 then return end
    local model=tonumber(getElementData(v,"vcs_vehicle:originalModel")) or tonumber(getElementData(v,"npchlc_traffic:originalModel"))
    local legacy=getElementData(v,"mod.model")
    local ground=model==194 or legacy=="FIRETRUK"
    if not ground and model~=188 and legacy~="HUEY" then return end
    local x,y,z=getElementPosition(v)
    local deep=false
    if not ground and z<20 then
        local water=getWaterLevel(x,y,z,true)
        local floor=getGroundPosition(x,y,z+1)
        deep=water and floor and floor<0.2 and z-floor<20 and z>water-2 or false
    end
    local dx,dy,slope = 0,1,0
    if ground then
        local yaw,pitch = getVehicleTurretPosition(v)
        local m = getElementMatrix(v)
        if not yaw or not m then return end
        local right,forward,up = -math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)
        dx = right*m[1][1]+forward*m[2][1]+up*m[3][1]
        dy = right*m[1][2]+forward*m[2][2]+up*m[3][2]
        local dz = right*m[1][3]+forward*m[2][3]+up*m[3][3]
        local length=math.sqrt(dx*dx+dy*dy)
        if length<0.001 then return end
        dx,dy,slope=dx/length,dy/length,dz/length
    end
    triggerServerEvent("mission:fireControls",resourceRoot,MissionRunToken,ground and "firefighter" or "firecopter",
        getPedControlState(localPlayer,"vehicle_fire"),dx,dy,slope,deep)
end

update=function()
    local x,y,z=getElementPosition(localPlayer)
    for marker,effect in pairs(effects) do
        if isElement(marker) then drawFire(marker,effect,x,y,z) else clearFire(marker) end
    end
    sendControls()
    updateTimer()
end

-- Emit from the moving rope end at PS2 frame cadence. Once released, a
-- droplet falls in world space independently of subsequent helicopter motion.
addEventHandler("onClientPreRender",root,function()
    local now=getTickCount()
    for bucket,flow in pairs(buckets) do
        local visible=getElementDimension(bucket)==getElementDimension(localPlayer)
            and getElementInterior(bucket)==getElementInterior(localPlayer)
        local spraying=visible and getElementData(bucket,"mission:bucketSpraying",false)
        if spraying or flow then
            local x,y,z=getElementPosition(bucket)
            z=z-1
            if not flow or now<flow.time then
                flow={particles={},nextEmission=now,x=x,y=y,z=z,time=now}
                buckets[bucket]=flow
            end
            if spraying then
                sprayTexture=sprayTexture or dxCreateTexture("assets/bucket_spray.png")
                flow.nextEmission=math.max(flow.nextEmission,now-100)
                while flow.nextEmission<=now do
                    local u=math.min(1,(now-flow.nextEmission)/math.max(1,now-flow.time))
                    for i=1,2 do
                        local angle=math.rad((flow.nextEmission*0.7+i*180)%360)
                        table.insert(flow.particles,{at=flow.nextEmission,x=x+(flow.x-x)*u,y=y+(flow.y-y)*u,
                            z=z+(flow.z-z)*u,vx=math.cos(angle),vy=math.sin(angle),vz=i==1 and -4 or -2})
                    end
                    flow.nextEmission=flow.nextEmission+1000/30
                end
            else
                flow.nextEmission=now
            end
            flow.x,flow.y,flow.z,flow.time=x,y,z,now
            for i=#flow.particles,1,-1 do
                local drop=flow.particles[i]
                local t=(now-drop.at)/1000
                if t>=0.9 or not visible then
                    table.remove(flow.particles,i)
                elseif sprayTexture then
                    local px,py=drop.x+drop.vx*t,drop.y+drop.vy*t
                    local pz=drop.z+drop.vz*t-4.905*t*t
                    local width=0.35+t
                    dxDrawMaterialLine3D(px,py,pz+width,px,py,pz-width,sprayTexture,width,
                        tocolor(210,234,255,190*(1-t/0.9)))
                end
            end
            if not spraying and #flow.particles==0 then buckets[bucket]=false end
        end
    end
end)

addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if not token then return end
    for marker in pairs(effects) do
        local target=isElement(marker) and getElementData(marker,"mission:fireTarget",false)
        if target and target[1]==token then clearFire(marker) end
    end
    updateTimer()
end,false)

addEventHandler("onClientResourceStop",resourceRoot,function()
    stopping=true
    if updater and isTimer(updater) then killTimer(updater) end
    for marker in pairs(effects) do clearFire(marker) end
    for bucket in pairs(buckets) do clearBucket(bucket) end
end)
