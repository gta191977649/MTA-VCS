PedVehicleEvasion = {}
local active, last = {}, {}
local revision = 0
local function age(now, previous) return (now-previous)%4294967296 end

function PedVehicleEvasion.cancel(ped)
    local state = active[ped]
    if not state then return end
    active[ped] = nil
    if isTimer(state.timer) then killTimer(state.timer) end
    if isElement(ped) then removeElementData(ped, PedEvasion.key) end
end

function PedVehicleEvasion.active(ped)
    return active[ped] ~= nil
end

local function eligible(ped, car, owner)
    if not isElement(ped) or getElementType(ped) ~= "ped" or not isElement(car) or getElementType(car) ~= "vehicle"
        or PedAI.isScriptControlled and PedAI.isScriptControlled(ped) or PedSpecial and PedSpecial.active(ped)
        or not TrafficAmbient.isManagedPed(ped) or TrafficAmbient.isRecovering and TrafficAmbient.isRecovering(ped)
        or getElementSyncer(ped) ~= owner or isPedDead(ped) or isPedInVehicle(ped)
        or getElementInterior(ped) ~= getElementInterior(car) or getElementDimension(ped) ~= getElementDimension(car)
        or PedEvasion.activityBlocks(ped)
        or getElementData(ped, "npchlc_traffic:activityHeading", false) then return false end
    local driver = getVehicleOccupant(car, 0)
    if not driver or getElementType(driver) ~= "player" then return false end
    local px, py, pz = getElementPosition(ped)
    local cx, cy, cz = getElementPosition(car)
    -- The car and victim usually have different syncers. Allow arrival skew at
    -- this validation boundary; the victim owner tests the actual front bumper.
    local vx, vy = getElementVelocity(car)
    local dx,dy = px-cx,py-cy
    local matrix = getElementMatrix(car)
    if not matrix or dx*dx+dy*dy >= 30^2 or math.abs(pz-cz) >= 5 then return false end
    local fx,fy = matrix[2][1],matrix[2][2]
    return vx*fx+vy*fy > 0.05 and dx*fx+dy*fy > -4 and math.abs(dx*fy-dy*fx) < 5
end

addEvent("npchlc_traffic:vehicleApproach",true)
addEventHandler("npchlc_traffic:vehicleApproach",resourceRoot,function(ped,car)
    if source ~= resourceRoot or active[ped] or not eligible(ped,car,client) then return end
    local brain = PedAI.attach(ped)
    if not brain.event then
        brain:react("approach", getVehicleOccupant(car,0), 0, "flee", "run", 2000)
    end
end)

local function begin(ped,brain,now,kind,fx,fy,voice,native)
    if TrafficAmbient.suspend then TrafficAmbient.suspend(ped) end
    PedActivity.cancel(ped)
    brain.tasks:clear()
    if brain.event then brain.event.task = nil end
    revision = revision + 1
    local state = {revision=revision, started=now}
    active[ped], last[ped] = state, now
    setElementData(ped,PedEvasion.key,{revision,kind,fx,fy,native},"broadcast","deny")
    if voice and PedVoice then PedVoice.emit(ped,voice) end
    state.timer = setTimer(function()
        if active[ped] == state then PedVehicleEvasion.cancel(ped) end
    end, PedEvasion.duration(kind), 1)
end

addEvent("npchlc_traffic:evadeCar", true)
addEventHandler("npchlc_traffic:evadeCar", resourceRoot, function(ped, car, kind, fx, fy, horn)
    if source ~= resourceRoot or active[ped] or not eligible(ped,car,client)
        or kind ~= "ev_dive" and kind ~= "ev_step" and kind ~= "handsup" and kind ~= "idle_taxi"
        or type(fx) ~= "number" or type(fy) ~= "number" or not (math.abs(fx*fx+fy*fy-1) < 0.01) then return end
    local now, brain = getTickCount(), PedAI.attach(ped)
    if last[ped] and age(now,last[ped]) < 2500 or brain.event and brain.event.intent == "fight" then return end
    if kind == "ev_dive" and math.floor(brain.profile.flags/16)%2 == 1 then
        kind = "handsup"
        local px, py = getElementPosition(ped)
        local cx, cy = getElementPosition(car)
        local length = math.sqrt((cx-px)^2 + (cy-py)^2)
        if length > 0.01 then fx,fy = (cx-px)/length,(cy-py)/length end
    end
    begin(ped,brain,now,kind,fx,fy,not horn and "evade",kind=="ev_dive" or kind=="ev_step")
    if brain.profile.pedType == 6 and (kind == "ev_dive" or kind == "handsup") then
        local driver = getVehicleOccupant(car, 0)
        exports.wanted:reportWantedCrime(driver, 8, ped, true)
        exports.wanted:reportWantedCrime(driver, 9, ped, true)
    end
end)

addEvent("npchlc_traffic:evadeClock", true)
addEventHandler("npchlc_traffic:evadeClock", resourceRoot, function(ped, id)
    local state = active[ped]
    if source ~= resourceRoot or not state or state.revision ~= id or not isElement(client)
        or getElementDimension(client) ~= getElementDimension(ped)
        or getElementInterior(client) ~= getElementInterior(ped) then return end
    triggerClientEvent(client,"npchlc_traffic:evadeTime",resourceRoot,ped,id,age(getTickCount(),state.started))
end)
addEventHandler("onPedDamage", root, function() PedVehicleEvasion.cancel(source) end)
addEventHandler("onPedWasted", root, function() PedVehicleEvasion.cancel(source) end)
addEventHandler("onElementDestroy", root, function()
    if active[source] and isTimer(active[source].timer) then killTimer(active[source].timer) end
    active[source], last[source] = nil,nil
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for ped in pairs(active) do PedVehicleEvasion.cancel(ped) end
end)

-- A bullet selected on the server asks only its victim's syncer to check the
-- two landing strips. It uses the same PS2 root motion and get-up clock as a car.
function PedVehicleEvasion.bullet(ped,event)
    local peer = getElementSyncer(ped)
    if not isElement(peer) or event.probePeer==peer then return end
    event.probePeer = peer
    revision = revision + 1
    event.probeId = revision
    triggerClientEvent(peer,"npchlc_traffic:bulletLanding",resourceRoot,ped,event.target,event.probeId,
        event.animation:lower())
end
addEvent("npchlc_traffic:bulletLandingReply",true)
addEventHandler("npchlc_traffic:bulletLandingReply",resourceRoot,function(ped,id,fx,fy)
    local brain = PedAI.brain(ped)
    local event = brain and brain.event
    if not event or event.kind~="nearMiss" or event.probeId~=id or event.probePeer~=client
        or getElementSyncer(ped)~=client or isPedInVehicle(ped) or isPedDead(ped) or active[ped]
        or not isElement(event.target) or age(getTickCount(),event.started)>1000
        or type(fx)~="number" or type(fy)~="number" or not (math.abs(fx*fx+fy*fy-1)<0.01) then return end
    event.probeId=nil
    local kind=event.animation:lower()
    begin(ped,brain,getTickCount(),kind,fx,fy,nil)
end,false)
