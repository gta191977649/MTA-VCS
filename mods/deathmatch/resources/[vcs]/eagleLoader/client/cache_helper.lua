-- ========================================
-- Global Asset/Model Cache Tables
-- ========================================
globalCache = {}
mapStockModelIDs = {}
idCache     = {}
resourceIDCache = {}
reverseID   = {}
allocatedModelIDs = {} -- only IDs returned by engineRequestModel may be freed

-- Check the full GTA:SA object catalog instead of assuming every numeric ID
-- below 20000 is a stock object. Newer MTA builds can return custom allocations
-- inside that range (for example, Monaco received model ID 5091).
function isSAModelID(modelID)
    modelID = tonumber(modelID)
    return modelID and saObjectIDSet and saObjectIDSet[modelID] == true or false
end

function isSAPhysicsObjectID(modelID)
    modelID = tonumber(modelID)
    return modelID
        and saPhysicsObjectIDSet
        and saPhysicsObjectIDSet[modelID] == true
        or false
end
skippedSAIDs = {
    [6694] = true,
}
reservedSkippedSAIDs = {}

local function isSkippedSAID(modelID)
    return skippedSAIDs[tonumber(modelID)] and true or false
end

local function reserveSkippedSAID(modelID)
    modelID = tonumber(modelID)
    if modelID then
        reservedSkippedSAIDs[modelID] = true
    end
end

local function freeRejectedCustomModel(modelID)
    if not (modelID and engineFreeModel) then return end
    local ok, result = pcall(engineFreeModel, modelID)
    if not ok or result == false then
        outputDebugString2(string.format(
            "Could not free rejected extended custom model ID %s.",
            tostring(modelID)
        ), 2)
    end
end

local function modelIDIsInUse(modelID)
    if reverseID[modelID] or allocatedModelIDs[modelID] then
        return true
    end

    for _, stockIDs in pairs(mapStockModelIDs) do
        if stockIDs[modelID] then return true end
    end

    for _, overrides in pairs(modelOverrides or {}) do
        if overrides[modelID] then
            return true
        end
    end

    return false
end

local function requestAvailableSAModel(logicalID)
    if not allocateDefaultIDs then return false end

    while true do
        local candidate = tonumber(engineRequestSAModel('object'))
        if not candidate then return false end

        if candidate < 0 or candidate > 19999 then
            outputDebugString2(string.format(
                "Skipping out-of-range SA fallback model ID %s for logical ID %s",
                tostring(candidate), tostring(logicalID)
            ), 2)
        elseif isSAPhysicsObjectID(candidate) then
            -- Arbitrary custom definitions must not inherit hard-coded GTA
            -- behavior from dynamic stock models such as traffic lights,
            -- breakable props, or physics objects. Those slots are only safe
            -- when a definition explicitly opts into one via nativeModel.
            outputDebugString2(string.format(
                "Skipping physics-tagged SA fallback model ID %s for logical ID %s",
                tostring(candidate), tostring(logicalID)
            ))
        elseif isSkippedSAID(candidate) then
            outputDebugString2(string.format(
                "Skipping reserved SA fallback model ID %s for logical ID %s",
                tostring(candidate), tostring(logicalID)
            ))
            reserveSkippedSAID(candidate)
        elseif modelIDIsInUse(candidate) then
            -- The SA list contains duplicate rows and can also overlap a
            -- below-cap ID returned by engineRequestModel. Never hand an ID to
            -- two logical models at the same time.
        else
            return candidate
        end
    end
end

-- ========================================
-- Model ID Request (unique per logical key)
-- ========================================
function getResourceModelID(resourceName, modelID)
    if resourceName then
        return resourceIDCache[resourceName] and resourceIDCache[resourceName][modelID]
    end
    return idCache[modelID]
end

function refreshSharedModelID(modelID, removedID)
    if idCache[modelID] ~= removedID then
        return
    end

    idCache[modelID] = nil
    for _, scopedCache in pairs(resourceIDCache) do
        if scopedCache[modelID] then
            idCache[modelID] = scopedCache[modelID]
            return
        end
    end
end

function requestModelID(modelID, resourceName)
    if not modelID then return false end

    if resourceName then
        resourceIDCache[resourceName] = resourceIDCache[resourceName] or {}
    end
    local scopedCache = resourceName and resourceIDCache[resourceName]
    local cachedID = tonumber(scopedCache and scopedCache[modelID] or nil)
    if not scopedCache then
        cachedID = tonumber(idCache[modelID])
    end
    if cachedID then
        return cachedID, false, allocatedModelIDs[cachedID] == true
    end

    local newID
    for _ = 1, 8 do
        newID = engineRequestModel('object')
        if isSkippedSAID(newID) then
            outputDebugString2(string.format("Skipping reserved SA model ID %s for logical ID %s", tostring(newID), tostring(modelID)))
            reserveSkippedSAID(newID)
            newID = nil
        else
            break
        end
    end

    newID = tonumber(newID)
    if newID and capAt19999 and newID > 19999 then
        outputDebugString2(string.format(
            "Custom model ID %s exceeds capAt19999; falling back to the SA model pool for %s.",
            tostring(newID), tostring(modelID)
        ))
        freeRejectedCustomModel(newID)
        newID = nil
    end

    -- engineRequestModel owns every accepted ID it successfully returns,
    -- regardless of whether that number also exists in the stock SA catalog.
    if newID then
        if scopedCache then scopedCache[modelID] = newID end
        idCache[modelID] = idCache[modelID] or newID
        reverseID[newID] = modelID
        allocatedModelIDs[newID] = true
        return newID, true, true
    end

    -- Fallback: allocate a unique, in-range model from the curated SA pool.
    newID = requestAvailableSAModel(modelID)
    if newID then
        if scopedCache then scopedCache[modelID] = newID end
        idCache[modelID] = idCache[modelID] or newID
        reverseID[newID] = modelID
        -- This is a built-in SA model ID, not an engineRequestModel
        -- allocation. It can be restored, but must never be passed to
        -- engineFreeModel during map unload.
        return newID, true, false
    end

    return false
end

-- ========================================
-- Generic Asset Loader (with per-resource cache)
-- ========================================
local function requestAsset(path, resourceName, loadFunc)
    if not (path and resourceName and loadFunc) then return false end

    globalCache[resourceName] = globalCache[resourceName] or {}

    if not isElement(globalCache[resourceName][path]) and fileExists(path) then
        globalCache[resourceName][path] = loadFunc(path)
    end

    return globalCache[resourceName][path] or false
end

-- ========================================
-- Specialized Asset Requests
-- ========================================
function requestTextureArchive(path, resourceName)
    return requestAsset(path, resourceName, engineLoadTXD)
end

function requestCollision(path, resourceName)
    return requestAsset(path, resourceName, engineLoadCOL)
end

function requestModel(path, resourceName)
    return requestAsset(path, resourceName, engineLoadDFF)
end
