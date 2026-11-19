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
    if pending and pending.key == key and (now - pending.started) % 4294967296 < TIMEOUT_MS then
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
                if not isElement(actor) or (now - request.started) % 4294967296 >= TIMEOUT_MS then
                    playerRequests[actor] = nil
                elseif actor ~= slot then count = count + 1 end
            end
        end
        if count >= MAX_REACH_REQUESTS then return nil end
    end

    serial = serial + 1
    playerRequests[slot] = {id = serial, started = now, kind = kind, key = key, acceptable = acceptable,
        interior = getElementInterior(player), dimension = getElementDimension(player)}
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
        points[index] = {candidate.x, candidate.y, candidate.z}
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

function TrafficWorld.reachable(player, ped, nodeId, candidates, origin)
    if not isElement(ped) or #candidates > 15
        or getElementInterior(player) ~= getElementInterior(ped)
        or getElementDimension(player) ~= getElementDimension(ped) then return false end
    local x, y, z = getElementPosition(ped)
    local px, py, pz = getElementPosition(player)
    if getDistanceBetweenPoints3D(px, py, pz, x, y, z) > MAX_ACTOR_DISTANCE then return false end
    local ids = {}
    for _, candidate in ipairs(candidates) do ids[candidate.id] = true end
    local key = origin and nodeId .. "/ahead" or nodeId
    return query(player, "reach", ped, key, ids, ped, candidates, origin)
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
        pending.result = {groundZ = result[1], visible = result[2], clear = true, destination = destination}
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
                and math.abs(probe[1] - point[3] - 1.5) <= 7 then
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
    elseif pending.kind == "reach" and type(result) == "table" and #result <= 15 then
        local reachable = {}
        for _, nodeId in ipairs(result) do
            if type(nodeId) ~= "number" or not pending.acceptable[nodeId] then return end
            reachable[#reachable + 1] = nodeId
        end
        pending.result = reachable
    end
end, false)

addEvent("npchlc_traffic:worldProbeReady", true)
addEventHandler("npchlc_traffic:worldProbeReady", resourceRoot, function()
    if client then ready[client] = true end
end, false)

addEventHandler("onPlayerQuit", root, function()
    requests[source], ready[source], roadViews[source] = nil, nil, nil
end)
