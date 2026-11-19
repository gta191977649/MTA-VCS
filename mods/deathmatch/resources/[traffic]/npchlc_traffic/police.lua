TrafficPolice = {}

local route
local provider
local timer
local pursuits, attempts = {}, {}
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
    if not isElement(helicopter) then return end
    if pursuit.taken or TrafficVisibility.hasPlayerOccupant(helicopter) then
        TrafficVisibility.detach(helicopter)
    elseif not getVehicleOccupant(helicopter, 0) then
        destroyElement(helicopter)
    end
end

local function removePursuit(player, fade)
    local pursuit = pursuits[player]
    if not pursuit then return end
    pursuits[player] = nil
    stats.active = stats.active - 1
    local helicopter = pursuit.heli
    if fade and isElement(helicopter) and getElementSyncer(helicopter)
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
    local wanted = getPlayerWantedLevel(player)
    return not isPedDead(player) and getElementInterior(player) == route.originalArea
        and wanted >= route.minWantedLevel and wanted <= route.maxWantedLevel
end

local function spawn(player)
    local vehicleModel = queryModel(route.originalModelId)
    local pedModel = TrafficAmbient.getPedestrianModel(route.pilotModelId)
    stats.waitingForModels = not vehicleModel or not pedModel
    if stats.waitingForModels then return end

    local x, y, targetZ = getElementPosition(player)
    x, y = TrafficPoliceFlight.spawnPoint(route, x, y, math.random(0, 255))
    local floor = call(provider, "getPoliceTerrainHeight", x, y, player)
    if floor ~= true and (type(floor) ~= "number" or not (floor >= -1000 and floor <= 1000)) then
        return
    end
    local z = TrafficPoliceFlight.spawnAltitude(route, targetZ, type(floor) == "number" and floor or nil)
    local heli = createVehicle(vehicleModel, x, y, z)
    if not heli then return end
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
    pursuits[player] = {heli = heli, pilot = pilot, dimension = dimension}
    stats.active = stats.active + 1
end

local function updatePursuit(player, pursuit, canPursue)
    local heli = pursuit.heli
    if not isElement(heli) or getVehicleOccupant(heli, 0) ~= pursuit.pilot or not isElement(pursuit.pilot) then
        pursuit.taken = isElement(heli) and isElement(getVehicleOccupant(heli, 0))
        removePursuit(player)
        return
    end
    if not canPursue or getElementHealth(heli) < 230 then pursuit.retiring = true end
    if pursuit.retiring then
        local x, y, z = getElementPosition(heli)
        local px, py, pz = getElementPosition(player)
        local dx, dy, dz = x - px, y - py, z - pz
        if dx * dx + dy * dy + dz * dz > route.retireDistance * route.retireDistance then
            removePursuit(player, true)
            return
        end
    end
    -- Adapter maps verified flight intent and controls to the installed engine.
    if call(provider, "controlPoliceHelicopter", heli, pursuit.pilot, player, pursuit.retiring == true) ~= true then
        removePursuit(player, true)
    end
end

local function tick()
    stats.waitingForProvider = not provider or getResourceState(provider) ~= "running"
    if stats.waitingForProvider then
        for player in pairs(pursuits) do removePursuit(player) end
        return
    end
    for player, pursuit in pairs(pursuits) do
        if getElementDimension(player) ~= pursuit.dimension or getElementInterior(player) ~= route.originalArea then
            removePursuit(player)
        else
            updatePursuit(player, pursuit, eligible(player))
        end
    end
    local now = getTickCount()
    local spawned = 0
    for _, player in ipairs(getElementsByType("player")) do
        if not pursuits[player] and eligible(player)
            and (not attempts[player] or (now - attempts[player]) % 4294967296 >= route.spawnAttemptMs) then
            attempts[player] = now
            spawn(player)
            spawned = spawned + 1
            if spawned == spawnBudget then break end
        end
    end
end

local function playerLeft()
    removePursuit(source)
    attempts[source] = nil
end

function TrafficPolice.start(graph)
    route = graph.policeFlight
    if not route then return end
    addEventHandler("onPlayerQuit", root, playerLeft)
    timer = setTimer(tick, 500, 0)
end

function TrafficPolice.stop()
    if timer then
        killTimer(timer)
        removeEventHandler("onPlayerQuit", root, playerLeft)
    end
    for player in pairs(pursuits) do removePursuit(player) end
    timer, route = nil, nil
    attempts = {}
end
