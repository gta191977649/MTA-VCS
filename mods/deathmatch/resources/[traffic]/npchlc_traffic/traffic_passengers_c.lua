addEvent("npchlc_traffic:reclaimDriverSeat", true)
addEventHandler("npchlc_traffic:reclaimDriverSeat", resourceRoot, function(ped, vehicle, jacker)
    if not isElement(ped) or not isElement(vehicle) or not isElementSyncer(ped)
        or not isElementStreamedIn(vehicle) or isPedDead(ped) or isPedInVehicle(ped) then return end
    local driver = getVehicleOccupant(vehicle, 0)
    if not driver or driver == jacker then setPedEnterVehicle(ped, vehicle, false) end
end, false)

addEvent("npchlc_traffic:occupantExit", true)
addEventHandler("npchlc_traffic:occupantExit", resourceRoot, function(ped, vehicle, seat, target, actor, x, y, z, stamp)
    if stamp and (not isElement(ped) or getElementData(ped,"npchlc_traffic:exitStamp",false)~=stamp) then return end
    if target then
        if not isElement(vehicle) or not isElement(target) or (getPedOccupiedVehicle(target) or target) ~= actor
            or getDistanceBetweenPoints3D(x, y, z, getElementPosition(actor)) > 1
            or not canTrafficPursuerExit(vehicle, target) then return end
        local vx, vy, vz = getElementVelocity(vehicle)
        if vx*vx + vy*vy + vz*vz > 0.05^2 then return end
    end
    if isElement(ped) and isElementSyncer(ped) and isElement(vehicle)
        and getPedOccupiedVehicle(ped) == vehicle and getPedOccupiedVehicleSeat(ped) == seat then
        setPedExitVehicle(ped)
    end
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
    for officer in pairs(doorAttempts) do
        if isElement(officer) and isElementSyncer(officer) then
            setPedAnimation(officer,"PED","IDLE_stance",180,false,false,false,false,0)
        end
    end
end,false)
