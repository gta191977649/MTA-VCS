TrafficAircraft = {}

local SLOT_DATA = "npchlc_traffic:flightSlot"
local UPDATE_INTERVAL_MS = 50
local INTEREST_DISTANCE = 420
local aircraft = {}
local binding, activeRoute, updateTimer

local function currentClock()
    return getTickCount() % 4294967296
end

local function applyPose(vehicle, pose)
    return setElementMatrix(vehicle, {
        {pose.rx, pose.ry, pose.rz, 0},
        {pose.fx, pose.fy, pose.fz, 0},
        {pose.ux, pose.uy, pose.uz, 0},
        {pose.x, pose.y, pose.z, 1},
    })
end

local function removeAircraft()
    if isTimer(updateTimer) then killTimer(updateTimer) end
    updateTimer = nil
    for _, vehicle in pairs(aircraft) do
        if isElement(vehicle) then destroyElement(vehicle) end
    end
    aircraft = {}
end

local function updateAircraft()
    if getPlayerCount() == 0 then return end
    local clock = currentClock()
    for slot, vehicle in pairs(aircraft) do
        if isElement(vehicle) and not isVehicleBlown(vehicle) then
            local pose = TrafficFlight.sample(activeRoute, clock, slot)
            local viewers = getElementsWithinRange(pose.x, pose.y, pose.z, INTEREST_DISTANCE, "player", 0, 0)
            if #viewers == 0 then
                -- An old position may have become visible while this flight was out of range.
                local x, y, z = getElementPosition(vehicle)
                viewers = getElementsWithinRange(x, y, z, INTEREST_DISTANCE, "player", 0, 0)
            end
            if #viewers > 0 then applyPose(vehicle, pose) end
        end
    end
end

local function createAircraft()
    if not activeRoute then return true end
    local clock = currentClock()
    for slot = 0, activeRoute.instances - 1 do
        local pose = TrafficFlight.sample(activeRoute, clock, slot)
        local vehicle = createVehicle(binding, pose.x, pose.y, pose.z)
        if not vehicle then
            removeAircraft()
            return false
        end
        aircraft[slot] = vehicle
        if getVehicleType(vehicle) ~= "Plane" or not setVehicleLocked(vehicle, true)
            or not setElementSyncer(vehicle, false) or not setElementFrozen(vehicle, true)
            or not applyPose(vehicle, pose) then
            removeAircraft()
            return false
        end
        setElementData(vehicle, SLOT_DATA, slot, "local", "deny")
        TrafficModelBindings.tag(vehicle, activeRoute.originalModelId)
        TrafficVisibility.track(vehicle, "aircraft")
    end
    updateTimer = setTimer(updateAircraft, UPDATE_INTERVAL_MS, 0)
    return true
end

function TrafficAircraft.start(route)
    activeRoute = route
    if binding and not createAircraft() then
        binding = nil
        outputDebugString("[npchlc_traffic] Could not start fixed-wing traffic with the bound model.", 2)
    end
end

function TrafficAircraft.stop()
    removeAircraft()
    activeRoute = nil
end

function bindTrafficFixedWingModel(model)
    if model ~= false and (type(model) ~= "number" or model % 1 ~= 0 or model < 400 or model > 611
        or getVehicleType(model) ~= "Plane") then return false end
    if binding == model then return true end

    local previous = binding
    removeAircraft()
    binding = model
    if not binding or createAircraft() then return true end
    binding = previous
    if binding and not createAircraft() then binding = nil end
    return false
end
