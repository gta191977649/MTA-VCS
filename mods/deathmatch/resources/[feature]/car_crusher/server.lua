local bayMin, bayMax, drop = Crusher.pickupMin, Crusher.pickupMax, Crusher.drop
local missionTargets, helpSeen = {}, {}
local helpText = "Park in the marked area and exit your vehicle. The vehicle will then be crushed."
local idleX, idleY = (bayMin[1]+bayMax[1])/2, (bayMin[2]+bayMax[2])/2
local idleZ = bayMin[3]+8.5
local hook, scanArea
local phase, target, owner, saved, roof, deadline = "idle"
local drivers, rejected = {}, {}
local interruptedKey = "car_crusher:interrupted"
local blocked = {[407]=true,[544]=true,[408]=true,[428]=true,[431]=true,[432]=true,[593]=true}
local hookMotion, lidMotion, hookPhase, revision = nil, nil, nil, 0
local lastSnapshot = {}
local hookSettled = true
local lidTime = math.ceil(math.pi/2 / (0.005*50) * 1000)

addEvent("onCarCrusherCrushed", false)

local function outsideWorld(element)
    return getElementDimension(element) ~= 0 or getElementInterior(element) ~= 0
end

local function inPickup(car)
    local x,y,z = getElementPosition(car)
    return not outsideWorld(car) and x >= bayMin[1] and x <= bayMax[1]
        and y >= bayMin[2] and y <= bayMax[2] and math.abs(z-bayMin[3]) < 4
end

local function eligible(car)
    if not isElement(car) or not inPickup(car) or next(getVehicleOccupants(car))
        or getElementData(car,interruptedKey,false) or getVehicleType(car) ~= "Automobile" or isVehicleBlown(car)
        or getElementHealth(car) < 250 or getElementAttachedTo(car) then return false end
    local vx,vy,vz = getElementVelocity(car)
    if math.max(math.abs(vx),math.abs(vy),math.abs(vz)) >= 0.01 then return false end
    if blocked[getElementModel(car)] then
        if not rejected[car] and isElement(drivers[car]) then
            triggerClientEvent(drivers[car],"car_crusher:message",resourceRoot,"Crane cannot lift this vehicle.")
            rejected[car] = true
        end
        return false
    end
    return true
end

local function publish()
    revision = revision+1
    local now = getTickCount()
    for player in pairs(lastSnapshot) do
        triggerClientEvent(player,"car_crusher:motion",resourceRoot,revision,now,hookMotion,lidMotion)
    end
end

-- Only the server changes the carried vehicle, its parent, and its reward.
-- Clients sample the same paths between these authoritative collision updates.
local function moveHook(x,y,z,speed,align)
    local now = getTickCount()
    if hookPhase ~= phase then
        local hx,hy,hz = getElementPosition(hook)
        local _,_,yaw = getElementRotation(hook)
        hookMotion = craneMovement(hx,hy,hz,yaw,x,y,z,align,speed,now)
        hookMotion.pickup = phase == "lift"
        hookPhase,hookSettled = phase,false
        publish()
    end
    return now >= hookMotion.start+hookMotion.duration
end

local function moveLid(from,to,duration,shake)
    lidMotion = {from=from,to=to,start=getTickCount(),duration=duration,shake=shake or false}
    publish()
end

local function restoreTarget()
    if saved and isElement(target) then
        setElementData(target,interruptedKey,true,"local","deny")
        if getElementAttachedTo(target) == hook then detachElements(target,hook) end
        setElementPosition(target,unpack(saved.position))
        setElementRotation(target,unpack(saved.rotation))
        setElementCollisionsEnabled(target,saved.collision)
        setElementFrozen(target,saved.frozen)
        setVehicleLocked(target,saved.locked)
    end
    target, owner, saved = nil, nil, nil
end

local function abort()

    restoreTarget()
    hookPhase = nil
    moveLid(-90,-90,0)
    phase = "return"
end

local function pickUp()
    saved = {position={getElementPosition(target)},rotation={getElementRotation(target)},
        collision=getElementCollisionsEnabled(target),frozen=isElementFrozen(target),locked=isVehicleLocked(target)}
    setElementFrozen(target,true)
    setElementCollisionsEnabled(target,false)
    setVehicleLocked(target,true)
    setElementRotation(hook,0,0,saved.rotation[3])
    if not attachElements(target,hook,0,0,-roof) then abort() return end
    phase = "lift"
end

local function complete()
    local car, player = target, owner
    local monetary = getVehicleHandling(car).monetary
    local reward = math.floor(math.min(125,25+monetary*getElementHealth(car)/500000))
    -- Commit before notifying mission resources; handlers can destroy the car.
    phase, deadline = "shake", getTickCount()+3000
    moveLid(0,0,3000,true)
    target, owner, saved = nil,nil,nil
    if isElement(player) then
        givePlayerMoney(player,reward)
        triggerClientEvent(player,"car_crusher:message",resourceRoot,"Scrap value: $"..reward)
    end
    triggerEvent("onCarCrusherCrushed",car,player,reward)
    if isElement(car) then destroyElement(car) end
end

-- MEAT1 and JOEY5 share one help flag and require the designated mission car.
function setCrusherMissionVehicle(player,car)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if car and (not isElement(car) or getElementType(car) ~= "vehicle") then return false end
    missionTargets[player] = car or nil
    return true
end

local function updateMissionHelp()
    for player,car in pairs(missionTargets) do
        if not isElement(car) or helpSeen[player] then
            missionTargets[player] = nil
        elseif getPedOccupiedVehicle(player) == car and not outsideWorld(player) then
            local x,y = getElementPosition(player)
            if math.abs(x-Crusher.missionHelp[1]) <= 20 and math.abs(y-Crusher.missionHelp[2]) <= 20 then
                helpSeen[player],missionTargets[player] = true,nil
                exports.frontend:showTextBox(player,helpText,6500)
            end
        end
    end
end

local function update()
    local now = getTickCount()
    if next(missionTargets) then updateMissionHelp() end
    if not hookSettled then
        local x,y,z,yaw = cranePose(hookMotion,now)
        setElementPosition(hook,x,y,z,false)
        setElementRotation(hook,0,0,yaw)
        hookSettled = now >= hookMotion.start+hookMotion.duration
    end
    if target and (not isElement(target) or isVehicleBlown(target) or outsideWorld(target)
        or (saved and next(getVehicleOccupants(target)))) then abort() end
    if phase == "idle" then
        for _,car in ipairs(getElementsWithinColShape(scanArea,"vehicle")) do
            if eligible(car) then
                local _,_,_,_,_,top = exports.server_coldata:getModelBoundingBox(getElementModel(car))
                if top then
                    target,owner,roof,phase = car,drivers[car],top,"approach"
                    break
                end
            end
        end
    elseif phase == "approach" then
        if not eligible(target) then abort() return end
        local x,y,z = getElementPosition(target)
        if moveHook(x,y,z+roof,1) then
            local hx,hy,hz = getElementPosition(hook)
            if getDistanceBetweenPoints3D(x,y,z+roof,hx,hy,hz) < 0.5 then pickUp() else hookPhase = nil end
        end
    elseif phase == "lift" then
        if moveHook(saved.position[1],saved.position[2],bayMin[3]+7,0.3) then phase = "transfer" end
    elseif phase == "transfer" then
        if moveHook(drop[1],drop[2],drop[3]+5,0.3,true) then phase = "lower" end
    elseif phase == "lower" then
        if moveHook(drop[1],drop[2],drop[3],0.3,true) then
            local _,_,heading = getElementRotation(hook)
            detachElements(target,hook)
            setElementRotation(target,0,0,heading)
            setElementPosition(target,drop[1],drop[2],drop[3]-roof)
            setElementCollisionsEnabled(target,true)
            setElementFrozen(target,false)
            setElementVelocity(target,0,0,0)
            phase,deadline = "settle",now+3000
        end
    elseif phase == "settle" then
        moveHook(drop[1],drop[2],drop[3]+7,0.3)
        if now >= deadline then
            local x,y,z = getElementPosition(target)
            if math.abs(x-drop[1])>3.45 or math.abs(y-drop[2])>6.5 or math.abs(z-bayMin[3])>5 then abort() return end
            setElementFrozen(target,true)
            setElementCollisionsEnabled(target,false)
            moveLid(-90,0,lidTime)
            deadline,phase = now+lidTime,"close"
        end
    elseif phase == "close" then
        moveHook(idleX,idleY,idleZ,1)
        if now >= deadline then complete() end
    elseif phase == "shake" then
        if now >= deadline then
            moveLid(0,-90,lidTime)
            deadline,phase = now+lidTime,"opening"
        end
    elseif phase == "opening" then
        if now >= deadline then phase = "return" end
    elseif phase == "return" then
        if moveHook(idleX,idleY,idleZ,1) then phase = "idle" end
    end
end

local function createHook(x,y,z)
    local obj = createObject(1337,x,y,z)
    setElementID(obj,"car_crusher:hook")
    setElementAlpha(obj,0)
    setElementCollisionsEnabled(obj,false)
    return obj
end

addEventHandler("onResourceStart",resourceRoot,function()
    hook = createHook(idleX,idleY,idleZ)

    scanArea = createColCuboid(bayMin[1],bayMin[2],bayMin[3]-4,bayMax[1]-bayMin[1],bayMax[2]-bayMin[2],8)
    local pos = Crusher.info
    local info = createPickup(pos[1],pos[2],pos[3],3,1239,30000)
    addEventHandler("onPickupUse",info,function(player)
        exports.frontend:showTextBox(player,helpText,6500)
    end)
    local now = getTickCount()
    hookMotion = craneMovement(idleX,idleY,idleZ,0,idleX,idleY,idleZ,false,1,now)
    moveLid(-90,-90,0)
    setTimer(update,120,0)
end)

addEventHandler("onVehicleExit",root,function(player,seat)
    if seat == 0 and getElementType(player) == "player" then
        if getElementData(source,interruptedKey,false) then removeElementData(source,interruptedKey) end
        drivers[source] = inPickup(source) and player or nil
    end
end)
addEventHandler("onVehicleEnter",root,function(_,seat)
    if seat == 0 then drivers[source] = nil end
end)
addEventHandler("onVehicleStartEnter",root,function()
    if source == target then
        if saved then cancelEvent() else abort() end
    end
end)
addEventHandler("onElementDestroy",root,function()
    drivers[source],rejected[source] = nil,nil
end)
addEventHandler("onPlayerQuit",root,function()

    for car,player in pairs(drivers) do if player == source then drivers[car] = nil end end
    lastSnapshot[source],missionTargets[source],helpSeen[source] = nil,nil,nil
    if owner == source then abort() end
end)
addEventHandler("onResourceStop",resourceRoot,restoreTarget)

-- Read-only clock handshake for resource start, late join, and clock drift.
addEvent("car_crusher:requestMotion",true)
addEventHandler("car_crusher:requestMotion",resourceRoot,function(sent)
    if source ~= resourceRoot or not client or type(sent) ~= "number" or not hookMotion then return end
    local now = getTickCount()
    if lastSnapshot[client] and now-lastSnapshot[client] < 500 then return end
    lastSnapshot[client] = now
    triggerClientEvent(client,"car_crusher:motion",resourceRoot,revision,now,hookMotion,lidMotion,sent)
end)