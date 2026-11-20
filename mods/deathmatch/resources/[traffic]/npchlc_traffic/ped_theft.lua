PedTheft = {}
local claims = setmetatable({}, {__mode="kv"})
local requests = setmetatable({}, {__mode="k"})
local hlc = exports.npc_hlc
local function elapsed(now,start) return (now-start)%4294967296 end

function PedTheft.cancel(ped, walk)
    if not walk.theft then return end
    local car = walk.theft.car
    if claims[car] == ped then claims[car] = nil end
    walk.theft = nil
end

-- Native door animations can complete after a threat or mission takeover.
-- A stale sync packet may finish only the driver's own current entry.
local function stale(ped,car)
    local entry = requests[ped]
    if not entry or entry.car ~= car or elapsed(getTickCount(),entry.tick) > 12000 then return false end
    return claims[car] ~= ped and not PedAI.expectsDriverSeat(ped,car)
end

addEventHandler("onVehicleStartEnter",root,function(ped,seat)
    if seat == 0 and stale(ped,source) then cancelEvent() end
end)
addEventHandler("onVehicleEnter",root,function(ped,seat)
    if seat ~= 0 then return end
    if stale(ped,source) then TrafficPassengers.requestExit(ped,source,0) end
    requests[ped] = nil
end)

local function available(car)
    return isElement(car) and not isVehicleLocked(car) and not isVehicleBlown(car)
        and getElementHealth(car) > 800 and getVehicleType(car) == "Automobile"
        and not next(getVehicleOccupants(car) or {})
end

local function start(ped,walk,car,now,driver)
    if not car or not hlc:setNPCTask(ped,{"walkFollowElement",car,2.5}) then return false end
    claims[car] = ped
    walk.queued,walk.anchor,walk.blockedSince,walk.crossing = 0,nil,nil,nil
    walk.theft = {car=car,start=now,driver=driver}
    return true
end

-- Separate 0x001F16D0 opportunity. The driver's seat must be occupied.
function PedTheft.seekOccupied(ped,walk,now)
    local x,y,z = getElementPosition(ped)
    local nearby = getElementsWithinRange(x,y,z,10,"vehicle",getElementInterior(ped),getElementDimension(ped)) or {}
    local best, bestPrice = nil,2000
    for i=1,math.min(#nearby,6) do
        local car = nearby[i]
        local value = PedTheftValues[getElementData(car,"npchlc_traffic:originalModel",false)]
        local driver = getVehicleOccupant(car,0)
        if value and value > bestPrice and driver and not claims[car] and not isVehicleLocked(car)
            and not isVehicleBlown(car) and not (PedAI.isScriptControlled and PedAI.isScriptControlled(driver)) then
            local vx,vy,vz = getElementVelocity(car)
            local alone = true
            for seat in pairs(getVehicleOccupants(car)) do if seat ~= 0 then alone=false break end end
            if alone and vx*vx+vy*vy+vz*vz <= 0.01 then best,bestPrice = car,value end
        end
    end
    return best and start(ped,walk,best,now,getVehicleOccupant(best,0))
end

function PedTheft.update(ped,walk,now)
    local info = PedAIModels[walk.originalModelId]
    if not info or info[1] ~= 18 then return false end
    local event = walk.theft
    if event then
        local car = event.car
        if isElement(car) and getVehicleOccupant(car,0) == ped then
            if TrafficRoad.driveStolenCar(ped,car,walk.originalModelId) then
                PedTheft.cancel(ped,walk)
                return true
            end
            local peer = getElementSyncer(ped)
            if isElement(peer) then triggerClientEvent(peer,"npchlc_traffic:occupantExit",resourceRoot,ped,car,0) end
        end
        local suitable = event.driver and isElement(car) and not isVehicleLocked(car)
            and (not getVehicleOccupant(car,0) or getVehicleOccupant(car,0) == event.driver)
        if (not suitable and not available(car)) or elapsed(now,event.start) >= 10000 or getElementDimension(car) ~= getElementDimension(ped)
            or getElementInterior(car) ~= getElementInterior(ped) then
            PedTheft.cancel(ped,walk)
            hlc:clearNPCTasks(ped)
            return false
        end
        local x,y,z = getElementPosition(ped)
        local a,b,c = getElementPosition(car)
        local peer = getElementSyncer(ped)
        if (a-x)^2+(b-y)^2+(c-z)^2 < 16 and isElement(peer)
            and (not event.entered or peer ~= event.peer) then
            hlc:clearNPCTasks(ped)
            event.entered,event.peer = true,peer
            requests[ped] = {car=car,tick=now}
            triggerClientEvent(peer,"npchlc_traffic:reclaimDriverSeat",resourceRoot,ped,car,event.driver)
        end
        return true
    end
    if walk.theftUsed or walk.mug or walk.partner or walk.leader or PedActivity.active(ped) or isPedInVehicle(ped) then return false end
    walk.theftTick = (walk.theftTick or 0)+1
    if walk.theftTick <= 8 then return false end
    walk.theftTick = 0
    if not walk.theftModels then
        walk.theftModels = {}
        for _ = 1,16 do walk.theftModels[math.random(170,280)] = true end
    end
    local x,y,z = getElementPosition(ped)
    local best, distance = nil,100
    for _,car in ipairs(getElementsWithinRange(x,y,z,10,"vehicle",getElementInterior(ped),getElementDimension(ped)) or {}) do
        local id = getElementData(car,"npchlc_traffic:originalModel",false)
        if walk.theftModels[id] and not claims[car] and available(car) then
            local a,b,c = getElementPosition(car)
            local d = (a-x)^2+(b-y)^2+(c-z)^2
            if d < distance then best,distance = car,d end
        end
    end
    if not start(ped,walk,best,now) then return false end
    walk.theftUsed = true
    return true
end
