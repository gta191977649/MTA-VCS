-- =========================
-- Player Load Event Handler
-- =========================

local remoteEventWindows = setmetatable({}, { __mode = "k" })

local function allowRemoteEvent(player, eventName, limit, windowMs)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    local now = getTickCount()
    local playerWindows = remoteEventWindows[player] or {}
    remoteEventWindows[player] = playerWindows
    local window = playerWindows[eventName]
    if not window or now - window.startedAt >= windowMs then
        playerWindows[eventName] = { startedAt = now, count = 1 }
        return true
    end
    if window.count >= limit then return false end
    window.count = window.count + 1
    return true
end

local function cleanRemoteText(value, maxLength)
    local text = tostring(value or ""):gsub("[%c]", " ")
    return text:sub(1, maxLength)
end

local function playerLoaded(loadTime, mapResourceName)
    if source ~= resourceRoot then return end
    if not allowRemoteEvent(client, "player-load", 10, 10000) then return end
    local milliseconds = tonumber(loadTime)
    if not milliseconds or milliseconds < 0 or milliseconds > 3600000 then return end
    mapResourceName = cleanRemoteText(mapResourceName, 64)
    if mapResourceName == "" or not getResourceFromName(mapResourceName) then return end

    local seconds = milliseconds / 1000
    print(getPlayerName(client), 'Loaded ' .. mapResourceName .. ' In: ' .. string.format('%.2f', seconds) .. ' Seconds')
end
addEvent("onPlayerLoad", true)
addEventHandler("onPlayerLoad", resourceRoot, playerLoaded)

-- =========================
-- Player Disconnect Location Recorder
-- =========================

local DISCONNECT_LOCATION_LOG = "player_disconnect_locations.log"
local MODEL_CRASH_DEBUG_LOG = "model_crash_debug.log"
local POSITION_SAMPLE_INTERVAL = 1000
local lastPlayerLocations = {}

local function getTimestamp()
    local now = getRealTime()

    return string.format(
        "%04d-%02d-%02d %02d:%02d:%02d",
        now.year + 1900,
        now.month + 1,
        now.monthday,
        now.hour,
        now.minute,
        now.second
    )
end

local function appendLog(path, line)
    local file

    if fileExists(path) then
        file = fileOpen(path)
        if file then
            fileSetPos(file, fileGetSize(file))
        end
    else
        file = fileCreate(path)
    end

    if not file then
        outputDebugString("eagleLoader: could not write " .. path, 1)
        return
    end

    fileWrite(file, line .. "\n")
    fileClose(file)
end

local function appendDisconnectLocationLog(line)
    appendLog(DISCONNECT_LOCATION_LOG, line)
end

local function appendModelCrashDebugLog(line)
    appendLog(MODEL_CRASH_DEBUG_LOG, line)
end

local allowedCrashDebugEvents = {
    ["confirmed-safe"] = true,
    ["finished"] = true,
    ["skip-listed"] = true,
    ["attempt"] = true,
    ["stream-in"] = true,
    ["spawned"] = true,
    ["skip-no-model"] = true
}

addEvent("eagleLoader:modelCrashDebug", true)
addEventHandler("eagleLoader:modelCrashDebug", resourceRoot, function(eventName, id, model, index, total, extra)
    if source ~= resourceRoot then return end
    local player = client
    if not allowRemoteEvent(player, "model-crash-debug", 100, 1000) then return end
    eventName = cleanRemoteText(eventName, 32)
    if not allowedCrashDebugEvents[eventName] then return end
    id = cleanRemoteText(id, 128)
    extra = cleanRemoteText(extra, 256)
    local playerName = isElement(player) and getPlayerName(player) or "unknown"
    local serial = isElement(player) and getPlayerSerial(player) or "unknown"

    appendModelCrashDebugLog(string.format(
        "%s player=%s serial=%s event=%s id=%s model=%s index=%d/%d note=%s",
        getTimestamp(),
        tostring(playerName),
        tostring(serial),
        tostring(eventName or ""),
        tostring(id or ""),
        tostring(model or ""),
        tonumber(index) or 0,
        tonumber(total) or 0,
        tostring(extra or "")
    ))
end)

local function samplePlayerLocation(player)
    if not isElement(player) then
        return
    end

    local x, y, z = getElementPosition(player)
    local rx, ry, rz = getElementRotation(player)
    local vehicle = getPedOccupiedVehicle(player)

    lastPlayerLocations[player] = {
        x = x,
        y = y,
        z = z,
        rx = rx,
        ry = ry,
        rz = rz,
        interior = getElementInterior(player),
        dimension = getElementDimension(player),
        vehicleModel = vehicle and getElementModel(vehicle) or nil,
        tick = getTickCount()
    }
end

local function sampleAllPlayerLocations()
    for _, player in ipairs(getElementsByType("player")) do
        samplePlayerLocation(player)
    end
end

addEventHandler("onResourceStart", resourceRoot, function()
    sampleAllPlayerLocations()
    setTimer(sampleAllPlayerLocations, POSITION_SAMPLE_INTERVAL, 0)
end)

addEventHandler("onPlayerQuit", root, function(quitType, reason, responsibleElement)
    samplePlayerLocation(source)

    local location = lastPlayerLocations[source]
    if not location then
        return
    end

    local serial = getPlayerSerial(source) or "unknown"
    local account = getPlayerAccount(source)
    local accountName = account and not isGuestAccount(account) and getAccountName(account) or "guest"
    local responsibleName = isElement(responsibleElement) and getPlayerName(responsibleElement) or ""
    local vehicleText = location.vehicleModel and tostring(location.vehicleModel) or "none"

    appendDisconnectLocationLog(string.format(
        "%s name=%s serial=%s account=%s quitType=%s reason=%s responsible=%s pos=%.3f,%.3f,%.3f rot=%.3f,%.3f,%.3f interior=%d dimension=%d vehicle=%s sampledMsAgo=%d",
        getTimestamp(),
        getPlayerName(source),
        serial,
        accountName,
        tostring(quitType or ""),
        tostring(reason or ""),
        responsibleName,
        location.x,
        location.y,
        location.z,
        location.rx,
        location.ry,
        location.rz,
        location.interior,
        location.dimension,
        vehicleText,
        getTickCount() - location.tick
    ))

    lastPlayerLocations[source] = nil
    remoteEventWindows[source] = nil
end)

-- =========================
-- Resource Stop Handler
-- =========================

function onResourceStop(stoppedResource)
    if stoppedResource ~= getThisResource() then
        triggerClientEvent(root, "resourceStop", resourceRoot, getResourceName(stoppedResource))
    end
end
addEventHandler("onResourceStop", root, onResourceStop)

-- Client native crashes do not include the Lua call site. Persist the last
-- map-stop phase in the server log so cleanup crashes can be pinpointed.
addEvent("eagleLoader:stopTrace", true)
addEventHandler("eagleLoader:stopTrace", resourceRoot, function(mapName, phase)
    if source ~= resourceRoot then return end
    if not allowRemoteEvent(client, "stop-trace", 5000, 10000) then return end
    mapName = cleanRemoteText(mapName, 64)
    phase = cleanRemoteText(phase, 128)
    if not getResourceFromName(mapName) or not phase:match("^[%w%._%-]+$") then return end
    outputServerLog(string.format(
        "eagleLoader stop trace: player=%s map=%s phase=%s",
        isElement(client) and getPlayerName(client) or "unknown",
        tostring(mapName),
        tostring(phase)
    ))
end)

-- =========================
-- Streamed Element Creators
-- =========================

function streamObject(id, x, y, z, xr, yr, zr, interior, lod)
    if id == nil then return false end
    x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    xr, yr, zr = tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0
    local obj = createObject(1337, x, y, z, xr, yr, zr, lod == true)
    if not obj then return false end
    setElementInterior(obj, tonumber(interior) or 0)
    setElementID(obj, tostring(id))
    return obj
end

function streamBuilding(id, x, y, z, xr, yr, zr, interior, _lod)
    if id == nil then return false end
    x, y, z = tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
    xr, yr, zr = tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0
    local build = createBuilding(1337, x, y, z, xr, yr, zr, tonumber(interior) or 0)
    if not build then return false end
    setElementID(build, tostring(id))
    return build
end

function setElementStream(object, newModel)
    if not isElement(object) or newModel == nil then return false end
    return triggerClientEvent(root, "setElementStream", resourceRoot, object, newModel)
end

function getMaps()
    local maps = {}
    for _, mapResource in ipairs(getResources()) do
        if getResourceState(mapResource) == "running" then
            local name = getResourceName(mapResource)
            if fileExists(":" .. name .. "/eagleZones.txt") then
                table.insert(maps, name)
            end
        end
    end
    table.sort(maps)
    return maps
end
