TrafficWorld = {}

local requests = {}
local ready = {}
local roadViews = {}
local serial = 0
local TIMEOUT_MS = 1000
local MAX_ACTOR_DISTANCE = 220
local MAX_REACH_REQUESTS = 8

local function query(player, kind, slot, key, acceptable, ...)
    if not ready[player] then return false end
    local now = getTickCount()
    local playerRequests = requests[player]
    if not playerRequests then
        playerRequests = {}
        requests[player] = playerRequests
    end
    local pending = playerRequests[slot]
    local reusable = pending and pending.key==key and (now-pending.started)%4294967296<TIMEOUT_MS
    if pending and pending.key==key and kind=="reach" and pending.finished then
        -- The reply deadline applies to the network peer. A stationary actor
        -- may wait longer for its turn in the server's round-robin scheduler.
        local x,y,z=getElementPosition(slot)
        reusable=pending.interior==getElementInterior(slot) and pending.dimension==getElementDimension(slot)
            and (pending.fixedOrigin or (x-pending.x)^2+(y-pending.y)^2+(z-pending.z)^2<=2^2)
    end
    if reusable then
        if pending.finished then
            playerRequests[slot] = nil
            return pending.result
        end
        return nil
    end
    if kind == "reach" then
        local count = 0
        for actor, request in pairs(playerRequests) do
            if request.kind == "reach" then
                if not isElement(actor) or not request.finished and (now - request.started) % 4294967296 >= TIMEOUT_MS then
                    playerRequests[actor] = nil
                elseif not request.finished and actor ~= slot then count = count + 1 end
            end
        end
        -- Reserve one extra in-flight probe for a player interacting with
        -- this ped when background wander/flee probes occupy the usual slots.
        local limit = MAX_REACH_REQUESTS + (acceptable.direct and 1 or 0)
        if count >= limit then return nil end
    end

    serial = serial + 1
    playerRequests[slot] = {id = serial, started = now, kind = kind, key = key, acceptable = acceptable,
        interior = getElementInterior(player), dimension = getElementDimension(player)}
    if kind=="reach" then
        local request=playerRequests[slot]
        request.x,request.y,request.z=getElementPosition(slot)
    end
    triggerClientEvent(player, "npchlc_traffic:worldProbe", resourceRoot, serial, kind, ...)
    return nil
end

function TrafficWorld.probeSpawn(player, x, y, z, model, endpoints)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > MAX_ACTOR_DISTANCE then return false end
    local key = table.concat({x, y, z, model, endpoints and endpoints[1].id or "sample",
        endpoints and endpoints[2] and endpoints[2].id or ""}, "/")
    return query(player, "spawn", "spawn", key, {z = z, endpoints = endpoints}, x, y, z, endpoints)
end

function TrafficWorld.isReady(player)
    return ready[player] == true
end

function TrafficWorld.roadObserverPosition(player)
    local vehicle = getPedOccupiedVehicle(player)
    return getElementPosition(isElement(vehicle) and vehicle or player)
end

function TrafficWorld.probeRoad(player, batch, onResult)
    if not ready[player] then return false end
    local px, py, pz = TrafficWorld.roadObserverPosition(player)
    local points = {}
    for index, candidate in ipairs(batch.points) do
        if getDistanceBetweenPoints3D(px, py, pz, candidate.x, candidate.y, candidate.z) > MAX_ACTOR_DISTANCE then return false end
        points[index] = {candidate.x, candidate.y, candidate.z, candidate.boat and "boat" or nil}
    end
    query(player, "road", "road", batch, points, points)
    requests[player].road.onResult = onResult
    return true
end

function TrafficWorld.cancelRoad(player, batch)
    local playerRequests = requests[player]
    if playerRequests and playerRequests.road and playerRequests.road.key == batch then
        playerRequests.road = nil
    end
end

function TrafficWorld.getRoadView(player)
    local view = roadViews[player]
    if view and (getTickCount() - view.tick) % 4294967296 < TIMEOUT_MS then return view.x, view.y end
end

function TrafficWorld.resetRoadView(player)
    roadViews[player] = nil
end

function TrafficWorld.reachable(player, ped, nodeId, candidates, origin, rejoining, reaction)
    if not isElement(ped) or #candidates > 15
        or getElementInterior(player) ~= getElementInterior(ped)
        or getElementDimension(player) ~= getElementDimension(ped) then return false end
    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > MAX_ACTOR_DISTANCE then return false end
    local ids = {}
    for _, candidate in ipairs(candidates) do ids[candidate.id] = true end
    ids.direct = reaction and reaction.kind=="damage" and isElement(reaction.target)
        and getElementType(reaction.target)=="player"
    local key = rejoining and nodeId .. "/rejoin" or origin and nodeId .. "/ahead" or nodeId
    local slots=requests[player]
    if slots and slots[ped] and slots[ped].reaction~=reaction then slots[ped]=nil end
    local result=query(player, "reach", ped, key, ids, ped, candidates, origin)
    local pending=requests[player] and requests[player][ped]
    if reaction and pending and pending.key==key then
        pending.reaction,pending.ped,pending.fixedOrigin=reaction,ped,origin~=nil
    end
    return result
end

function TrafficWorld.cancelPursuit(car)
    for _, slots in pairs(requests) do slots[car] = nil end
end

function TrafficWorld.pursuitExit(owner, car, target, phase)
    if not isElement(owner) or not isElement(car) or getElementSyncer(car) ~= owner
        or not isElement(target) or getElementDimension(car) ~= getElementDimension(target)
        or getElementInterior(car) ~= getElementInterior(target) then return false end
    local actor = getPedOccupiedVehicle(target) or target
    local x, y, z = getElementPosition(car)
    local tx, ty, tz = getElementPosition(actor)
    local key = phase .. "/" .. tostring(target)
    local snapshot = {car = car, actor = actor, target = target, x = x, y = y, z = z, tx = tx, ty = ty, tz = tz}
    return query(owner, "pursuitExit", car, key, snapshot, car, target)
end

addEvent("npchlc_traffic:worldProbeResult", true)
addEventHandler("npchlc_traffic:worldProbeResult", resourceRoot, function(id, result)
    local playerRequests = requests[client]
    if not playerRequests then return end
    local pending
    for _, request in pairs(playerRequests) do
        if request.id == id then pending = request break end
    end
    if not pending or pending.id ~= id or pending.finished
        or pending.interior ~= getElementInterior(client) or pending.dimension ~= getElementDimension(client)
        or (getTickCount() - pending.started) % 4294967296 >= TIMEOUT_MS then return end
    pending.finished, pending.result = true, false
    if pending.kind == "spawn" and type(result) == "table" and type(result[1]) == "number"
        and math.abs(result[1] - pending.acceptable.z) <= 3 and type(result[2]) == "boolean" then
        local endpoints = pending.acceptable.endpoints
        local destination = result[3]
        if endpoints and destination ~= endpoints[1].id
            and (not endpoints[2] or destination ~= endpoints[2].id) then return end
        pending.result = {groundZ = result[1], visible = result[2], clear = true, destination = destination, skatable = result[4] == true}
    elseif pending.kind == "road" then
        playerRequests.road = nil
        if type(result) ~= "table" or type(result[1]) ~= "table" then
            pending.onResult(client, pending.key, false)
            return
        end
        local probes = {}
        for index, point in ipairs(pending.acceptable) do
            local probe = result[1][index]
            if type(probe) == "table" and type(probe[1]) == "number" and type(probe[2]) == "boolean"
                and math.abs(probe[1] - point[3] - (point[4] == "boat" and 0 or 1.5)) <= 7 then
                probes[index] = {groundZ = probe[1], visible = probe[2]}
            end
        end
        pending.result = {probes = probes}
        local x, y = result[2], result[3]
        if type(x) == "number" and type(y) == "number" and math.abs(x * x + y * y - 1) < 0.01 then
            roadViews[client] = {x = x, y = y, tick = getTickCount()}
            pending.result.viewX, pending.result.viewY = x, y
        end
        pending.onResult(client, pending.key, pending.result)
    elseif pending.kind == "pursuitExit" and result == true then
        local p = pending.acceptable
        if not isElement(p.car) or getElementSyncer(p.car) ~= client or not isElement(p.target)
            or (getPedOccupiedVehicle(p.target) or p.target) ~= p.actor then return end
        local x, y, z = getElementPosition(p.car)
        local tx, ty, tz = getElementPosition(p.actor)
        pending.result = (x-p.x)^2 + (y-p.y)^2 + (z-p.z)^2 <= 2^2
            and (tx-p.tx)^2 + (ty-p.ty)^2 + (tz-p.tz)^2 <= 1
    elseif pending.kind == "reach" and type(result) == "table" and #result <= 15 then
        local reachable = {}
        for _, nodeId in ipairs(result) do
            if type(nodeId) ~= "number" or not pending.acceptable[nodeId] then return end
            reachable[#reachable + 1] = nodeId
        end
        if pending.ped and (not isElement(pending.ped) or getElementSyncer(pending.ped)~=client) then
            playerRequests[pending.ped]=nil
            return
        end
        pending.result = reachable
        if pending.reaction then
            local ped,event=pending.ped,pending.reaction
            local brain=PedAI.brain(ped)
            if not brain or brain.event~=event or not isElement(event.target) then return end
            event.probe=nil
            TrafficAmbient.wakeReaction(ped,event)
        end
    end
end, false)

addEvent("npchlc_traffic:worldProbeReady", true)
addEventHandler("npchlc_traffic:worldProbeReady", resourceRoot, function()
    if client then ready[client] = true end
end, false)

addEventHandler("onPlayerQuit", root, function()
    requests[source], ready[source], roadViews[source] = nil, nil, nil
end)
