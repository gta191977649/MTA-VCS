TrafficPassengers = {}

local passengers, byVehicle, leaving = {}, {}, {}
local detachedBikePassengers=setmetatable({}, {__mode="k"})
local hlc = exports.npc_hlc

-- US GAME.DTZ: automobile models with animation block 89 ("van") at +0x26c.
local van = {[182]=true, [210]=true, [218]=true, [220]=true, [221]=true, [224]=true,
    [227]=true, [234]=true, [235]=true, [236]=true, [240]=true, [242]=true}
local reservedFront = {[183]=true, [226]=true, [228]=true}
-- 0x00395868 builds passenger capacity from model type, handling flags and
-- door count (+0x274). Other US vehicle models 170..280 have one passenger slot.
local capacityByModel = {
    [170]=0,[173]=0,[174]=0,[178]=0,[179]=0,[181]=0,[198]=0,[222]=0,[233]=0,[251]=0,[275]=0,
    [171]=3,[176]=3,[182]=3,[183]=3,[186]=3,[193]=3,[195]=3,[196]=3,[200]=3,[203]=3,[207]=3,
    [209]=3,[210]=3,[211]=3,[213]=3,[223]=3,[224]=3,[226]=3,[227]=3,[228]=3,[234]=3,[235]=3,
    [240]=3,[242]=3,[261]=3,[268]=3,[269]=3,[271]=3,[274]=3,[276]=3,[237]=8,
}

function TrafficPassengers.count(hostCapacity, originalId, roll)
    if hostCapacity == 0 or originalId < 170 or originalId > 280 or originalId == 230 then return 0 end
    local count = 0
    for _ = 1, capacityByModel[originalId] or 1 do
        if roll() < 0.125 then count = count + 1 end
    end
    return math.min(count, hostCapacity, van[originalId] and 1 or count)
end

function TrafficPassengers.spawn(state, graph, group, class, originalId)
    if graph.edition ~= "SLUS-21590 USA v1.00" or class == 13 or class == 23 or class == 24 then return end
    local capacity = getVehicleMaxPassengers(state.vehicle) or 0
    local count = TrafficPassengers.count(capacity, originalId, math.random)
    local used = {[state.originalDriver] = true}
    local officer = PedServices and PedServices.policeCrewModel(originalId)
    local function available(id)
        return not used[id] and TrafficAmbient.getPedestrianModel(id)
    end
    for seat = 1, count do
        if (seat > 1 or not reservedFront[originalId]) and not getVehicleOccupant(state.vehicle, seat) then
            local model = officer or TrafficRoad.chooseDriver(group, graph.pedestrianDriverMasks, class,
                math.random(0, 15), available, graph.fallbackDriverModelId)
            if model and TrafficAmbient.getPedestrianModel(model) then
                local x, y, z = getElementPosition(state.vehicle)
                local ped = createPed(TrafficAmbient.getPedestrianModel(model), x, y, z)
                if ped then
                    setElementDimension(ped, state.dimension)
                    TrafficModelBindings.tag(ped, model)
                    if warpPedIntoVehicle(ped, state.vehicle, seat) and hlc:enableHLCForNPC(ped) then
                        used[model] = true
                        local entry = {ped=ped, vehicle=state.vehicle, seat=seat, model=model}
                        passengers[ped] = entry
                        byVehicle[state.vehicle] = byVehicle[state.vehicle] or {}
                        byVehicle[state.vehicle][seat] = entry
                        PedAI.attach(ped, model)
                        TrafficVisibility.track(ped, "road")
                    else
                        destroyElement(ped)
                    end
                end
            end
        end
    end
end

function TrafficPassengers.isManaged(ped)
    return passengers[ped] ~= nil
end

local function forget(entry)
    passengers[entry.ped], leaving[entry.ped] = nil, nil
    local seats = byVehicle[entry.vehicle]
    if seats then
        seats[entry.seat] = nil
        if not next(seats) then byVehicle[entry.vehicle] = nil end
    end
end

local function release(entry)
    forget(entry)
    PedAI.detach(entry.ped)
    TrafficVisibility.releasePed(entry.ped)
end

function TrafficPassengers.release(vehicle)
    for _, entry in pairs(byVehicle[vehicle] or {}) do release(entry) end
end

function TrafficPassengers.fading(vehicle, value)
    for _, entry in pairs(byVehicle[vehicle] or {}) do
        if isElement(entry.ped) and not isPedDead(entry.ped) then
            setElementData(entry.ped, TrafficVisibility.retiringKey, value, "broadcast", "deny")
        end
    end
end

local function adopt(entry, jacker, directlyJacked)
    forget(entry)
    local ped = entry.ped
    if isElement(ped) and not isPedDead(ped) then
        if getElementData(ped, TrafficVisibility.retiringKey) then
            setElementData(ped, TrafficVisibility.retiringKey, false, "broadcast", "deny")
        end
        TrafficAmbient.adoptDriver(ped, directlyJacked and jacker or nil, entry.vehicle, entry.model)
        if isElement(jacker) and not directlyJacked then
            if entry.retaliate then PedAI.vehicleThreat(ped, jacker) else PedAI.passengerThreat(ped, jacker) end
        end
    end
end

function TrafficPassengers.vehicleUnderFire(vehicle, attacker, retaliate)
    local delay = 200
    local seats = byVehicle[vehicle]
    if not seats then return end
    -- 0x003ef910 gives occupants the same attacker and staggers their
    -- response by 200 ms in seat order.
    for seat = 1, getVehicleMaxPassengers(vehicle) do
        local entry = seats[seat]
        if entry then
            entry.since, entry.delay = getTickCount(), delay
            entry.jacker, entry.retaliate = attacker, retaliate
            leaving[entry.ped] = entry
            if not retaliate and PedVoice then PedVoice.emit(entry.ped, "fear") end
            delay = delay + 200
        end
    end
end

function TrafficPassengers.bikeFall(vehicle,impact)
    local seats=byVehicle[vehicle]
    local entry=seats and seats[1]
    local recent=detachedBikePassengers[vehicle]
    detachedBikePassengers[vehicle]=nil
    if not entry and recent and (getTickCount()-recent.at)%4294967296<=1200 then
        local ped=recent.ped
        if isElement(ped) and not isPedInVehicle(ped) and not PedAI.isScriptControlled(ped) then
            TrafficAmbient.bikeFall(ped,impact,false,nil,recent.entry)
        end
        return
    end
    if not entry or isPedDead(entry.ped) then return end
    local aboard=getPedOccupiedVehicle(entry.ped)
    if aboard and (aboard~=vehicle or not removePedFromVehicle(entry.ped)) then return end
    if passengers[entry.ped] then adopt(entry,nil,false) end
    detachedBikePassengers[vehicle]=nil
    TrafficAmbient.bikeFall(entry.ped,impact,aboard==vehicle,nil,entry)
end

-- Objective 0x11 after a bike spill retains the passenger's original seat.
function TrafficPassengers.returnToBike(ped,walk,now)
    local entry=walk.bikePassenger
    local car=entry.vehicle
    local aboard=getPedOccupiedVehicle(ped)
    if not isElement(car) or isVehicleBlown(car) or getElementDimension(car)~=getElementDimension(ped)
        or getElementInterior(car)~=getElementInterior(ped) or aboard and aboard~=car
        or (now-walk.bikeReturnAt)%4294967296>20000 then
        walk.bikePassenger=nil
        hlc:clearNPCTasks(ped)
        return false
    end
    local occupant=getVehicleOccupant(car,entry.seat)
    if occupant then
        walk.bikePassenger=nil
        hlc:clearNPCTasks(ped)
        if occupant~=ped then return false end
        TrafficAmbient.releaseDriver(ped)
        entry.jacker,entry.retaliate=nil,nil
        passengers[ped]=entry
        byVehicle[car]=byVehicle[car] or {}
        byVehicle[car][entry.seat]=entry
        TrafficVisibility.track(ped,"road")
        return true
    end
    local x,y,z=getElementPosition(ped)
    if getDistanceBetweenPoints3D(x,y,z,getElementPosition(car))>6 then
        if not walk.bikeApproach then
            hlc:setNPCWalkSpeed(ped,"run")
            walk.bikeApproach=hlc:setNPCTask(ped,{"walkFollowElement",car,3})
        end
    elseif not walk.boardTick or (now-walk.boardTick)%4294967296>=1600 then
        hlc:clearNPCTasks(ped)
        walk.bikeApproach,walk.boardTick=nil,now
        local owner=getElementSyncer(ped)
        if owner then triggerClientEvent(owner,"npchlc_traffic:boardPassenger",resourceRoot,ped,car) end
    end
    return true
end

function TrafficPassengers.driverGone(vehicle, jacker)
    local seats = byVehicle[vehicle]
    if not seats then return end
    -- 0x003ef018 assigns leave-car objectives in seat order. Some occupants
    -- remain in a car for ten seconds before leaving.
    local delay = 1800
    local linger = getVehicleType(vehicle) == "Automobile" and math.random(0, 1) == 0
    for seat = 1, getVehicleMaxPassengers(vehicle) do
        local entry = seats[seat]
        if entry then
            local pedType = PedAIRules.profile(entry.model).pedType
            local waits = linger and (pedType == 5 or pedType == 20 or math.random(0, 1) == 0)
            entry.since, entry.delay = getTickCount(), waits and 10000 or delay
            entry.jacker = jacker
            leaving[entry.ped] = entry
            delay = delay + math.random(300, 599)
        end
    end
end

local exitStamp="npchlc_traffic:exitStamp"
addEventHandler("onVehicleExit",root,function(ped)
    if getElementData(ped,exitStamp,false) then removeElementData(ped,exitStamp) end
end)
local exitSerial=0

function TrafficPassengers.requestExit(ped, vehicle, seat, target, actor, x, y, z)
    local owner = getElementSyncer(ped)
    if not owner then
        local vehicleOwner = getElementSyncer(vehicle)
        if vehicleOwner and setElementSyncer(ped, vehicleOwner, false) then owner = getElementSyncer(ped) end
    end
    if not owner then return false end
    exitSerial=exitSerial+1
    setElementData(ped,exitStamp,exitSerial,"broadcast","deny")
    return triggerClientEvent(owner, "npchlc_traffic:occupantExit", resourceRoot, ped, vehicle, seat,
        target or false, actor or false, x or false, y or false, z or false, exitSerial)
end

function TrafficPassengers.update(now)
    for ped, entry in pairs(leaving) do
        if (now - entry.since) % 4294967296 >= entry.delay then
            if not isElement(ped) or isPedDead(ped) then
                release(entry)
            elseif getPedOccupiedVehicle(ped) ~= entry.vehicle then
                adopt(entry, entry.jacker, false)
            else
                -- Request the native exit on the current ped syncer. Retrying
                -- also recovers a migration during MTA's enter/exit cooldown.
                if not TrafficPassengers.requestExit(ped, entry.vehicle, entry.seat) then
                    local x, y, z = getElementPosition(ped)
                    local nearby = getElementsWithinRange(x, y, z, TrafficVisibility.roadRange, "player",
                        getElementInterior(ped), getElementDimension(ped))
                    if nearby and #nearby == 0 then release(entry) end
                end
                entry.since, entry.delay = now, 1500
            end
        end
    end
end

addEventHandler("onVehicleExit", root, function(ped, seat, jacker)
    local entry = passengers[ped]
    if entry and entry.vehicle == source and entry.seat == seat then
        local directlyJacked = isElement(jacker) and getElementType(jacker) == "player"
        if seat==1 and not directlyJacked and getVehicleType(source)=="Bike" then
            detachedBikePassengers[source]={ped=ped,entry=entry,at=getTickCount()}
        end
        adopt(entry, directlyJacked and jacker or entry.jacker, directlyJacked)
    end
end)

addEventHandler("onElementDestroy", root, function()
    if passengers[source] then forget(passengers[source]) end
    if byVehicle[source] then TrafficPassengers.release(source) end
end)

function TrafficPassengers.stop()
    for _, entry in pairs(passengers) do release(entry) end
end
