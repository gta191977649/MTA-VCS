-- PS2 SCM 0313 selects a fixed hour from weather table 6.
-- Expose it as MTA's active weather while the room's timecycle is applied.
local EXTRA_COLOURS = 6
local CHANGE_EVENT = "onClientInteriorChanged"
local rooms = {}
local area, dimension, colour
local outdoorWeather, outdoorTarget
local transition

addEvent(CHANGE_EVENT, false)

local function scope(interior, dim)
    return interior * 65536 + dim
end

function getInteriorState()
    return area, dimension, colour and EXTRA_COLOURS, colour
end

function getOutdoorWeather()
    if outdoorWeather then return outdoorWeather, outdoorTarget end
    return getWeather()
end

local function applyWeather(weather, target)
    if not setWeather(weather) then return false end
    if target and target ~= weather then return setWeatherBlended(target) end
    return true
end

function setOutdoorWeather(weather, target)
    if type(weather) ~= "number" or weather < 0 or weather > 255 or weather % 1 ~= 0 then return false end
    if target ~= nil and (type(target) ~= "number" or target < 0 or target > 255 or target % 1 ~= 0) then
        return false
    end
    if outdoorWeather then
        outdoorWeather, outdoorTarget = weather, target
        return true
    end
    return applyWeather(weather, target)
end

local function refresh()
    transition = nil
    local nextArea, nextDimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local nextColour = rooms[scope(nextArea, nextDimension)]
    if area == nextArea and dimension == nextDimension and colour == nextColour then return end

    if nextColour and not outdoorWeather then
        outdoorWeather, outdoorTarget = getWeather()
        setWeather(EXTRA_COLOURS)
    elseif not nextColour and outdoorWeather then
        applyWeather(outdoorWeather, outdoorTarget)
        outdoorWeather, outdoorTarget = nil, nil
    end
    area, dimension, colour = nextArea, nextDimension, nextColour
    triggerEvent(CHANGE_EVENT, localPlayer, getInteriorState())
end

local function scheduleRefresh()
    -- ENEX changes dimension and interior in the same tick.
    if not transition then transition = setTimer(refresh, 0, 1) end
end

local function loadRooms()
    rooms = {}
    local xml = xmlLoadFile(":vcs/portals.xml", true)
    if not xml then return end
    for _, pair in ipairs(xmlNodeGetChildren(xml)) do
        for _, endpoint in ipairs(xmlNodeGetChildren(pair)) do
            local interior = tonumber(xmlNodeGetAttribute(endpoint, "interior"))
            local dim = tonumber(xmlNodeGetAttribute(endpoint, "dimension"))
            local row = tonumber(xmlNodeGetAttribute(endpoint, "timecycle"))
            if interior and interior ~= 0 and dim and row and row >= 0 and row < 24 then
                rooms[scope(interior, dim)] = row
            end
        end
    end
    xmlUnloadFile(xml)
end

addEventHandler("onClientElementInteriorChange", localPlayer, scheduleRefresh, false)
addEventHandler("onClientElementDimensionChange", localPlayer, scheduleRefresh, false)
addEventHandler("onClientPlayerSpawn", localPlayer, scheduleRefresh, false)
addEventHandler("onClientResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == "vcs" then
        loadRooms()
        scheduleRefresh()
    end
end)
addEventHandler("onClientResourceStop", root, function(resource)
    if resource == getThisResource() then
        if transition then killTimer(transition) end
        if outdoorWeather then applyWeather(outdoorWeather, outdoorTarget) end
    elseif getResourceName(resource) == "vcs" then
        rooms = {}
        scheduleRefresh()
    end
end)
