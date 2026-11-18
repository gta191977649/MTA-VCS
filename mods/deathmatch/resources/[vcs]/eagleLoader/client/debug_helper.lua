-- =========================
-- Crash Finder
-- =========================

if modelCrashDebug then
    LOG_FILE  = "spawned_objects.log"
    SKIP_FILE = "skip_objects.log"

    if fileExists(LOG_FILE) then
        LOG_FILE_HANDLE = fileOpen(LOG_FILE)
    else
        LOG_FILE_HANDLE = fileCreate(LOG_FILE)
    end

    if fileExists(SKIP_FILE) then
        SKIP_FILE_HANDLE = fileOpen(SKIP_FILE)
    end
end
local loggedIds   = {}
local skippedIds  = {}
local spawnedObjects = {}
local lastSpawned = nil
local streamFlightRecorderPath = "stream_flight_recorder.log"

local function notifyModelCrashDebug(eventName, id, model, extra)
    if not modelCrashDebug then return end

    triggerServerEvent(
        "eagleLoader:modelCrashDebug",
        resourceRoot,
        tostring(eventName or ""),
        tostring(id or ""),
        tonumber(model) or 0,
        tonumber(crashIndex) or 0,
        tonumber(#objectsToSpawn) or 0,
        tostring(extra or "")
    )
end

-- Load previously logged IDs
local function loadLoggedIds()
    if LOG_FILE_HANDLE then
        local content = fileRead(LOG_FILE_HANDLE, fileGetSize(LOG_FILE_HANDLE))
        for id in string.gmatch(content, "[^\r\n]+") do
            loggedIds[id] = true
        end
    end
end

local function loadSkippedIds()
    if SKIP_FILE_HANDLE then
        local content = fileRead(SKIP_FILE_HANDLE, fileGetSize(SKIP_FILE_HANDLE))
        for id in string.gmatch(content, "[^\r\n]+") do
            skippedIds[id] = true
        end
    end
end

local function appendLoggedId(id)
    fileSetPos(LOG_FILE_HANDLE, fileGetSize(LOG_FILE_HANDLE))
    fileWrite(LOG_FILE_HANDLE, tostring(id) .. "\n")
    loggedIds[tostring(id)] = true
    notifyModelCrashDebug("confirmed-safe", id, idCache[id], "previous object survived until next attempt")
end

loadLoggedIds()
loadSkippedIds()

local function appendStreamFlightRecord(line)
    local file

    if fileExists(streamFlightRecorderPath) then
        file = fileOpen(streamFlightRecorderPath)
        if file then
            fileSetPos(file, fileGetSize(file))
        end
    else
        file = fileCreate(streamFlightRecorderPath)
    end

    if not file then
        return
    end

    fileWrite(file, line .. "\n")
    fileClose(file)
end

local function recordStreamIn(element)
    if not streamFlightRecorder then
        return
    end

    local elementType = getElementType(element)
    if elementType ~= "object" and elementType ~= "building" then
        return
    end

    local model = getElementModel(element)
    local id = getElementID(element) or ""
    local x, y, z = getElementPosition(element)
    local px, py, pz = getElementPosition(localPlayer)
    local distance = getDistanceBetweenPoints3D(px, py, pz, x, y, z)

    appendStreamFlightRecord(string.format(
        "%d type=%s model=%s id=%s pos=%.3f,%.3f,%.3f player=%.3f,%.3f,%.3f distance=%.1f",
        getTickCount(),
        elementType,
        tostring(model),
        tostring(id),
        x, y, z,
        px, py, pz,
        distance
    ))
end

objectsToSpawn = {}
objList = {}

function addToSpawnList(id)
    if id and not objList[id] then
        objList[id] = true
        table.insert(objectsToSpawn, {id = id, x = 0, y = 0, z = 10})
    end
end

-- Main crash-finding spawn loop
function spawnNextObject()
    if not modelCrashDebug then return end

    movePlayer()
    crashIndex = crashIndex + 1
    if crashIndex > #objectsToSpawn then
        outputChatBox("Finished spawning all objects.")
        notifyModelCrashDebug("finished", "", 0, "Finished spawning all objects.")
        return
    end

    local data = objectsToSpawn[crashIndex]

    -- Skip already logged/skipped
    if loggedIds[tostring(data.id)] or skippedIds[tostring(data.id)] then
        notifyModelCrashDebug("skip-listed", data.id, idCache[data.id], "already logged or manually skipped")
        spawnNextObject()
        return
    end

    local model = idCache[data.id]
    if tonumber(model) then
        outputChatBox("Trying to spawn object ID " .. data.id .. " using model " .. tostring(model) .. " at index " .. crashIndex .. '/' .. #objectsToSpawn)
        notifyModelCrashDebug("attempt", data.id, model, "creating test object")
        if lastSpawned then appendLoggedId(lastSpawned) end

        spawnedObjects[model] = createObject(model, 0, 0, 0)
        setElementID(spawnedObjects[model], data.id)

        addEventHandler("onClientElementStreamIn", spawnedObjects[model],
            function()
                lastSpawned = data.id
                notifyModelCrashDebug("stream-in", data.id, model, "test object streamed in")
                setTimer(function()
                    outputChatBox("Spawned object ID " .. data.id .. " using model " .. tostring(model) .. " at index " .. crashIndex .. '/' .. #objectsToSpawn)
                    notifyModelCrashDebug("spawned", data.id, model, despawnDebug and "despawnDebug enabled" or "")
                    if despawnDebug then destroyElement(spawnedObjects[model]) end
                    spawnedObjects[model] = nil
                    spawnNextObject()
                end, modelCrashDebugRate, 1)
            end
        )
    else
        if lastSpawned then
            appendLoggedId(lastSpawned)
            lastSpawned = nil
        end
        outputChatBox("Skipping Object " .. data.id)
        notifyModelCrashDebug("skip-no-model", data.id, model, "no numeric model in idCache")
        setTimer(spawnNextObject, modelCrashDebugRate, 1)
    end
end

-- Repeatedly move the player (for streaming tests)
local playerMoved = false
function movePlayer()
    if not playerMoved then
        addEventHandler("onClientRender", root, function()
            setElementPosition(localPlayer, 0, 0, 0)
        end)
        playerMoved = true
    end
end

-- Do not install a root-level hot-path handler when both diagnostics are off.
if streamDebug or streamFlightRecorder then
    addEventHandler("onClientElementStreamIn", root,
        function()
            local elementType = getElementType(source)
            if elementType == "object" or elementType == "building" then
                local model = getElementModel(source)
                recordStreamIn(source)
                if streamDebug then
                    print(string.format("Building streamed in: ID %s, Element ID %s", model, getElementID(source) or ''))
                end
            end
        end
    )
end

-- =========================
-- Debug File Handling
-- =========================

local DEBUG_LINE_LIMIT = 1000
local debugLines = {}
local debugLineStart = 1
local debugLineCount = 0

function outputDebugString2(str, level)
    outputDebugString(str, level)
    str = tostring(str)
    if debugLineCount < DEBUG_LINE_LIMIT then
        local index = ((debugLineStart + debugLineCount - 1) % DEBUG_LINE_LIMIT) + 1
        debugLines[index] = str
        debugLineCount = debugLineCount + 1
    else
        debugLines[debugLineStart] = str
        debugLineStart = (debugLineStart % DEBUG_LINE_LIMIT) + 1
    end
end

function writeDebugFile()
    if debugLineCount == 0 then
        outputDebugString("No debug lines to write.", 3)
        return false
    end

    local f = fileCreate('debug.txt')
    if not f then
        outputDebugString("Failed to create debug.txt!", 1)
        return false
    end

    for offset = 0, debugLineCount - 1 do
        local index = ((debugLineStart + offset - 1) % DEBUG_LINE_LIMIT) + 1
        local entry = debugLines[index]
        fileWrite(f, entry .. "\n")
    end

    fileClose(f)
    outputDebugString("Wrote debug to: debug.txt")
    return true
end

local function countEntries(value)
    local count = 0
    for _ in pairs(value or {}) do count = count + 1 end
    return count
end

local function countNestedEntries(value)
    local count = 0
    for _, nested in pairs(value or {}) do
        count = count + countEntries(nested)
    end
    return count
end

-- On-demand diagnostics keep normal gameplay free of polling timers while
-- making streamer usage and retained Eagle state visible during profiling.
addCommandHandler("eaglemem", function()
    local usedBytes = engineStreamingGetUsedMemory and engineStreamingGetUsedMemory() or 0
    local limitBytes = engineStreamingGetMemorySize and engineStreamingGetMemorySize() or 0
    local bufferBytes = engineStreamingGetBufferSize and engineStreamingGetBufferSize() or 0
    local luaKilobytes = collectgarbage("count")
    local poolUsed, poolCapacity = 0, 0
    if engineGetPoolUsedCapacity then
        local ok, value = pcall(engineGetPoolUsedCapacity, "building")
        if ok then poolUsed = tonumber(value) or 0 end
    end
    if engineGetPoolCapacity then
        local ok, value = pcall(engineGetPoolCapacity, "building")
        if ok then poolCapacity = tonumber(value) or 0 end
    end

    outputChatBox(string.format(
        "[Eagle Memory] streamer %.1f/%.1f MB | buffer %.1f MB | Lua %.1f MB",
        usedBytes / 1048576,
        limitBytes / 1048576,
        bufferBytes / 1048576,
        luaKilobytes / 1024
    ))
    outputChatBox(string.format(
        "[Eagle Memory] maps %d | TXDs %d | asset handles %d | placements %d",
        countEntries(resourceElements),
        countEntries(textureIDs),
        countNestedEntries(globalCache),
        countNestedEntries(mapElements)
    ))
    outputChatBox(string.format(
        "[Eagle Memory] IMG entries %d | async jobs %d | building pool %d/%d | debug %d/%d",
        countNestedEntries(imageFiles),
        Async and Async.instance and #Async.instance.threads or 0,
        poolUsed,
        poolCapacity,
        debugLineCount,
        DEBUG_LINE_LIMIT
    ))
end)
