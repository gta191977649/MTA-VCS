PedCarjack = {}
local hlc = exports.npc_hlc
local requestedCars = {}

addEventHandler("onElementDestroy", root, function() requestedCars[source] = nil end)
addEventHandler("onVehicleStartEnter", root, function(ped, seat)
    if seat == 0 and requestedCars[ped] == source and not PedAI.expectsDriverSeat(ped, source) then
        cancelEvent()
        requestedCars[ped] = nil
    end
end)

-- Road rage uses the native carjacking task. Seat ownership always comes
-- from the vehicle, including when the player changes seats during approach.
local extractionSerial = 0

function PedCarjack.cancelExtraction(ped, event)
    if not event or not event.extractId then return end
    if isElement(event.extractOwner) then
        triggerClientEvent(event.extractOwner, "npchlc_traffic:cancelPullOut", resourceRoot, ped, event.extractId)
    end
    event.extractOwner, event.extractId, event.extractCar, event.extractStatus = nil, nil, nil, nil
end

local function stopped(car)
    local vx, vy, vz = getElementVelocity(car)
    return vx*vx + vy*vy + vz*vz <= 0.05^2
end

addEventHandler("onVehicleStartEnter", root, function(ped, seat, occupant, door)
    local brain = PedAI.brain(ped)
    local event = brain and brain.event
    if not event or not event.committed then return end
    -- MTA 1.7 also reports door 2 for a native automobile jack through
    -- the front left door. Both forms still require seat zero, the exact
    -- victim, and the validated driver-side approach for this request.
    if seat ~= 0 or (door ~= 0 and door ~= 2) or event.extractCar ~= source or occupant ~= event.target
        or getVehicleOccupant(source, 0) ~= event.target or isVehicleLocked(source) or not stopped(source) then cancelEvent() end
end)

local function currentExtraction(ped, id)
    if not client or type(id) ~= "number" then return end
    local brain = PedAI.brain(ped)
    local event = brain and brain.event
    if event and event.extractId == id and event.extractOwner == client and getElementSyncer(ped) == client then
        return event
    end
end

addEvent("npchlc_traffic:pullOutStarted", true)
addEventHandler("npchlc_traffic:pullOutStarted", resourceRoot, function(ped, id)
    local event = currentExtraction(ped, id)
    if event and not event.extractStatus then
        event.extractStatus = "active"
        if event.lastApproachedCar ~= event.extractCar then
            event.lastApproachedCar, event.lastSeen = event.extractCar, getTickCount()
        end
    end
end, false)

addEvent("npchlc_traffic:pullOutBlocked", true)
addEventHandler("npchlc_traffic:pullOutBlocked", resourceRoot, function(ped, id)
    local event = currentExtraction(ped, id)
    if event then
        event.extractStatus = "blocked"
        event.maneuver = "Driver door blocked"
    end
end, false)

-- The walking task reports arrival at the final handle from its syncer.
-- MTA may omit the final position delta when the ped stops moving.
addEventHandler("npc_hlc:onDriverDoorArrival", root, function(car, order)
    local brain = PedAI.brain(source)
    local event = brain and brain.event
    if not event or not event.committed or event.doorOrder ~= order or event.followCar ~= car
        or getVehicleOccupant(car, 0) ~= event.target or not stopped(car) then return end
    local x, y, z = getElementPosition(source)
    if getDistanceBetweenPoints3D(x, y, z, getElementPosition(car)) > 8 then return end
    event.arrivalOwner, event.arrivalAt = getElementSyncer(source), getTickCount()
end)

function PedCarjack.confront(manager, event, now)
    local ped, target = manager.ped, event.target
    local car = getPedOccupiedVehicle(target)
    if not car then
        if event.maneuver then
            PedCarjack.cancelExtraction(ped, event)
            manager:clear()
            event.task, event.maneuver, event.lastApproachedCar = nil, nil, nil
            event.lastSeen = now
        end
        return false
    end
    local owner = getElementSyncer(ped)
    local x, y, z = getElementPosition(ped)
    local distance = getDistanceBetweenPoints3D(x, y, z, getElementPosition(car))
    if event.extractId and (event.extractCar ~= car or event.extractOwner ~= owner
        or distance > 8 or getVehicleOccupant(car, 0) ~= target or isVehicleLocked(car) or not stopped(car)) then
        PedCarjack.cancelExtraction(ped, event)
    end
    local arrived = event.followCar == car and event.arrivalOwner == owner and event.arrivalAt
        and (now-event.arrivalAt) % 4294967296 < 1500
    local phase
    if distance > 8 then phase = "Approach driver door"
    elseif getVehicleOccupant(car, 0) ~= target then phase = "Waiting for target to exit"
    elseif not stopped(car) then phase = "Waiting for driver to stop"
    elseif isVehicleLocked(car) then phase = "Driver door locked"
    elseif not event.extractId and not arrived and not TrafficWanted.atDriverDoor(ped, car) then phase = "Approach driver door"
    end
    if phase then
        if event.maneuver ~= phase or event.followCar ~= car then
            manager:clear()
            event.task, event.maneuver, event.followCar = nil, phase, car
            event.doorOrder, event.arrivalAt = nil, nil
            if phase == "Approach driver door" then
                hlc:setNPCWalkSpeed(ped, "run")
                if getVehicleOccupant(car, 0) == target then
                    local side, along = TrafficWanted.driverDoorApproach(car)
                    local task = {"approachDriverDoor", target, side, along}
                    if side then
                        extractionSerial = extractionSerial + 1
                        event.doorOrder, task[5] = extractionSerial, extractionSerial
                    end
                    hlc:setNPCTask(ped, task)
                else
                    hlc:setNPCTask(ped, {"walkFollowElement", target, 3})
                end
            end
        end
        return true
    end
    local retryAfter = event.extractStatus == "active" and 12500 or 5500
    if isElement(owner) and (not event.extractId or (now - event.requested) % 4294967296 >= retryAfter) then
        PedCarjack.cancelExtraction(ped, event)
        manager:clear()
        extractionSerial = extractionSerial + 1
        event.doorOrder, event.arrivalAt = nil, nil
        event.extractId, event.extractOwner, event.extractCar = extractionSerial, owner, car
        event.requested, event.maneuver, event.task = now, "Pull driver out", nil
        triggerClientEvent(owner, "npchlc_traffic:pullDriverOut", resourceRoot, ped, car, target, extractionSerial)
    end
    return true
end

function PedCarjack.capture(event, car, jacker)
    event.exitDriver = getVehicleOccupant(car, 0)
    if event.exitDriver == event.road.driver then event.exitDriver = nil end
    event.playerCar = event.road.jacker == jacker or getPedOccupiedVehicle(jacker) == car
    event.origin = {getElementPosition(car)}
end

function PedCarjack.quickDrag(vehicle, model, door)
    if getVehicleType(vehicle) ~= "Automobile" or door ~= 0 and door ~= 2 then return false end
    local flags = TrafficCarjackHandlingFlags[model] or 0
    if flags >= 2 or flags == 1 and door ~= 0 then return false end
    local panel = door == 0 and 2 or 4
    local opening = getVehicleDoorOpenRatio(vehicle, panel)
    return not isVehicleLocked(vehicle) and getVehicleDoorState(vehicle, panel) ~= 4
        and type(opening) == "number" and opening < 0.5
end

-- Ordinary ambient actors use the free-roam objectives in 0x00306010 and
-- 0x00306680. Door 10 (MTA door 0) bypasses the preliminary temper flags.
function PedCarjack.decide(profile, door, quick, driver, jacker, isPlayerCar, attackTarget)
    local angry = profile.temper > profile.fear
    if door and door ~= 0 then
        if not angry then return "flee", quick and 14000 or 4000 end
        -- An existing objective 8 survives the interval between the victim
        -- leaving and the thief finishing the entry animation.
        if attackTarget then return "fight" end
        if driver then return "reclaim" end
        return "flee", quick and 14000 or 4000
    end
    if angry and (driver == jacker or not quick and not driver and isPlayerCar) then return "reclaim" end
    return "flee", 10000
end

addEventHandler("onVehicleEnter", root, function(ped, seat)
    if seat ~= 0 then return end
    if getElementType(ped) ~= "player" then
        local stale = requestedCars[ped] == source and not PedAI.expectsDriverSeat(ped, source)
        requestedCars[ped] = nil
        if not PedAI.confirmDriverSeat(ped) and stale then TrafficPassengers.requestExit(ped, source, 0) end
    end
end)

-- The dragged-out callback resolves its saved target after the victim gets up.
-- Keep the original car and driver until the native seat transfer completes.
function PedCarjack.seated(brain)
    local event = brain.event
    local road = event and event.road
    if not road then return false end
    local vehicle = event.entryVehicle or road.vehicle
    if not isElement(vehicle) or getVehicleOccupant(vehicle, 0) ~= brain.ped then return false end
    if event.intent == "fight" and event.entryVehicle == vehicle then
        local now = getTickCount()
        if event.task ~= "leave" or (now - event.requested) % 4294967296 >= 1600 then
            event.task, event.requested = "leave", now
            TrafficPassengers.requestExit(brain.ped, vehicle, 0)
        end
        return true
    end
    if event.intent ~= "reclaim" then return false end
    if TrafficRoad.resumeDriver(road) then
        requestedCars[brain.ped] = nil
        brain.objectives:clear()
        brain.event = nil
        return true
    end
    return false
end

function PedCarjack.update(brain, now)
    local ped, event = brain.ped, brain.event
    local car = event.road.vehicle
    if (not event.resolved or event.intent ~= "fight") and (not isElement(car) or isVehicleBlown(car)
        or getElementDimension(car) ~= getElementDimension(ped) or getElementInterior(car) ~= getElementInterior(ped)) then
        event.road, event.intent, event.task = nil, "flee", nil
        brain.tasks:clear()
        return false
    end
    if not event.resolved then
        event.resolved = true
        local x, y, z = getElementPosition(ped)
        local tx, ty, tz = getElementPosition(event.target)
        local gang = brain.profile.pedType >= 7 and brain.profile.pedType <= 15
        local door, quick = event.road.jackDoor, event.road.quickDrag
        local attackTarget = isElement(event.attackTarget) and event.attackTarget or nil
        if door and door ~= 0 and brain.profile.temper > brain.profile.fear then
            if quick then PedVoice.emit(ped, "reclaim") end
            -- 0x002FDCB0 installs objective 8 against the thief before the
            -- ordinary pull-out. Nearby gang drivers can reacquire it on foot.
            if not quick or brain.profile.pedType == 6
                or gang and getDistanceBetweenPoints3D(x, y, z, tx, ty, tz) < 3.5 then attackTarget = event.target end
            if brain.profile.pedType == 6 then
                exports.wanted:raisePlayerWanted(event.target, 1, "carjackPolice")
            end
        end
        event.intent, event.duration = PedCarjack.decide(brain.profile, door, quick, event.exitDriver, event.target,
            event.playerCar, attackTarget)
        if event.intent == "fight" then event.target = attackTarget end
        event.id = event.intent == "fight" and 8 or event.intent == "reclaim" and 0x12 or 10
        event.vehicle = event.road.vehicle
        brain.objectives.revision = brain.objectives.revision + 1
        event.lastSeen = now
    end
    if event.intent == "fight" then
        car = getPedOccupiedVehicle(event.target)
        if not car or getVehicleOccupant(car, 0) ~= event.target or brain.tasks:hasRangedWeapon() then
            if event.task == "enter" or event.task == "leave" or event.task == "approachDoor" then
                brain.tasks:clear()
                event.task = nil
            end
            return false
        end
    elseif event.intent ~= "reclaim" then return false end
    local driver = getVehicleOccupant(car, 0)
    if driver and driver ~= event.target then
        event.intent, event.duration, event.task = "flee", 4000, nil
        brain.tasks:clear()
        return false
    end
    if event.entryVehicle ~= car then
        brain.tasks:clear()
        event.entryVehicle, event.task, event.requested = car, nil, nil
    end
    local x, y, z = getElementPosition(ped)
    local cx, cy, cz = getElementPosition(car)
    local range = getDistanceBetweenPoints3D(x, y, z, cx, cy, cz)
    if range > 9 then
        if event.task ~= "approachDoor" then
            hlc:setNPCWalkSpeed(ped, "run")
            if hlc:setNPCTask(ped, {"walkFollowElement", car, 3}) then event.task = "approachDoor" end
        end
        return true
    end
    if event.task and event.task ~= "enter" then brain.tasks:clear() end
    event.task = "enter"
    local owner = getElementSyncer(ped)
    if isElement(owner) and (owner ~= event.owner or not event.requested
        or (now - event.requested) % 4294967296 >= 1600) then
        event.owner, event.requested = owner, now
        requestedCars[ped] = car
        triggerClientEvent(owner, "npchlc_traffic:reclaimDriverSeat", resourceRoot, ped, car, event.target)
    end
    return true
end
