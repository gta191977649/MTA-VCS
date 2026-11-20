TrafficPolice = {}

local route
local provider
local timer
local pursuits, attempts, candidates, pending, boats = {}, {}, {}, {}, {}
local nextProbe = 0
local step = 0
local stats = {active = 0, waitingForProvider = false, waitingForModels = false}
local spawnBudget = 4

-- Providers are trusted server resources. Terrain returns a height, true on a
-- completed ray miss, or false if collision is unavailable.
function registerTrafficPoliceProvider()
    if not sourceResource then return false end
    if provider and provider ~= sourceResource and getResourceState(provider) == "running" then return false end
    provider = sourceResource
    return true
end

function getTrafficPoliceStatus()
    return stats
end

function getTrafficPoliceFlightIntent(...)
    return TrafficPoliceFlight.intent(...)
end

function getTrafficPoliceFlightControls(...)
    return TrafficPoliceFlight.controls(...)
end

local function finishPursuit(pursuit)
    TrafficVisibility.releasePed(pursuit.pilot)
    local helicopter = pursuit.heli
    if not isElement(helicopter) or TrafficVisibility.isWreck(helicopter) then return end
    if pursuit.taken or TrafficVisibility.hasPlayerOccupant(helicopter) then
        TrafficVisibility.detach(helicopter)
        TrafficRoad.retainPlayerVehicle(helicopter)
    elseif not getVehicleOccupant(helicopter, 0) then
        destroyElement(helicopter)
    end
end

local function removePursuit(player, fade)
    local pursuit = pursuits[player]
    if not pursuit then return end
    pursuits[player] = nil
    TrafficPoliceResponse.release(pursuit)
    if isElement(pursuit.heli) then removeElementData(pursuit.heli, "traffic:policeMission") end
    stats.active = stats.active - 1
    local helicopter = pursuit.heli
    if fade and isElement(helicopter) and not TrafficVisibility.isWreck(helicopter) and getElementSyncer(helicopter)
        and not TrafficVisibility.hasPlayerOccupant(helicopter) then
        TrafficVisibility.retire(helicopter, pursuit.pilot, function() finishPursuit(pursuit) end)
    else
        finishPursuit(pursuit)
    end
end

local function queryModel(id)
    return TrafficModelBindings and TrafficModelBindings.get(id)
end

local function eligible(player)
    local level = getPlayerWantedLevel(player)
    if level < route.minWantedLevel or isPedDead(player) or getElementInterior(player) ~= route.originalArea then return false end
    local response = TrafficWanted.getPoliceResponse(level, player)
    return response and response.policeHelicopters > 0
end

local function externalProvider()
    return provider and getResourceState(provider) == "running" and provider
end

local function mission(vehicle, player, kind, level)
    setElementData(vehicle, "traffic:policeMission", {player, kind, level}, "broadcast", "deny")
end

local function spawn(player, x, y, floor)
    if pursuits[player] or not eligible(player) then return end
    local vehicleModel = queryModel(route.originalModelId)
    local pedModel = TrafficAmbient.getPedestrianModel(route.pilotModelId)
    if not vehicleModel or not pedModel then return end
    local px, py, targetZ = getElementPosition(player)
    if (x - px)^2 + (y - py)^2 > 330^2 then return end
    local z = TrafficPoliceFlight.spawnAltitude(route, targetZ, type(floor) == "number" and floor or nil)
    local heli = createVehicle(vehicleModel, x, y, z)
    if not heli then return end
    -- SLUS-21590 model 261 has one paint pair, palette entries 46 and 1.
    if route.originalModelId == 261 then setVehicleColor(heli,157,152,114,188,188,180) end
    local pilot = createPed(pedModel, x, y, z)
    if not pilot then
        destroyElement(heli)
        return
    end
    TrafficModelBindings.tag(pilot, route.pilotModelId)
    TrafficModelBindings.tag(heli, route.originalModelId)
    local dimension = getElementDimension(player)
    setElementDimension(heli, dimension)
    setElementDimension(pilot, dimension)
    if not warpPedIntoVehicle(pilot, heli, 0) then
        destroyElement(pilot)
        destroyElement(heli)
        return
    end
    setTrafficPolicePed(pilot, true)
    TrafficVisibility.track(heli, "aircraft")
    TrafficVisibility.track(pilot, "aircraft")
    setVehicleEngineState(heli, true)
    local pursuit = {heli = heli, pilot = pilot, player = player, dimension = dimension, remaining = 4}
    pursuits[player] = pursuit
    stats.active = stats.active + 1
    pursuit.usedAdapter = externalProvider()
    if not pursuit.usedAdapter then mission(heli, player, "air") end
end

local function attempt(player, now)
    local available = queryModel(route.originalModelId) and TrafficAmbient.getPedestrianModel(route.pilotModelId)
    stats.waitingForModels = not available
    if not available then return end
    local adapter = externalProvider()
    if not adapter and not TrafficWorld.isReady(player) then return end
    attempts[player] = now
    if pursuits[player] then return end
    local x, y = getElementPosition(player)
    x, y = TrafficPoliceFlight.spawnPoint(route, x, y, math.random(0, 255))
    if adapter then
        local floor = call(adapter, "getPoliceTerrainHeight", x, y, player)
        if floor == true or type(floor) == "number" and floor >= -1000 and floor <= 1000 then spawn(player, x, y, floor) end
    else
        nextProbe = nextProbe + 1
        pending[player] = {id = nextProbe, at = now, x = x, y = y, dimension = getElementDimension(player)}
        triggerClientEvent(player, "traffic:policeTerrain", resourceRoot, nextProbe, x, y)
    end
    return true
end

addEvent("traffic:policeTerrainResult", true)
addEventHandler("traffic:policeTerrainResult", resourceRoot, function(id, floor)
    local request = pending[client]
    if not request or request.id ~= id then return end
    pending[client] = nil
    if (getTickCount() - request.at) % 4294967296 > 2500 or getElementDimension(client) ~= request.dimension then return end
    if floor ~= true and (type(floor) ~= "number" or not (floor >= -1000 and floor <= 1000)) then return end
    spawn(client, request.x, request.y, floor)
end, false)

function TrafficPolice.assignBoat(boat, driver, player)
    if not route or not isElement(boat) or getVehicleOccupant(boat, 0) ~= driver or not isElement(player)
        or getElementType(player) ~= "player" or getPlayerWantedLevel(player) < 2 then return false end
    if boats[boat] and boats[boat].player == player then return true end
    TrafficPolice.releaseBoat(boat)
    boats[boat] = {boat = boat, pilot = driver, player = player, burst = 20}
    mission(boat, player, "boat", getPlayerWantedLevel(player))
    return true
end

function TrafficPolice.releaseBoat(boat)
    if not boats[boat] then return end
    TrafficPoliceResponse.release(boats[boat])
    boats[boat] = nil
    if isElement(boat) then removeElementData(boat, "traffic:policeMission") end
end

function TrafficPolice.isBoatAssigned(boat)
    return boats[boat] ~= nil
end

function TrafficPolice.assignment(player, vehicle)
    local state = pursuits[player]
    if state and state.heli == vehicle then return state end
    state = boats[vehicle]
    if state and state.player == player then return state end
end

local function updatePursuit(player, pursuit, now)
    local heli = pursuit.heli
    if not isElement(heli) or not isElement(pursuit.pilot) or getVehicleOccupant(heli, 0) ~= pursuit.pilot then
        pursuit.taken = isElement(heli) and isElement(getVehicleOccupant(heli, 0))
        removePursuit(player)
        return
    end
    if getElementDimension(player) ~= pursuit.dimension or getElementInterior(player) ~= route.originalArea then
        removePursuit(player)
        return
    end
    local adapter = externalProvider()
    if adapter and not pursuit.usedAdapter then removeElementData(heli, "traffic:policeMission") end
    if not adapter and pursuit.usedAdapter then mission(heli, player, pursuit.retiring and "retire" or "air") end
    if not pursuit.retiring and (not eligible(player) or getElementHealth(heli) < 230 or isPedDead(pursuit.pilot)) then
        pursuit.retiring = true
        TrafficPoliceResponse.release(pursuit)
        if not adapter then mission(heli, player, "retire") end
    end
    local x, y, z = getElementPosition(heli)
    local px, py, pz = getElementPosition(player)
    local dx, dy, dz = px - x, py - y, pz - z
    if pursuit.retiring and dx * dx + dy * dy + dz * dz > route.retireDistance^2 then
        removePursuit(player, true)
    elseif adapter then
        if not call(adapter, "controlPoliceHelicopter", heli, pursuit.pilot, player, pursuit.retiring == true) then
            removePursuit(player, true)
        end
    elseif not getElementSyncer(heli) then
        -- The 250-unit spawn ring can be outside a client's streaming radius.
        -- Advance the unsimulated craft until native sync takes over.
        local elapsed = math.min((now - (pursuit.lastMove or now)) % 4294967296, 1000)
        local reach = elapsed * 0.019
        if not pursuit.retiring then reach = math.min(math.sqrt(dx * dx + dy * dy), reach) end
        local bearing = math.atan2(dy, dx) + (pursuit.retiring and math.pi or 0)
        setElementRotation(heli, 0, 0, math.deg(bearing) - 90)
        setElementPosition(heli, x + math.cos(bearing) * reach, y + math.sin(bearing) * reach, z)
    end
    pursuit.usedAdapter, pursuit.lastMove = adapter, now
end

local function tick()
    step = (step + 1) % 5
    local now = getTickCount()
    for player, state in pairs(pursuits) do
        if step == 0 then updatePursuit(player, state, now) end
        if pursuits[player] then TrafficPoliceResponse.air(state, now) end
    end
    for boat, state in pairs(boats) do
        local player = state.player
        if not isElement(boat) or not isElement(player) or not isElement(state.pilot) or isPedDead(state.pilot)
            or getVehicleOccupant(boat, 0) ~= state.pilot or isPedDead(player) or getPlayerWantedLevel(player) == 0
            or getElementDimension(boat) ~= getElementDimension(player) or getElementInterior(boat) ~= getElementInterior(player) then
            TrafficPolice.releaseBoat(boat)
        else
            TrafficPoliceResponse.boat(state, now)
        end
    end
    TrafficPoliceResponse.descend(now)
    if step ~= 0 then return end
    local count = 0
    for player in pairs(candidates) do
        if (not attempts[player] or (now-attempts[player])%4294967296 > route.spawnAttemptMs)
            and eligible(player) and attempt(player, now) then
            count = count + 1
            if count >= spawnBudget then break end
        end
    end
end

local function wantedChanged(_, level)
    if level == 0 then TrafficPoliceResponse.clear(source) end
    candidates[source] = level >= route.minWantedLevel or nil
    if not candidates[source] then pending[source] = nil end
    for boat, state in pairs(boats) do
        if state.player == source then
            if level == 0 then TrafficPolice.releaseBoat(boat)
            else mission(boat, source, "boat", level) end
        end
    end
end

local function playerLeft()
    TrafficPoliceResponse.clear(source)
    removePursuit(source)
    attempts[source], candidates[source], pending[source] = nil, nil, nil
    for boat, state in pairs(boats) do if state.player == source then TrafficPolice.releaseBoat(boat) end end
end

function TrafficPolice.start(graph)
    route = graph.policeFlight
    if not route then return end
    for _, player in ipairs(getElementsByType("player")) do
        if getPlayerWantedLevel(player) >= route.minWantedLevel then candidates[player] = true end
    end
    addEventHandler("onPlayerWanted", root, wantedChanged)
    addEventHandler("onPlayerQuit", root, playerLeft)
    timer = setTimer(tick, 100, 0)
end

function TrafficPolice.stop()
    if timer then
        killTimer(timer)
        removeEventHandler("onPlayerWanted", root, wantedChanged)
        removeEventHandler("onPlayerQuit", root, playerLeft)
    end
    for player in pairs(pursuits) do removePursuit(player) end
    for boat in pairs(boats) do TrafficPolice.releaseBoat(boat) end
    TrafficPoliceResponse.clear()
    timer, route = nil, nil
    attempts, candidates, pending = {}, {}, {}
end
