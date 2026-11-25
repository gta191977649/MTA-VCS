addEvent("npchlc_traffic:reclaimDriverSeat", true)
addEventHandler("npchlc_traffic:reclaimDriverSeat", resourceRoot, function(ped, vehicle, jacker)
    if not isElement(ped) or not isElement(vehicle) or not isElementSyncer(ped)
        or not isElementStreamedIn(vehicle) or isPedDead(ped) or isPedInVehicle(ped) then return end
    local driver = getVehicleOccupant(vehicle, 0)
    if not driver or driver == jacker then setPedEnterVehicle(ped, vehicle, false) end
end, false)

addEvent("npchlc_traffic:occupantExit", true)
addEventHandler("npchlc_traffic:occupantExit", resourceRoot, function(ped, vehicle, seat, target, actor, x, y, z, stamp, onFoot, committed)
    if stamp and (not isElement(ped) or getElementData(ped,"npchlc_traffic:exitStamp",false)~=stamp) then return end
    if target then
        if not isElement(vehicle) or not isElement(target) or (getPedOccupiedVehicle(target) or target) ~= actor
            or not onFoot and getDistanceBetweenPoints3D(x, y, z, getElementPosition(actor)) > 1
            or not canTrafficPursuerExit(vehicle, target, onFoot, committed) then return end
        local vx, vy, vz = getElementVelocity(vehicle)
        if vx*vx + vy*vy + vz*vz > 0.05^2 then return end
    end
    if isElement(ped) and isElementSyncer(ped) and isElement(vehicle)
        and getPedOccupiedVehicle(ped) == vehicle and getPedOccupiedVehicleSeat(ped) == seat then
        setPedExitVehicle(ped)
    end
end, false)

-- Stop the native entry as soon as the target leaves the driver seat.
-- GTA performs the actual door opening and drag animation on the syncer.
local pullOuts = {}

local function finishPullOut(ped)
    pullOuts[ped] = nil
    if isElement(ped) and isElementSyncer(ped) and not isPedDead(ped) and not isPedInVehicle(ped) then
        setPedAnimation(ped, "PED", "IDLE_stance", 180, false, false, false, false, 0)
    end
end

local function validPullOut(ped, car, target)
    if not isElement(ped) or not isElementSyncer(ped) or isPedDead(ped) or not isElement(car)
        or not isElementStreamedIn(car) or not isElement(target) or isPedDead(target)
        or getVehicleOccupant(car, 0) ~= target or isVehicleLocked(car) then return false end
    if getElementDimension(ped) ~= getElementDimension(car) or getElementInterior(ped) ~= getElementInterior(car) then return false end
    local x, y, z = getElementPosition(ped)
    if getDistanceBetweenPoints3D(x, y, z, getElementPosition(car)) > 8 then return false end
    local vx, vy, vz = getElementVelocity(car)
    return vx*vx + vy*vy + vz*vz <= 0.05^2
end

local function doorAccessible(ped, car)
    local m = getElementMatrix(car)
    local left, rear, _, _, front = getElementBoundingBox(car)
    if not m or not left or m[3][3] < 0.8 then return false end
    local px, py, pz = getElementPosition(ped)
    local dx, dy = px-m[4][1], py-m[4][2]
    local side = dx*m[1][1] + dy*m[1][2]
    local along = (front - rear) * 0.1
    local longitudinal = dx*m[2][1] + dy*m[2][2]
    if side >= -0.45 or math.abs(side-left) > 1.1 or math.abs(longitudinal-along) > 1.2
        or math.abs(pz-m[4][3]) > 1.8 then return false end
    local x = m[4][1] + left*m[1][1] + along*m[2][1]
    local y = m[4][2] + left*m[1][2] + along*m[2][2]
    local z = m[4][3] + 0.35
    return isLineOfSightClear(x, y, z, x-m[1][1], y-m[1][2], z, true, true, false, true, false, false, false, car)
end

local function observePullOuts()
    for ped, a in pairs(pullOuts) do
        local entering = isElement(ped) and (getPedOccupiedVehicle(ped) == a.car
            or getPedTask(ped, "primary", 3) == "TASK_COMPLEX_ENTER_CAR_AS_DRIVER")
        if not validPullOut(ped, a.car, a.target) or isPedInVehicle(ped) then
            finishPullOut(ped)
        elseif (getTickCount()-a.at) % 4294967296 >= (a.started and 12000 or 5000) then
            finishPullOut(ped)
            triggerServerEvent("npchlc_traffic:pullOutBlocked", resourceRoot, ped, a.id)
        elseif not a.started and entering then
            a.started = true
            triggerServerEvent("npchlc_traffic:pullOutStarted", resourceRoot, ped, a.id)
        elseif a.started and not entering then
            finishPullOut(ped)
            triggerServerEvent("npchlc_traffic:pullOutBlocked", resourceRoot, ped, a.id)
        end
    end
    if not next(pullOuts) then removeEventHandler("onClientPreRender", root, observePullOuts) end
end

addEvent("npchlc_traffic:cancelPullOut", true)
addEventHandler("npchlc_traffic:cancelPullOut", resourceRoot, function(ped, id)
    local a = pullOuts[ped]
    if a and a.id == id then finishPullOut(ped) end
end, false)

addEvent("npchlc_traffic:pullDriverOut", true)
addEventHandler("npchlc_traffic:pullDriverOut", resourceRoot, function(ped, car, target, id)
    if not validPullOut(ped, car, target) or isPedInVehicle(ped) then return end
    if not doorAccessible(ped, car) or not setPedEnterVehicle(ped, car, false) then
        triggerServerEvent("npchlc_traffic:pullOutBlocked", resourceRoot, ped, id)
        return
    end
    if not next(pullOuts) then
        addEventHandler("onClientPreRender", root, observePullOuts)
    end
    pullOuts[ped] = {car=car, target=target, at=getTickCount(), id=id}
end, false)

-- The damage hook identifies the body and the entity that actually struck it.
addEventHandler("onClientVehicleDamage", root, function(attacker, weapon, loss, _, _, _, tire)
    if tire or not isElement(attacker) or not loss
        or getElementData(source, TrafficVisibility.profileKey) ~= "road" then return end
    if getElementType(attacker) == "vehicle" then
        if loss > 0 and (isElementSyncer(source) or getVehicleOccupant(attacker, 0) == localPlayer)
            and (not weapon or weapon == 49 or weapon == 50) then
            triggerServerEvent("npchlc_traffic:collisionDamage", resourceRoot, source, attacker)
        end
        return
    end
    local kind = getElementType(attacker)
    if kind ~= "ped" and kind ~= "player" then return end
    if attacker ~= localPlayer and not isElementSyncer(source) and not (kind == "ped" and isElementSyncer(attacker)) then return end
    if type(weapon) ~= "number" then return end
    if weapon >= 0 and weapon <= 15 or loss > 0 and weapon >= 16 and (weapon <= 39 or weapon == 51) then
        local health = getElementHealth(source)
        if health > loss then
            triggerServerEvent("npchlc_traffic:vehicleBodyHit", resourceRoot, source, attacker, weapon, health, loss)
        end
    end
end)

-- Intercept the actual opening task on its owning GTA client while the
-- driver is still seated. Replacing its primary task generates JACK_ABORT.
local doorAttempts={}
addEvent("npchlc_traffic:cancelPoliceDriverDoor",true)
addEventHandler("npchlc_traffic:cancelPoliceDriverDoor",resourceRoot,function(officer,id)
    local a=doorAttempts[officer]
    if not a or a.id~=id then return end
    doorAttempts[officer]=nil
    if isElement(officer) and isElementSyncer(officer) then
        setPedAnimation(officer,"PED","IDLE_stance",180,false,false,false,false,0)
    end
end,false)
local function monitorDoors()
    for officer,a in pairs(doorAttempts) do
        local car=a.car
        local owned=isElement(officer) and isElementSyncer(officer)
        local valid=owned and isElement(car) and isElementStreamedIn(car) and not isPedDead(officer)
            and not isVehicleLocked(car) and getVehicleOccupant(car,0)==a.player
        local opened=false
        if valid then
            setPedControlState(officer,"fire",false)
            local vx,vy,vz=getElementVelocity(car)
            valid=vx*vx+vy*vy+vz*vz<0.05^2 and (getTickCount()-a.at)%4294967296<4600
            local task=getPedSimplestTask(officer)
            opened=valid and task=="TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE" and getVehicleDoorOpenRatio(car,2)>=.8
            -- An interrupted entry can leave a partially open door behind.
            -- After GTA starts opening, relinquish the attempt if that task ends.
            if a.reaching and task~="TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE" then valid=false end
            a.reaching=a.reaching or task=="TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE"
        end
        if not valid or opened then
            if owned then
                setPedAnimation(officer,"PED",opened and "ARRESTgun" or "IDLE_stance",180,false,false,false,false,0)
                if isElement(car) then triggerServerEvent("npchlc_traffic:observedDriverDoor",resourceRoot,car,a.id,opened) end
            end
            doorAttempts[officer]=nil
        end
    end
    if not next(doorAttempts) then removeEventHandler("onClientPreRender",root,monitorDoors) end
end
addEvent("npchlc_traffic:openPoliceDriverDoor",true)
addEventHandler("npchlc_traffic:openPoliceDriverDoor",resourceRoot,function(officer,car,player,id)
    if not isElement(officer) or not isElement(car) or not isElementSyncer(officer) or not isElementStreamedIn(car)
        or isVehicleLocked(car) or getVehicleOccupant(car,0)~=player or doorAttempts[officer]
        or not setPedEnterVehicle(officer,car,false) then
        if isElement(car) then triggerServerEvent("npchlc_traffic:observedDriverDoor",resourceRoot,car,id,false) end
        return
    end
    setPedControlState(officer,"fire",false)
    if not next(doorAttempts) then addEventHandler("onClientPreRender",root,monitorDoors,true,"low-100") end
    doorAttempts[officer]={car=car,player=player,id=id,at=getTickCount()}
end,false)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for ped in pairs(pullOuts) do finishPullOut(ped) end
    for officer in pairs(doorAttempts) do
        if isElement(officer) and isElementSyncer(officer) then
            setPedAnimation(officer,"PED","IDLE_stance",180,false,false,false,false,0)
        end
    end
end,false)
