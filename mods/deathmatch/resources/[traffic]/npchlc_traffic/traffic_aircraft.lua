TrafficAircraft = {}

local SLOT_DATA = "npchlc_traffic:flightSlot"
local STATE_DATA = "npchlc_traffic:flightState"
local HALT_DATA = "npchlc_traffic:flightHaltClock"
local aircraft, readyPlayers = {}, {}
local activeRoute, binding, override, timer, haltClock
local routeCatalog, controller
local state, failed = "stopped", 0
local nextBindingCheck = 0

local function clock()
    return getTickCount() % 4294967296
end

local function setState(value)
    if state == value then return end
    state = value
    setElementData(resourceRoot, STATE_DATA, value, "broadcast", "deny")
end

local function removeAircraft()
    for slot, vehicle in pairs(aircraft) do
        aircraft[slot] = nil
        if isElement(vehicle) and not TrafficVisibility.isWreck(vehicle) then destroyElement(vehicle) end
    end
end

local function registerRoutes()
    if controller then return true end
    local resource = getResourceFromName("vcs_vehicle")
    if resource and getResourceState(resource) == "running" and routeCatalog
        and exports.vcs_vehicle:setPlaneRoutes(routeCatalog) then
        controller = resource
    end
    return controller ~= nil
end

function TrafficAircraft.sample(routeId, time, slot)
    if not registerRoutes() then return false end
    return exports.vcs_vehicle:samplePlaneRoute(routeId, time, slot)
end

local function createSlot(slot, time)
    local pose = TrafficAircraft.sample(activeRoute.id, time, slot)
    if not pose then return false end
    local vehicle = createVehicle(binding, pose.x, pose.y, pose.z)
    if not vehicle then return false end
    if not exports.vcs_vehicle:updatePlaneRouteVehicle(vehicle, activeRoute.id, time, slot, true) then
        destroyElement(vehicle)
        return false
    end
    TrafficModelBindings.tag(vehicle, activeRoute.originalModelId)
    TrafficVisibility.track(vehicle, "aircraft")
    setElementData(vehicle, SLOT_DATA, slot, "broadcast", "deny")
    aircraft[slot] = vehicle
    return true
end

local function validModel(model)
    return type(model) == "number" and model % 1 == 0 and model >= 400 and model <= 611
        and getVehicleType(model) == "Plane"
end

local function tick(force)
    if not activeRoute then return end
    if not registerRoutes() then setState("waiting-controller") return end
    local now = clock()
    local check = force or (now - nextBindingCheck) % 4294967296 < 2147483648
    if check then
        nextBindingCheck = (now + 1000) % 4294967296
        local model = override
        if model == nil then model = TrafficModelBindings.get(activeRoute.originalModelId) end
        if not validModel(model) then model = nil end
        if binding ~= model then removeAircraft() end
        binding = model
    end
    if not binding then
        setState(override == false and "disabled" or "waiting-model")
        return
    end
    local missing = false
    for slot = 0, activeRoute.instances - 1 do
        local vehicle = aircraft[slot]
        if isElement(vehicle) then
            if not haltClock and not isVehicleBlown(vehicle) then
                exports.vcs_vehicle:updatePlaneRouteVehicle(vehicle, activeRoute.id, now, slot)
            end
        elseif not check or not createSlot(slot, haltClock or now) then
            missing = true
            if check then failed = failed + 1 end
        end
    end
    setState(missing and "retrying" or haltClock and "paused" or "running")
end

local function sendRoute(player)
    if activeRoute then
        triggerClientEvent(player, "npchlc_traffic:flightRoute", resourceRoot, activeRoute, clock())
    end
end

addEventHandler("onPlayerResourceStart", root, function(resource)
    if resource == getThisResource() then
        readyPlayers[source] = true
        sendRoute(source)
    end
end)

addEventHandler("onPlayerQuit", root, function() readyPlayers[source] = nil end)

addEventHandler("onResourceStop", root, function(resource)
    if resource == controller then controller = nil end
end)

function TrafficAircraft.start(route, routes)
    activeRoute, routeCatalog = route, routes
    if not route then setState("no-route") return end
    tick(true)
    -- Native elements carry collisions and authoritative world positions.
    -- Clients sample the same PS2 trajectory each frame for rendering.
    timer = setTimer(tick, 250, 0)
    for player in pairs(readyPlayers) do sendRoute(player) end
end

function TrafficAircraft.stop()
    if isTimer(timer) then killTimer(timer) end
    removeAircraft()
    binding, activeRoute, override, timer, haltClock = nil, nil, nil, nil, nil
    controller, routeCatalog = nil, nil
    setState("stopped")
end

-- SCM 0534 (003D9320). Enable resumes from the live clock; the three
-- world slots survive the render and movement gate in 0022CF80 / 0022D1F8.
function setTrafficPlanesMoving(allowed)
    if type(allowed) ~= "boolean" then return false end
    if allowed == (haltClock == nil) then return true end
    haltClock = nil
    if not allowed then haltClock = clock() end
    setElementData(resourceRoot, HALT_DATA, haltClock or false, "broadcast", "deny")
    tick(true)
    return true
end

function bindTrafficFixedWingModel(model)
    if model ~= false and not validModel(model) then return false end
    local previous = override
    override = model
    tick(true)
    if state ~= "retrying" then return true end
    override = previous
    tick(true)
    return false
end

function getTrafficAircraftStatus()
    local now = haltClock or clock()
    local result = {state=state, expected=activeRoute and activeRoute.instances or 0,
        active=0, failed=failed, originalModelId=activeRoute and activeRoute.originalModelId or false,
        model=binding or false, phaseMs=activeRoute and now % activeRoute.clockPeriodMs or 0, slots={}}
    for slot = 0, result.expected - 1 do
        local pose = TrafficAircraft.sample(activeRoute.id, now, slot)
        local live = isElement(aircraft[slot]) and not isVehicleBlown(aircraft[slot])
        if live then result.active = result.active + 1 end
        result.slots[#result.slots+1] = {slot=slot, active=live, x=pose and pose.x, y=pose and pose.y, z=pose and pose.z,
            phaseMs=(now + slot * activeRoute.phaseStepMs) % activeRoute.clockPeriodMs}
    end
    return result
end
