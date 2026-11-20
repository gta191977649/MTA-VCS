TrafficRoad = {}

local HLC = exports.npc_hlc
local models = exports.server_coldata
local cells, vehicles, drivers, pending, cursorByPlayer = {}, {}, {}, {}, {}
local retiring, unclaimed = {}, {}
local ownedVehicles = {}
local waterSeatTransfers = {}
local PLAYER_PARKING_GRACE_MS = 30000
local detachedBikes = {}
local recentShots = setmetatable({}, {__mode = "k"})
local incoming = {}
local waterCells = {}
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
    if from.kind == "boat" then
        -- 00267928 uses different radii for the crossing test and interpolation.
        local squared = radius * radius * 1.5
        if (distanceFrom ^ 2 - squared) * (distanceTo ^ 2 - squared) >= 0 then return false end
        radius = radius * 1.5
    elseif (distanceFrom > radius) == (distanceTo > radius) then return false end
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
        if (node.kind == "vehicle" or node.kind == "boat") and node.scene == "outdoor" and not hasFlag(node, 0x20) then
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
                    if node.kind == "boat" then
                        -- Offshore links can cross the search area with both endpoints outside its cells.
                        local target = graph.nodes[edge.to + 1]
                        for cx = math.floor(math.min(node.x,target.x)/CELL_SIZE), math.floor(math.max(node.x,target.x)/CELL_SIZE) do
                            local column = waterCells[cx] or {}
                            waterCells[cx] = column
                            for cy = math.floor(math.min(node.y,target.y)/CELL_SIZE), math.floor(math.max(node.y,target.y)/CELL_SIZE) do
                                local bucket = column[cy] or {}
                                column[cy] = bucket
                                bucket[#bucket + 1] = edge
                            end
                        end
                    end
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

-- 004361A8: draw from all adjoining links before relaxing the turn rules.
local function chooseWaterLink(edge, lane, current)
    local previous = graph.nodes[edge.from + 1]
    local ix, iy = current.x - previous.x, current.y - previous.y
    local inLength = length2D(ix, iy)
    local twoWay = edge.leftLanes > 0 and edge.rightLanes > 0
    local function accepts(candidate, stage)
        local target = graph.nodes[candidate.to + 1]
        if not TrafficGraph.canDriveTransition(graph, edge, candidate)
            or target.scene ~= current.scene or (hasFlag(target, 0x20) and not hasFlag(previous, 0x20)) then return false end
        if stage == 3 then return true end
        if candidate.to == edge.from then return false end
        if stage == 2 then return true end
        if hasFlag(target, 0x10) and not hasFlag(previous, 0x10) then return false end
        if not twoWay and (candidate.leftLanes == 0 or candidate.rightLanes == 0) then return false end
        local ox, oy = target.x - current.x, target.y - current.y
        local length = inLength * length2D(ox, oy)
        if length == 0 then return false end
        local cross = (ix * oy - iy * ox) / length
        if cross > 0.77 then return lane == 0 end
        if cross < -0.77 then return lane == edge.lanes - 1 end
        return edge.lanes < 3 or (lane > 0 and lane < edge.lanes - 1)
    end
    if current.linkCount == 0 then return end
    for stage = 1, 2 do
        for attempt = 1, 14 do
            local candidate = graph.links[current.firstLink + math.random(current.linkCount)]
            if accepts(candidate, stage) then return candidate end
        end
    end
    for offset = 1, current.linkCount do
        local candidate = graph.links[current.firstLink + offset]
        if accepts(candidate, 3) then return candidate end
    end
end

local function chooseOutgoing(edge, lane, context)
    local junction = graph.nodes[edge.to + 1]
    if junction.kind == "boat" then
        local nextEdge = chooseWaterLink(edge, lane, junction)
        if not nextEdge then return false end
        local target = graph.nodes[nextEdge.to + 1]
        local dx, dy = target.x - junction.x, target.y - junction.y
        if dx * dx + dy * dy >= 196 and math.random(0, 3) == 0 then
            lane = lane + (math.random(0, 1) == 0 and -1 or 1)
        end
        return nextEdge, math.max(0, math.min(lane, nextEdge.lanes - 1))
    end
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

local function releaseRoadControl(state)
    local vehicle = state.vehicle
    if state.rail then
        setElementFrozen(vehicle, false)
        setElementData(vehicle, railTag, false, "broadcast", "deny")
    end
end

local function finishRelease(state)
    retiring[state.vehicle] = nil
    TrafficPassengers.release(state.vehicle)
    PedAI.detach(state.driver)
    TrafficVisibility.releasePed(state.driver)
    local vehicle = state.vehicle
    if not isElement(vehicle) then return end
    releaseRoadControl(state)
    if TrafficVisibility.isWreck(vehicle) then return end
    if state.borrowed or TrafficVisibility.hasPlayerOccupant(vehicle) then
        if not state.borrowed then
            state.lastPlayerUse = getTickCount()
            unclaimed[vehicle] = state.lastPlayerUse
        end
        TrafficVisibility.detach(vehicle)
    else
        destroyElement(vehicle)
    end
end

local function register(state)
    if not state.borrowed then
        ownedVehicles[state.vehicle] = state
        unclaimed[state.vehicle] = nil
    end
    detachedBikes[state.vehicle] = nil
    state.bikeFell=nil
    vehicles[state.vehicle], drivers[state.driver] = state, state
    state.before, state.after = vehicleTail, nil
    if vehicleTail then vehicleTail.after = state else vehicleHead = state end
    vehicleTail = state
    activeCount = activeCount + 1
end

local function unregister(state)
    if state.pursuit then TrafficWorld.cancelPursuit(state.vehicle) end
    vehicles[state.vehicle], drivers[state.driver] = nil, nil
    activeCount = activeCount - 1
    local before, after = state.before, state.after
    if before then before.after = after else vehicleHead = after end
    if after then after.before = before else vehicleTail = before end
    if vehicleCursor == state then vehicleCursor = after or vehicleHead end
    state.before, state.after = nil, nil
end

local function release(state, fade)
    if vehicles[state.vehicle] ~= state then return end
    unregister(state)
    local vehicle = state.vehicle
    if fade and isElement(vehicle) and getElementSyncer(vehicle) and not TrafficVisibility.hasPlayerOccupant(vehicle) then
        retiring[vehicle] = state
        TrafficPassengers.fading(vehicle, true)
        if isElement(state.driver) then HLC:clearNPCTasks(state.driver) end
        TrafficVisibility.retire(vehicle, state.driver, function() finishRelease(state) end, true)
    else
        finishRelease(state)
    end
end

local function roadInteraction(vehicle)
    local state = retiring[vehicle]
    if state and TrafficVisibility.cancelRetirement(vehicle) then
        retiring[vehicle] = nil
        TrafficPassengers.fading(vehicle, false)
        register(state)
        state.railStall = nil
        state.lastProgress = getTickCount()
        return state, true
    end
    return vehicles[vehicle], false
end

local function yieldDriver(state, player, claimed)
    if not player and state.pursuit and state.pursuit.phase == "exit" then
        state.evacuating = {retaliate=true, pursuitExit=true, attacker=state.pursuit.target}
    end
    unregister(state)
    local vehicle, ped = state.vehicle, state.driver
    releaseRoadControl(state)
    TrafficVisibility.detach(vehicle)
    if not state.evacuating or state.evacuating.roadRage or state.evacuating.pursuitExit then TrafficPassengers.driverGone(vehicle, player) end
    if not state.borrowed then
        unclaimed[vehicle] = getTickCount()
        if claimed then state.lastPlayerUse = getTickCount() end
    end
    if isElement(ped) and not isPedDead(ped) then
        HLC:clearNPCTasks(ped)
        TrafficAmbient.adoptDriver(ped, player, vehicle, state.originalDriver, player and state)
        if not player and not state.evacuating and getVehicleType(vehicle)=="Bike" then
            detachedBikes[vehicle]={road=state,at=getTickCount()}
        end
        if not player and state.evacuating and isElement(state.evacuating.attacker) then
            if state.evacuating.roadRage then
                PedAI.roadRage(ped, state.evacuating.attacker, state)
            elseif state.evacuating.retaliate then
                PedAI.vehicleThreat(ped, state.evacuating.attacker, state.evacuating.pursuitExit and state)
            else
                PedAI.passengerThreat(ped, state.evacuating.attacker)
            end
        end
    else
        TrafficVisibility.releasePed(ped)
        PedAI.detach(ped)
    end
end

local function assignTask(state, task)
    if state.scriptPaused then return end
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

local function resetPhysicsSequence(state)
    local previous=state.physicsTask
    state.physicsSequence=(state.physicsSequence or 0)+(previous and #previous[5] or 0)+1
end

local function followPhysics(state, extending)
    local route, start = state.railRoute, state.railStart
    fillRoute(state, 3)
    local vx,vy=getElementVelocity(state.vehicle)
    local horizon=2*math.max(state.cruiseSpeed,50*length2D(vx,vy))
    local px,py=getElementPosition(state.vehicle)
    local metres=0
    local segments = {}
    for index = 1, 8 do
        if index>3 and (metres>=horizon or state.pursuit) then break end
        if not route[index] and index>3 then fillRoute(state,index) end
        local item = route[index]
        if not item then break end
        local x, y, z = unpack(item.point)
        metres=metres+length2D(x-px,y-py)
        px,py=x,y
        local dx, dy = edgeDirection(item.edge)
        segments[index] = {item.edge.id, item.lane, x, y, z + state.heightOffset, dx, dy,
            item.speedClass or item.edge.speedClass, state.drivingStyle == 2 and 0 or signalGroup(item.edge)}
    end
    if extending and #segments<=#state.physicsTask[5] then return end
    local task = {"driveTrafficPhysics", state.physicsSequence, state.cruiseSpeed,
        {start[1], start[2], start[3] + state.heightOffset}, segments, state.drivingStyle}
    state.physicsTask = task
    return assignTask(state, task)
end

-- Rebuild only the route when an incident moved the vehicle to another street.
-- Walk legal directed lane connections and stop on the first reachable lane
-- within dismount range. Never use the body itself as a driving waypoint.
function TrafficRoad.serviceRoute(state,x,y,z)
    local first=state.railRoute and state.railRoute[1]
    if not first then return end
    local queue={{edge=first.edge,lane=first.lane}}
    local seen={[first.edge.id]=true}
    local index=1
    while index<=#queue and index<=512 do
        local item=queue[index]
        local ax,ay,az=TrafficGraph.lanePoint(graph,item.edge,item.lane)
        if ax then
            local a,b=graph.nodes[item.edge.from+1],graph.nodes[item.edge.to+1]
            local dx,dy=b.x-a.x,b.y-a.y
            local t=math.max(-0.5,math.min(0.5,((x-ax)*dx+(y-ay)*dy)/(dx*dx+dy*dy)))
            local tx,ty,tz=ax+t*dx,ay+t*dy,az+t*(b.z-a.z)
            if (tx-x)^2+(ty-y)^2<22^2 and math.abs(tz-z)<5 then
                local path={{tx,ty,tz+state.heightOffset}}
                local parent=item.parent
                while parent do
                    table.insert(path,1,parent.point)
                    parent=parent.parent
                end
                return path
            end
            item.point={ax,ay,az+state.heightOffset}
            for _,edge in ipairs(outgoingChoices(graph,item.edge,item.lane)) do
                if not seen[edge.id] then
                    seen[edge.id]=true
                    queue[#queue+1]={edge=edge,lane=math.min(item.lane,edge.lanes-1),parent=item}
                end
            end
        end
        index=index+1
    end
end

local function rejoinRoadAtVehicle(state, maxOffset)
    local matrix = getElementMatrix(state.vehicle)
    if not matrix then return end
    local x,y,z = unpack(matrix[4])
    local fx,fy = unpack(matrix[2])
    local best, score
    for i = math.floor((x-60)/CELL_SIZE), math.floor((x+60)/CELL_SIZE) do
        for j = math.floor((y-60)/CELL_SIZE), math.floor((y+60)/CELL_SIZE) do
            for _, node in ipairs(cells[i] and cells[i][j] or {}) do
                local count = node.kind == (state.boat and "boat" or "vehicle") and node.linkCount or 0
                for k = 1,count do
                    local edge = graph.links[node.firstLink+k]
                    for lane = 0,edge.lanes-1 do
                        local px,py,pz = TrafficGraph.lanePoint(graph,edge,lane)
                        if px and math.abs(z-pz) < 7 then
                            local dx,dy = edgeDirection(edge)
                            local along = (x-px)*dx + (y-py)*dy
                            local halfLength = length2D(px-node.x,py-node.y)
                            local beyond = math.max(0,math.abs(along)-halfLength)
                            local offset = ((x-px)*dy-(y-py)*dx)^2 + beyond^2 + (z-pz)^2
                            local cost = offset + 20*(1-fx*dx-fy*dy)
                            if (not maxOffset or offset <= maxOffset^2) and (not score or cost < score) then
                                best,score = {edge=edge,lane=lane,x=x,y=y,dx=dx,dy=dy},cost
                            end
                        end
                    end
                end
            end
        end
    end
    if best and prepareSpawnRail(best) then
        state.railPrevious, state.railStart, state.railRoute = best.rail.railPrevious, best.rail.railStart, best.rail.railRoute
        return true
    end
end

function TrafficRoad.isDriving(ped,car)
    local state=vehicles[car]
    return state and state.driver==ped and getVehicleOccupant(car,0)==ped or false
end

-- 0x001FF680 rejoins the road system after objective 0x12 completes.
function TrafficRoad.resumeDriver(state, stolen)
    local car, ped = state.vehicle, state.driver
    if not graph or vehicles[car] or not isElement(car) or getVehicleOccupant(car,0) ~= ped
        or not TrafficAmbient.releaseDriver(ped) then return false end
    if getVehicleType(car)=="Bike" then
        state.ride=(state.ride or 0)+1
        setElementData(car,"npchlc_traffic:ride",state.ride,"broadcast","deny")
    end
    local afterRage = stolen or state.evacuating and (state.evacuating.roadRage or state.evacuating.pursuitExit)
    state.jacker, state.jackStarted, state.evacuating = nil, nil, nil
    state.damagePending, state.awaitingImpactAt, state.gunHit, state.lossAt = nil, nil, nil, nil
    state.rail, state.railTask, state.railMotion, state.railStall = false, nil, nil, nil
    -- The two native enter-driver completions set different cruise speeds.
    state.physicsSequence, state.cruiseSpeed = 1, afterRage and 10 or 25
    state.drivingStyle = not afterRage and 2 or nil
    state.crashDecision, state.collisionLossAt, state.pursuit = nil, nil, nil
    state.panicDriving = nil
    rejoinRoadAtVehicle(state)
    register(state)
    HLC:clearNPCTasks(ped)
    local owner = getElementSyncer(ped)
    if not getElementSyncer(car) and isElement(owner) then setElementSyncer(car,owner,false) end
    HLC:setNPCDriveSpeed(ped, state.cruiseSpeed / 50)
    setVehicleEngineState(car,true)
    TrafficVisibility.track(car,"road")
    TrafficVisibility.track(ped,"road")
    if state.boat then
        state.rail = true
        setElementData(car, railTag, true, "broadcast", "deny")
        followRail(state)
        return vehicles[car] == state
    end
    return followPhysics(state)
end

-- 0x002D9860 finishes a successful civilian theft with mission 1, cruise 10.
function TrafficRoad.driveStolenCar(ped,car,originalDriver)
    if not graph or vehicles[car] or retiring[car] then return false end
    local _,_,minimumZ = models:getModelBoundingBox(getElementModel(car))
    local boat = getVehicleType(car) == "Boat"
    local height = boat and 0 or math.max(0,-(minimumZ or 0))
    local state = {vehicle=car,driver=ped,dimension=getElementDimension(car),
        originalDriver=originalDriver,originalVehicle=getElementData(car,"npchlc_traffic:originalModel",false),
        boat=boat,heightOffset=height,centreHeight=height,borrowed=getElementParent(car) ~= getResourceDynamicElementRoot(getThisResource())}
    if not rejoinRoadAtVehicle(state) then return false end
    return TrafficRoad.resumeDriver(state,true)
end

function TrafficRoad.driverScriptChanged(ped, controlled)
    local state = drivers[ped]
    if not state then return end
    if controlled and not state.scriptPaused then
        if PedServices then PedServices.relinquish(ped) end
        TrafficWorld.cancelPursuit(state.vehicle)
        releaseRoadControl(state)
        state.rail, state.railTask, state.railMotion = false, nil, nil
        state.scriptPaused, state.pursuit, state.evacuating = true, nil, nil
        state.crashDecision, state.gunHit, state.jacker, state.damagePending = nil, nil, nil, nil
    elseif not controlled and state.scriptPaused then
        state.scriptPaused = nil
        if not isElement(state.vehicle) then
            unregister(state)
            if isElement(ped) and not isPedDead(ped) then
                TrafficAmbient.adoptDriver(ped,nil,nil,state.originalDriver)
            end
        elseif getVehicleOccupant(state.vehicle, 0) == ped then
            rejoinRoadAtVehicle(state)
            if state.boat then
                state.rail = true
                setElementData(state.vehicle, railTag, true, "broadcast", "deny")
                followRail(state)
            else
                resetPhysicsSequence(state)
                followPhysics(state)
            end
        else
            local occupant = getVehicleOccupant(state.vehicle, 0)
            local taken = isElement(occupant) and getElementType(occupant) == "player"
            yieldDriver(state, taken and occupant or nil, taken)
        end
    end
end

local function advancePhysics(state, steps)
    for _ = 1, steps do
        state.railStart = table.remove(state.railRoute, 1).point
    end
    state.physicsSequence = state.physicsSequence + steps
    followPhysics(state)
end

addEvent("npchlc_traffic:routeLow",true)
addEventHandler("npchlc_traffic:routeLow",resourceRoot,function(vehicle,first,last)
    local state=vehicles[vehicle]
    if not state or not client or client~=getElementSyncer(vehicle) or state.rail or state.scriptPaused
        or state.jacker or state.pursuit or state.evacuating or getVehicleOccupant(vehicle,0)~=state.driver then return end
    local task=state.physicsTask
    if not task or task[2]~=first or first+#task[5]-1~=last or state.hintedTask==task then return end
    state.hintedTask=task
    local index=HLC:getNPCTrafficWindowProgress(task,vehicle)
    local steps=math.min(index-1,#state.railRoute-1)
    if steps>0 then advancePhysics(state,steps) else followPhysics(state,true) end
end,false)

addEvent("npchlc_traffic:cruiseStuck", true)
addEventHandler("npchlc_traffic:cruiseStuck", resourceRoot, function(vehicle)
    local state = vehicles[vehicle]
    if not state or state.scriptPaused or not client or client ~= getElementSyncer(vehicle) or state.rail or not state.canReverse
        or state.drivingStyle == 2 or state.jacker or state.pursuit or state.evacuating
        or not state.stoppedAt or (getTickCount() - state.stoppedAt) % 4294967296 < 29000 then return end
    state.drivingStyle = 2
    followPhysics(state)
end, false)

local function taskDone(task)
    local state = drivers[source]
    if not state or state.scriptPaused or state.jacker or state.evacuating then return end
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

function TrafficRoad.contactVelocity(car,now)
    local vx,vy,vz=getElementVelocity(car)
    local observer=observers[getVehicleOccupant(car,0)]
    if observer and observer.impactVehicle==car then
        for _,s in ipairs(observer.impactSamples) do
            if (now-s.tick)%4294967296<=180 and s.x*s.x+s.y*s.y+s.z*s.z>vx*vx+vy*vy+vz*vz then
                vx,vy,vz=s.x,s.y,s.z
            end
        end
    elseif vehicles[car] then
        local motion=vehicles[car].railMotion
        if motion and (now-motion.tick)%4294967296<=180 then return motion.vx,motion.vy,motion.vz end
    end
    return vx,vy,vz
end

-- Validate the reported contact against a recent observed vehicle segment.
function TrafficRoad.pedContactMotion(car,now,x,y,z)
    local cx,cy,cz=getElementPosition(car)
    local vx,vy,vz=TrafficRoad.contactVelocity(car,now)
    local matched=false
    local function onSegment(ax,ay,az,bx,by,bz)
        local dx,dy,dz=bx-ax,by-ay,bz-az
        local t=math.max(0,math.min(1,((x-ax)*dx+(y-ay)*dy+(z-az)*dz)/math.max(.001,dx*dx+dy*dy+dz*dz)))
        return (x-ax-t*dx)^2+(y-ay-t*dy)^2+(z-az-t*dz)^2<=8^2
    end
    local observer=observers[getVehicleOccupant(car,0)]
    if observer and observer.impactVehicle==car then
        for _,s in ipairs(observer.impactSamples) do
            local dt=(now-s.tick)%4294967296
            if s.px and dt<=400 and s.dimension==getElementDimension(car) and s.interior==getElementInterior(car)
                and (s.px-cx)^2+(s.py-cy)^2+(s.pz-cz)^2<=(8+dt*.05*math.sqrt(s.x*s.x+s.y*s.y+s.z*s.z))^2
                and onSegment(s.px,s.py,s.pz,cx,cy,cz) then
                if s.x*s.x+s.y*s.y+s.z*s.z>vx*vx+vy*vy+vz*vz then vx,vy,vz=s.x,s.y,s.z end
                matched=true
            end
        end
    end
    if matched then return vx,vy,vz end
    if onSegment(cx,cy,cz,cx-vx*12,cy-vy*12,cz-vz*12) then return vx,vy,vz end
    -- A driver's reliable contact event may arrive before their next position
    -- sync. Only project the current synchronized velocity, for at most 120 ms.
    local dx,dy,dz=getElementVelocity(car)
    if onSegment(cx,cy,cz,cx+dx*6,cy+dy*6,cz+dz*6) then return dx,dy,dz end
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
    if not state.rail or state.boat or state.jacker or state.evacuating then return end
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
addEventHandler("npchlc_traffic:railImpact", resourceRoot, function(vehicle, other, x, y, z, nx, ny, nz, impulse,ride)
    local detached = detachedBikes[vehicle]
    local state = vehicles[vehicle] or detached and detached.road
    if not client or not state or state.boat or state.scriptPaused or state.jacker or state.evacuating then return end
    local now = getTickCount()
    if detached and (now-detached.at)%4294967296>1200 then return end
    local bike=getVehicleType(vehicle)=="Bike"
    if bike and (ride or 0)~=(state.ride or 0) then return end
    local awaitingImpact = state.awaitingImpactAt and (now - state.awaitingImpactAt) % 4294967296 <= 600
    if not state.rail and not awaitingImpact and (not finite(impulse) or impulse <= 0 or not bike and impulse <= 25) then return end
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
    if otherVehicle and finite(impulse) and not detached then
        if TrafficVehicleCollision.driverReaction(state, other, impulse, now,
            observers[getVehicleOccupant(other, 0)], nx, ny, nz) then
            record("vehicleCrashReactions")
        end
    end
    local contact = {x, y, z, nx, ny, nz}
    local fall
    local driver=getVehicleOccupant(vehicle,0)
    if bike and finite(impulse) and impulse>0 and not state.bikeFell and (not driver or driver==state.driver) then
        local mass=graph.edition=="SLUS-21590 USA v1.00" and TrafficVehicleMass[state.originalVehicle] or getVehicleHandling(vehicle).mass
        local svx,svy,svz=TrafficRoad.contactVelocity(vehicle,now)
        local ox,oy,oz=0,0,0
        if otherVehicle then ox,oy,oz=TrafficRoad.contactVelocity(other,now) end
        local relative=math.sqrt((ox-svx)^2+(oy-svy)^2+(oz-svz)^2)
        impulse=math.min(impulse,2*mass*relative)
        local score=PedRoadInjury.bikeScore(state.originalVehicle,impulse,mass,getElementMatrix(vehicle),nx,ny,nz)
        if score>75 then
            local attacker=otherVehicle and getVehicleOccupant(other,0)
            if attacker and not TrafficVehicleCollision.struckByDriver(state,other,observers[attacker],now,nx,ny,nz) then attacker=nil end
            fall={score=score,impulse=impulse,mass=mass,nx=nx,ny=ny,vx=svx,vy=svy,vz=svz,attacker=attacker}
        end
    end
    if not detached and state.rail then
        switchToPhysics(state, otherVehicle and other or nil, contact)
    elseif not detached and awaitingImpact then
        state.awaitingImpactAt = nil
        applyImpactMotion(state, otherVehicle and other or nil, contact)
    end
    if fall and isElement(state.driver) and not isPedDead(state.driver) then
        local aboard=getPedOccupiedVehicle(state.driver)
        if aboard and aboard~=vehicle then return end
        state.bikeFell=true
        if aboard and not removePedFromVehicle(state.driver) then state.bikeFell=nil return end
        TrafficPassengers.bikeFall(vehicle,fall)
        if vehicles[vehicle]==state then yieldDriver(state,nil,false) end
        detachedBikes[vehicle]=nil
        TrafficAmbient.bikeFall(state.driver,fall,aboard==vehicle,state)
    end
end, false)

-- The server exposes loss, the client exposes the cause, and weapon fire
-- identifies the shooter. All three observations may arrive in different frames.
function TrafficRoad.noteGunfire(shooter, weapon, ex, ey, ez, sx, sy, sz)
    if not graph then return end
    if not sx then sx, sy, sz = getElementPosition(shooter) end
    local shots = recentShots[shooter] or {cursor=0}
    shots.cursor = shots.cursor % 8 + 1
    shots[shots.cursor] = {weapon=weapon, tick=getTickCount(), x=ex, y=ey, z=ez, sx=sx, sy=sy, sz=sz}
    recentShots[shooter] = shots
end

addEvent("npchlc_traffic:vehicleGunHit", true)
addEventHandler("npchlc_traffic:vehicleGunHit", resourceRoot, function(vehicle, attacker, weapon)
    local state = vehicles[vehicle]
    if not state or state.boat or state.scriptPaused or not client or state.evacuating or state.panicDriving or not isElement(attacker)
        or (getElementType(attacker) ~= "player" and getElementType(attacker) ~= "ped")
        or (client ~= attacker and client ~= getElementSyncer(vehicle))
        or not finite(weapon) or not PedAIRules.ranged(weapon)
        or getElementDimension(attacker) ~= state.dimension or getElementInterior(attacker) ~= 0 then return end
    local x, y, z = getElementPosition(vehicle)
    state.gunHit = {attacker=attacker, weapon=weapon, tick=getTickCount(), x=x, y=y, z=z}
end, false)

-- MTA can report the end of the weapon's reach beyond the struck vehicle.
local function shotCrossesVehicle(shot, x, y, z)
    local dx, dy, dz = shot.x-shot.sx, shot.y-shot.sy, shot.z-shot.sz
    local squaredLength = dx*dx + dy*dy + dz*dz
    if squaredLength == 0 then return false end
    local t = ((x-shot.sx)*dx + (y-shot.sy)*dy + (z-shot.sz)*dz) / squaredLength
    t = math.max(0, math.min(t, 1))
    return (shot.sx+t*dx-x)^2 + (shot.sy+t*dy-y)^2 + (shot.sz+t*dz-z)^2 <= 5^2
end

local function gunHitConfirmed(state, now)
    local hit = state.gunHit
    if not hit then return false end
    if not isElement(hit.attacker) or (now - hit.tick) % 4294967296 > 1200 then
        state.gunHit = nil
        return false
    end
    if not state.lossAt or (now - state.lossAt) % 4294967296 > 1200 then return false end
    local x, y, z = hit.x, hit.y, hit.z
    for _, shot in ipairs(recentShots[hit.attacker] or {}) do
        if shot.weapon == hit.weapon and (now - shot.tick) % 4294967296 <= 1200 then
            if finite(shot.x) and finite(shot.y) and finite(shot.z) then
                if shotCrossesVehicle(shot, x, y, z) then return true end
            elseif getElementType(hit.attacker) == "ped" then
                local ax, ay, az = getElementPosition(hit.attacker)
                if (ax-x)^2 + (ay-y)^2 + (az-z)^2 <= 400^2 then return true end
            end
        end
    end
    return false
end

local function reactToVehicleGunHit(state)
    local attacker = state.gunHit.attacker
    state.gunHit, state.lossAt = nil, nil
    -- 0x003ef910 diverts emergency/police responses before the civilian branch.
    local model = state.originalVehicle
    if model == 0x105 or model == 0xdb or model == 0xcf or model == 0xea then return end
    local profile = PedAI.profile(state.driver)
    local retaliate = profile and profile.pedType >= 7 and profile.pedType <= 15
        and getElementType(attacker) == "player"
    if not retaliate and math.random() > 0.5 then
        state.panicDriving = true
        state.cruiseSpeed = math.floor(state.cruiseSpeed * 1.5)
        HLC:setNPCDriveSpeed(state.driver, state.cruiseSpeed / 50)
        if state.rail then switchToPhysics(state) else followPhysics(state) end
        return
    end
    state.evacuating = {attacker=attacker, retaliate=retaliate}
    HLC:clearNPCTasks(state.driver)
    releaseRoadControl(state)
    TrafficPassengers.vehicleUnderFire(state.vehicle, attacker, retaliate)
    if not retaliate and PedVoice then PedVoice.emit(state.driver, "fear") end
end

local function targetNearby(state, target)
    if not isElement(target) or isPedDead(target) or getElementDimension(target) ~= state.dimension
        or getElementInterior(target) ~= 0 then return false end
    local x, y, z = getElementPosition(state.vehicle)
    return getDistanceBetweenPoints3D(x, y, z, getElementPosition(getPedOccupiedVehicle(target) or target)) <= 65
end

local function resumeCruise(state)
    TrafficWorld.cancelPursuit(state.vehicle)
    state.pursuit = nil
    rejoinRoadAtVehicle(state)
    resetPhysicsSequence(state)
    followPhysics(state)
end

local function followPursuitRoute(state)
    if not rejoinRoadAtVehicle(state, 15) then return false end
    local tx, ty, tz = getElementPosition(state.pursuit.actor)
    local route = state.railRoute
    for i = #route + 1, 4 do
        local prev = route[i-1]
        local selected, best
        for _, edge in ipairs(outgoingChoices(graph, prev.edge, prev.lane)) do
            local lane = math.min(prev.lane, edge.lanes - 1)
            local point = laneCentre(edge, lane)
            if point then
                local score = (point[1]-tx)^2 + (point[2]-ty)^2 + (point[3]-tz)^2
                if not best or score < best then
                    selected, best = {edge=edge, lane=lane, point=point}, score
                end
            end
        end
        if not selected then break end
        route[i] = selected
    end
    resetPhysicsSequence(state)
    return followPhysics(state)
end

local function updatePursuit(state, owner, now)
    local pursuit = state.pursuit
    if not targetNearby(state, pursuit.target) then return resumeCruise(state) end
    local action = pursuit:update(state.vehicle, owner, now)
    if action == "end" then
        resumeCruise(state)
    elseif action == "route" then
        TrafficWorld.cancelPursuit(state.vehicle)
        if not followPursuitRoute(state) then resumeCruise(state) end
    elseif action == "brake" then
        assignTask(state, {"stopVehicle"})
    elseif action == "chase" then
        TrafficWorld.cancelPursuit(state.vehicle)
        assignTask(state, {"driveAtPed", pursuit.target})
    elseif action == "exit" then
        TrafficPassengers.requestExit(state.driver, state.vehicle, 0, pursuit.target,
            pursuit.actor, pursuit.anchorX, pursuit.anchorY, pursuit.anchorZ)
    end
end

local function decideAfterCrash(state, now)
    local incident = state.crashDecision
    if (now - incident.at) % 4294967296 > 900 or not targetNearby(state, incident.target) then
        state.crashDecision = nil
        return
    end
    if not state.collisionLossAt or (now - state.collisionLossAt) % 4294967296 > 900 then return end
    state.crashDecision, state.collisionLossAt = nil, nil
    local response = TrafficVehicleCollision.chooseResponse(PedAI.profile(state.driver), math.random())
    if response == 1031 then
        -- CTaskComplexRoadRage leaves only the offended driver, then seeks
        -- the driver responsible for the collision.
        state.evacuating = {roadRage = true, attacker = incident.target}
        assignTask(state, {"stopVehicle"})
        record("crashRoadRage")
    elseif response == 726 then
        state.panicDriving, state.drivingStyle, state.cruiseSpeed = true, 2, 40
        HLC:setNPCDriveSpeed(state.driver, 40 / 50)
        followPhysics(state)
        record("crashFlee")
    elseif response == 729 then
        state.pursuit = TrafficVehiclePursuit.new(incident.target, now)
        assignTask(state, {"driveAtPed", incident.target})
        record("crashPursuit")
    else
        record("crashContinue")
    end
end

addEventHandler("onVehicleDamage", root, function(loss)
    local vehicle = source
    local state = vehicles[vehicle]
    if not state or state.boat or state.scriptPaused or loss <= 0 then return end
    state.lossAt = getTickCount()
    state.collisionLossAt = state.lossAt
    if not state.rail or state.evacuating or state.damagePending then return end
    -- Damage and the contact report may arrive in either order.
    state.damagePending = true
    setTimer(function()
        state.damagePending = nil
        if vehicles[vehicle] == state and state.rail then switchToPhysics(state) end
    end, 150, 1)
end)

addEventHandler("onVehicleStartEnter", root, function(player, seat, jacked, door)
    if getElementType(player) ~= "player" then return end
    local owned = ownedVehicles[source]
    if owned then owned.boardingAt = getTickCount() end
    local entry=detachedBikes[source]
    if seat==0 and entry and (getTickCount()-entry.at)%4294967296<=1200 and jacked==entry.road.driver then
        detachedBikes[source]=nil
        entry.road.jacker,entry.road.jackDoor=player,door or 0
        PedAI.carjacked(entry.road.driver,player,source,entry.road)
        return
    end
    local state, restored = roadInteraction(source)
    if not state or state.scriptPaused then return end
    if seat == 0 and (jacked == state.driver or getVehicleOccupant(source, 0) == state.driver) then
        if state.pursuit then TrafficWorld.cancelPursuit(source) end
        state.pursuit = nil
        state.jacker, state.jackStarted = player, getTickCount()
        state.jackDoor = door or 0
        state.quickDrag = PedCarjack.quickDrag(source,state.originalVehicle,state.jackDoor)
        HLC:clearNPCTasks(state.driver)
    elseif restored then
        assignTask(state, state.railTask or state.physicsTask)
    end
end, true, "low")

addEventHandler("onVehicleExit", root, function(ped, seat, jacker)
    if waterSeatTransfers[source] then return end
    local owned = ownedVehicles[source]
    if owned and not TrafficVisibility.isWreck(source) and getElementType(ped)=="player" then
        owned.lastPlayerUse = getTickCount()
        if not vehicles[source] and not retiring[source] then unclaimed[source] = owned.lastPlayerUse end
    end
    if seat ~= 0 then return end
    local state = vehicles[source] or retiring[source]
    if not state or state.scriptPaused or state.driver ~= ped or not isElement(ped) or isPedDead(ped) then return end
    state = roadInteraction(source)
    local player = isElement(jacker) and getElementType(jacker) == "player" and jacker or state.jacker
    yieldDriver(state, player, false)
end)

addEventHandler("onVehicleEnter", root, function(player, seat)
    if waterSeatTransfers[source] or getElementType(player) ~= "player" then return end
    local owned = ownedVehicles[source]
    if owned then owned.lastPlayerUse = getTickCount() end
    if seat == 0 and owned and owned.boat and getElementSyncer(source) ~= player then
        -- A second observer may still own the unoccupied-boat sync when the captain leaves.
        setElementSyncer(source, player, false)
    end
    local detached=detachedBikes[source]
    if seat==0 and detached and (getTickCount()-detached.at)%4294967296<=1200 then
        detachedBikes[source]=nil
        local road=detached.road
        if isElement(road.driver) and not isPedDead(road.driver) and not isPedInVehicle(road.driver) then
            road.jacker=player
            PedAI.carjacked(road.driver,player,source,road)
        end
    end
    local state, restored = roadInteraction(source)
    if not state or state.scriptPaused then return end
    if seat == 0 then
        yieldDriver(state, player, true)
    elseif restored then
        assignTask(state, state.railTask or state.physicsTask)
    end
end)

-- Native enter can refuse an open watercraft while the player is swimming.
-- The caller validates the boarding position. Keep seat ownership and traffic state atomic here.
function TrafficRoad.isAmbientWatercraft(vehicle)
    local state = ownedVehicles[vehicle]
    return state and state.boat == true or false
end

function TrafficRoad.boardWatercraft(player, vehicle)
    if not isElement(player) or getElementType(player) ~= "player" or isPedDead(player)
        or getPedOccupiedVehicle(player) or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
        or (getVehicleType(vehicle) ~= "Boat" and getElementData(vehicle,"mod.model",false) ~= "JETSKI")
        or getElementDimension(player) ~= getElementDimension(vehicle) or getElementInterior(player) ~= getElementInterior(vehicle)
        or isVehicleLocked(vehicle) or isVehicleBlown(vehicle) or waterSeatTransfers[vehicle] then return false end
    local state = vehicles[vehicle] or retiring[vehicle]
    local driver = getVehicleOccupant(vehicle, 0)
    if state and (not state.boat or state.driver ~= driver or state.scriptPaused or state.jacker and state.jacker ~= player)
        or driver and (not state or getElementType(driver) ~= "ped" or isPedDead(driver)
            or PedAI.isScriptControlled(driver)) then return false end

    waterSeatTransfers[vehicle] = true
    local boarded = exports.vcs_vehicle:transferWatercraftSeat(player, vehicle, driver)
    waterSeatTransfers[vehicle] = nil
    if not boarded then return false end
    if state then
        state = roadInteraction(vehicle)
        if state then
            state.jacker, state.jackDoor, state.quickDrag = player, 0, false
            yieldDriver(state,player,true)
        end
    elseif ownedVehicles[vehicle] then
        ownedVehicles[vehicle].lastPlayerUse = getTickCount()
    end
    return true
end

-- Only the population owner can release its NPC and retire its route task.
addEventHandler("vcs_vehicle:onWatercraftBoardRequest", root, function(player)
    if TrafficRoad.isAmbientWatercraft(source) then
        cancelEvent()
        TrafficRoad.boardWatercraft(player, source)
    end
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
        local nearby = getElementsWithinRange(x, y, ground, candidate.boat and kind == "vehicle" and 40 or 10, kind, 0, dimension)
        if not nearby or #nearby > 0 then record("occupied") return end
    end
    local model, original, class, incident
    local vcsServices = PedServices and graph.edition == "SLUS-21590 USA v1.00"
    if candidate.boat then
        local wanted = getPlayerWantedLevel(player)
        local available = false
        if wanted >= 2 then
            local response = TrafficWantedRules.getPoliceResponse(wanted)
            local cops, units = 0, 0
            for _, state in pairs(vehicles) do
                if state.dimension == dimension and state.lawEnforcer then units = units + 1 end
            end
            for _, ped in ipairs(getElementsWithinRange(x,y,ground,TRAFFIC_AREA_RADIUS,"ped",0,dimension) or {}) do
                if TrafficActors.isPolicePed(ped) and not isPedDead(ped) then cops = cops + 1 end
            end
            available = response and units < response.pursuitVehicleLimit and cops < response.pursuitPedLimit
        end
        model, original, class = TrafficAmbient.chooseBoat(candidate.playerX,candidate.playerY,candidate.playerZ,wanted,available)
    else
        if vcsServices then model,original,class,incident=PedServices.dispatch(x,y,ground,dimension,player) end
        if not model then model,original,class=chooseTrafficCivilianVehicle(x,y,ground,false) end
    end
    if not model then record("modelUnavailable") return end
    local kind = getVehicleType(model)
    -- 0x00430290 has a separate construction branch for VCS model type 6.
    -- MTA's native bike uses the same throttle, brake and steering inputs.
    if candidate.boat and kind ~= "Boat" or not candidate.boat and kind ~= "Automobile" and kind ~= "Bike" then
        record("modelUnavailable") return
    end

    local profile = TrafficPopulation.sample(graph.population,
        candidate.playerX, candidate.playerY, candidate.playerZ, (getTime()))
    local group = profile and graph.population.pedGroups[profile.pedestrianGroupId + 1]
    local originalDriver = vcsServices and (PedServices.crewModel(original) or PedServices.policeCrewModel(original)) or TrafficRoad.chooseDriver(group, graph.pedestrianDriverMasks, class,
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
    local centreHeight = candidate.boat and 0 or math.max(0, -minimumZ)
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
    local cruiseSpeed = class == 23 and math.floor(12 + math.random() * 4)
        or vehicleClassSpeed(class, math.random(), maximumY - minimumY)
    if candidate.boat and math.random(0, 127) < 40 then
        cruiseSpeed = cruiseSpeed + 10
        setElementData(vehicle, "npchlc_traffic:boatStyle", 2, "broadcast", "deny")
    end
    HLC:setNPCDriveSpeed(driver, cruiseSpeed / 50)
    local state = candidate.rail
    state.boat = candidate.boat
    state.vehicle, state.driver, state.dimension = vehicle, driver, dimension
    state.originalDriver, state.originalVehicle = originalDriver, original
    -- 0x00431D34 sets the law-enforcer flag on these traffic classes.
    state.lawEnforcer = class == 13 or class == 23 or class == 24
    -- The spawn ground belongs to this XY only. Subsequent rail samples
    -- carry the packed path height plus chassis clearance.
    state.heightOffset, state.centreHeight = centreHeight, centreHeight
    state.cruiseSpeed, state.rail = cruiseSpeed, true
    if not state.boat and graph.edition == "SLUS-21590 USA v1.00" then
        -- The PS2 tests three bits of the vehicle's fixed seed in UpdateCarAI.
        state.canReverse = math.random(0, 7) == 0
        setElementData(vehicle, "npchlc_traffic:stuckReverse", state.canReverse and 400 or 0, "broadcast", "deny")
    end
    sampleRailVelocity(state, x, y, z, getTickCount())
    register(state)
    PedAI.attach(driver, graph.modelIdSpace ~= "mta" and originalDriver or nil)
    if class == 23 then setTrafficPolicePed(driver, true) end
    setElementFrozen(vehicle, false)
    setElementData(vehicle, railTag, true, "broadcast", "deny")
    followRail(state)
    if not vehicles[vehicle] then record("creationFailed") return false end
    TrafficVisibility.track(vehicle, "road")
    TrafficVisibility.track(driver, "road")
    if vcsServices and PedServices.crewModel(original) then
        PedServices.linkCrew(state,incident,true)
    else
        TrafficPassengers.spawn(state, graph, group, class, original)
    end
    record("spawned")
    if state.boat then record("boatSpawned") end
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
    local cars, boats = density("cars") > 0, density("boats") > 0 and next(waterCells) ~= nil
    local searchRadius = boats and radius * 1.5 or radius
    local startX, startY = math.floor((originX - searchRadius) / CELL_SIZE), math.floor((originY - searchRadius) / CELL_SIZE)
    local sizeX = math.floor((originX + searchRadius) / CELL_SIZE) - startX + 1
    local sizeY = math.floor((originY + searchRadius) / CELL_SIZE) - startY + 1
    local visited = {}
    local function consider(edge)
        if edge.lanes == 0 or visited[edge] then return end
        visited[edge] = true
        local from, to = graph.nodes[edge.from + 1], graph.nodes[edge.to + 1]
        local boat = from.kind == "boat"
        if boat and not boats or not boat and not cars then return end
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
                playerX = x, playerY = y, playerZ = z, range = range, boat = boat}
        end
    end
    local cellCount = sizeX * sizeY
    for cursor = 0, cellCount - 1 do
        if (getTickCount() - searchStarted) % 4294967296 >= SEARCH_BUDGET_MS then break end
        local index = (phase + cursor) % cellCount
        local column = cells[startX + index % sizeX]
        local bucket = column and column[startY + math.floor(index / sizeX)]
        local waterColumn = boats and waterCells[startX + index % sizeX]
        local water = waterColumn and waterColumn[startY + math.floor(index / sizeX)]
        if water then
            for _, edge in ipairs(water) do consider(edge) end
        end
        if cars and bucket then
            for i = 0, math.min(#bucket, MAX_NODES_PER_LOCAL_CELL) - 1 do
                if i % 16 == 0 and (getTickCount() - searchStarted) % 4294967296 >= SEARCH_BUDGET_MS then break end
                local node = bucket[(i + phase) % #bucket + 1]
                if node.kind == "vehicle" then
                    for offset = 1, node.linkCount do consider(graph.links[node.firstLink + offset]) end
                    for _, edge in ipairs(incoming[node.id] or {}) do consider(edge) end
                end
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
        or visible ~= true and squared <= (candidate.boat and 90 or 60) ^ 2
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
            sample.px,sample.py,sample.pz=getElementPosition(occupant)
            sample.dimension,sample.interior=dimension,interior
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

local function boatCap(x, y, z)
    if not next(waterCells) or density("boats") <= 0 then return 0 end
    local profile = TrafficPopulation.sample(graph.population, x, y, z, (getTime()))
    return profile and math.min(MAX_PER_TRAFFIC_AREA, TrafficRoadPopulation.zoneTarget(profile, density("boats"))) or 0
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
                admission = {x = x, y = y, z = z, vx = vx, vy = vy,
                    cap = x and areaCap(x, y, z, densityFactor), boatCap = x and boatCap(x, y, z)}
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
                or admission.count >= math.max(admission.cap, admission.boatCap) then
                record(activeCount >= MAX_SERVER_VEHICLES and "globalCapacity" or "capacity")
                finishBatch(player, batch)
            else
                local index, result = batch.nextProbe, batch.result
                local candidate, probe = batch.points[index], result.probes[index]
                if admission.count >= (candidate.boat and admission.boatCap or admission.cap) then
                    record("capacity")
                elseif not probe then
                    record(candidate.boat and "boatWaterRejected" or "groundRejected")
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
                local cap = math.max(areaCap(x, y, z, densityFactor), boatCap(x, y, z))
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
    TrafficPassengers.update(now)
    for vehicle,entry in pairs(detachedBikes) do
        if (now-entry.at)%4294967296>1200 or not isElement(vehicle) then
            detachedBikes[vehicle]=nil
            local ped=entry.road.driver
            if isElement(vehicle) and isElement(ped) and not isPedDead(ped) and not isPedInVehicle(ped)
                and not getVehicleOccupant(vehicle,0) and not PedAI.isScriptControlled(ped) then
                TrafficAmbient.bikeFall(ped,{},false,entry.road)
            end
        end
    end
    for vehicle, checkedAt in pairs(unclaimed) do
        local state = ownedVehicles[vehicle]
        if not state or not isElement(vehicle) then
            unclaimed[vehicle], ownedVehicles[vehicle] = nil, nil
        elseif (now - checkedAt) % 4294967296 >= 1000 then
            unclaimed[vehicle] = now
            if TrafficVisibility.hasPlayerOccupant(vehicle) then
                state.lastPlayerUse = now
            elseif not state.boardingAt or (now - state.boardingAt) % 4294967296 > 8000 then
                local x, y, z = getElementPosition(vehicle)
                local nearby = getElementsWithinRange(x, y, z, syncRadius, "player",
                    getElementInterior(vehicle), getElementDimension(vehicle))
                local service = state.originalVehicle == 227 or state.originalVehicle == 194
                local expired = state.lastPlayerUse and (now - state.lastPlayerUse) % 4294967296 >= PLAYER_PARKING_GRACE_MS
                local brain = isElement(state.driver) and PedAI.brain(state.driver)
                local event = brain and brain.event
                local reserved = event and (event.road == state or event.originalRoad == state)
                if service and PedServices then reserved = reserved or PedServices.needsParkedVehicle(state) end
                if not reserved and ((nearby and #nearby == 0) or expired or service) then
                    unclaimed[vehicle], ownedVehicles[vehicle] = nil, nil
                    destroyElement(vehicle)
                end
            end
        end
    end
    for _ = 1, math.min(MAX_CLEANUP_PER_TICK, activeCount) do
        local state = vehicleCursor or vehicleHead
        if not state or state.checkedAt == now then break end
        state.checkedAt = now
        vehicleCursor = state.after or vehicleHead
        local vehicle = state.vehicle
        local scripted = PedAI.isScriptControlled and PedAI.isScriptControlled(state.driver)
        if scripted and not state.scriptPaused then TrafficRoad.driverScriptChanged(state.driver, true) end
        if state.scriptPaused and isElement(state.driver) and not isPedDead(state.driver) then
            if not scripted then TrafficRoad.driverScriptChanged(state.driver, false) end
        elseif not isElement(vehicle) or not isElement(state.driver) or isPedDead(state.driver) or isVehicleBlown(vehicle)
            or not state.boat and isElementInWater(vehicle) then
            release(state)
        elseif not state.jacker and not state.evacuating and getVehicleOccupant(vehicle,0)==state.driver
            and not state.boat and PedServices and graph.edition=="SLUS-21590 USA v1.00" and PedServices.inVehicle(state,now,switchToPhysics,followPhysics) then
            state.lastProgress=now
        elseif state.evacuating then
            local occupant = getVehicleOccupant(vehicle, 0)
            if occupant ~= state.driver then
                local taken = isElement(occupant) and getElementType(occupant) == "player"
                yieldDriver(state, taken and occupant or nil, taken)
            elseif state.evacuating.roadRage and not targetNearby(state, state.evacuating.attacker) then
                state.evacuating = nil
                followPhysics(state)
            elseif (not state.evacuating.roadRage or length2D(getElementVelocity(vehicle)) <= 0.05)
                and (not state.evacuating.requested or (now - state.evacuating.requested) % 4294967296 >= 1500) then
                state.evacuating.requested = now
                if not TrafficPassengers.requestExit(state.driver, vehicle, 0) then
                    local x, y, z = getElementPosition(vehicle)
                    local observers = getElementsWithinRange(x, y, z, syncRadius, "player", 0, state.dimension)
                    if observers and #observers == 0 then release(state) end
                end
            end
        elseif state.jacker then
            -- MTA reports start/exit/enter, but no event for a player abandoning the door.
            local elapsed = (now - state.jackStarted) % 4294967296
            local abandoned = not isElement(state.jacker)
            if not abandoned and elapsed >= 500 then
                local x,y,z = getElementPosition(state.jacker)
                local vx,vy,vz = getElementPosition(vehicle)
                abandoned = getDistanceBetweenPoints3D(x,y,z,vx,vy,vz) > 7
            end
            if elapsed >= 8000 or abandoned or elapsed >= 500 and getVehicleOccupant(vehicle,0) ~= state.driver then
                local player = state.jacker
                state.jacker, state.jackStarted, state.railStall = nil, nil, nil
                if getVehicleOccupant(vehicle, 0) == state.driver then
                    if state.rail and state.damagePending then
                        switchToPhysics(state)
                    else
                        assignTask(state, state.railTask or state.physicsTask)
                    end
                else
                    local occupant = getVehicleOccupant(vehicle, 0)
                    local taken = isElement(occupant) and getElementType(occupant) == "player"
                    yieldDriver(state, taken and occupant or isElement(player) and player or nil, taken)
                end
            end
        elseif getVehicleOccupant(vehicle, 0) ~= state.driver then
            local occupant = getVehicleOccupant(vehicle, 0)
            local taken = isElement(occupant) and getElementType(occupant) == "player"
            yieldDriver(state, taken and occupant or nil, taken)
        else
            local x, y, z = getElementPosition(vehicle)
            local syncer = getElementSyncer(vehicle)
            if not state.rail and (not state.progressX or (x - state.progressX)^2 + (y - state.progressY)^2 >= 1) then
                state.progressX, state.progressY, state.lastProgress = x, y, now
            end
            if state.canReverse and not state.rail and state.drivingStyle ~= 2 then
                if length2D(getElementVelocity(vehicle)) > 0.018 then state.stoppedAt = nil
                else state.stoppedAt = state.stoppedAt or now end
            end
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
            elseif (now - state.lastProgress) % 4294967296 > (state.rail and MAX_LIFETIME_WITHOUT_PROGRESS or 60000) then
                record("despawnStalled")
                release(state, true)
            elseif state.gunHit and gunHitConfirmed(state, now) then
                if state.pursuit then TrafficWorld.cancelPursuit(vehicle) end
                state.crashDecision, state.pursuit = nil, nil
                reactToVehicleGunHit(state)
            elseif state.crashDecision then
                decideAfterCrash(state, now)
            elseif state.pursuit then
                updatePursuit(state, syncer, now)
            elseif state.rail then
                sampleRailVelocity(state, x, y, z, now)
            elseif state.physicsTask then
                local rejoin, displaced = HLC:getNPCTrafficPhysicsRejoin(state.physicsTask, vehicle)
                if rejoin then
                    record("physicsRejoins")
                    advancePhysics(state, rejoin - 1)
                elseif displaced and (not state.rejoinAttempt or (now - state.rejoinAttempt) % 4294967296 >= 2000) then
                    state.rejoinAttempt = now
                    if rejoinRoadAtVehicle(state, 12) then
                        state.physicsSequence = state.physicsSequence + #state.physicsTask[5]
                        record("physicsRejoins")
                        followPhysics(state)
                    end
                end
            end
        end
    end
    local densityFactor = density("cars")
    local combinedDensity = math.max(densityFactor, density("boats"))
    local urgent = refreshPending(now, combinedDensity)
    if combinedDensity <= 0 then
        readyBatches, readyHead, readyTail = {}, 1, 0
        return
    end
    consumeReady(densityFactor)
    if activeCount < MAX_SERVER_VEHICLES then dispatchProbes(densityFactor, urgent)
    else record("globalCapacity") end
end

function getTrafficRoadStatus()
    local status = {vehicles = activeCount, boats = 0, densityProfile = densityMode or "zone", range = syncRadius}
    for _, state in pairs(vehicles) do if state.boat then status.boats = status.boats + 1 end end
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
    return drivers[ped] ~= nil or TrafficPassengers.isManaged(ped)
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

addEventHandler("onVehicleExplode",root,function()
    local car=source
    if not ownedVehicles[car] or TrafficVisibility.isWreck(car) then return end
    unclaimed[car]=nil
    roadInteraction(car) -- cancel a pending population fade before starting the wreck clock
    TrafficVisibility.keepWreck(car,"road")
end)

addEventHandler("onElementDestroy",root,function()
    ownedVehicles[source], unclaimed[source] = nil, nil
end)

-- A pursuit helicopter can outlive its AI pilot when a player takes a seat.
function TrafficRoad.retainPlayerVehicle(vehicle)
    local now = getTickCount()
    ownedVehicles[vehicle] = {vehicle=vehicle, lastPlayerUse=now}
    unclaimed[vehicle] = now
end

function TrafficRoad.stop()
    if timer then
        killTimer(timer)
        removeEventHandler("npc_hlc:onNPCTaskDone", root, taskDone)
        removeEventHandler("onPlayerQuit", root, disconnected)
    end
    for _, state in pairs(vehicles) do release(state) end
    for vehicle, state in pairs(retiring) do
        if isElement(vehicle) then TrafficVisibility.cancelRetirement(vehicle) end
        finishRelease(state)
    end
    for vehicle in pairs(unclaimed) do
        if isElement(vehicle) and not TrafficVisibility.hasPlayerOccupant(vehicle) then destroyElement(vehicle) end
    end
    unclaimed, ownedVehicles = {}, {}
    recentShots = setmetatable({}, {__mode = "k"})
    detachedBikes = {}
    TrafficPassengers.stop()
    for player, batch in pairs(pending) do finishBatch(player, batch) end
    graph, density, timer, vehicleCursor, densityMode = nil, nil, nil, nil, nil
    cells, incoming, pending, cursorByPlayer, lastRoadAttempt = {}, {}, {}, {}, {}
    waterCells = {}
    activeCount, nextPlayer = 0, 0
    vehicleHead, vehicleTail = nil, nil
    gameDay, previousHour = 4, nil
    observers, observerList = {}, {}
    readyBatches, readyHead, readyTail, stats = {}, 1, 0, {}
end
