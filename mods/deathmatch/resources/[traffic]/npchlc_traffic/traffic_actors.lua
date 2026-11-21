TrafficActors = {}

local npc = exports.npc_hlc
local actors = {}
local maxRouteNodes = 4096
local arrivalTolerance = 1
local missionSequence = 0
local progressTimer
local routeDoneEvent = "npchlc_traffic:onNPCTrafficRouteDone"
local landVehicle = { Automobile = true, Bike = true, Bicycle = true, ["Monster Truck"] = true, Quad = true }
local interiorScenes = { [0] = "outdoor", [3] = "underground" }

addEvent(routeDoneEvent, false)

local function getTravelKind(ped)
    local vehicle = getPedOccupiedVehicle(ped)
    if not vehicle then
        return "pedestrian"
    end
    if getVehicleOccupant(vehicle, 0) ~= ped then
        return
    end
    local vehicleType = getVehicleType(vehicle)
    if landVehicle[vehicleType] then
        return "vehicle", vehicle
    end
    if vehicleType == "Boat" then
        return "boat", vehicle
    end
end

local function finish(ped, actor, completed)
    actor.route = nil
    if not actor.police then
        actors[ped] = nil
    end
    triggerEvent(routeDoneEvent, ped, completed)
end

local function nextWaypoint(ped, actor)
    local route = actor.route
    local waypoint = route.nodes[route.index]
    if not waypoint and route.loop then
        route.index = 1
        waypoint = route.nodes[1]
    end
    if not waypoint then
        finish(ped, actor, true)
        return true
    end

    local kind, vehicle = getTravelKind(ped)
    if kind ~= route.kind or vehicle ~= route.vehicle or getElementInterior(ped) ~= route.interior then
        finish(ped, actor, false)
        return false
    end
    if route.mission then
        local previous=route.nodes[route.index-1]
        local anchor=previous and {previous[3],previous[4],previous[5]} or route.anchor
        local segments={}
        for i=route.index,math.min(#route.nodes,route.index+7) do segments[#segments+1]=route.nodes[i] end
        route.task={"driveTrafficPhysics",route.sequence+route.index,route.speed,anchor,segments,2}
        route.task.mission=true
    else
        route.task = { kind == "pedestrian" and "walkToPos" or "driveTrafficToPoint",
            waypoint.x, waypoint.y, waypoint.z, arrivalTolerance }
    end
    if not npc:setNPCTask(ped, route.task) then
        finish(ped, actor, false)
        return false
    end
    return true
end

local function findRouteLink(graph, from, to)
    for offset = 1, from.linkCount do
        local link = graph.links[from.firstLink + offset]
        if link.to == to.id and (from.kind == "pedestrian" or (link.lanes or 0) > 0) then
            return link
        end
    end
    return false
end

function TrafficActors.driveMissionPath(ped, segments, speed)
    local kind, vehicle = getTravelKind(ped)
    if kind ~= "vehicle" or not segments or not segments[1] then return false end
    local actor = actors[ped] or {}
    actors[ped] = actor
    actor.route = {nodes=segments,index=1,kind=kind,vehicle=vehicle,interior=getElementInterior(ped),mission=true,
        speed=speed,anchor={getElementPosition(vehicle)},sequence=missionSequence,lastMoved=getTickCount()}
    missionSequence=missionSequence+#segments+1
    return nextWaypoint(ped, actor)
end

function TrafficActors.endMissionPath(ped)
    local actor = actors[ped]
    if actor and actor.route and actor.route.mission then
        actor.route = nil
        if not actor.police then actors[ped] = nil end
        npc:clearNPCTasks(ped)
    end
end

function TrafficActors.startRoute(graph, ped, nodeIds, loop)
    if not graph or not isElement(ped) or getElementType(ped) ~= "ped" or isPedDead(ped)
        or type(nodeIds) ~= "table" or #nodeIds < 2 or #nodeIds > maxRouteNodes
        or (loop ~= nil and type(loop) ~= "boolean") then
        return false
    end
    local kind, vehicle = getTravelKind(ped)
    local interior = getElementInterior(ped)
    local scene = interiorScenes[interior]
    if not kind or not scene then
        return false
    end

    local route = { nodes = {}, index = 1, loop = loop, kind = kind, vehicle = vehicle, interior = interior }
    local previous
    local function addRoadPoint(edge)
        local x, y, z = TrafficGraph.lanePoint(graph, edge, 0)
        if not x then return false end
        route.nodes[#route.nodes + 1] = {x = x, y = y, z = z}
        return true
    end
    for index = 1, #nodeIds do
        local id = nodeIds[index]
        local node = type(id) == "number" and graph.nodes[id + 1]
        if not node or node.kind ~= kind or node.scene ~= scene then
            return false
        end
        if previous then
            local edge = findRouteLink(graph, previous, node)
            if not edge or kind == "vehicle" and not addRoadPoint(edge) then return false end
        end
        if kind ~= "vehicle" or not loop and (index == 1 or index == #nodeIds) then
            route.nodes[#route.nodes + 1] = node
        end
        previous = node
    end
    if loop then
        local edge = findRouteLink(graph, previous, graph.nodes[nodeIds[1] + 1])
        if not edge or kind == "vehicle" and not addRoadPoint(edge) then return false end
    end

    if not npc:isHLCEnabled(ped) and not npc:enableHLCForNPC(ped) then
        return false
    end
    local actor = actors[ped] or {}
    actors[ped] = actor
    actor.route = route
    return nextWaypoint(ped, actor)
end

function TrafficActors.isManagedPed(ped)
    return actors[ped] ~= nil or (TrafficAmbient and TrafficAmbient.isManagedPed(ped))
        or (TrafficRoad and TrafficRoad.isManagedPed(ped)) or false
end

function TrafficActors.isPolicePed(ped)
    local actor = actors[ped]
    return actor and actor.police == true or false
end

function setTrafficPolicePed(ped, police)
    if not isElement(ped) or getElementType(ped) ~= "ped" or type(police) ~= "boolean"
        or (police and isPedDead(ped)) then
        return false
    end
    local actor = actors[ped] or {}
    actor.police = police == true
    actors[ped] = (actor.route or actor.police) and actor or nil
    return true
end

local presenceModels = {[261]=true,[219]=true,[207]=true,[234]=true}
local presencePeds = {[8]=true,[9]=true,[10]=true,[11]=true,[117]=true,[118]=true,[119]=true}
function TrafficActors.isPoliceNearby(player, radius)
    local occupied = getPedOccupiedVehicle(player)
    local x, y, z = getElementPosition(occupied or player)
    for _, ped in ipairs(getElementsWithinRange(x, y, z, radius, "ped",
        getElementInterior(player), getElementDimension(player))) do
        if TrafficActors.isPolicePed(ped) or presencePeds[getElementData(ped, "npchlc_traffic:originalModel", false)] then
            local px, py, pz = getElementPosition(ped)
            local dx, dy, dz = px - x, py - y, pz - z
            if dx * dx + dy * dy + dz * dz < radius * radius then
                return true
            end
        end
    end
    for _, vehicle in ipairs(getElementsWithinRange(x, y, z, radius, "vehicle",
        getElementInterior(player), getElementDimension(player))) do
        if vehicle ~= occupied and not isVehicleBlown(vehicle) then
            local driver = getVehicleOccupant(vehicle)
            local model = getElementData(vehicle, "npchlc_traffic:originalModel", false)
            if presenceModels[model] or (driver and TrafficActors.isPolicePed(driver)) then
                local vx, vy, vz = getElementPosition(vehicle)
                if (vx-x)^2 + (vy-y)^2 + (vz-z)^2 < radius^2 then return true end
            end
        end
    end
    return false
end

local function onTaskDone(task)
    local actor = actors[source]
    local route = actor and actor.route
    local expected = route and route.task
    if not expected then
        return
    end
    -- NPCHLC is a separate resource. The event crosses the Lua VM boundary.
    -- Physics windows are copied between resources. Their sequence number
    -- identifies the window even when its nested lane records have been copied.
    for index = 1, route.mission and 2 or #expected do
        if task[index] ~= expected[index] then
            return
        end
    end
    route.index = route.index + 1
    nextWaypoint(source, actor)
end

local function onPedRemoved()
    actors[source] = nil
end

local function checkMissionProgress()
    local now=getTickCount()
    for ped,actor in pairs(actors) do
        local route=actor.route
        if route and route.mission and isElement(route.vehicle) then
            local x,y=getElementPosition(route.vehicle)
            if not getElementSyncer(route.vehicle) or not route.sampleX or
                (x-route.sampleX)^2+(y-route.sampleY)^2>3^2 then
                route.sampleX,route.sampleY,route.lastMoved=x,y,now
            elseif (now-route.lastMoved)%4294967296>45000 then
                npc:clearNPCTasks(ped)
                finish(ped,actor,false)
            end
        end
    end
end

function TrafficActors.start()
    progressTimer=setTimer(checkMissionProgress,3000,0)
    addEventHandler("npc_hlc:onNPCTaskDone", root, onTaskDone)
    addEventHandler("onPedWasted", root, onPedRemoved, true, "low")
    addEventHandler("onElementDestroy", root, onPedRemoved)
end

function TrafficActors.stop()
    if isTimer(progressTimer) then killTimer(progressTimer) end
    removeEventHandler("npc_hlc:onNPCTaskDone", root, onTaskDone)
    removeEventHandler("onPedWasted", root, onPedRemoved)
    removeEventHandler("onElementDestroy", root, onPedRemoved)
    for ped, actor in pairs(actors) do
        if actor.route and isElement(ped) then
            npc:clearNPCTasks(ped)
        end
    end
    actors = {}
end
