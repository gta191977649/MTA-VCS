TrafficRoad = {}

local HLC = exports.npc_hlc
local models = exports.server_coldata
local cells, vehicles, drivers, pending, cursorByPlayer = {}, {}, {}, {}, {}
local incoming = {}
local lastRoadAttempt = {}
local observers, observerList = {}, {}
local vehicleHead, vehicleTail, vehicleCursor
local gameDay, previousHour = 4, nil
local graph, density, timer, densityMode
local activeCount, nextPlayer = 0, 0
local readyBatches, readyHead, readyTail = {}, 1, 0
local stats = {}
local CELL_SIZE = 80
local UPDATE_MS = 50
local MAX_LIFETIME_WITHOUT_PROGRESS = 30000
local TRAFFIC_AREA_RADIUS = TrafficVisibility.roadRange
local DEFAULT_MTA_SYNC_RADIUS = 130
local syncRadius = DEFAULT_MTA_SYNC_RADIUS
local EDGE_WIDTH = 30
local EDGE_STALL_MS = 2500
local OBSERVER_SQUARE_SIZE = 25
local MAX_CLEANUP_PER_TICK = 40
local MAX_PER_TRAFFIC_AREA = 16
-- Bound the number of replicated traffic entities when players occupy disjoint areas.
local MAX_SERVER_VEHICLES = 160
local MAX_NODES_PER_LOCAL_CELL = 100
local MAX_OBSERVERS_PER_TICK = 12
local MAX_BATCHES_PER_TICK = 4
local SEARCH_BUDGET_MS = 2
local SPAWN_ATTEMPTS = 5
local FAST_SPEED = 20 -- metres per second
local IMPACT_RESTITUTION = 0.35 -- MTA traffic response tuning
local MAX_CREATES_PER_TICK = 4
local MAX_ADMISSIONS_PER_TICK = 20
local PROBE_TIMEOUT_MS = 1000
local SHARED_SPAWN_RADIUS = 80
local SPAWN_POSITION_TOLERANCE = 15
local railTag = "npchlc_traffic:rail"

local function hasFlag(node, mask)
    return math.floor(node.flags / mask) % 2 == 1
end

local function length2D(x, y)
    return math.sqrt(x * x + y * y)
end

local function record(reason)
    stats[reason] = (stats[reason] or 0) + 1
end

-- SLUS_215.90 0x00267928 interpolates between endpoint distances when
-- the directed path crosses the spawn circle. This is a radial interpolation.
function TrafficRoad.crossing(from, to, x, y, radius)
    local distanceFrom = length2D(from.x - x, from.y - y)
    local distanceTo = length2D(to.x - x, to.y - y)
    if (distanceFrom > radius) == (distanceTo > radius) then return false end
    return math.abs(distanceFrom - radius) / (math.abs(distanceFrom - radius) + math.abs(distanceTo - radius))
end

function TrafficRoad.chooseDriver(group, masks, class, firstSlot, loaded, fallback)
    -- 0x002B3CA0, 0x002B35B0 and 0x002B36C0 use a group roll, then a wrapped
    -- sequence of up to sixteen models with the traffic-class bit at offset 0x3C.
    if group then
        local flag = 2 ^ (class % 32)
        for offset = 0, 15 do
            local id = group[(firstSlot + offset) % 16 + 1]
            local mask = id and masks and masks[tostring(id)]
            if id and (not masks or mask and math.floor(mask / flag) % 2 == 1) and loaded(id) then return id end
        end
    end
    if fallback and loaded(fallback) then return fallback end
    return false
end

local function indexRoads()
    for _, node in ipairs(graph.nodes) do
        if node.kind == "vehicle" and node.scene == "outdoor" and not hasFlag(node, 0x20) then
            local i, j = math.floor(node.x / CELL_SIZE), math.floor(node.y / CELL_SIZE)
            if not cells[i] then cells[i] = {} end
            if not cells[i][j] then cells[i][j] = {} end
            local cell = cells[i][j]
            cell[#cell + 1] = node
            for offset = 1, node.linkCount do
                local edge = graph.links[node.firstLink + offset]
                if edge.lanes > 0 then
                    local edges = incoming[edge.to] or {}
                    edges[#edges + 1] = edge
                    incoming[edge.to] = edges
                end
            end
        end
    end
end

local function outgoingChoices(graph, edge, lane)
    local from, current = graph.nodes[edge.from + 1], graph.nodes[edge.to + 1]
    local dx, dy = current.x - from.x, current.y - from.y
    local length = length2D(dx, dy)
    if length == 0 then return {} end
    local preferred, available = {}, {}
    local reverse
    for offset = 1, current.linkCount do
        local candidate = graph.links[current.firstLink + offset]
        local target = graph.nodes[candidate.to + 1]
        if TrafficGraph.canDriveTransition(graph, edge, candidate) and target.scene == current.scene
            and (not hasFlag(target, 0x20) or hasFlag(from, 0x20)) then
            if target == from then
                reverse = candidate
            else
                local tx, ty = target.x - current.x, target.y - current.y
                local turnLength = length2D(tx, ty)
                if turnLength > 0 then
                    available[#available + 1] = candidate
                    local cross = (dx * ty - dy * tx) / (length * turnLength)
                    -- Turn classes and lane bias from 0x004369D0 and 0x004361A8.
                    local canTurn = (cross > 0.77 and lane == 0)
                        or (cross < -0.77 and lane == edge.lanes - 1)
                        or (math.abs(cross) <= 0.77 and (edge.lanes < 3 or (lane > 0 and lane < edge.lanes - 1)))
                    if canTurn and (not hasFlag(target, 0x10) or hasFlag(from, 0x10)) then
                        preferred[#preferred + 1] = candidate
                    end
                end
            end
        end
    end
    if #preferred > 0 then return preferred end
    if #available > 0 then return available end
    return {reverse}, true
end

-- The VCS lane-choice roll nominates a lane. Use synchronized traffic
-- positions to refuse optional changes with an occupied entry gap.
function TrafficRoad.laneEntryClear(roadGraph, edge, lane, dimension, vehicle, speed)
    local from, to = roadGraph.nodes[edge.from + 1], roadGraph.nodes[edge.to + 1]
    local cx, cy, cz = TrafficGraph.lanePoint(roadGraph, edge, lane)
    local dx, dy = to.x - from.x, to.y - from.y
    local length = length2D(dx, dy)
    if not cx or length == 0 then return false end
    cx, cy, cz = cx - dx * 0.5, cy - dy * 0.5, cz - (to.z - from.z) * 0.5
    dx, dy = dx / length, dy / length
    local nearby = getElementsWithinRange(cx, cy, cz, 44, "vehicle", 0, dimension)
    if not nearby then return false end
    for _, other in ipairs(nearby) do
        if other ~= vehicle then
            local x, y, z = getElementPosition(other)
            local px, py = x - cx, y - cy
            if math.abs(z - cz) <= 3 and math.abs(px * dy - py * dx) <= 2.75 then
                local ahead = px * dx + py * dy
                local vx, vy = getElementVelocity(other)
                local state = vehicles[other]
                if state and state.rail and state.railMotion then vx, vy = state.railMotion.vx, state.railMotion.vy end
                local otherSpeed = (vx * dx + vy * dy) * 50
                local closing = ahead < 0 and otherSpeed - speed or speed - otherSpeed
                if math.abs(ahead) < math.max(9, 5 + 1.5 * closing) then return false end
            end
        end
    end
    return true
end

local function chooseOutgoing(edge, lane, context)
    local choices, fallback = outgoingChoices(graph, edge, lane)
    local nextEdge = #choices > 0 and choices[fallback and 1 or math.random(#choices)]
    if not nextEdge then return false end
    local current, target = graph.nodes[edge.to + 1], graph.nodes[nextEdge.to + 1]
    local tx, ty = target.x - current.x, target.y - current.y
    -- 0x004361A8 tests two random bits, then permits one lane change on links at least 14 units long.
    lane = math.min(lane, nextEdge.lanes - 1)
    if nextEdge.lanes > 1 and tx * tx + ty * ty >= 196 and math.random(0, 3) == 0 then
        local targetLane = math.max(0, math.min(lane + (math.random(0, 1) == 0 and -1 or 1), nextEdge.lanes - 1))
        if targetLane ~= lane and context and TrafficRoad.laneEntryClear(graph, nextEdge, targetLane, context.dimension,
            context.vehicle, context.cruiseSpeed or 12) then
            lane = targetLane
        end
    end
    return nextEdge, lane
end

local function finishRelease(state)
    TrafficVisibility.releasePed(state.driver)
    local vehicle = state.vehicle
    if not isElement(vehicle) then return end
    if state.rail then
        setElementFrozen(vehicle, false)
        setElementData(vehicle, railTag, false, "broadcast", "deny")
    end
    if TrafficVisibility.hasPlayerOccupant(vehicle) then
        TrafficVisibility.detach(vehicle)
    else
        destroyElement(vehicle)
    end
end

local function release(state, fade)
    if vehicles[state.vehicle] ~= state then return end
    vehicles[state.vehicle], drivers[state.driver] = nil, nil
    activeCount = activeCount - 1
    local before, after = state.before, state.after
    if before then before.after = after else vehicleHead = after end
    if after then after.before = before else vehicleTail = before end
    if vehicleCursor == state then vehicleCursor = after or vehicleHead end
    state.before, state.after = nil, nil
    local vehicle = state.vehicle
    if fade and isElement(vehicle) and getElementSyncer(vehicle) and not TrafficVisibility.hasPlayerOccupant(vehicle) then
        if isElement(state.driver) then HLC:clearNPCTasks(state.driver) end
        TrafficVisibility.retire(vehicle, state.driver, function() finishRelease(state) end)
    else
        finishRelease(state)
    end
end

local function assignTask(state, task)
    if not HLC:setNPCTask(state.driver, task) then
        release(state)
        return
    end
    state.lastProgress = getTickCount()
    return true
end

local function laneCentre(edge, lane)
    local x, y, z = TrafficGraph.lanePoint(graph, edge, lane)
    if x then return {x, y, z} end
end

local function signalGroup(edge)
    return edge.lightDirection and (edge.lightGroup == 1 or edge.lightGroup == 2) and edge.lightGroup or 0
end

local function edgeDirection(edge)
    local from, to = graph.nodes[edge.from + 1], graph.nodes[edge.to + 1]
    local dx, dy = to.x - from.x, to.y - from.y
    local distance = length2D(dx, dy)
    return dx / distance, dy / distance
end

local function extrapolate(from, to)
    return {2 * to[1] - from[1], 2 * to[2] - from[2], 2 * to[3] - from[3]}
end

local function debugLanePoint(graph, edge, lane)
    local x, y, z = TrafficGraph.lanePoint(graph, edge, math.min(lane, edge.lanes - 1))
    return x and {x, y, z}
end

local function debugPredecessor(graph, edge, lane)
    local junction = graph.nodes[edge.from + 1]
    for offset = 1, junction.linkCount do
        local neighbour = graph.nodes[graph.links[junction.firstLink + offset].to + 1]
        for incomingOffset = 1, neighbour.linkCount do
            local inbound = graph.links[neighbour.firstLink + incomingOffset]
            if inbound.to == edge.from and inbound.lanes > 0 and neighbour.scene == junction.scene then
                for _, choice in ipairs(outgoingChoices(graph, inbound, math.min(lane, inbound.lanes - 1))) do
                    if choice == edge then return debugLanePoint(graph, inbound, lane) end
                end
                break
            end
        end
    end
end

function TrafficRoad.debugConnections(graph, edge, lane)
    local connections = {}
    if hasFlag(graph.nodes[edge.from + 1], 0x20) or hasFlag(graph.nodes[edge.to + 1], 0x20) then
        return connections
    end
    local b = debugLanePoint(graph, edge, lane)
    if not b then return connections end
    local a = debugPredecessor(graph, edge, lane) or b
    for _, nextEdge in ipairs(outgoingChoices(graph, edge, lane)) do
        local c = debugLanePoint(graph, nextEdge, lane)
        if c then
            local following = outgoingChoices(graph, nextEdge, math.min(lane, nextEdge.lanes - 1))[1]
            local d = following and debugLanePoint(graph, following, lane) or extrapolate(b, c)
            local samples = HLC:getNPCTrafficRailDebugPoints({"driveTrafficRail",
                a[1], a[2], a[3], b[1], b[2], b[3], c[1], c[2], c[3], d[1], d[2], d[3], 0, 0, 0})
            local points = {}
            for i = 1, #samples, 2 do points[#points + 1] = samples[i] end
            connections[#connections + 1] = points
        end
    end
    return connections
end

local function fillRoute(state, count)
    local route = state.railRoute
    while #route < count do
        local last = route[#route]
        local edge, lane = chooseOutgoing(last.edge, last.lane, state)
        local point = edge and laneCentre(edge, lane)
        if not point then break end
        route[#route + 1] = {edge = edge, lane = lane, point = point}
    end
end

local function railTask(state)
    local route, height = state.railRoute, state.heightOffset or 0
    fillRoute(state, 4)
    local a, b, c = state.railPrevious, state.railStart, route[1].point
    local d = route[2] and route[2].point or extrapolate(b, c)
    local task = {"driveTrafficRail", a[1], a[2], a[3] + height, b[1], b[2], b[3] + height,
        c[1], c[2], c[3] + height, d[1], d[2], d[3] + height,
        state.cruiseSpeed or 0, signalGroup(route[1].edge), state.centreHeight or 0}
    local count = math.min(3, #route)
    for index = 2, count do
        local following = route[index + 1] and route[index + 1].point
            or extrapolate(route[index - 1].point, route[index].point)
        task[#task + 1] = signalGroup(route[index].edge)
        task[#task + 1] = following[1]
        task[#task + 1] = following[2]
        task[#task + 1] = following[3] + height
    end
    for index = 1, count do
        task[#task + 1] = route[index].speedClass or route[index].edge.speedClass
    end
    return task
end

local function followRail(state)
    local task = railTask(state)
    state.railTask = task
    assignTask(state, task)
end

local function prepareSpawnRail(candidate)
    local edge, lane = candidate.edge, candidate.lane
    local midpoint = laneCentre(edge, lane)
    if not midpoint then return false end
    local previous, count = nil, 0
    for _, approach in ipairs(incoming[edge.from] or {}) do
        if approach.from ~= edge.to and TrafficGraph.canDriveTransition(graph, approach, edge) then
            local centre = laneCentre(approach, math.min(lane, approach.lanes - 1))
            if centre then
                count = count + 1
                if math.random(count) == 1 then previous = centre end
            end
        end
    end
    if not previous then return false end

    -- 0x002D1BC0 seeds the curve from the incoming and selected lane centres,
    -- then projects the provisional spawn position onto that curve.
    local rail = {railPrevious = previous, railStart = previous}
    local initial = {edge = edge, lane = lane, point = midpoint,
        speedClass = graph.nodes[edge.to + 1].speedClass}
    if (candidate.x - midpoint[1]) * candidate.dx + (candidate.y - midpoint[2]) * candidate.dy > 0 then
        local nextEdge, nextLane = chooseOutgoing(edge, lane, candidate)
        local point = nextEdge and laneCentre(nextEdge, nextLane)
        if not point then return false end
        rail.railStart = midpoint
        initial = {edge = nextEdge, lane = nextLane, point = point}
    end
    rail.railRoute = {initial}
    local x, y, z, dx, dy = HLC:projectNPCTrafficRailStart(railTask(rail), candidate.x, candidate.y)
    if not x or dx == 0 and dy == 0 then return false end
    candidate.x, candidate.y, candidate.z, candidate.dx, candidate.dy = x, y, z, dx, dy
    candidate.rail = rail
    return true
end

local function followPhysics(state)
    local route, start = state.railRoute, state.railStart
    fillRoute(state, 3)
    local segments = {}
    for index = 1, math.min(3, #route) do
        local item = route[index]
        local x, y, z = unpack(item.point)
        local dx, dy = edgeDirection(item.edge)
        segments[index] = {item.edge.id, item.lane, x, y, z + state.heightOffset, dx, dy,
            item.speedClass or item.edge.speedClass, signalGroup(item.edge)}
    end
    local task = {"driveTrafficPhysics", state.physicsSequence, state.cruiseSpeed,
        {start[1], start[2], start[3] + state.heightOffset}, segments}
    state.physicsTask = task
    return assignTask(state, task)
end

local function advancePhysics(state, steps)
    for _ = 1, steps do
        state.railStart = table.remove(state.railRoute, 1).point
    end
    state.physicsSequence = state.physicsSequence + steps
    followPhysics(state)
end

local function taskDone(task)
    local state = drivers[source]
    if not state then return end
    local route = state.railRoute
    if state.rail and task[1] == "driveTrafficRail" then
        if #route < 2 then release(state, true) return end
        state.railPrevious, state.railStart = state.railStart, table.remove(route, 1).point
        followRail(state)
    elseif not state.rail and task[1] == "driveTrafficPhysics" and task[2] == state.physicsSequence then
        if #route < 2 then release(state, true) return end
        advancePhysics(state, 1)
    end
end

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function sampleRailVelocity(state, x, y, z, now)
    local sample = state.railMotion
    if not sample then
        state.railMotion = {x = x, y = y, z = z, tick = now, vx = 0, vy = 0, vz = 0}
        return
    end
    local elapsed = (now - sample.tick) % 4294967296
    if elapsed < 40 then return end
    local dx, dy, dz = x - sample.x, y - sample.y, z - sample.z
    if dx * dx + dy * dy < 0.0001 and elapsed < 180 then return end
    local speed = math.sqrt(dx * dx + dy * dy) * 1000 / elapsed
    local scale = elapsed <= 400 and speed <= state.cruiseSpeed * 2.5 and 20 / elapsed or 0
    sample.vx, sample.vy, sample.vz = dx * scale, dy * scale, math.abs(dz) <= 2 and dz * scale or 0
    sample.x, sample.y, sample.z, sample.tick = x, y, z, now
end

local function railVelocity(state)
    local vx, vy, vz = getElementVelocity(state.vehicle)
    if vx * vx + vy * vy + vz * vz > 0.000001 then return vx, vy, vz, true end
    local sample = state.railMotion
    if sample and (getTickCount() - sample.tick) % 4294967296 <= 180 then
        return sample.vx, sample.vy, sample.vz
    end
    return 0, 0, 0
end

local function applyImpactMotion(state, collider, contact)
    local vehicle = state.vehicle
    local vx, vy, vz, nativeMotion = railVelocity(state)
    local nx, ny, nz = contact[4], contact[5], contact[6]
    local normalSpeed = vx * nx + vy * ny + vz * nz
    local targetNormal = 0
    local yawImpulse
    if collider then
        local cx, cy, cz = getElementVelocity(collider)
        local otherSpeed = cx * nx + cy * ny + cz * nz
        local driver = getVehicleOccupant(collider, 0)
        local approach = driver and observers[driver]
        if approach and approach.impactVehicle == collider then
            for _, sample in ipairs(approach.impactSamples) do
                if (getTickCount() - sample.tick) % 4294967296 <= 180 then
                    otherSpeed = math.max(otherSpeed, sample.x * nx + sample.y * ny + sample.z * nz)
                end
            end
        end
        local sample = state.railMotion
        local before = normalSpeed
        if sample and (getTickCount() - sample.tick) % 4294967296 <= 180 then
            before = sample.vx * nx + sample.vy * ny + sample.vz * nz
        end
        local target, other = getVehicleHandling(vehicle), getVehicleHandling(collider)
        targetNormal = before + math.min(1.5, (1 + IMPACT_RESTITUTION) * math.max(0, otherSpeed - before)
            * other.mass / (target.mass + other.mass))
        if otherSpeed <= before then targetNormal = normalSpeed end
        local x, y = getElementPosition(vehicle)
        yawImpulse = target.mass / math.max(target.mass, target.turnMass) * ((contact[1] - x) * ny - (contact[2] - y) * nx)
    elseif nativeMotion then
        return
    end
    -- Cruise velocity can already be nonzero before a side impact. Compare
    -- only the normal component so an existing collision response is retained.
    local missing = math.min(1.5, math.max(0, targetNormal - normalSpeed))
    if missing > 0.00001 or not nativeMotion then
        setElementVelocity(vehicle, vx + nx * missing, vy + ny * missing, vz + nz * missing)
        if yawImpulse and missing > 0.00001 then
            local wx, wy, wz = getElementAngularVelocity(vehicle)
            setElementAngularVelocity(vehicle, wx, wy, wz + math.max(-0.12, math.min(0.12, yawImpulse * missing)))
        end
    end
end

local function switchToPhysics(state, collider, contact)
    if not state.rail then return end
    local vehicle = state.vehicle
    local x, y, z = getElementPosition(vehicle)
    local _, _, yaw = getElementRotation(vehicle)
    local heading = math.rad(yaw)
    local segment = HLC:getNPCTrafficRailSegment(state.railTask, x, y, z, -math.sin(heading), math.cos(heading)) or 1
    for _ = 2, segment do
        state.railStart = table.remove(state.railRoute, 1).point
    end
    state.physicsSequence, state.railTask = 1, nil
    if not followPhysics(state) then return end
    state.rail = false
    record("physicsHandoffs")
    setElementData(vehicle, railTag, false, "broadcast", "deny")
    setElementFrozen(vehicle, false)
    if contact then
        applyImpactMotion(state, collider, contact)
    else
        state.awaitingImpactAt = getTickCount()
    end
end

addEvent("npchlc_traffic:railImpact", true)
addEventHandler("npchlc_traffic:railImpact", resourceRoot, function(vehicle, other, x, y, z, nx, ny, nz)
    local state = vehicles[vehicle]
    if not client or not state then return end
    if not state.rail and (not state.awaitingImpactAt
        or (getTickCount() - state.awaitingImpactAt) % 4294967296 > 600) then return end
    if getElementDimension(client) ~= state.dimension or getElementInterior(client) ~= 0 then return end
    local owner = client == getElementSyncer(vehicle)
    local otherVehicle = isElement(other) and other ~= vehicle and getElementType(other) == "vehicle"
    if not owner and (not otherVehicle or getVehicleOccupant(other, 0) ~= client) then return end
    if not finite(x) or not finite(y) or not finite(z) or not finite(nx) or not finite(ny) or not finite(nz) then return end
    local length = math.sqrt(nx * nx + ny * ny + nz * nz)
    if length < 0.5 or length > 1.5 then return end
    local vx, vy, vz = getElementPosition(vehicle)
    if getDistanceBetweenPoints3D(vx, vy, vz, x, y, z) > 8 then return end
    nx, ny, nz = nx / length, ny / length, nz / length
    if otherVehicle then
        if getElementDimension(other) ~= state.dimension or getElementInterior(other) ~= 0 then return end
        local ox, oy, oz = getElementPosition(other)
        if getDistanceBetweenPoints3D(ox, oy, oz, x, y, z) > 8 then return end
        local agreement = nx * (vx - ox) + ny * (vy - oy) + nz * (vz - oz)
        if agreement < 0 then nx, ny, nz = -nx, -ny, -nz end
    end
    local contact = {x, y, z, nx, ny, nz}
    if state.rail then
        switchToPhysics(state, otherVehicle and other or nil, contact)
    else
        state.awaitingImpactAt = nil
        applyImpactMotion(state, otherVehicle and other or nil, contact)
    end
end, false)

addEventHandler("onVehicleDamage", root, function(loss)
    local vehicle = source
    local state = vehicles[vehicle]
    if not state or not state.rail or state.damagePending or loss <= 0 then return end
    -- Damage and the contact report may arrive in either order.
    state.damagePending = true
    setTimer(function()
        if vehicles[vehicle] == state and state.rail then switchToPhysics(state) end
    end, 150, 1)
end)

addEventHandler("onVehicleEnter", root, function(driver, seat)
    local state = vehicles[source]
    if state and seat == 0 and getElementType(driver) == "player" then release(state) end
end)

local function vehicleClassSpeed(class, roll, length)
    -- Ordinary cruise speed variants in 0x00430290, in world units per second.
    local minimum, spread = 9, 5
    if class == 3 then minimum, spread = 12, 6 end
    if class == 1 then minimum, spread = 7, 3 end
    local speed = math.floor(minimum + roll * spread)
    if class == 5 or length > 10 then speed = math.floor(speed * 0.75) end
    return speed
end

local function localVehicleCount(x, y, z, dimension)
    local nearby = getElementsWithinRange(x, y, z, TRAFFIC_AREA_RADIUS, "vehicle", 0, dimension)
    if not nearby then return MAX_PER_TRAFFIC_AREA end
    local count = 0
    for _, vehicle in ipairs(nearby) do
        if vehicles[vehicle] then
            local vx, vy = getElementPosition(vehicle)
            local dx, dy = vx - x, vy - y
            if dx * dx + dy * dy <= TRAFFIC_AREA_RADIUS * TRAFFIC_AREA_RADIUS then
                count = count + 1
            end
        end
    end
    return count
end

local function syncerDistanceSquared(player, x, y, z, dimension)
    if not isElement(player) or getElementDimension(player) ~= dimension or getElementInterior(player) ~= 0 then
        return math.huge
    end
    local px, py, pz = TrafficWorld.roadObserverPosition(player)
    return (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2
end

local function replaceDistantSyncer(state, oldOwner, x, y, z)
    local range = syncRadius - EDGE_WIDTH
    local nearest, distance = nil, range ^ 2
    for _, player in ipairs(getElementsWithinRange(x, y, z, range, "player", 0, state.dimension) or {}) do
        if player ~= oldOwner then
            local squared = syncerDistanceSquared(player, x, y, z, state.dimension)
            if squared < distance then nearest, distance = player, squared end
        end
    end
    if nearest and setElementSyncer(state.vehicle, nearest, false) and getElementSyncer(state.vehicle) == nearest then
        state.railStall = nil
        state.lastProgress = getTickCount()
        record("edgeSyncerHandoffs")
        return true
    end
    return false
end

local function isWaitingInTraffic(state, x, y, z)
    local matrix = getElementMatrix(state.vehicle)
    if not matrix then return false end
    local fx, fy = matrix[2][1], matrix[2][2]
    if HLC:isNPCTrafficRailWaitingForSignal(state.railTask, x, y, z, fx, fy) then return true end
    for _, vehicle in ipairs(getElementsWithinRange(x, y, z, 12, "vehicle", 0, state.dimension) or {}) do
        if vehicle ~= state.vehicle then
            local bx, by, bz = getElementPosition(vehicle)
            local dx, dy = bx - x, by - y
            if dx * fx + dy * fy > 0 and math.abs(dx * fy - dy * fx) < 2.2 and math.abs(bz - z) < 2.5 then
                return true
            end
        end
    end
    return false
end

local function stalledOnRail(state, owner, distance, x, y, z, now)
    if not state.railTask then
        state.railStall = nil
        return false
    end
    local sample = state.railStall
    local atEdge = distance >= (syncRadius - EDGE_WIDTH) ^ 2
    if not sample or sample.owner ~= owner or sample.atEdge ~= atEdge or (x - sample.x) ^ 2 + (y - sample.y) ^ 2 >= 0.5 ^ 2 then
        state.railStall = {owner = owner, x = x, y = y, tick = now, atEdge = atEdge}
        return false
    end
    local timeout = atEdge and EDGE_STALL_MS or 6000
    if (now - sample.tick) % 4294967296 < timeout then return false end
    sample.tick = now
    if isWaitingInTraffic(state, x, y, z) then
        state.lastProgress = now
        return false
    end
    return true
end

local function spawn(candidate, ground, player)
    local x, y, dimension = candidate.x, candidate.y, candidate.dimension
    for _, kind in ipairs({"vehicle", "ped", "player"}) do
        local nearby = getElementsWithinRange(x, y, ground, 10, kind, 0, dimension)
        if not nearby or #nearby > 0 then record("occupied") return end
    end
    local model, original, class = chooseTrafficCivilianVehicle(x, y, ground, false)
    if not model then record("modelUnavailable") return end
    local kind = getVehicleType(model)
    -- 0x00430290 has a separate construction branch for VCS model type 6.
    -- MTA's native bike uses the same throttle, brake and steering inputs.
    if kind ~= "Automobile" and kind ~= "Bike" then record("modelUnavailable") return end

    local profile = TrafficPopulation.sample(graph.population,
        candidate.playerX, candidate.playerY, candidate.playerZ, (getTime()))
    local group = profile and graph.population.pedGroups[profile.pedestrianGroupId + 1]
    local originalDriver = TrafficRoad.chooseDriver(group, graph.pedestrianDriverMasks, class,
        math.random(0, 15), TrafficAmbient.getPedestrianModel, graph.fallbackDriverModelId)
    if not originalDriver then record("modelUnavailable") return end
    local driverModel = TrafficAmbient.getPedestrianModel(originalDriver)
    -- The server uses the collision box of the MTA base model. Client-only
    -- model replacement is applied separately by the VCS model catalog.
    local _, minimumY, minimumZ, _, maximumY = models:getModelBoundingBox(model)
    if type(minimumY) ~= "number" or type(minimumZ) ~= "number" or type(maximumY) ~= "number" then
        record("modelUnavailable")
        return
    end
    local centreHeight = math.max(0, -minimumZ)
    local z = ground + centreHeight
    if syncerDistanceSquared(player, x, y, z, dimension) > syncRadius ^ 2 then record("noSyncer") return end
    local rotation = -math.deg(math.atan2(candidate.dx, candidate.dy))
    local vehicle = createVehicle(model, x, y, z, 0, 0, rotation)
    if not vehicle then record("creationFailed") return end
    local driver = createPed(driverModel, x, y, z)
    if not driver then destroyElement(vehicle) record("creationFailed") return end
    setElementDimension(vehicle, dimension)
    setElementDimension(driver, dimension)
    if not setElementSyncer(vehicle, player, false) or getElementSyncer(vehicle) ~= player then
        destroyElement(driver)
        destroyElement(vehicle)
        record("noSyncer")
        return
    end
    TrafficModelBindings.tag(vehicle, original)
    TrafficModelBindings.tag(driver, originalDriver)
    if not warpPedIntoVehicle(driver, vehicle, 0) or not HLC:enableHLCForNPC(driver) then
        destroyElement(driver)
        destroyElement(vehicle)
        record("creationFailed")
        return
    end
    setVehicleEngineState(vehicle, true)
    local cruiseSpeed = vehicleClassSpeed(class, math.random(), maximumY - minimumY)
    HLC:setNPCDriveSpeed(driver, cruiseSpeed / 50)
    local state = candidate.rail
    state.vehicle, state.driver, state.dimension = vehicle, driver, dimension
    -- The spawn ground belongs to this XY only. Subsequent rail samples
    -- carry the packed path height plus chassis clearance.
    state.heightOffset, state.centreHeight = centreHeight, centreHeight
    state.cruiseSpeed, state.rail = cruiseSpeed, true
    sampleRailVelocity(state, x, y, z, getTickCount())
    vehicles[vehicle], drivers[driver] = state, state
    state.before = vehicleTail
    if vehicleTail then vehicleTail.after = state else vehicleHead = state end
    vehicleTail = state
    activeCount = activeCount + 1
    setElementFrozen(vehicle, false)
    setElementData(vehicle, railTag, true, "broadcast", "deny")
    followRail(state)
    if not vehicles[vehicle] then record("creationFailed") return false end
    TrafficVisibility.track(vehicle, "road")
    TrafficVisibility.track(driver, "road")
    record("spawned")
    return true
end

local function spawnArc(dx, dy, range, viewX, viewY)
    if not viewX then return true end
    local distance = length2D(dx, dy)
    if distance == 0 then return false end
    local dot = (dx * viewX + dy * viewY) / distance
    if range.front then return dot > range.dot end
    return dot <= range.dot
end

local function spawnRange(player, phase)
    -- 0x00430290 chooses the spawn circle from the current camera heading
    -- when stationary and from the player's vehicle velocity when moving.
    local vehicle = getPedOccupiedVehicle(player)
    if isElement(vehicle) then
        local vx, vy = getElementVelocity(vehicle)
        local speed = length2D(vx, vy)
        if speed > 0.1 then
            local step = phase % 4
            local fast = speed > 0.4
            local front = step < 2 or fast and step == 2
            return {radius = front and 110 or 40, front = front,
                dot = fast and step < 2 and 0.85 or 0.707,
                x = vx / speed, y = vy / speed, vehicle = vehicle, speed = speed * 50}
        end
    end
    local front = phase % 2 == 0
    return {radius = front and 110 or 40, front = front, dot = 0.707}
end

local function scanSpawnPhase(player, x, y, z, searchStarted, attempts)
    local phase = (cursorByPlayer[player] or 0) + 1
    cursorByPlayer[player] = phase
    local range = spawnRange(player, phase)
    local radius = range.radius
    local fastFront = range.front and range.speed and range.speed > FAST_SPEED
    local rolls = attempts
    if fastFront then
        -- Keep the PS2 ring radius; predict the observer separately for RPC latency.
        rolls = attempts * 3
    end
    local originX, originY = x, y
    if range.vehicle then
        -- Account for the MTA probe round trip and the next admission tick.
        -- Leave room for the original front and rear admission distances.
        local wait = math.max(getPlayerPing(player), observers[player].probeDelay or 0) + UPDATE_MS
        local lead = math.min(range.front and 50 or 20, range.speed * wait * 0.001)
        originX, originY = x + range.x * lead, y + range.y * lead
    end
    local viewX, viewY = range.x, range.y
    if not viewX then viewX, viewY = TrafficWorld.getRoadView(player) end
    local dimension = getElementDimension(player)
    local choices, num = {}, 0
    local now = getTickCount()
    local startX, startY = math.floor((originX - radius) / CELL_SIZE), math.floor((originY - radius) / CELL_SIZE)
    local sizeX = math.floor((originX + radius) / CELL_SIZE) - startX + 1
    local sizeY = math.floor((originY + radius) / CELL_SIZE) - startY + 1
    local visited = {}
    local function consider(edge)
        if edge.lanes == 0 or visited[edge] then return end
        visited[edge] = true
        local from, to = graph.nodes[edge.from + 1], graph.nodes[edge.to + 1]
        if to.scene ~= "outdoor" or hasFlag(to, 0x20) then return end
        local t = TrafficRoad.crossing(from, to, originX, originY, radius)
        if not t then return end
        local lane = math.random(0, edge.lanes - 1)
        local mx, my = TrafficGraph.lanePoint(graph, edge, lane)
        if not mx then return end
        local dx, dy = to.x - from.x, to.y - from.y
        local px, py = mx + (t - 0.5) * dx, my + (t - 0.5) * dy
        local pz = from.z + t * (to.z - from.z)
        if math.abs(pz - z) >= 20 or not spawnArc(px - originX, py - originY, range, viewX, viewY) then return end
        num = num + 1
        local slot = num <= rolls and num or math.random(num)
        if slot <= rolls then
            choices[slot] = {x = px, y = py, z = pz, dx = dx, dy = dy, edge = edge, lane = lane,
                -- 0x00430290 takes the lower of the two endpoint thresholds.
                dimension = dimension, threshold = math.min(from.spawnThreshold, to.spawnThreshold),
                playerX = x, playerY = y, playerZ = z, range = range}
        end
    end
    local cellCount = sizeX * sizeY
    for cursor = 0, cellCount - 1 do
        if (getTickCount() - searchStarted) % 4294967296 >= SEARCH_BUDGET_MS then break end
        local index = (phase + cursor) % cellCount
        local column = cells[startX + index % sizeX]
        local bucket = column and column[startY + math.floor(index / sizeX)]
        if bucket then
            for i = 0, math.min(#bucket, MAX_NODES_PER_LOCAL_CELL) - 1 do
                if i % 16 == 0 and (getTickCount() - searchStarted) % 4294967296 >= SEARCH_BUDGET_MS then break end
                local node = bucket[(i + phase) % #bucket + 1]
                for offset = 1, node.linkCount do consider(graph.links[node.firstLink + offset]) end
                for _, edge in ipairs(incoming[node.id] or {}) do consider(edge) end
            end
        end
    end
    if #choices == 0 then record("noRingEdges") return end
    local points = {}
    local attempted = {}
    for attempt = 1, rolls do
        if #points >= attempts then break end
        local candidate = choices[attempt] or choices[math.random(#choices)]
        if math.random(0, 15) <= candidate.threshold and not attempted[candidate] then
            attempted[candidate] = true
            record("spawnRollPassed")
            if prepareSpawnRail(candidate)
                and spawnArc(candidate.x - originX, candidate.y - originY, range, viewX, viewY) then
                points[#points + 1] = candidate
            else
                record("routeRejected")
            end
        end
    end
    if #points == 0 then record("noPassingCandidates") end
    if #points > 0 then return {points = points, started = now, range = range, dimension = dimension,
        playerX = x, playerY = y, playerZ = z, nextProbe = 1} end
end

local function makeCandidate(proposal, searchStarted)
    local player, x, y, z = proposal.player, proposal.playerX, proposal.playerY, proposal.playerZ
    local cold = proposal.count == 0
    if not graph.roadPopulation and (not cold or proposal.vx) then
        return scanSpawnPhase(player, x, y, z, searchStarted, SPAWN_ATTEMPTS)
    end

    local observer = observers[player]
    -- VCSPC defaults to 30 FPS. The executable makes two attempts per
    -- normal frame. Bound the cold-area refill to the same RPC capacity.
    local elapsed = observer.lastFrameAt and (searchStarted - observer.lastFrameAt) % 4294967296 or UPDATE_MS
    local credit = (observer.frameRemainder or 0) + elapsed * 0.03
    local frames = math.min(2, math.floor(credit))
    observer.lastFrameAt, observer.frameRemainder = searchStarted, credit % 1
    if cold then frames = 2 end
    local batch
    for frame = 1, frames do
        if (getTickCount() - searchStarted) % 4294967296 >= SEARCH_BUDGET_MS then break end
        local phase = scanSpawnPhase(player, x, y, z, searchStarted, cold and frame == 1 and 3 or 2)
        if not batch then batch = phase
        elseif phase then
            for _, point in ipairs(phase.points) do batch.points[#batch.points + 1] = point end
        end
    end
    return batch
end

local function enqueueReady(batch)
    readyTail = readyTail + 1
    readyBatches[readyTail] = batch
end

local function finishBatch(player, batch)
    if pending[player] == batch then pending[player] = nil end
    TrafficWorld.cancelRoad(player, batch)
end

local function roadProbeResult(player, batch, result)
    if pending[player] ~= batch then return end
    if not result then
        record("probeRejected")
        finishBatch(player, batch)
        return
    end
    local observer = observers[player]
    if observer then
        local delay = (getTickCount() - batch.started) % 4294967296
        observer.probeDelay = math.max(delay, (observer.probeDelay or 0) * 0.75)
    end
    batch.result = result
    enqueueReady(batch)
end

local function batchPosition(player, batch)
    if not isElement(player) or isPedDead(player) or getElementInterior(player) ~= 0
        or getElementDimension(player) ~= batch.dimension then return end
    local x, y, z = TrafficWorld.roadObserverPosition(player)
    local range = batch.range
    if not range.vehicle then
        if not observers[player].relocated then return x, y, z end
        return
    end
    if getPedOccupiedVehicle(player) ~= range.vehicle then return end
    local vx, vy = getElementVelocity(range.vehicle)
    local speed = length2D(vx, vy)
    -- Each candidate is checked against the current direction and distance
    -- at admission. Normal turns and discrete vehicle sync updates are valid.
    if speed > 0.1 then return x, y, z, vx / speed, vy / speed end
    return x, y, z, range.x, range.y
end

local function candidateInRange(candidate, x, y, vx, vy, visible)
    local dx, dy = candidate.x - x, candidate.y - y
    if not spawnArc(dx, dy, candidate.range, vx, vy) then return false end
    local squared = dx * dx + dy * dy
    local fastFront = candidate.range.front and candidate.range.speed and candidate.range.speed > FAST_SPEED
    return (visible ~= false or fastFront) and squared >= 100 ^ 2 and squared <= syncRadius ^ 2
        or visible ~= true and squared <= 60 ^ 2
end

local function updateObservers()
    observerList = getElementsByType("player")
    local now = getTickCount()
    for _, player in ipairs(observerList) do
        local x, y, z = TrafficWorld.roadObserverPosition(player)
        local dimension, interior = getElementDimension(player), getElementInterior(player)
        local occupant = getPedOccupiedVehicle(player)
        local vx, vy, vz, speed
        if isElement(occupant) then
            vx, vy, vz = getElementVelocity(occupant)
            speed = length2D(vx, vy)
            if speed > 0.1 then vx, vy, speed = vx / speed, vy / speed, speed * 50
            else vx, vy, speed = nil, nil, nil end
        end
        local observer = observers[player] or {revision = 0}
        if speed and getVehicleOccupant(occupant, 0) == player then
            if observer.impactVehicle ~= occupant then
                observer.impactVehicle, observer.impactSamples, observer.impactIndex = occupant, {}, 0
            end
            observer.impactIndex = observer.impactIndex % 4 + 1
            local sample = observer.impactSamples[observer.impactIndex] or {}
            sample.x, sample.y, sample.z, sample.tick = vx * speed / 50, vy * speed / 50, vz or 0, now
            observer.impactSamples[observer.impactIndex] = sample
        elseif occupant ~= observer.impactVehicle then
            observer.impactVehicle = nil
        end
        local sx, sy = math.floor(x / OBSERVER_SQUARE_SIZE), math.floor(y / OBSERVER_SQUARE_SIZE)
        local relocated = false
        if observer.positionAt then
            local elapsed = math.min(1, (now - observer.positionAt) % 4294967296 * 0.001)
            local allowance = SPAWN_POSITION_TOLERANCE + math.max(speed or 0, observer.speed or 0) * elapsed
            relocated = dimension ~= observer.dimension or interior ~= observer.interior
                or (x - observer.x) ^ 2 + (y - observer.y) ^ 2 + (z - observer.z) ^ 2 > allowance ^ 2
        end
        if relocated then
            local batch = pending[player]
            if batch then finishBatch(player, batch) end
            TrafficWorld.resetRoadView(player)
            cursorByPlayer[player], lastRoadAttempt[player] = nil, nil
            observer.lastFrameAt, observer.frameRemainder, observer.refillSince = nil, nil, nil
            record("observerRelocations")
        end
        local changed = sx ~= observer.sx or sy ~= observer.sy or dimension ~= observer.dimension
            or interior ~= observer.interior or occupant ~= observer.occupant or (vx ~= nil) ~= (observer.vx ~= nil)
            or vx and observer.vx and vx * observer.vx + vy * observer.vy < 0.707
        if changed or relocated then
            observer.revision = observer.revision + 1
            observer.urgent = true
            record("observerSquareUpdates")
        end
        if x ~= observer.x or y ~= observer.y or z ~= observer.z or relocated then observer.positionAt = now end
        observer.x, observer.y, observer.z, observer.sx, observer.sy = x, y, z, sx, sy
        observer.relocated = relocated
        observer.dimension, observer.interior, observer.occupant = dimension, interior, occupant
        observer.vx, observer.vy, observer.speed = vx, vy, speed
        observers[player] = observer
    end
end

local function densityCentre(player, x, y)
    local observer = observers[player]
    if not observer.speed or observer.speed <= FAST_SPEED then return x, y end
    local lead = math.min(syncRadius * 0.5, observer.speed * (1 + math.max(0, getPlayerPing(player)) * 0.001))
    return x + observer.vx * lead, y + observer.vy * lead
end

local function areaCap(x, y, z, densityFactor)
    if densityMode == "scheduled" then
        return math.min(MAX_PER_TRAFFIC_AREA,
            TrafficRoadPopulation.cap(graph.roadPopulation, x, y, z, getTime(), gameDay, densityFactor))
    end
    local profile = TrafficPopulation.sample(graph.population, x, y, z, (getTime()))
    if not profile then return 0 end
    return math.min(MAX_PER_TRAFFIC_AREA, TrafficRoadPopulation.zoneTarget(profile, densityFactor))
end

local function consumeReady(densityFactor)
    local created = 0
    local admissions = {}
    for _ = 1, MAX_ADMISSIONS_PER_TICK do
        if readyHead > readyTail or created >= MAX_CREATES_PER_TICK then break end
        local batch = readyBatches[readyHead]
        readyBatches[readyHead], readyHead = nil, readyHead + 1
        local player = batch.player
        if pending[player] == batch then
            local admission = admissions[batch]
            if not admission then
                local x, y, z, vx, vy = batchPosition(player, batch)
                admission = {x = x, y = y, z = z, vx = vx, vy = vy, cap = x and areaCap(x, y, z, densityFactor)}
                admissions[batch] = admission
            end
            local x, y, z = admission.x, admission.y, admission.z
            if x and admission.at ~= created then
                local cx, cy = densityCentre(player, x, y)
                admission.count = localVehicleCount(cx, cy, z, batch.dimension)
                admission.at = created
            end
            if not x then
                record("staleProbe")
                finishBatch(player, batch)
            elseif activeCount >= MAX_SERVER_VEHICLES
                or admission.count >= admission.cap then
                record(activeCount >= MAX_SERVER_VEHICLES and "globalCapacity" or "capacity")
                finishBatch(player, batch)
            else
                local index, result = batch.nextProbe, batch.result
                local candidate, probe = batch.points[index], result.probes[index]
                if not probe then
                    record("groundRejected")
                elseif not candidateInRange(candidate, x, y, admission.vx or result.viewX,
                    admission.vy or result.viewY, probe.visible) then
                    record("visibilityRejected")
                elseif spawn(candidate, probe.groundZ, player) then
                    created = created + 1
                    local observer = observers[player]
                    if observer.refillSince then
                        local wait = (getTickCount() - observer.refillSince) % 4294967296
                        record("refills")
                        stats.refillTotalMs = (stats.refillTotalMs or 0) + wait
                        stats.refillMaxMs = math.max(stats.refillMaxMs or 0, wait)
                        observer.refillSince = nil
                    end
                end
                batch.nextProbe = index + 1
                if batch.nextProbe <= #batch.points then enqueueReady(batch)
                else finishBatch(player, batch) end
            end
        end
    end
    if readyHead > readyTail then readyBatches, readyHead, readyTail = {}, 1, 0 end
end

local function sharedArea(a, b)
    return a.dimension == b.dimension
        and (not a.vx or not b.vx or a.vx * b.vx + a.vy * b.vy >= 0)
        and (a.playerX - b.playerX) ^ 2 + (a.playerY - b.playerY) ^ 2 <= SHARED_SPAWN_RADIUS ^ 2
        and math.abs(a.playerZ - b.playerZ) <= 15
end

local function dispatchProbes(densityFactor, urgent)
    local players = observerList
    local started = getTickCount()
    local proposals, seen = {}, {}
    local inspected, priorityIndex = 0, 1
    local checked = {}
    for _ = 1, math.min(#players, MAX_OBSERVERS_PER_TICK) do
        local elapsed = (getTickCount() - started) % 4294967296
        if elapsed >= SEARCH_BUDGET_MS or #proposals > 0 and elapsed >= SEARCH_BUDGET_MS - 1 then break end
        local player = priorityIndex <= MAX_BATCHES_PER_TICK and urgent[priorityIndex]
        if player then
            priorityIndex = priorityIndex + 1
        else
            nextPlayer = nextPlayer % #players + 1
            player = players[nextPlayer]
        end
        inspected = inspected + 1
        if not checked[player] and not pending[player] and TrafficWorld.isReady(player)
            and getElementInterior(player) == 0 and not isPedDead(player) then
            local observer = observers[player]
            local x, y, z = observer.x, observer.y, observer.z
            local lastAttempt = lastRoadAttempt[player]
            local proposal = {player = player, playerX = x, playerY = y, playerZ = z,
                dimension = observer.dimension, order = inspected, urgent = observer.urgent,
                vx = observer.vx, vy = observer.vy,
                wait = lastAttempt and (started - lastAttempt) % 4294967296 or math.huge}
            local shared = false
            for _, other in pairs(pending) do
                if sharedArea(proposal, other) then shared = true break end
            end
            if not shared then
                for _, other in ipairs(seen) do
                    if sharedArea(proposal, other) then shared = true break end
                end
            end
            if not shared then
                seen[#seen + 1] = proposal
                local cap = areaCap(x, y, z, densityFactor)
                if cap > 0 then
                    local cx, cy = densityCentre(player, x, y)
                    local count = localVehicleCount(cx, cy, z, proposal.dimension)
                    if count < cap then
                        observer.refillSince = observer.refillSince or started
                        proposal.cap, proposal.count = cap, count
                        proposals[#proposals + 1] = proposal
                    else
                        observer.refillSince, observer.urgent = nil, nil
                        record("capacity")
                    end
                end
            end
        end
        checked[player] = true
    end
    if inspected == #players and #players > 0 then nextPlayer = nextPlayer % #players + 1 end
    table.sort(proposals, function(a, b)
        if (a.count == 0) ~= (b.count == 0) then return a.count == 0 end
        local waitA, waitB = a.wait + (a.urgent and 100 or 0), b.wait + (b.urgent and 100 or 0)
        if waitA ~= waitB then return waitA > waitB end
        local ratioA, ratioB = a.count * b.cap, b.count * a.cap
        if ratioA == ratioB then return a.order < b.order end
        return ratioA < ratioB
    end)
    local dispatched = 0
    for _, proposal in ipairs(proposals) do
        if dispatched >= MAX_BATCHES_PER_TICK or (getTickCount() - started) % 4294967296 >= SEARCH_BUDGET_MS then break end
        local player = proposal.player
        lastRoadAttempt[player] = started
        local observer = observers[player]
        observer.urgent = nil
        local batch = makeCandidate(proposal, started)
        if batch then
            batch.player = player
            batch.revision, batch.vx, batch.vy = observer.revision, observer.vx, observer.vy
            pending[player] = batch
            if TrafficWorld.probeRoad(player, batch, roadProbeResult) then
                dispatched = dispatched + 1
                record("probeBatches")
            else
                record("probeRejected")
                finishBatch(player, batch)
            end
        else record("noCandidate") end
    end
end

local function disconnected()
    local batch = pending[source]
    if batch then finishBatch(source, batch) end
    cursorByPlayer[source] = nil
    lastRoadAttempt[source] = nil
    observers[source] = nil
end

local function refreshPending(now, densityFactor)
    local urgent = {}
    for _, player in ipairs(observerList) do
        if #urgent >= MAX_BATCHES_PER_TICK then break end
        if observers[player].relocated and TrafficWorld.isReady(player) and observers[player].interior == 0 then
            urgent[#urgent + 1] = player
        end
    end
    for player, batch in pairs(pending) do
        if not densityFactor or densityFactor <= 0 then
            finishBatch(player, batch)
        elseif (now - batch.started) % 4294967296 >= PROBE_TIMEOUT_MS then
            record(batch.result and "staleProbe" or "probeTimeout")
            finishBatch(player, batch)
        elseif not observers[player] or observers[player].revision ~= batch.revision then
            local x, y, _, vx, vy = batchPosition(player, batch)
            local usable
            if x then
                if not vx and batch.result then vx, vy = batch.result.viewX, batch.result.viewY end
                for i = batch.nextProbe, #batch.points do
                    local probe = batch.result and batch.result.probes[i]
                    if (not batch.result or probe)
                        and candidateInRange(batch.points[i], x, y, vx, vy, probe and probe.visible) then
                        usable = true
                        break
                    end
                end
            end
            if usable then
                batch.revision = observers[player].revision
            else
                record("squareProbeCancelled")
                finishBatch(player, batch)
                if observers[player] then urgent[#urgent + 1] = player end
            end
        end
    end
    return urgent
end

local function tick()
    updateObservers()
    local hour = getTime()
    if previousHour == 23 and hour == 0 then gameDay = gameDay % 7 + 1 end
    previousHour = hour
    local now = getTickCount()
    for _ = 1, math.min(MAX_CLEANUP_PER_TICK, activeCount) do
        local state = vehicleCursor or vehicleHead
        if not state or state.checkedAt == now then break end
        state.checkedAt = now
        vehicleCursor = state.after or vehicleHead
        local vehicle = state.vehicle
        if not isElement(vehicle) or not isElement(state.driver) or isPedDead(state.driver) or isVehicleBlown(vehicle)
            or isElementInWater(vehicle) or getVehicleOccupant(vehicle, 0) ~= state.driver then
            release(state)
        else
            local x, y, z = getElementPosition(vehicle)
            local syncer = getElementSyncer(vehicle)
            local distance = syncerDistanceSquared(syncer, x, y, z, state.dimension)
            if not syncer then
                record("despawnNoSyncer")
                release(state)
            elseif distance > syncRadius ^ 2 then
                if not replaceDistantSyncer(state, syncer, x, y, z) then
                    record("despawnOutOfRange")
                    release(state)
                end
            elseif stalledOnRail(state, syncer, distance, x, y, z, now) then
                local atEdge = distance >= (syncRadius - EDGE_WIDTH) ^ 2
                if not atEdge or not replaceDistantSyncer(state, syncer, x, y, z) then
                    record(atEdge and "despawnEdgeStalled" or "despawnRailStalled")
                    release(state, true)
                end
            elseif (now - state.lastProgress) % 4294967296 > MAX_LIFETIME_WITHOUT_PROGRESS then
                record("despawnStalled")
                release(state, true)
            elseif state.rail then
                sampleRailVelocity(state, x, y, z, now)
            elseif state.physicsTask then
                local rejoin = HLC:getNPCTrafficPhysicsRejoin(state.physicsTask, vehicle)
                if rejoin then
                    record("physicsRejoins")
                    advancePhysics(state, rejoin - 1)
                end
            end
        end
    end
    local densityFactor = density("cars")
    local urgent = refreshPending(now, densityFactor)
    if not densityFactor or densityFactor <= 0 then
        readyBatches, readyHead, readyTail = {}, 1, 0
        return
    end
    consumeReady(densityFactor)
    if activeCount < MAX_SERVER_VEHICLES then dispatchProbes(densityFactor, urgent)
    else record("globalCapacity") end
end

function getTrafficRoadStatus()
    local status = {vehicles = activeCount, densityProfile = densityMode or "zone", range = syncRadius}
    status.observers, status.readyObservers, status.pendingObservers = #observerList, 0, 0
    for _, player in ipairs(observerList) do
        if TrafficWorld.isReady(player) then status.readyObservers = status.readyObservers + 1 end
        if pending[player] then status.pendingObservers = status.pendingObservers + 1 end
        local observer = observers[player]
        if observer and #observerList == 1 then
            status.observerInterior = observer.interior
            status.observerDead = isPedDead(player)
            status.observerZ = observer.z
            status.observerSpeed = observer.speed or 0
            status.observerCap = density and areaCap(observer.x, observer.y, observer.z, density("cars")) or 0
        end
    end
    for reason, count in pairs(stats) do status[reason] = count end
    return status
end

function TrafficRoad.isManagedPed(ped)
    return drivers[ped] ~= nil
end

function TrafficRoad.appendDebugRails(player, links, radius)
    local px, py, pz = getElementPosition(player)
    local dimension = getElementDimension(player)
    local nearby = {}
    for vehicle, state in pairs(vehicles) do
        if state.railTask and state.dimension == dimension and isElement(vehicle) then
            local x, y, z = getElementPosition(vehicle)
            local distance = (x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2
            if distance < radius ^ 2 then nearby[#nearby + 1] = {state.railTask, distance} end
        end
    end
    table.sort(nearby, function(a, b) return a[2] < b[2] end)
    for index = 1, math.min(6, #nearby) do
        local points = HLC:getNPCTrafficRailDebugPoints(nearby[index][1])
        for step = 2, #points do
            local a, b = points[step - 1], points[step]
            links[#links + 1] = {a[1], a[2], a[3], b[1], b[2], b[3], "rail", false, 0}
        end
    end
end

function TrafficRoad.start(loadedGraph, getDensity, requestedMode)
    graph, density = loadedGraph, getDensity
    local warning
    densityMode, warning = TrafficRoadPopulation.resolveMode(graph, requestedMode)
    if warning then outputDebugString("[npchlc_traffic] " .. warning, 2) end
    if not graph.population then return end
    local configuredRange = tonumber(getServerConfigSetting("unoccupied_vehicle_syncer_distance"))
    syncRadius = math.min(TrafficVisibility.roadRange, configuredRange or DEFAULT_MTA_SYNC_RADIUS)
    setElementData(resourceRoot, TrafficVisibility.roadRangeKey, syncRadius, "broadcast", "deny")
    indexRoads()
    addEventHandler("npc_hlc:onNPCTaskDone", root, taskDone)
    addEventHandler("onPlayerQuit", root, disconnected)
    timer = setTimer(tick, UPDATE_MS, 0)
end

function TrafficRoad.stop()
    if timer then
        killTimer(timer)
        removeEventHandler("npc_hlc:onNPCTaskDone", root, taskDone)
        removeEventHandler("onPlayerQuit", root, disconnected)
    end
    for _, state in pairs(vehicles) do release(state) end
    for player, batch in pairs(pending) do finishBatch(player, batch) end
    graph, density, timer, vehicleCursor, densityMode = nil, nil, nil, nil, nil
    cells, incoming, pending, cursorByPlayer, lastRoadAttempt = {}, {}, {}, {}, {}
    activeCount, nextPlayer = 0, 0
    vehicleHead, vehicleTail = nil, nil
    gameDay, previousHour = 4, nil
    observers, observerList = {}, {}
    readyBatches, readyHead, readyTail, stats = {}, 1, 0, {}
end
