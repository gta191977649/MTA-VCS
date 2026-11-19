TrafficAmbient = {}

local hlc = exports.npc_hlc
local graph, density, timer, provider
local models, pending, actors = {}, {}, {}
local playerIndex = 0
local pendingCursor
local actorCount = 0
local attemptInterval = 50
local attemptTimeout = 2000
local blockedRouteTimeout = 8000
local hitRecoveryMs = 900

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function integer(value, minimum, maximum)
    return finite(value) and value % 1 == 0 and value >= minimum and value <= maximum
end

local function query(name, ...)
    if provider and getResourceState(provider) == "running" then return call(provider, name, ...) end
    if TrafficWorld then
        if name == "probeTrafficPedestrianSpawn" then return TrafficWorld.probeSpawn(...) end
        if name == "getTrafficPedestrianReachable" then return TrafficWorld.reachable(...) end
    end
end

function registerTrafficPedestrianWorld()
    if not sourceResource then return false end
    if provider and provider ~= sourceResource and getResourceState(provider) == "running" then return false end
    provider = sourceResource
    return true
end

function bindTrafficPedestrianModel(originalModelId, mtaModelId)
    if not integer(originalModelId, 0, 65535)
        or mtaModelId ~= false and not integer(mtaModelId, 0, 65535) then return false end
    models[originalModelId] = mtaModelId or nil
    return true
end

function TrafficAmbient.getPedestrianModel(originalModelId)
    return models[originalModelId] or (TrafficModelBindings and TrafficModelBindings.getPedestrian(originalModelId)) or false
end

-- 0x00432888 reserves the police and territory branches before picking a road class.
-- 0x00432788 and 0x00432800 use cumulative thresholds in the zone record.
function TrafficAmbient.vehicleClass(values, water, categoryRoll, rollWithinClass)
    if not water then
        if categoryRoll < values[24] then return false, "police" end
        for index = 15, 23 do
            if categoryRoll < values[index] then return false, "territory", index - 15 end
        end
    end
    local start, finish = water and values[10] or 0, water and values[14] or values[10]
    if finish <= start then return false end
    local roll = start + rollWithinClass(finish - start)
    if water then
        for index = 11, 13 do
            if roll < values[index] then return index - 2 end
        end
        return 12
    end
    for index = 2, 9 do
        if roll < values[index] then return index - 2 end
    end
    return 8
end

-- 0x003C8CD8 registers each streamed model's class and frequency at 0x00432E90.
-- 0x00432A38 uses the first cumulative frequency greater than or equal to the roll.
function TrafficAmbient.pickVehicleModel(rules, class, available, rollWithinClass)
    local eligible, total = {}, 0
    for _, rule in ipairs(rules or {}) do
        if rule.trafficClass == class and available(rule.originalId) then
            total = total + rule.frequency
            eligible[#eligible + 1] = {id = rule.originalId, upper = total}
        end
    end
    if total == 0 then return false end
    local roll = rollWithinClass(total)
    for _, model in ipairs(eligible) do
        if roll <= model.upper then return model.id end
    end
    return false
end

-- SLUS_215.90 0x00267E98: intersect the directed segment with the search sphere.
local function intersect(from, to, x, y, radius)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local lengthSquared = dx * dx + dy * dy + dz * dz
    if lengthSquared == 0 then return false end

    -- 0x00268048 passes a center with the player's XY and zero Z.
    local px, py, pz = x - from.x, y - from.y, -from.z
    local projection = (px * dx + py * dy + pz * dz) / lengthSquared
    if projection < 0 then return false end
    local offsetSquared = px * px + py * py + pz * pz - projection * projection * lengthSquared
    local width = (radius * radius - offsetSquared) / lengthSquared
    if width < 0 then return false end
    width = math.sqrt(width)
    local lower, upper = math.max(0, projection - width), math.min(1, projection + width)
    if lower > upper then return false end
    return lower, upper
end

function TrafficAmbient.samplePedestrianEdge(from, to, edge, x, y, radius, chance, positionRoll)
    -- 0x00268048 skips disabled nodes and the high-bit adjacency class.
    if edge.flags >= 0x8000 or math.floor(from.flags / 0x20) % 2 == 1
        or math.floor(to.flags / 0x20) % 2 == 1
        or chance > math.min(from.spawnThreshold, to.spawnThreshold) then return false end
    local lower, upper = intersect(from, to, x, y, radius)
    if not lower then return false end
    local t = lower + (upper - lower) * positionRoll / 256
    return from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t, from.z + (to.z - from.z) * t
end

local maxPedestrianRange = TrafficVisibility.pedestrianRange * TrafficVisibility.pedestrianMaxScale

local function currentPopulationRecord(x, y, z, hour)
    local profile = TrafficPopulation.sample(graph.population, x, y, z, hour)
    if not profile then return end
    local recordId = hour >= 8 and hour < 19 and profile.dayProfileId or profile.nightProfileId
    return graph.population.records[recordId + 1].values, profile
end

local function rollBelow(limit)
    return math.random(0, limit - 1)
end

function chooseTrafficCivilianVehicle(x, y, z, water, hour)
    if not graph or not TrafficModelBindings or type(water) ~= "boolean" then return false end
    local values = currentPopulationRecord(x, y, z, hour or getTime())
    if not values then return false end
    local class, reserved = TrafficAmbient.vehicleClass(values, water, rollBelow(1000), rollBelow)
    if not class then return false, reserved end
    local originalId = TrafficAmbient.pickVehicleModel(graph.vehicleModelRules, class,
        TrafficModelBindings.get, rollBelow)
    return originalId and TrafficModelBindings.get(originalId) or false, originalId, class
end

function TrafficAmbient.zoneBudget(profile, rain)
    -- Ordinary freeroam values at 0x00488004, 0x0048A67C and 0x00487FF8.
    local weatherScale = 1 - math.sqrt(math.max(0, math.min(1, rain))) * 0.8
    return math.min(25, (profile.vehicleDensity + profile.pedestrianDensity) * 0.4 * weatherScale)
end

local function defaultContext(player)
    if getElementInterior(player) ~= 0 then return end
    local x, y, z = getElementPosition(player)
    local hour = getTime()
    local values, profile = currentPopulationRecord(x, y, z, hour)
    if not profile then return end
    local groupChance = 0
    for index = 26, 34 do groupChance = math.max(groupChance, values[index]) end
    return {
        cap = TrafficAmbient.zoneBudget(profile, getRainLevel() or 0),
        streamingDistanceScale = 1,
        groupChance = groupChance,
        policeChance = values[35],
    }
end

local function nearbyBuckets(x, y)
    local buckets = {}
    local centerX, centerY = math.floor(x / 80 + 30), math.floor(y / 80 + 25)
    for cy = centerY - 2, centerY + 2 do
        for cx = centerX - 2, centerX + 2 do
            local column = graph.pedestrianCells[cx]
            if column and column[cy] then buckets[#buckets + 1] = column[cy] end
        end
    end
    return buckets
end

local function headingFor(dx, dy)
    return math.floor(math.atan2(dx, dy) * 4 / math.pi + 0.5) % 8
end

local function spawnEndpoints(from, to, heading)
    for offset = 1, to.linkCount do
        local reverse = graph.links[to.firstLink + offset]
        if reverse.to == from.id and reverse.flags < 0x8000 then
            local direction = headingFor(to.x - from.x, to.y - from.y)
            local difference = (heading - direction) % 8
            -- Project the original eight-way wander choice onto this segment.
            if difference >= 3 and difference <= 6 then return {from, to} end
            return {to, from}
        end
    end
    return {to}
end

local function collectCandidate(player, context)
    local x, y, z = getElementPosition(player)
    local profile = TrafficPopulation.sample(graph.population, x, y, z, getTime(), math.random(0, 15))
    if not profile then return false end
    local model = TrafficAmbient.getPedestrianModel(profile.originalModelId)
    if not model then return false end

    -- Ordinary single-ped branch in 0x002B17A8. Group/police branches remain with their providers.
    local category = math.random(0, 999)
    if category < math.max(context.groupChance, context.policeChance) or math.random() > 0.95 then return false end

    local speed = TrafficVisibility.pedestrianScale(player)
    local visibleMin, visibleMax = speed * 35 * context.streamingDistanceScale, speed * 60 * context.streamingDistanceScale
    local hiddenMin, hiddenMax = speed * 20 - 10, speed * 20
    local chance, visited = math.random(0, 15), 0
    local scene = getElementInterior(player) == 3 and "underground" or "outdoor"
    local function visit(from)
        if from.scene ~= scene or getDistanceBetweenPoints2D(x, y, from.x, from.y) > 160 then return end
        for offset = 1, from.linkCount do
            local edge = graph.links[from.firstLink + offset]
            local to = graph.nodes[edge.to + 1]
            if to.scene == scene then
                local px, py, pz = TrafficAmbient.samplePedestrianEdge(from, to, edge, x, y, visibleMax, chance,
                    math.random(0, 255))
                if px then
                    local distance = getDistanceBetweenPoints2D(x, y, px, py)
                    if (visibleMin < distance and distance < visibleMax)
                        or (hiddenMin < distance and distance < hiddenMax) then
                        return {x = px, y = py, z = pz, from = from, to = to, model = model,
                            originalModelId = profile.originalModelId, started = getTickCount(),
                            visibleMin = visibleMin, visibleMax = visibleMax,
                            hiddenMin = hiddenMin, hiddenMax = hiddenMax, interior = getElementInterior(player),
                            dimension = getElementDimension(player), playerX = x, playerY = y}
                    end
                end
            end
        end
    end
    local buckets = nearbyBuckets(x, y)
    if #buckets == 0 then return end
    local start = math.random(0, #buckets - 1)
    for index = 0, #buckets - 1 do
        for _, from in ipairs(buckets[(start + index) % #buckets + 1]) do
            visited = visited + 1
            if visited > 150 then return end
            local candidate = visit(from)
            if candidate then return candidate end
        end
    end
end

local function removeActor(ped, fade)
    local state = actors[ped]
    if not state then return end
    actors[ped] = nil
    actorCount = actorCount - 1
    if not isElement(ped) then return end
    if fade then
        if state.queued > 0 then hlc:clearNPCTasks(ped) end
        TrafficVisibility.retire(ped, nil, function()
            if isElement(ped) then destroyElement(ped) end
        end)
    else
        destroyElement(ped)
    end
end

local function walkToNode(ped, state, target, heading, from, link)
    local signalized = link and (link.pedestrianSignal == true
        or link.pedestrianSignal == nil and link.flags == 0xc000)
    local task = signalized and {"walkTrafficCrossing", target.x, target.y, target.z, 0.45, from.x, from.y}
        or {"walkTrafficToPoint", target.x, target.y, target.z, 1}
    if not hlc:addNPCTask(ped, task) then return false end
    if state.queued == 0 then state.crossing = signalized else state.nextCrossing = signalized end
    state.anchor, state.heading, state.queued = target.id, heading, state.queued + 1
    state.blockedSince, state.retryAt = nil, nil
    if state.queued == 1 then
        state.lastX, state.lastY = getElementPosition(ped)
        state.lastMovement = getTickCount()
    end
    return true
end

local function hasPedestrianSpace(x, y, z, interior, dimension, cap)
    if cap <= 0 then return false end
    local population = getElementsWithinRange(x, y, z, maxPedestrianRange, "ped", interior, dimension) or {}
    local count = 0
    for _, ped in ipairs(population) do
        if not (TrafficRoad and TrafficRoad.isManagedPed(ped) and isPedInVehicle(ped)) then
            count = count + 1
            if count >= cap then return false end
        end
    end
    return true
end

local function saveActor(player, candidate)
    if not hasPedestrianSpace(candidate.playerX, candidate.playerY, candidate.playerZ,
        candidate.interior, candidate.dimension, candidate.cap) then return end

    -- Overlapping multiplayer interests must not introduce an actor immediately beside a second observer.
    local observers = getElementsWithinRange(candidate.finalX, candidate.finalY, candidate.groundZ, 35,
        "player", candidate.interior, candidate.dimension) or {}
    for _, observer in ipairs(observers) do
        if observer ~= player then return end
    end
    local ped = createPed(candidate.model, candidate.finalX, candidate.finalY, candidate.groundZ + 0.7)
    if not ped then return end
    setElementInterior(ped, getElementInterior(player))
    setElementDimension(ped, getElementDimension(player))
    TrafficModelBindings.tag(ped, candidate.originalModelId)
    if not hlc:enableHLCForNPC(ped, "walk") then
        destroyElement(ped)
        return
    end
    local state = {owner = player, queued = 0}
    local target = graph.nodes[candidate.destination + 1]
    local heading = headingFor(target.x - candidate.finalX, target.y - candidate.finalY)
    if not walkToNode(ped, state, target, heading) then destroyElement(ped) return end
    actors[ped] = state
    actorCount = actorCount + 1
    TrafficVisibility.track(ped, "pedestrian")
end

function TrafficAmbient.isManagedPed(ped)
    return actors[ped] ~= nil
end

local function advancePedestrian(ped, state)
    local x, y, z = getElementPosition(ped)
    local player = getElementSyncer(ped) or state.owner
    if not isElement(player) or getElementDimension(ped) ~= getElementDimension(player)
        or getElementInterior(ped) ~= getElementInterior(player) then
        local nearby = getElementsWithinRange(x, y, z, 80, "player", getElementInterior(ped), getElementDimension(ped))
        player = nearby and nearby[1]
        if not player then removeActor(ped) return end
        state.owner = player
    end
    local nodeId = state.queued > 0 and state.anchor or TrafficGraph.pedestrianAnchor(graph, x, y, z, state.anchor)
    if not nodeId then return false end
    local node = graph.nodes[nodeId + 1]
    local candidates = {}
    for offset = 1, node.linkCount do
        local edge = graph.links[node.firstLink + offset]
        local target = graph.nodes[edge.to + 1]
        candidates[#candidates + 1] = {id = target.id, x = target.x, y = target.y, z = target.z}
    end
    local reachable = query("getTrafficPedestrianReachable", player, ped, node.id, candidates,
        state.queued > 0 and node or nil)
    if reachable == nil then return end
    if type(reachable) ~= "table" then return false end
    local targetId, heading, link = TrafficGraph.pedestrianStep(graph, nodeId, state.heading, reachable)
    if not targetId or targetId == nodeId then return false end
    return walkToNode(ped, state, graph.nodes[targetId + 1], heading, node, link)
end

local actorCursor
local function onDamage(loss)
    local state = actors[source]
    if not state or loss <= 0 or isPedInVehicle(source) then return end
    if state.queued > 0 then hlc:clearNPCTasks(source) end
    -- Let the native collision task keep its velocity and animation. Re-anchor
    -- from the landing position instead of resuming the previous walk target.
    state.queued, state.blockedSince, state.retryAt = 0, nil, nil
    state.crossing, state.nextCrossing = nil, nil
    state.hitAt = getTickCount()
end

local function hasNearbyObserver(ped, x, y, z)
    local observers = getElementsWithinRange(x, y, z, maxPedestrianRange,
        "player", getElementInterior(ped), getElementDimension(ped)) or {}
    for _, player in ipairs(observers) do
        local px, py, pz = getElementPosition(player)
        local horizontal = (px - x) ^ 2 + (py - y) ^ 2
        local radius = TrafficVisibility.pedestrianRange * TrafficVisibility.pedestrianScale(player)
        if horizontal <= radius ^ 2 and horizontal + (pz - z) ^ 2 <= maxPedestrianRange ^ 2 then
            return true
        end
    end
    return false
end

local function updateActors()
    local now = getTickCount()
    for _ = 1, math.min(8, actorCount) do
        if actorCursor and not actors[actorCursor] then actorCursor = nil end
        local ped, state = next(actors, actorCursor)
        actorCursor = ped
        if not ped then break end
        if isPedDead(ped) then
            TrafficVisibility.keepDeadPed(ped)
        else
            local x, y, z = getElementPosition(ped)
            if not hasNearbyObserver(ped, x, y, z) then
                removeActor(ped)
            elseif state.hitAt then
                local elapsed = (now - state.hitAt) % 4294967296
                if elapsed >= hitRecoveryMs and (isPedOnGround(ped) or elapsed >= 2500) then
                    state.hitAt, state.blockedSince = nil, now
                end
            else
                if state.queued > 0 then
                    if (x - state.lastX) ^ 2 + (y - state.lastY) ^ 2 >= 0.25 then
                        state.lastX, state.lastY, state.lastMovement = x, y, now
                    elseif (now - state.lastMovement) % 4294967296 >= (state.crossing and 35000 or blockedRouteTimeout) then
                        hlc:clearNPCTasks(ped)
                        state.queued, state.blockedSince, state.retryAt = 0, now, nil
                        state.crossing, state.nextCrossing = nil, nil
                    end
                end
                if state.blockedSince and (now - state.blockedSince) % 4294967296 > blockedRouteTimeout then
                    removeActor(ped, true)
                elseif state.queued < 2 and (not state.retryAt or (now - state.retryAt) % 4294967296 >= 250) then
                    if advancePedestrian(ped, state) == false then state.retryAt = now end
                end
            end
        end
    end
end

local function continueCandidate(player, candidate)
    if not isElement(player) then pending[player] = nil return end
    local x, y = getElementPosition(player)
    if (getTickCount() - candidate.started) % 4294967296 > attemptTimeout
        or candidate.interior ~= getElementInterior(player) or candidate.dimension ~= getElementDimension(player)
        or TrafficAmbient.getPedestrianModel(candidate.originalModelId) ~= candidate.model
        or getDistanceBetweenPoints2D(x, y, candidate.playerX, candidate.playerY) > 2 then
        pending[player] = nil
        return
    end
    if candidate.finalX then
        local probe = query("probeTrafficPedestrianSpawn", player,
            candidate.finalX, candidate.finalY, candidate.groundZ, candidate.model, candidate.endpoints)
        if probe == nil then return end
        pending[player] = nil
        if type(probe) == "table" and probe.clear and finite(probe.groundZ) then
            for _, endpoint in ipairs(candidate.endpoints) do
                if probe.destination == endpoint.id then
                    candidate.destination, candidate.groundZ = endpoint.id, probe.groundZ
                    saveActor(player, candidate)
                    break
                end
            end
        end
        return
    end
    local probe = query("probeTrafficPedestrianSpawn", player, candidate.x, candidate.y, candidate.z, candidate.model)
    if probe == nil then return end
    pending[player] = nil
    if type(probe) ~= "table" or not finite(probe.groundZ) or math.abs(probe.groundZ - candidate.z) > 3 then return end
    local lower = probe.visible and candidate.visibleMin or candidate.hiddenMin
    local upper = probe.visible and candidate.visibleMax or candidate.hiddenMax
    local distance = getDistanceBetweenPoints2D(x, y, candidate.x, candidate.y)
    if not (lower < distance and distance < upper) then return end
    -- 0x0026B510 jitter uses two low nibbles and the narrower endpoint's packed width.
    local width = math.min(candidate.from.rawWidth, candidate.to.rawWidth)
    candidate.finalX = candidate.x + (math.random(0, 15) - 7) * width * 0.00775
    candidate.finalY = candidate.y + (math.random(0, 15) - 7) * width * 0.00775
    candidate.groundZ = probe.groundZ
    -- SLUS_215.90 0x002B17A8 samples a wander heading after finding the spawn.
    candidate.endpoints = spawnEndpoints(candidate.from, candidate.to, math.random(0, 7))
    pending[player] = candidate
end

local function tick()
    updateActors()
    if (not next(models) and not (TrafficModelBindings and TrafficModelBindings.hasCatalog()))
        or not (provider and getResourceState(provider) == "running" or TrafficWorld) then return end
    local densityScale = density("peds")
    if not densityScale or densityScale == 0 then
        pending, pendingCursor = {}, nil
        return
    end
    for _ = 1, 8 do
        if pendingCursor and not pending[pendingCursor] then pendingCursor = nil end
        local player, candidate = next(pending, pendingCursor)
        pendingCursor = player
        if not candidate then break end
        continueCandidate(player, candidate)
    end
    local players = getElementsByType("player")
    if #players == 0 then return end
    playerIndex = playerIndex % #players + 1
    local player = players[playerIndex]
    if pending[player] then return end

    local context = query("getTrafficPedestrianContext", player) or defaultContext(player)
    if type(context) ~= "table" or not finite(context.cap) or not finite(context.streamingDistanceScale)
        or context.streamingDistanceScale <= 0 or not integer(context.groupChance, 0, 1000)
        or not integer(context.policeChance, 0, 1000) then return end
    local cap = math.floor(context.cap * densityScale)
    local x, y, z = getElementPosition(player)
    local interior, dimension = getElementInterior(player), getElementDimension(player)
    if not hasPedestrianSpace(x, y, z, interior, dimension, cap) then return end
    local candidate = collectCandidate(player, context)
    if not candidate then return end
    candidate.cap, candidate.playerZ = cap, z
    pending[player] = candidate
    continueCandidate(player, candidate)
end

local function onTaskDone(task)
    local actor = actors[source]
    if not actor or (task[1] ~= "walkTrafficToPoint" and task[1] ~= "walkTrafficCrossing") then return end
    actor.queued = math.max(0, actor.queued - 1)
    actor.crossing, actor.nextCrossing = actor.nextCrossing, nil
    if actor.queued == 0 then actor.blockedSince = getTickCount() end
end

local function onDestroy()
    if actors[source] then
        actors[source] = nil
        actorCount = actorCount - 1
    end
end

local function onQuit()
    pending[source] = nil
end

function getTrafficAmbientStatus()
    local modelCount = 0
    for _ in pairs(models) do modelCount = modelCount + 1 end
    return {pedestrians = actorCount, pedestrianModels = modelCount,
        pedestrianProbe = provider ~= nil or TrafficWorld ~= nil}
end

function TrafficAmbient.start(loadedGraph, getDensity)
    graph, density = loadedGraph, getDensity
    if not graph.population then return end
    addEventHandler("npc_hlc:onNPCTaskDone", root, onTaskDone)
    addEventHandler("onPedDamage", root, onDamage)
    addEventHandler("onElementDestroy", root, onDestroy)
    addEventHandler("onPlayerQuit", root, onQuit)
    timer = setTimer(tick, attemptInterval, 0)
end

function TrafficAmbient.stop()
    if timer then
        killTimer(timer)
        removeEventHandler("npc_hlc:onNPCTaskDone", root, onTaskDone)
        removeEventHandler("onPedDamage", root, onDamage)
        removeEventHandler("onElementDestroy", root, onDestroy)
        removeEventHandler("onPlayerQuit", root, onQuit)
    end
    for ped in pairs(actors) do removeActor(ped) end
    graph, density, timer, pending, actorCursor, pendingCursor = nil, nil, nil, {}, nil, nil
end
