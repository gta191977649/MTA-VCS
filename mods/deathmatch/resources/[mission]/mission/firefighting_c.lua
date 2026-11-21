local effects, buckets = {}, {}
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
    if isElement(buckets[element]) then destroyElement(buckets[element]) end
    buckets[element]=nil
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
    for bucket,flow in pairs(buckets) do
        local visible=isElement(bucket) and getElementData(bucket,"mission:bucketSpraying",false)
            and getElementDimension(bucket)==getElementDimension(localPlayer)
            and getElementInterior(bucket)==getElementInterior(localPlayer)
        if visible then
            local bx,by,bz=getElementPosition(bucket)
            if not isElement(flow) then
                flow=createEffect("water_hydrant",bx,by,bz-1,180,0,0,100,false)
                if flow then
                    setElementDimension(flow,getElementDimension(bucket))
                    setElementInterior(flow,getElementInterior(bucket))
                    buckets[bucket]=flow
                end
            end
        elseif not isElement(bucket) then
            clearBucket(bucket)
        elseif isElement(flow) then
            destroyElement(flow)
            buckets[bucket]=false
        end
    end
    sendControls()
    updateTimer()
end

-- Follow the locally simulated bucket each rendered frame while spraying.
addEventHandler("onClientPreRender",root,function()
    for bucket,flow in pairs(buckets) do
        if isElement(flow) then
            local x,y,z=getElementPosition(bucket)
            setElementPosition(flow,x,y,z-1)
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
