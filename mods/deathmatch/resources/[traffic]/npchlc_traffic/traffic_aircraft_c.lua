TrafficAircraftClient = {}

local SLOT_DATA = "npchlc_traffic:flightSlot"
local MODEL_PROVIDER = "npchlc_traffic:modelProvider"
local STATE_DATA = "npchlc_traffic:flightState"
local HALT_DATA = "npchlc_traffic:flightHaltClock"
local route, serverClock, receivedAt

local function controllerReady()
    local controller = getResourceFromName("vcs_vehicle")
    return controller and getResourceState(controller) == "running"
end

local function register(vehicle)
    local slot = getElementData(vehicle, SLOT_DATA, false)
    if type(slot) == "number" then
        exports.vcs_vehicle:setPlanePresentationSlot(slot, vehicle, getElementData(vehicle, MODEL_PROVIDER, false))
    end
end

local function sendState()
    exports.vcs_vehicle:setPlanePresentationState(getElementData(resourceRoot, STATE_DATA, false) or "loading",
        getElementData(resourceRoot, HALT_DATA, false) or false)
end

local function sendRoute()
    if route then
        local clock = (serverClock + (getTickCount() - receivedAt) % 4294967296) % 4294967296
        exports.vcs_vehicle:setPlanePresentationRoute(route, clock)
    end
end

addEvent("npchlc_traffic:flightRoute", true)
addEventHandler("npchlc_traffic:flightRoute", resourceRoot, function(path, clock)
    route, serverClock, receivedAt = path, clock, getTickCount()
    if controllerReady() then sendRoute() end
end, false)

addEventHandler("onClientElementDataChange", root, function(key)
    if key == SLOT_DATA or key == MODEL_PROVIDER then
        if controllerReady() then register(source) end
    elseif source == resourceRoot and (key == STATE_DATA or key == HALT_DATA) and controllerReady() then
        sendState()
    end
end)

addEventHandler("onClientResourceStart", root, function(resource)
    if resource ~= getThisResource() and getResourceName(resource) ~= "vcs_vehicle" then return end
    if not controllerReady() then return end
    sendRoute()
    sendState()
    for _, vehicle in ipairs(getElementsByType("vehicle", resourceRoot)) do register(vehicle) end
end)

function TrafficAircraftClient.debugSlots()
    if controllerReady() then return exports.vcs_vehicle:getPlanePresentationStatus() end
    return {state="waiting-controller", expected=0, active=0, slots={}, phaseMs=0}
end
