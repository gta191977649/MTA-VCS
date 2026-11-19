TrafficDebug = {}

local graph, cells, roadConnections
local lastRequest = {}
local kinds = {road = "vehicle", ped = "pedestrian", boat = "boat"}
local cellSize, radius = 80, 145
local maxNodesPerKind, maxLinksPerKind = 100, 160
local maxRoadConnections = 128

function TrafficDebug.setGraph(value)
    graph, cells = value, nil
    roadConnections = {}
end

local function appendRoadConnections(connections, edge, lane)
    if #connections >= maxRoadConnections then return end
    local byLane = roadConnections[edge.id] or {}
    if not byLane[lane] then
        byLane[lane] = TrafficRoad.debugConnections(graph, edge, lane)
        roadConnections[edge.id] = byLane
    end
    for _, points in ipairs(byLane[lane]) do
        connections[#connections + 1] = points
        if #connections == maxRoadConnections then break end
    end
end

local function indexNodes()
    cells = {}
    for _, node in ipairs(graph.nodes) do
        local cx, cy = math.floor(node.x / cellSize), math.floor(node.y / cellSize)
        local column = cells[cx] or {}
        local bucket = column[cy] or {}
        cells[cx], column[cy] = column, bucket
        bucket[#bucket + 1] = node
    end
end

local function collect(player, mode)
    if not cells then indexNodes() end
    local x, y, z = getElementPosition(player)
    local nearby = {}
    for cx = math.floor((x - radius) / cellSize), math.floor((x + radius) / cellSize) do
        local column = cells[cx]
        if column then
            for cy = math.floor((y - radius) / cellSize), math.floor((y + radius) / cellSize) do
                for _, node in ipairs(column[cy] or {}) do
                    if mode == "all" or node.kind == kinds[mode] then
                        local horizontal = (node.x - x) ^ 2 + (node.y - y) ^ 2
                        if horizontal <= radius ^ 2 then
                            nearby[#nearby + 1] = {node = node, distance = horizontal + (node.z - z) ^ 2}
                        end
                    end
                end
            end
        end
    end
    table.sort(nearby, function(a, b)
        if a.distance == b.distance then return a.node.id < b.node.id end
        return a.distance < b.distance
    end)

    local nodes, links, connections, nodeCounts, linkCounts, seen = {}, {}, {}, {}, {}, {}
    for _, item in ipairs(nearby) do
        local node, kind = item.node, item.node.kind
        if (nodeCounts[kind] or 0) < maxNodesPerKind then
            nodes[#nodes + 1] = {node.x, node.y, node.z, kind, node.id}
            nodeCounts[kind] = (nodeCounts[kind] or 0) + 1
        end
        for offset = 1, node.linkCount do
            if (linkCounts[kind] or 0) >= maxLinksPerKind then break end
            local edge = graph.links[node.firstLink + offset]
            local target = graph.nodes[edge.to + 1]
            local directed = kind == "vehicle" and edge.lanes > 0
            local a, b = math.min(node.id, target.id), math.max(node.id, target.id)
            local key = a .. ":" .. b
            if directed then
                local dx, dy, dz = target.x - node.x, target.y - node.y, target.z - node.z
                local length = math.sqrt(dx * dx + dy * dy)
                if length > 0 then
                    local span = math.min(0.22, 5 / length)
                    for lane = 0, math.min(edge.lanes, maxLinksPerKind - (linkCounts[kind] or 0)) - 1 do
                        local mx, my, mz = TrafficGraph.lanePoint(graph, edge, lane)
                        links[#links + 1] = {mx - dx * span, my - dy * span, mz - dz * span,
                            mx + dx * span, my + dy * span, mz + dz * span, kind, true,
                            edge.lightDirection and edge.lightGroup or 0}
                        linkCounts[kind] = (linkCounts[kind] or 0) + 1
                        appendRoadConnections(connections, edge, lane)
                    end
                end
            elseif kind ~= "vehicle" and not seen[key] then
                links[#links + 1] = {node.x, node.y, node.z, target.x, target.y, target.z, kind, false, 0}
                linkCounts[kind] = (linkCounts[kind] or 0) + 1
                seen[key] = true
            end
        end
    end
    if (mode == "all" or mode == "road") and getElementInterior(player) == 0 then
        TrafficRoad.appendDebugRails(player, links, radius)
    end
    return nodes, links, connections
end

addEvent("npchlc_traffic:debugRequest", true)
addEventHandler("npchlc_traffic:debugRequest", resourceRoot, function(mode)
    if not client or (mode ~= "all" and not kinds[mode]) then return end
    local now = getTickCount()
    if lastRequest[client] and (now - lastRequest[client]) % 4294967296 < 500 then return end
    lastRequest[client] = now
    if not graph then
        triggerClientEvent(client, "npchlc_traffic:debugPaths", resourceRoot, mode, false)
        return
    end
    local nodes, links, connections = collect(client, mode)
    triggerClientEvent(client, "npchlc_traffic:debugPaths", resourceRoot, mode, nodes, links, connections)
end, false)

addEventHandler("onPlayerQuit", root, function() lastRequest[source] = nil end)
