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
local function intersect(from, to, x, y, radius, centerZ)
    local dx, dy, dz = to.x - from.x, to.y - from.y, to.z - from.z
    local lengthSquared = dx * dx + dy * dy + dz * dz
    if lengthSquared == 0 then return false end

    -- 0x00268048 passes a center with the player's XY and zero Z.
    local px, py, pz = x - from.x, y - from.y, (centerZ or 0) - from.z
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

function TrafficAmbient.samplePedestrianEdge(from, to, edge, x, y, radius, chance, positionRoll, centerZ)
    -- 0x00268048 skips disabled nodes and the high-bit adjacency class.
    if edge.flags >= 0x8000 or math.floor(from.flags / 0x20) % 2 == 1
        or math.floor(to.flags / 0x20) % 2 == 1
        or chance > math.min(from.spawnThreshold, to.spawnThreshold) then return false end
    local lower, upper = intersect(from, to, x, y, radius, centerZ)
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

-- 00430290 keeps the observer's zone record when a candidate lands on a water edge.
function TrafficAmbient.chooseBoat(x, y, z, wanted, pursuitAvailable)
    local values = currentPopulationRecord(x, y, z, (getTime()))
    if not values then return false end
    local police = wanted >= 2 and pursuitAvailable and (wanted > 2 or rollBelow(31) > 15)
    if not police then
        for attempt = 1, (wanted > 0 and 5 or 1) do
            police = rollBelow(1000) < values[24]
            if not police then break end
        end
    end
    if police then return TrafficModelBindings.get(219), 219, 23 end
    for attempt = 1, 10 do
        local class = TrafficAmbient.vehicleClass(values, true, 0, rollBelow)
        if not class then return false end
        local original = TrafficAmbient.pickVehicleModel(graph.vehicleModelRules, class, TrafficModelBindings.get, rollBelow)
        if original then
            -- The native predecremented counter expires even on a tenth successful draw.
            if attempt < 10 then return TrafficModelBindings.get(original), original, class end
            break
        end
    end
    return false
end

function TrafficAmbient.zoneBudget(profile, rain)
    -- Ordinary freeroam values at 0x00488004, 0x0048A67C and 0x00487FF8.
    local weatherScale = 1 - math.sqrt(math.max(0, math.min(1, rain))) * 0.8
    return math.min(25, (profile.vehicleDensity + profile.pedestrianDensity) * 0.4 * weatherScale)
end

local function defaultContext(player)
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
        thresholds = values,
    }
end

-- SLUS_215.90 0x002B17A8 tests the police threshold first, then nine
-- cumulative territory thresholds. Custom world providers retain their
-- existing reserved population branches.
local function chooseActor(profile, context, roll)
    if context.thresholds and graph.edition == "SLUS-21590 USA v1.00" then
        if roll < context.policeChance then return 8, true end
        for group = 1, 9 do
            local threshold = context.thresholds[25 + group]
            if roll < threshold then
                if threshold ~= 1000 and math.random(0, 1) == 0 then break end
                local modelsForGang = graph.population.gangModels and graph.population.gangModels[group]
                if not modelsForGang then return end
                local model = modelsForGang[math.random(1, 2)]
                -- 0x002B3B90 selects a single ped for territory type 11.
                if group == 5 then return model, false, 1 end
                local clustered = math.random() >= 0.333
                local formation = clustered and (group == 4 and "cluster" or "chat") or "follow"
                return model, false, math.random(2, 3), modelsForGang, formation
            end
        end
    elseif roll < math.max(context.groupChance, context.policeChance) then
        return
    end
    if math.random() <= 0.95 then return profile.originalModelId end
    if graph.edition == "SLUS-21590 USA v1.00" then
        local group = graph.population.pedGroups[profile.pedestrianGroupId + 1]
        local man, woman = PedSocial.pickPair(group, TrafficAmbient.getPedestrianModel, math.random)
        if man then return man, false, 2, {woman, woman}, "couple" end
    end
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

local function collectCandidate(player, context, targeted, stinger)
    local x, y, z = getElementPosition(player)
    local profile = TrafficPopulation.sample(graph.population, x, y, z, getTime(), math.random(0, 15))
    if not profile then return false end
    local roll = math.random(0,999)
    local originalId, police, groupSize, gangModels, formation = chooseActor(profile, context,roll)
    if targeted then originalId,police,groupSize,gangModels,formation=8,true,nil,nil,nil end
    local model = originalId and TrafficAmbient.getPedestrianModel(originalId)
    if not model then return false end

    local speed = TrafficVisibility.pedestrianScale(player)
    local visibleMin, visibleMax = speed * 35 * context.streamingDistanceScale, speed * 60 * context.streamingDistanceScale
    local hiddenMin, hiddenMax = speed * 20 - 10, speed * 20
    local chance, visited = math.random(0, 15), 0
    local underground = z < -50
    local indoors = underground or getElementInterior(player) ~= 0
    local scene = underground and "underground" or "outdoor"
    local function visit(from)
        if from.scene ~= scene or getDistanceBetweenPoints2D(x, y, from.x, from.y) > 160 then return end
        for offset = 1, from.linkCount do
            local edge = graph.links[from.firstLink + offset]
            local to = graph.nodes[edge.to + 1]
            if to.scene == scene then
                local px, py, pz = TrafficAmbient.samplePedestrianEdge(from, to, edge, x, y, visibleMax, chance,
                    math.random(0, 255), indoors and z or 0)
                if px and (not indoors or math.abs(pz-z)<=3) then
                    local distance = getDistanceBetweenPoints2D(x, y, px, py)
                    if (visibleMin < distance and distance < visibleMax)
                        or (hiddenMin < distance and distance < hiddenMax) then
                        local originalId,police,groupSize,gangModels,formation,model =
                            originalId,police,groupSize,gangModels,formation,model
                        if context.thresholds and graph.edition == "SLUS-21590 USA v1.00" and not police then
                            local values,destination = currentPopulationRecord(px,py,pz,getTime())
                            if destination and destination.zoneId ~= profile.zoneId then
                                originalId,police,groupSize,gangModels,formation = chooseActor(profile,
                                    {thresholds=values,policeChance=0},roll)
                                model = originalId and TrafficAmbient.getPedestrianModel(originalId)
                                if not model then return end
                            end
                        end
                        return {x = px, y = py, z = pz, from = from, to = to, model = model,
                            originalModelId = originalId, police = police, targeted = targeted, stinger = stinger, groupSize = groupSize,
                            gangModels = gangModels, formation = formation, started = getTickCount(),
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
            if from.scene == scene then
                visited = visited + 1
                if visited > 150 then return end
                local candidate = visit(from)
                if candidate then return candidate end
            end
        end
    end
end

local function removeActor(ped, fade)
    local state = actors[ped]
    if not state then return end
    if PedCarService then PedCarService.relinquish(ped) end
    actors[ped] = nil
    actorCount = actorCount - 1
    PedSocial.interrupt(ped,state)
    PedActivity.cancel(ped)
    PedAI.detach(ped)
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
        or link.pedestrianSignal == nil and math.floor(link.flags/0x4000)%2 == 1)
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
    local target = graph.nodes[candidate.destination+1]
    local facing = math.deg(math.atan2(candidate.finalX-target.x,target.y-candidate.finalY))
    if candidate.formation == "couple" and isElement(candidate.leader) then
        local _,_,heading = getElementRotation(candidate.leader)
        facing = heading
    end
    local ped = createPed(candidate.model, candidate.finalX, candidate.finalY, candidate.groundZ+0.7, facing)
    if not ped then return end
    setElementInterior(ped, getElementInterior(player))
    setElementDimension(ped, getElementDimension(player))
    TrafficModelBindings.tag(ped, candidate.originalModelId)
    if not hlc:enableHLCForNPC(ped, "walk") then
        destroyElement(ped)
        return
    end
    local state = {owner = player, queued = 0, originalModelId = candidate.originalModelId}
    local heading = headingFor(target.x - candidate.finalX, target.y - candidate.finalY)
    if not walkToNode(ped, state, target, heading) then destroyElement(ped) return end
    actors[ped] = state
    actorCount = actorCount + 1
    TrafficVisibility.track(ped, "pedestrian")
    PedAI.attach(ped, graph.modelIdSpace ~= "mta" and candidate.originalModelId or nil)
    if candidate.police then
        setTrafficPolicePed(ped, true)
        if candidate.stinger and getPlayerWantedLevel(player)>2 then
            TrafficGroundPolice.prepareStinger(ped,player,candidate.from,candidate.to,target)
        end
    end
    if not candidate.gangModels and graph.edition == "SLUS-21590 USA v1.00" then
        PedActivity.onSpawn(ped, state, candidate.originalModelId)
    end
    return ped
end

function TrafficAmbient.suspend(ped)
    if PedCarService then PedCarService.relinquish(ped) end
    local state = actors[ped]
    if not state then return end
    PedAmbientWait.cancel(ped, state)
    state.bikePassenger,state.bikeApproach=nil,nil
    if state.roadFall then
        setPedAnimation(ped)
        state.roadFall=nil
    end
    PedMugging.cancel(ped, state)
    PedTheft.cancel(ped, state)
    PedSocial.interrupt(ped, state)
    PedActivity.cancel(ped)
    hlc:clearNPCTasks(ped)
    state.queued, state.anchor, state.blockedSince, state.crossing = 0, nil, nil, nil
    -- A wait can begin and end between two visits by the actor scheduler.
    state.behaviorOwned = true
end

function TrafficAmbient.resumeWander(ped, heading)
    local state = actors[ped]
    if state then
        state.heading = heading
        state.behaviorOwned, state.rejoining = true, true
    end
end

function TrafficAmbient.isWaiting(ped)
    local state = actors[ped]
    return state and state.wait ~= nil or false
end

function TrafficAmbient.debugTask(ped)
    local walk = actors[ped]
    if not walk then return end
    if walk.chatAnim then return "chat", walk.gesture or "listening" end
    if walk.leader then return "formation" end
    return "pedestrian"
end

function TrafficAmbient.isManagedPed(ped)
    return actors[ped] ~= nil
end

function TrafficAmbient.isRecovering(ped)
    local walk=actors[ped]
    return walk and (walk.roadFall or walk.hitAt)
end

function TrafficAmbient.adoptDriver(ped, player, vehicle, originalModelId, roadState, recoveryMs)
    if not graph or not isElement(ped) or isPedDead(ped) then return false end
    if actors[ped] then return true end
    local _, _, rotation = getElementRotation(ped)
    actors[ped] = {owner = player or getElementSyncer(ped), queued = 0, hitAt = recoveryMs and getTickCount(), recoveryMs = recoveryMs,
        originalModelId = originalModelId, heading = math.floor(-rotation / 45 + 0.5) % 8}
    actorCount = actorCount + 1
    hlc:clearNPCTasks(ped)
    hlc:setNPCWalkSpeed(ped, "walk")
    TrafficVisibility.track(ped, "pedestrian")
    if player then PedAI.carjacked(ped, player, vehicle, roadState) end
    return true
end

function TrafficAmbient.releaseDriver(ped)
    if not actors[ped] then return false end
    actors[ped] = nil
    actorCount = actorCount - 1
    PedActivity.cancel(ped)
    return true
end

function TrafficAmbient.bikeFall(ped,impact,launch,road,passenger)
    local walk=actors[ped]
    if walk then PedRoadInjury.startBike(ped,walk,impact,launch,road,passenger) end
end

addEvent("npchlc_traffic:pedRoadContact",true)
addEventHandler("npchlc_traffic:pedRoadContact",resourceRoot,function(ped,car,impulse,normalZ,hx,hy,hz)
    local walk=actors[ped]
    if not client or not walk or not isElement(car) or getElementType(car)~="vehicle"
        or (getElementSyncer(ped)~=client and getVehicleOccupant(car,0)~=client)
        or not finite(impulse) or impulse<=0 or not finite(normalZ) or math.abs(normalZ)>1.001
        or isPedDead(ped) or isPedInVehicle(ped)
        or PedAI.isScriptControlled(ped) or getElementInterior(ped)~=getElementInterior(car)
        or getElementDimension(ped)~=getElementDimension(car) then return end
    local x,y,z=getElementPosition(ped)
    if not finite(hx) or not finite(hy) or not finite(hz) then return end
    local px,py,pz=getElementVelocity(ped)
    local dt=math.max(0,math.min(12,((x-hx)*px+(y-hy)*py+(z-hz)*pz)/math.max(.001,px*px+py*py+pz*pz)))
    if (x-hx-dt*px)^2+(y-hy-dt*py)^2+(z-hz-dt*pz)^2>8^2 then return end
    local vx,vy,vz=TrafficRoad.pedContactMotion(car,getTickCount(),hx,hy,hz)
    if vx then PedRoadInjury.strike(ped,walk,car,impulse,normalZ,vx,vy,vz) end
end,false)

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
    if state.rejoining then
        local candidates=TrafficGraph.pedestrianEntryPoints(graph,x,y,z,state.failedAnchor)
        if #candidates==0 then return false end
        local reachable=query("getTrafficPedestrianReachable",player,ped,candidates[1].id,candidates,nil,true)
        if reachable==nil then return end
        if type(reachable)~="table" then return false end
        local visible={}
        for _,id in ipairs(reachable) do visible[id]=true end
        for _,node in ipairs(candidates) do
            if visible[node.id] then
                if (node.x-x)^2+(node.y-y)^2>1 then
                    if not walkToNode(ped,state,node,headingFor(node.x-x,node.y-y)) then return false end
                    state.rejoining,state.failedAnchor=nil,nil
                    return true
                end
                state.anchor=node.id
                state.rejoining,state.failedAnchor=nil,nil
                break
            end
        end
        if state.rejoining then return false end
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
    if not targetId or targetId == nodeId then
        if graph.edition == "SLUS-21590 USA v1.00" and state.queued == 0 then
            state.rejoining,state.failedAnchor=true,nodeId
            PedAmbientWait.start(ped,state,8,getTickCount())
            return true
        end
        return false
    end
    local target = graph.nodes[targetId+1]
    if graph.edition == "SLUS-21590 USA v1.00" and link and link.flags >= 0x4000 then
        if state.queued > 0 then return end
        local signal = math.floor(link.flags/0x4000)%2 == 1
        PedAmbientWait.start(ped,state,signal and 1 or 2,getTickCount(),{target,heading,node,link})
        return true
    end
    return walkToNode(ped, state, target, heading, node, link)
end

local actorCursor
local function resetWalk(state)
    state.queued, state.blockedSince, state.retryAt = 0, nil, nil
    state.crossing, state.nextCrossing, state.anchor = nil, nil, nil
end

local function onDamage(loss)
    local state = actors[source]
    if not state or PedAI.isScriptControlled and PedAI.isScriptControlled(source) or loss <= 0 or isPedInVehicle(source) then return end
    -- Standing melee and bullet hits do not require a collision landing.
    -- A late native damage notification must not clear the new combat task.
    if isPedOnGround(source) or state.roadFall then
        PedAI.damaged(source,loss)
        return
    end
    if PedCarService then PedCarService.cancel(source) end
    PedAmbientWait.cancel(source, state)
    PedMugging.cancel(source, state)
    PedTheft.cancel(source, state)
    PedSocial.interrupt(source, state)
    PedActivity.cancel(source)
    if state.queued > 0 then hlc:clearNPCTasks(source) end
    -- Let the native collision task keep its velocity and animation. Re-anchor
    -- from the landing position instead of resuming the previous walk target.
    resetWalk(state)
    state.hitAt = state.hitAt or getTickCount()
    PedAI.damaged(source, loss)
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

local function updateBehavior(ped,state,now)
    if TrafficCustody and TrafficCustody.isArresting(ped) then return true end
    if state.hitAt and not state.roadFall then
        local elapsed = (now - state.hitAt) % 4294967296
        if elapsed < (state.recoveryMs or hitRecoveryMs) or (not isPedOnGround(ped) and elapsed < 2500) then return true end
        state.hitAt, state.recoveryMs, state.blockedSince = nil, nil, now
        state.behaviorOwned = true
    end
    if state.roadFall then
        PedRoadInjury.update(ped,state,now)
    elseif state.bikePassenger and not PedAI.busy(ped) and TrafficPassengers.returnToBike(ped,state,now) then
        -- The passenger owns this approach until the native seat is occupied.
    elseif PedAI.busy(ped) then
        local brain = PedAI.brain(ped)
        local event = brain and brain.event
        if event and event.kind=="gunshot" and not event.consumed
            and (now-event.started)%4294967296 < brain.reactionDelay and not brain.wait then
            return true
        end
        if PedCarService then PedCarService.cancel(ped) end
        if PedServices then PedServices.interrupt(ped) end
        PedAmbientWait.cancel(ped, state)
        PedMugging.cancel(ped, state)
        PedTheft.cancel(ped, state)
        PedSocial.interrupt(ped, state)
        if not PedActivity.leaveForThreat(ped, state, now) then
            PedActivity.cancel(ped)
            resetWalk(state)
            PedAI.update(ped, graph)
            state.blockedSince = now
        end
    elseif state.rejoining then
        return false
    elseif graph.edition == "SLUS-21590 USA v1.00" and PedCarService and PedCarService.update(ped,state,now) then
        resetWalk(state)
    elseif state.wait and PedAmbientWait.update(ped,state,now,walkToNode) then
        return true -- A crossing wait resumes its own stored route.
    elseif graph.edition == "SLUS-21590 USA v1.00" and PedServices and PedServices.update(ped,state.originalModelId,now) then
        resetWalk(state)
        state.blockedSince=now
    elseif graph.edition == "SLUS-21590 USA v1.00" and PedTheft.update(ped,state,now) then
        -- The native vehicle-entry animation owns movement.
    elseif graph.edition == "SLUS-21590 USA v1.00" and PedMugging.update(ped,state,actors,now) then
        -- Objective 0x25 owns the approach and gesture.
    elseif (state.partner or state.leader or state.gatherLeader) and PedSocial.update(ped,state,now,actors) then
        -- A conversation or follow objective owns this actor.
    elseif graph.edition == "SLUS-21590 USA v1.00" and state.queued > 0
        and not PedActivity.active(ped) and PedSocial.meet(ped,state,actors,now) then
        PedSocial.update(ped,state,now,actors)
    elseif graph.edition == "SLUS-21590 USA v1.00" and (PedActivity.active(ped) or (state.queued>0 and not state.behaviorOwned and not state.rejoining))
        and PedActivity.update(ped, state, now) then
        -- The activity owns movement until its exit or interruption.
    else
        return false
    end
    state.behaviorOwned=true
    return true
end

local reactions = {}
local directKinds = {damage=true,gunpoint=true,carjack=true,passenger=true,vehicleThreat=true,roadRage=true}

function TrafficAmbient.scheduleReaction(ped,event)
    local direct = directKinds[event.kind]==true and getElementType(event.target)=="player"
    reactions[ped] = {event=event,direct=direct}
end

function TrafficAmbient.wakeReaction(ped,event)
    local brain,state = PedAI.brain(ped),actors[ped]
    if not state or not brain or brain.event~=event or brain.scriptOwner or isPedDead(ped) then return end
    updateBehavior(ped,state,getTickCount())
    if event.task or event.consumed then reactions[ped]=nil end
end

local function dispatchReactions(now,direct)
    local remaining = 8
    for ped,entry in pairs(reactions) do
        local brain = PedAI.brain(ped)
        local event = entry.event
        if not actors[ped] or not brain or brain.event~=event or brain.scriptOwner or isPedDead(ped)
            or event.task or event.consumed then
            reactions[ped]=nil
        elseif entry.direct==direct and (direct or remaining>0) and (event.kind~="gunshot"
            or (now-event.started)%4294967296 >= brain.reactionDelay) then
            if not entry.direct then remaining=remaining-1 end
            TrafficAmbient.wakeReaction(ped,event)
        end
    end
end

local function updateWander(ped,state,x,y,now)
    if state.behaviorOwned then
        -- All special objectives yield here. An NPC that just regained a seat
        -- belongs to the vehicle controller until it comes back on foot.
        hlc:clearNPCTasks(ped)
        resetWalk(state)
        hlc:setNPCWalkSpeed(ped,"walk")
        state.failedAnchor=nil
        state.behaviorOwned,state.rejoining=nil,true
        state.blockedSince=now
    end
    if state.queued>0 and (not state.queueChecked or (now-state.queueChecked)%4294967296>=500) then
        state.queueChecked=now
        state.queued=math.min(state.queued,hlc:getNPCTaskCount(ped))
        if state.queued==0 then
            resetWalk(state)
            state.rejoining,state.blockedSince=true,now
        end
    end
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

local function updateActors()
    local now = getTickCount()
    for _ = 1, math.min(8, actorCount) do
        if actorCursor and not actors[actorCursor] then actorCursor = nil end
        local ped, state = next(actors, actorCursor)
        actorCursor = ped
        if not ped then break end
        if PedAI.isScriptControlled and PedAI.isScriptControlled(ped) then
            state.behaviorOwned=true
            if PedServices then PedServices.relinquish(ped) end
            -- Mission controller owns tasks, lifetime and animations.
        elseif isPedDead(ped) then
            PedActivity.cancel(ped)
            TrafficVisibility.keepDeadPed(ped)
        else
            PedAI.sampleHealth(ped)
            local x, y, z = getElementPosition(ped)
            if not hasNearbyObserver(ped, x, y, z) then
                removeActor(ped)
            elseif not updateBehavior(ped,state,now) and actors[ped]==state and not isPedInVehicle(ped) then
                updateWander(ped,state,x,y,now)
            end
        end
    end
end

local function cancelFormation(candidate)
    if candidate.leader and candidate.groupIndex == 1 and (candidate.formation == "chat" or candidate.formation == "couple" or candidate.formation == "cluster")
        and actors[candidate.leader] and not (PedAI.isScriptControlled and PedAI.isScriptControlled(candidate.leader)) then
        removeActor(candidate.leader)
    end
end

local function continueCandidate(player, candidate)
    if not isElement(player) then cancelFormation(candidate) pending[player] = nil return end
    local x, y = getElementPosition(player)
    if (getTickCount() - candidate.started) % 4294967296 > attemptTimeout
        or candidate.interior ~= getElementInterior(player) or candidate.dimension ~= getElementDimension(player)
        or TrafficAmbient.getPedestrianModel(candidate.originalModelId) ~= candidate.model
        or candidate.targeted and getPlayerWantedLevel(player)<3
        or getDistanceBetweenPoints2D(x, y, candidate.playerX, candidate.playerY) > (candidate.stinger and 12 or 2) then
        cancelFormation(candidate)
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
                    local info = graph.edition == "SLUS-21590 USA v1.00" and PedAIModels[candidate.originalModelId]
                    if info and info[2] == 39 and not probe.skatable then break end
                    if candidate.leaderGround and candidate.formation == "follow"
                        and math.abs(candidate.groundZ-candidate.leaderGround) > 1 then break end
                    local limits = not candidate.leader and candidate.gangModels and info and PedGangLimits[info[1]]
                    if limits then
                        local count = 0
                        for _,neighbor in ipairs(getElementsWithinRange(candidate.finalX,candidate.finalY,candidate.groundZ,
                            limits[1],"ped",candidate.interior,candidate.dimension) or {}) do
                            local profile = PedAI.profile(neighbor)
                            if profile and profile.pedType >= 7 and profile.pedType <= 15 then count=count+1 end
                        end
                        if count >= limits[2] then break end
                    end
                    local ped = saveActor(player, candidate)
                    if ped and candidate.gangModels then
                        if candidate.leader then
                            local slot = candidate.formation == "couple" and 7 or candidate.formation == "follow" and candidate.groupIndex
                            local joined = PedSocial.bind(candidate.leader, ped, actors, candidate.formation == "chat" and candidate.groupSize == 1, slot,candidate.slotX,candidate.slotY)
                            if joined and candidate.formation == "chat" and candidate.groupSize > 1 then
                                actors[ped].gatherLeader = candidate.leader
                            end
                        else candidate.leader,candidate.leaderGround = ped,candidate.groundZ end
                    end
                    if ped and candidate.groupSize and candidate.groupSize > 1 then
                        -- Admit companions through the same ground, clearance,
                        -- dimension and population checks as their leader.
                        candidate.groupSize = candidate.groupSize - 1
                        candidate.groupIndex = (candidate.groupIndex or 0) + 1
                        candidate.finalX,candidate.finalY = PedSocial.formationPoint(candidate,candidate.groupIndex)
                        candidate.originalModelId = candidate.gangModels[math.random(1, 2)]
                        candidate.model = TrafficAmbient.getPedestrianModel(candidate.originalModelId)
                        if candidate.model and candidate.finalX then pending[player] = candidate end
                    end
                    if ped and (not candidate.groupSize or candidate.groupSize == 1 and not pending[player]) then
                        candidate.complete = true
                    end
                    break
                end
            end
        end
        if not pending[player] and not candidate.complete then cancelFormation(candidate) end
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
    if candidate.gangModels then
        candidate.centerX,candidate.centerY,candidate.total = candidate.finalX,candidate.finalY,candidate.groupSize
        candidate.finalX,candidate.finalY = PedSocial.formationPoint(candidate,0)
    end
    candidate.groundZ = probe.groundZ
    -- SLUS_215.90 0x002B17A8 samples a wander heading after finding the spawn.
    candidate.endpoints = spawnEndpoints(candidate.from, candidate.to, math.random(0, 7))
    pending[player] = candidate
end

local function tick()
    local now = getTickCount()
    dispatchReactions(now,true)
    dispatchReactions(now,false)
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
    local targeted,stinger
    if graph.edition=="SLUS-21590 USA v1.00" and TrafficGroundPolice and getPlayerWantedLevel(player)>2 then
        targeted,stinger=TrafficGroundPolice.footCandidate(player)
        if targeted then
            local _,response=TrafficGroundPolice.response(player)
            cap=cap+response.pursuitPedLimit
        end
    end
    if not hasPedestrianSpace(x, y, z, interior, dimension, cap) then return end
    local candidate = collectCandidate(player, context, targeted, stinger)
    if not candidate then return end
    candidate.cap, candidate.playerZ = cap, z
    pending[player] = candidate
    continueCandidate(player, candidate)
end

local function onTaskDone(task)
    local actor = actors[source]
    if not actor or PedAI.isScriptControlled and PedAI.isScriptControlled(source) or (task[1] ~= "walkTrafficToPoint" and task[1] ~= "walkTrafficCrossing") then return end
    actor.queued = math.max(0, actor.queued - 1)
    actor.crossing, actor.nextCrossing = actor.nextCrossing, nil
    if actor.queued == 0 then actor.blockedSince = getTickCount() end
end

local function onDestroy()
    if actors[source] then
        PedActivity.cancel(source)
        PedAI.detach(source)
        PedAmbientWait.cancel(source, actors[source])
        PedMugging.cancel(source, actors[source])
        PedTheft.cancel(source, actors[source])
        actors[source] = nil
        actorCount = actorCount - 1
    end
end

local function onQuit()
    if pending[source] then cancelFormation(pending[source]) end
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
    PedActivity.stop()
    reactions={}
    graph, density, timer, pending, actorCursor, pendingCursor = nil, nil, nil, {}, nil, nil
end
