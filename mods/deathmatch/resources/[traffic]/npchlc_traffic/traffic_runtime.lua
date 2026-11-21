local graph
local graphLoader
local loadTimer
local status = "stopped"
local failure
local sliceStarted
local density = { peds = 1, cars = 1, boats = 1, planes = 1 }

local function checkpoint()
    if getTickCount() - sliceStarted >= 3 then
        coroutine.yield()
    end
end

local function continueLoad()
    loadTimer = nil
    sliceStarted = getTickCount()
    local success, result = coroutine.resume(graphLoader)
    if not success then
        status, failure = "unavailable", tostring(result)
        graphLoader = nil
        outputDebugString("[npchlc_traffic] " .. failure, 2)
    elseif coroutine.status(graphLoader) == "dead" then
        graphLoader = nil
        graph, status = result, "ready"
        PedAI.graph = graph
        TrafficDebug.setGraph(graph)
        TrafficModelBindings.load(graph, get("npchlc_traffic.modelProvider"))
        TrafficLights.start()
        TrafficAircraft.start(graph.ambientFlight, graph.routes)
        TrafficAmbient.start(graph, getTrafficDensity)
        if PedServices then PedServices.start(graph) end
        TrafficRoad.start(graph, getTrafficDensity, get("npchlc_traffic.roadPopulationMode"))
        TrafficPolice.start(graph)
        local counts = graph.counts
        outputDebugString(("[npchlc_traffic] Loaded %d pedestrian, %d road and %d boat nodes, %d links and %d routes.")
            :format(counts.peds, counts.cars, counts.boats, counts.links, counts.routes), 3)
    else
        loadTimer = setTimer(continueLoad, 50, 1)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    local enabled = get("npchlc_traffic.enabled")
    TrafficActors.start()
    if enabled == false or enabled == "false" then
        status = "disabled"
        return
    end
    status = "loading"
    graphLoader = coroutine.create(function()
        local path = get("npchlc_traffic.graphFile")
        if type(path) ~= "string" or path == "" then error("Missing traffic graphFile setting", 0) end
        return TrafficGraph.load(path, checkpoint)
    end)
    continueLoad()
end, false)

addEventHandler("onResourceStop", resourceRoot, function()
    if loadTimer then
        killTimer(loadTimer)
    end
    if PedServices then PedServices.stop() end
    TrafficPolice.stop()
    TrafficRoad.stop()
    TrafficAmbient.stop()
    TrafficActors.stop()
    TrafficLights.stop()
    TrafficAircraft.stop()
    TrafficVisibility.stop()
    TrafficDebug.setGraph(nil)
    loadTimer, graphLoader, graph = nil, nil, nil
    status = "stopped"
end, false)

function setTrafficDensity(kind, percent)
    if percent == nil then
        percent, kind = kind, nil
    end
    percent = tonumber(percent)
    if not percent or percent ~= percent or percent < 0 or percent >= math.huge
        or (kind ~= nil and not density[kind]) then
        return false
    end
    if kind then
        density[kind] = percent / 100
    else
        for key in pairs(density) do
            density[key] = percent / 100
        end
    end
    return true
end

function getTrafficDensity(kind)
    return density[kind] or false
end

function getTrafficStatus()
    return status, graph and graph.counts or false, failure
end

function getTrafficPopulationAt(x, y, z, hour, modelSlot)
    return TrafficPopulation.sample(graph and graph.population, x, y, z, hour or getTime(), modelSlot)
end

function chooseTrafficPedestrianStep(nodeId, heading, reachableNodeIds)
    local target, direction = TrafficGraph.pedestrianStep(graph, nodeId, heading, reachableNodeIds)
    return target, direction
end

function findTrafficPedestrianAnchor(x, y, z, previousNodeId)
    return TrafficGraph.pedestrianAnchor(graph, x, y, z, previousNodeId)
end

function setNPCTrafficRoute(ped, nodeIds, loop)
    return TrafficActors.startRoute(graph, ped, nodeIds, loop)
end

function sampleTrafficFlight(routeId, clockMs, slot)
    local route = graph and graph.routes[routeId]
    if not route or route.kind ~= "fixedWing" then
        return false
    end
    return TrafficAircraft.sample(routeId, clockMs, slot)
end

function getTrafficDynamicRoute(routeId)
    return graph and graph.dynamicRoutes[routeId] or false
end

function getTrafficNodePosition(nodeId)
    local node = graph and type(nodeId) == "number" and graph.nodes[nodeId + 1]
    if node then return node.x, node.y, node.z end
    return false
end
