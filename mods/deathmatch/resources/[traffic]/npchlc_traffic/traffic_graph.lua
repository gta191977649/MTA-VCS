TrafficGraph = {}

local maxGraphBytes = 12 * 1024 * 1024
local cellSize = 80
local kinds = {
    pedestrian = "peds",
    vehicle = "cars",
    boat = "boats",
}

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function integer(value, min, max)
    return finite(value) and value % 1 == 0 and value >= min and value <= max
end

local function coordinates(record)
    return finite(record.x) and finite(record.y) and finite(record.z)
end

local function requireRecord(condition, category, index)
    if not condition then
        error(("invalid %s record %d"):format(category, index), 0)
    end
end

local function validateFixedWing(route, index, checkpoint)
    requireRecord(finite(route.length) and finite(route.clockDuration)
        and route.clockDuration > 0 and finite(route.takeoffDistance) and finite(route.landingDistance)
        and route.takeoffDistance > 0 and route.takeoffDistance < route.landingDistance
        and route.landingDistance < route.length and integer(route.clockPeriodMs, 1, 2147483647)
        and integer(route.phaseStepMs, 0, route.clockPeriodMs - 1) and integer(route.instances, 1, 32)
        and type(route.motionSegments) == "table" and #route.motionSegments > 0
        and type(route.motionEnd) == "table" and route.motionEnd.kind == 0
        and finite(route.motionEnd.distance), "fixed-wing header", index)
    local previous = 0
    for slot, segment in ipairs(route.motionSegments) do
        requireRecord(type(segment) == "table" and (segment.kind == 1 or segment.kind == 2)
            and segment.start == previous and finite(segment["end"]) and segment["end"] > previous
            and finite(segment.distance) and finite(segment.velocity) and finite(segment.acceleration),
            "fixed-wing motion", slot)
        previous = segment["end"]
        checkpoint()
    end
    requireRecord(previous == route.motionEnd.start and previous == route.clockDuration,
        "fixed-wing phase range", index)
    local previousDistance = -1
    for slot, point in ipairs(route.points) do
        requireRecord(type(point) == "table" and coordinates(point) and finite(point.distance)
            and point.distance >= 0 and point.distance > previousDistance and point.distance < route.length
            and integer(point.flags, 0, 4294967295), "fixed-wing point", slot)
        previousDistance = point.distance
        checkpoint()
    end
    requireRecord(route.points[1].distance == 0, "fixed-wing loop origin", index)
end

local function cell(value, axisOffset)
    return math.floor(value / cellSize + axisOffset)
end

local function addToSpatialIndex(cells, node)
    local x, y = cell(node.x, 30), cell(node.y, 25)
    local column = cells[x]
    if not column then
        column = {}
        cells[x] = column
    end
    local bucket = column[y]
    if not bucket then
        bucket = {}
        column[y] = bucket
    end
    bucket[#bucket + 1] = node
end

function TrafficGraph.build(data, checkpoint)
    if type(data) ~= "table" or data.schemaVersion ~= 1 or type(data.nodes) ~= "table"
        or #data.nodes == 0 or type(data.links) ~= "table" or type(data.routes) ~= "table" then
        error("missing or unsupported traffic graph schema", 0)
    end

    local nodes, links = data.nodes, data.links
    local legacy = data.edition == "SLUS-21590 USA v1.00"
    local graph = {
        edition = data.edition,
        nodes = nodes,
        links = links,
        routes = {},
        dynamicRoutes = {},
        modelBindings = data.modelBindings,
        modelProvider = data.modelProvider or (legacy and "vcs_model" or nil),
        modelIdSpace = data.modelIdSpace,
        fallbackDriverModelId = data.fallbackDriverModelId or (legacy and 14 or nil),
        vehicleSteeringLimits = data.vehicleSteeringLimits or (legacy and {["234"] = 0.7} or {}),
        vehicleModelRules = data.vehicleModelRules,
        pedestrianDriverMasks = data.pedestrianDriverMasks,
        pedestrianCells = {},
        roadTurnClosures = {},
        counts = { peds = 0, cars = 0, boats = 0, routes = #data.routes, links = #links },
    }

    for index, node in ipairs(nodes) do
        requireRecord(type(node) == "table" and node.id == index - 1 and coordinates(node)
            and kinds[node.kind] and integer(node.flags, 0, 65535)
            and integer(node.rawWidth, 0, 255)
            and integer(node.firstLink, 0, 65535) and integer(node.linkCount, 0, 15)
            and (node.linkCount == 0 or node.firstLink + node.linkCount <= #links), "node", index)
        local kind = kinds[node.kind]
        node.speedClass = math.floor(node.flags / 0x400) % 4
        if kind == "peds" then
            addToSpatialIndex(graph.pedestrianCells, node)
        end
        graph.counts[kind] = graph.counts[kind] + 1
        checkpoint()
    end

    for index, link in ipairs(links) do
        requireRecord(type(link) == "table" and link.id == index - 1
            and integer(link.from, 0, #nodes - 1) and integer(link.to, 0, #nodes - 1), "link", index)
        local source = nodes[link.from + 1]
        requireRecord(index > source.firstLink and index <= source.firstLink + source.linkCount, "link owner", index)
        requireRecord(nodes[link.to + 1].kind == source.kind, "link kind", index)
        if source.kind ~= "pedestrian" then
            requireRecord(integer(link.lanes, 0, 7) and integer(link.leftLanes, 0, 7)
                and integer(link.rightLanes, 0, 7) and integer(link.lightGroup, 0, 3),
                "vehicle lanes", index)
            requireRecord(link.speedClass == nil or link.speedClass == source.speedClass, "vehicle speed class", index)
            link.speedClass = source.speedClass
        end
        checkpoint()
    end

    for index, node in ipairs(nodes) do
        for offset = 1, node.linkCount do
            requireRecord(links[node.firstLink + offset].from == node.id, "node link span", index)
        end
        checkpoint()
    end

    for index, pair in ipairs(data.roadTurnClosures or {}) do
        requireRecord(type(pair) == "table" and integer(pair[1], 0, #links - 1)
            and integer(pair[2], 0, #links - 1), "road turn closure", index)
        local inbound, outbound = links[pair[1] + 1], links[pair[2] + 1]
        requireRecord(nodes[inbound.from + 1].kind == "vehicle" and inbound.to == outbound.from
            and inbound.lanes > 0 and outbound.lanes > 0, "road turn closure endpoints", index)
        local blocked = graph.roadTurnClosures[inbound.id] or {}
        blocked[outbound.id] = true
        graph.roadTurnClosures[inbound.id] = blocked
        checkpoint()
    end

    for index, route in ipairs(data.routes) do
        requireRecord(type(route) == "table" and type(route.id) == "string" and route.id ~= ""
            and not graph.routes[route.id] and route.kind == "fixedWing"
            and type(route.points) == "table" and #route.points >= 2, "route", index)
        validateFixedWing(route, index, checkpoint)
        graph.routes[route.id] = route
        if not graph.ambientFlight and (route.usage == "ambient" or legacy and route.id == "fake-plane") then
            graph.ambientFlight = route
        end
    end
    for index, route in ipairs(data.dynamicRoutes or {}) do
        requireRecord(type(route) == "table" and type(route.id) == "string" and route.id ~= ""
            and not graph.dynamicRoutes[route.id], "dynamic route", index)
        graph.dynamicRoutes[route.id] = route
        if not graph.policeFlight and route.kind == "helicopter" and route.usage == "wanted" then
            if legacy and not route.pilotModelId then route.pilotModelId = 8 end
            graph.policeFlight = route
        end
        checkpoint()
    end
    graph.counts.dynamicRoutes = #(data.dynamicRoutes or {})
    if data.population then
        graph.population = TrafficPopulation.build(data.population, checkpoint)
        graph.counts.populationZones = #data.population.zones
    end
    local roadPopulation = data.roadPopulation or data.pcRoadPopulation
    if roadPopulation then
        graph.roadPopulation = TrafficRoadPopulation.build(roadPopulation, checkpoint)
    end
    return graph
end

local function pedestrianDirection(x, y)
    local horizontal = math.abs(x)
    if horizontal > 2 * math.abs(y) then
        return x >= 0 and 2 or 6
    elseif y > 2 * horizontal then
        return 0
    elseif y < -2 * horizontal then
        return 4
    elseif x >= 0 then
        return y > 0 and 1 or 3
    end
    return y > 0 and 7 or 5
end

-- 0x00267308 keeps a previous anchor inside seven metres. Its fallback
-- 0x00268880 visits the original 80 m bins and ranks using a weighted L1 distance.
function TrafficGraph.pedestrianAnchor(graph, x, y, z, previousId)
    if not graph or not finite(x) or not finite(y) or not finite(z) then
        return false
    end
    if integer(previousId, 0, #graph.nodes - 1) then
        local previous = graph.nodes[previousId + 1]
        local dx, dy, dz = previous.x - x, previous.y - y, previous.z - z
        if previous.kind == "pedestrian" and dx * dx + dy * dy + dz * dz <= 49 then
            return previousId
        end
    end
    local best, bestDistance = false, 10000
    for cy = cell(y - 100, 25), cell(y + 100, 25) do
        for cx = cell(x - 100, 30), cell(x + 100, 30) do
            local column = graph.pedestrianCells[cx]
            local bucket = column and column[cy]
            if bucket then
                for _, node in ipairs(bucket) do
                    if math.floor(node.flags / 32) % 2 == 0 and math.floor(node.flags / 512) % 2 == 0 then
                        local distance = math.abs(node.x - x) + math.abs(node.y - y) + 3 * math.abs(node.z - z)
                        if distance < 0.01 then
                            return node.id
                        elseif distance < bestDistance then
                            best, bestDistance = node.id, distance
                        end
                    end
                end
            end
        end
    end
    return best
end

-- A completed objective may leave a pedestrian off the navigation graph.
-- Return a short list in nearest-first order for the syncer's visibility test.
function TrafficGraph.pedestrianEntryPoints(graph,x,y,z,excluded)
    local candidates={}
    for cx=cell(x-45,30),cell(x+45,30) do
        local column=graph.pedestrianCells[cx]
        for cy=cell(y-45,25),cell(y+45,25) do
            for _,node in ipairs(column and column[cy] or {}) do
                local dz=node.z-z
                local distance=(node.x-x)^2+(node.y-y)^2+dz^2*4
                if node.id~=excluded and node.linkCount>0 and math.abs(dz)<4 and distance<=45^2
                    and math.floor(node.flags/32)%2==0 and math.floor(node.flags/512)%2==0 then
                    candidates[#candidates+1]={id=node.id,x=node.x,y=node.y,z=node.z,distance=distance}
                end
            end
        end
    end
    table.sort(candidates,function(a,b)
        if a.distance==b.distance then return a.id<b.id end
        return a.distance<b.distance
    end)
    while #candidates>8 do candidates[#candidates]=nil end
    return candidates
end

-- The ordinary-ped branch of 0x00267308, after it chooses the anchor
-- node and checks static line of sight. Reachability comes from the caller.
function TrafficGraph.pedestrianStep(graph, nodeId, heading, reachableNodeIds)
    if not graph or not integer(nodeId, 0, #graph.nodes - 1) or not integer(heading, 0, 7)
        or type(reachableNodeIds) ~= "table" or #reachableNodeIds > 15 then
        return false
    end
    local from = graph.nodes[nodeId + 1]
    if from.kind ~= "pedestrian" then
        return false
    end
    local reachable = {}
    for _, id in ipairs(reachableNodeIds) do
        if not integer(id, 0, #graph.nodes - 1) then
            return false
        end
        reachable[id] = true
    end
    local xAim, yAim = math.sin(heading * math.pi / 4), math.cos(heading * math.pi / 4)
    local startDisabled = math.floor(from.flags / 32) % 2 == 1
    local best, bestDirection, bestScore, bestLink = from.id, 0, -math.huge, nil
    for offset = 1, from.linkCount do
        local link = graph.links[from.firstLink + offset]
        local to = graph.nodes[link.to + 1]
        if reachable[to.id] and (startDisabled or math.floor(to.flags / 32) % 2 == 0) then
            local x, y = to.x - from.x, to.y - from.y
            local length = math.sqrt(x * x + y * y)
            if length > 0 then
                local score = (x * xAim + y * yAim) / length
                if score >= bestScore then
                    best, bestDirection, bestScore, bestLink = to.id, pedestrianDirection(x, y), score, link
                end
            end
        end
    end
    return best, bestDirection, bestLink
end

function TrafficGraph.load(graphPath, checkpoint)
    local file = fileOpen(graphPath, true)
    if not file then
        error("Traffic graph file not found: " .. graphPath, 0)
    end
    local size = fileGetSize(file)
    if size < 1 or size > maxGraphBytes then
        fileClose(file)
        error("invalid traffic graph file size", 0)
    end
    local contents = fileRead(file, size)
    fileClose(file)
    if type(contents) ~= "string" or #contents ~= size then
        error("could not read the complete traffic graph", 0)
    end
    return TrafficGraph.build(fromJSON(contents), checkpoint)
end

function TrafficGraph.lanePoint(graph, edge, lane)
    if not edge or type(edge.lanes) ~= "number" or not integer(lane, 0, edge.lanes - 1) then
        return false
    end
    local from, to = graph.nodes[edge.from + 1], graph.nodes[edge.to + 1]
    local dx, dy = to.x - from.x, to.y - from.y
    local length = math.sqrt(dx * dx + dy * dy)
    if length == 0 then return false end

    -- SLUS_215.90 0x002D13D0 uses the greater packed endpoint width on two-way links.
    local offset
    if edge.leftLanes > 0 and edge.rightLanes > 0 then
        offset = (2 * lane + 1) * 2.5 + math.max(from.rawWidth, to.rawWidth) / 16
    else
        offset = (2 * lane + 1 - edge.lanes) * 2.5
    end
    return (from.x + to.x) * 0.5 + dy * offset / length,
        (from.y + to.y) * 0.5 - dx * offset / length, (from.z + to.z) * 0.5
end

function TrafficGraph.canDriveTransition(graph, inbound, outbound)
    if inbound.to ~= outbound.from or inbound.lanes == 0 or outbound.lanes == 0 then return false end
    local blocked = graph.roadTurnClosures[inbound.id]
    return not (blocked and blocked[outbound.id])
end

