resourceLoaded = {}
lodIDsByResource = {}
crashZoneMarkers = {}
local VCS_ARCHIVES = { "dff", "dff_1", "col", "txd" }
local vcsArchiveRetries
local defaultWorldRemovalApplied = false
local defaultWaterLevelApplied = false
local defaultWorldOcclusionsEnabled

-- Utility: Read all lines from a file handle, returns a table of lines
local function fileToLines(fh)
    if not fh then return {} end
    local size = fileGetSize(fh)
    if not size or size == 0 then fileClose(fh); return {} end
    local data = fileRead(fh, size)
    fileClose(fh)
    local result = {}
    for line in data:gmatch("[^\r\n]+") do
        table.insert(result, line)
    end
    return result
end

local function parseOffsetDirective(line, directive)
    local x, y, z = line:match("^" .. directive .. "%s+([^,]+),([^,]+),([^,]+)%s*$")
    if not (x and y and z) then
        return
    end

    return tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0
end

-- Load a zone .definition file (returns table of attribute tables)
function loadZone(resourceName, zone)
    zone = zone:gsub("%s+", "")
    local path = (":%s/zones/%s/%s.definition"):format(resourceName, zone, zone)
    if not fileExists(path) then
        outputDebugString("Eagle: missing zone definition " .. path, 1)
        return
    end
    local xml = xmlLoadFile(path)
    if not xml then
        outputDebugString("Eagle: invalid zone definition " .. path, 1)
        return
    end
    if xmlNodeGetName(xml) ~= "zoneDefinitions" then
        xmlUnloadFile(xml)
        outputDebugString("Eagle: expected zoneDefinitions in " .. path, 1)
        return
    end
    local defs = {}
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local attributes = xmlNodeGetAttributes(node)
        -- The containing directory is the authoritative zone. Older generated
        -- definition files (including Nice_Optimized) omit the zone attribute.
        attributes.zone = attributes.zone or zone
        attributes.definitionType = xmlNodeGetName(node)
        if not attributes.id or attributes.id == "" then
            xmlUnloadFile(xml)
            outputDebugString("Eagle: definition without a model ID in " .. path, 1)
            return
        end
        getFlags(attributes)
        table.insert(defs, attributes)
    end
    xmlUnloadFile(xml)
    return defs
end

local function getMapInfoOffset(attributes)
    if not (attributes.offsetX or attributes.offsetY or attributes.offsetZ) then
        return
    end

    return {
        x = tonumber(attributes.offsetX) or 0,
        y = tonumber(attributes.offsetY) or 0,
        z = tonumber(attributes.offsetZ) or 0
    }
end

-- Load a zone .map file (returns table of attribute tables with .type field and optional map info offset)
function loadMap(resourceName, zone)
    zone = zone:gsub("%s+", "")
    local path = (":%s/zones/%s/%s.map"):format(resourceName, zone, zone)
    if not fileExists(path) then return end
    local xml = xmlLoadFile(path)
    if not xml or xmlNodeGetName(xml) ~= "map" then
        if xml then xmlUnloadFile(xml) end
        outputDebugString("Eagle: invalid map " .. path, 1)
        return false
    end
    local entries = {}
    local mapOffset
    for _, node in ipairs(xmlNodeGetChildren(xml)) do
        local attributes = xmlNodeGetAttributes(node)
        local nodeType = xmlNodeGetName(node)
        if nodeType == "info" then
            mapOffset = getMapInfoOffset(attributes) or mapOffset
        else
            attributes.type = nodeType
            table.insert(entries, attributes)
        end
    end
    xmlUnloadFile(xml)
    return entries, mapOffset
end

-- Remove world map and/or interiors as needed
function removeWorldMapConfirm(water)
    if removeDefaultMap then
        if water and not defaultWaterLevelApplied then
            setWaterLevel(-10000000, true, false, true)
            defaultWaterLevelApplied = true
        end
        if defaultWorldRemovalApplied then
            return
        end

        if removeDefaultInteriors then
            removeGameWorld()
        else
            for i = 0, 50000 do
                removeWorldModel(i, 5000, 0, 0, 0, 0)
                removeWorldModel(i, 5000, 0, 0, 0, 13)
            end
        end
        if defaultWorldOcclusionsEnabled == nil and getOcclusionsEnabled then
            defaultWorldOcclusionsEnabled = getOcclusionsEnabled()
        end
        setOcclusionsEnabled(false)
        defaultWorldRemovalApplied = true
    end
end

-- Restore the stock GTA:SA world after Eagle has removed it.  This must only
-- run when no Eagle map is loaded (or still unloading), otherwise restored
-- stock geometry can overlap the map that is about to be streamed.
function restoreSAWorld()

    if (resourceElements and next(resourceElements))
        or (unloadingResources and next(unloadingResources))
    then
        outputDebugString2("Cannot restore the GTA:SA world while an Eagle map is still active.", 2)
        return false
    end

    if defaultWorldRemovalApplied then
        restoreGameWorld()
        setOcclusionsEnabled(true)
        defaultWorldOcclusionsEnabled = nil
        defaultWorldRemovalApplied = false
    end

    if defaultWaterLevelApplied then
        if resetWaterLevel then
            resetWaterLevel()
        else
            setWaterLevel(0)
        end
        defaultWaterLevelApplied = false
    end

    engineRestreamWorld(true)
    outputDebugString2("Restored the stock GTA:SA world.")
    return true
end

local function crashZoneAppliesToResource(zone, resourceName)
    return not zone.resource or zone.resource == "" or zone.resource == resourceName
end

local function getCrashZoneForPosition(resourceName, x, y, z, skipOnly)
    for _, zone in ipairs(crashZones or {}) do
        if crashZoneAppliesToResource(zone, resourceName) and (not skipOnly or zone.skip) then
            local dx, dy, dz = x - zone.x, y - zone.y, z - zone.z
            if (dx * dx + dy * dy + dz * dz) <= (zone.radius * zone.radius) then
                return zone
            end
        end
    end
end

local function createCrashZoneMarkers(resourceName)
    if crashZoneMarkers[resourceName] then
        return
    end

    crashZoneMarkers[resourceName] = {}

    for _, zone in ipairs(crashZones or {}) do
        if zone.blip and crashZoneAppliesToResource(zone, resourceName) then
            local blip = createBlip(zone.x, zone.y, zone.z, 0, 3, 255, 0, 0, 255, 0, 99999)
            local area = createRadarArea(
                zone.x - zone.radius,
                zone.y - zone.radius,
                zone.radius * 2,
                zone.radius * 2,
                255,
                0,
                0,
                80
            )

            if isElement(blip) then
                table.insert(crashZoneMarkers[resourceName], blip)
            end
            if isElement(area) then
                table.insert(crashZoneMarkers[resourceName], area)
            end
        end
    end
end

local function destroyCrashZoneMarkers(resourceName)
    for _, element in ipairs(crashZoneMarkers[resourceName] or {}) do
        if isElement(element) then
            destroyElement(element)
        end
    end

    crashZoneMarkers[resourceName] = nil
end

local function isTrueAttribute(value)
    if type(value) == "boolean" then return value end
    if type(value) == "number" then return value ~= 0 end
    if type(value) ~= "string" then return false end
    value = value:lower()
    return value == "true" or value == "1" or value == "yes" or value == "on"
end

local function resolvesToSAPhysicsModel(element, resourceName)
    if not (element and element.id) then
        return false
    end

    local requestedModel = getResourceModelID(resourceName, element.id)
    if requestedModel then
        -- Ordinary custom allocations stay eligible for promotion even when
        -- their logical name matches a stock model. An explicit nativeModel is
        -- different: it deliberately opts into that stock model's behavior.
        local definition = resourceDefinitions[resourceName]
            and resourceDefinitions[resourceName][element.id]
        local nativeValue = definition and (
            definition.nativeModel
            or definition.nativeModelID
            or definition.native_model
            or definition.native_model_id
        )
        local nativeModel = nativeValue
            and (defaultIDs[tostring(nativeValue):gsub("^%s*(.-)%s*$", "%1")]
                or tonumber(nativeValue))
        return nativeModel and isSAPhysicsObjectID(nativeModel) or false
    end

    local model = defaultIDs[element.id] or tonumber(element.id)
    return model and isSAPhysicsObjectID(model) or false
end

local function canPromoteStaticObject(element, overrides, resourceName)
    if not preferStaticBuildings or element.type ~= "object" then
        return false
    end
    if (tonumber(element.dimension) or 0) ~= 0 then
        return false
    end
    if isTrueAttribute(element.lowLOD)
        or isTrueAttribute(element.dynamic)
        or isTrueAttribute(element.forceObject)
        or isTrueAttribute(element.force_object)
    then
        return false
    end
    if lodAttach and (lodAttach[element.id] or lodAttach[element.lodParent]) then
        return false
    end

    -- Keep physics-tagged stock GTA:SA models on the native object path. Their
    -- object.dat behavior is lost if the static-building optimization recreates
    -- them as buildings. Untagged stock scenery and custom definitions remain
    -- eligible; custom definitions have an idCache entry even when they reuse
    -- a stock logical name.
    if resolvesToSAPhysicsModel(element, resourceName) then
        return false
    end

    -- Preserve object-only behavior when a placement explicitly asks for it
    -- or uses per-instance physics (buildings do not support object physics).
    return not overrides or (
        overrides.breakable == nil
        and overrides.frozen == nil
        and overrides.streamable == nil
        and overrides.scale == nil
        and overrides.simulated ~= true
        and overrides.objectProperties == nil
    )
end

local function ensureBuildingPoolCapacity(elementList, resourceName)
    if not (engineGetPoolCapacity and engineSetPoolCapacity) then
        return
    end

    local requested = 0
    for _, element in ipairs(elementList or {}) do
        if (tonumber(element.dimension) or 0) == 0
            and (element.type == "building"
            or (preferStaticBuildings
                and element.type == "object"
                and not isTrueAttribute(element.lowLOD)
                and not isTrueAttribute(element.dynamic)
                and not isTrueAttribute(element.forceObject)
                and not isTrueAttribute(element.force_object)
                and not resolvesToSAPhysicsModel(element, resourceName)))
        then
            requested = requested + 1
        end
    end

    local okCapacity, currentCapacity = pcall(engineGetPoolCapacity, "building")
    if not okCapacity or not tonumber(currentCapacity) then
        return
    end

    local used = 0
    if engineGetPoolUsedCapacity then
        local okUsed, currentUsed = pcall(engineGetPoolUsedCapacity, "building")
        if okUsed then used = tonumber(currentUsed) or 0 end
    end

    local target = used + requested + math.max(0, tonumber(buildingPoolHeadroom) or 0)
    if target > currentCapacity then
        local ok, result = pcall(engineSetPoolCapacity, "building", target)
        if not ok or result == false then
            outputDebugString2(string.format(
                "Could not grow the building pool from %d to %d; static placements will fall back to objects.",
                currentCapacity, target
            ), 2)
        else
            outputDebugString2(string.format(
                "Expanded the building pool from %d to %d for %d candidate placements.",
                currentCapacity, target, requested
            ))
        end
    end
end

function streamMapElements(resourceName, elementList,offX,offY,offZ, initializeImmediately)
    local objects = {}
    local skippedByCrashZone = {}
    local resourceLODIDs = lodIDsByResource[resourceName] or {}

    for _, element in ipairs(elementList or {}) do
        if not (resourceLODIDs[element.id] and highDefLODs) then
            local elementOffsetX = element.eagleOffsetX or offX
            local elementOffsetY = element.eagleOffsetY or offY
            local elementOffsetZ = element.eagleOffsetZ or offZ
            local x = (tonumber(element.posX) or 0) + elementOffsetX
            local y = (tonumber(element.posY) or 0) + elementOffsetY
            local z = (tonumber(element.posZ) or 0) + elementOffsetZ
            local crashZone = getCrashZoneForPosition(resourceName, x, y, z, true)

            if crashZone then
                skippedByCrashZone[crashZone.name] = (skippedByCrashZone[crashZone.name] or 0) + 1
            else
                local resourcePhysics = resourceDefinitionPhysicsOverrides[resourceName]
                local overrides = mergePlacementOverrides(
                    resourcePhysics and resourcePhysics[element.id],
                    getPlacementOverrides(element)
                )
                -- An unpaired distant mesh can explicitly use the native
                -- low-LOD object path without inventing a duplicate target.
                local isLowLODElement = element.type == "object" and isTrueAttribute(element.lowLOD)
                    or (element.uniqueID and resourceLODIDs[element.id] and not highDefLODs)
                    or (element.type ~= "building" and resourceLODIDs[element.id] and not highDefLODs)
                local newElement = streamElement(
                    element.id,
                    element.type,
                    {x, y, z},
                    {tonumber(element.rotX) or 0, tonumber(element.rotY) or 0, tonumber(element.rotZ) or 0},
                    element.interior,
                    element.dimension,
                    element.lodParent,
                    element.uniqueID,
                    not initializeImmediately,
                    isLowLODElement,
                    canPromoteStaticObject(element, overrides, resourceName),
                    resourceName,
                    element.type,
                    overrides
                )
                if newElement then
                    local modelID = getElementModel(newElement)
                    local distance = streamingDistances[modelID]
                    if distance and worldDistanceModels[modelID] and getElementType(newElement) == "object"
                        and not (overrides and overrides.streamable ~= nil) then
                        registerExtendedObjectRange(newElement, distance, isLowLODElement)
                    end
                    local near = tonumber(element.lodNear)
                    if near and near > 0 and isTrueAttribute(element.lowLOD) and element.lodBounds then
                        local minX, minY, maxX, maxY = element.lodBounds:match("^(%S+) (%S+) (%S+) (%S+)$")
                        minX, minY, maxX, maxY = tonumber(minX), tonumber(minY), tonumber(maxX), tonumber(maxY)
                        if minX and minY and maxX and maxY and minX <= maxX and minY <= maxY then
                            registerRangeLOD(newElement, near, minX + elementOffsetX, minY + elementOffsetY,
                                maxX + elementOffsetX, maxY + elementOffsetY)
                        end
                    end
                    table.insert(objects, newElement)
                end
            end
        end
    end

    for zoneName, count in pairs(skippedByCrashZone) do
        outputDebugString2(string.format("Skipped %d elements in crash zone: %s", count, zoneName))
    end

    return objects
end

-- Handles loading zones, maps, and water on resource start
function onResourceStartTimer(resourceThatStarted)
    local resourceName = getResourceName(resourceThatStarted)
    local zoneFilePath = (":%s/eagleZones.txt"):format(resourceName)
    local waterFilePath = (":%s/water.dat"):format(resourceName)

    -- A fast map restart can arrive while the previous instance is waiting for
    -- its delayed native cleanup. Retry after that cleanup instead of mixing
    -- the old model/IMG state with the new map load.
    if unloadingResources and unloadingResources[resourceName] then
        setTimer(onResourceStartTimer, (EAGLE_UNLOAD_DELAY_MS or 100) + 25, 1, resourceThatStarted)
        return
    end

    if getResourceState(resourceThatStarted) ~= "running"
        or not fileExists(zoneFilePath) or resourceLoaded[resourceName] then return end

    if resourceName == "vcs" then
        for _, archive in ipairs(VCS_ARCHIVES) do
            if not fileExists(":vcs/imgs/" .. archive .. ".img") then
                local retries = (vcsArchiveRetries or 0) + 1
                vcsArchiveRetries = retries
                if retries <= 20 then
                    setTimer(onResourceStartTimer, 250, 1, resourceThatStarted)
                else
                    outputDebugString("Eagle: missing VCS IMG after resource start: " .. archive, 1)
                end
                return
            end
        end
        vcsArchiveRetries = nil
    end

    local elementList, definitionList = {}, {}
    lodIDsByResource[resourceName] = {}
    local resourceLODIDs = lodIDsByResource[resourceName]

    -- Load maps first
    local fh = fileOpen(zoneFilePath)
    local maps = fileToLines(fh)

    -- Read optional map/water offsets before the zone names. Water has its own
    -- directive because some converted maps need the geometry and exported
    -- water adjusted independently.
    local offsetX, offsetY, offsetZ = 0, 0, 0
    local waterOffsetX, waterOffsetY, waterOffsetZ = 0, 0, 0
    while maps[1] do
        local directive = maps[1]
        if directive:match("^#offset%s+") then
            local x, y, z = parseOffsetDirective(directive, "#offset")
            if x then
                offsetX, offsetY, offsetZ = x, y, z
            else
                outputDebugString("Invalid eagleZones offset directive: " .. directive, 2)
            end
            table.remove(maps, 1)
        elseif directive:match("^#waterOffset%s+") then
            local x, y, z = parseOffsetDirective(directive, "#waterOffset")
            if x then
                waterOffsetX, waterOffsetY, waterOffsetZ = x, y, z
            else
                outputDebugString("Invalid eagleZones water offset directive: " .. directive, 2)
            end
            table.remove(maps, 1)
        else
            break
        end
    end

    for _, map in ipairs(maps) do
        local mapEntries, mapOffset = loadMap(resourceName, map)
        if mapEntries == false then
            lodIDsByResource[resourceName] = nil
            return
        end
        for _, v in ipairs(mapEntries or {}) do
            if mapOffset then
                v.eagleOffsetX = mapOffset.x
                v.eagleOffsetY = mapOffset.y
                v.eagleOffsetZ = mapOffset.z
            end
            table.insert(elementList, v)
            if v.lodParent then
                resourceLODIDs[v.lodParent] = true
            end
        end
    end


    local lowLODObjects = {}
    for _, placement in ipairs(elementList) do
        if (placement.type == "object" or forceObject)
            and (isTrueAttribute(placement.lowLOD) or resourceLODIDs[placement.id]) then
            lowLODObjects[placement.id] = true
        end
    end
    -- GTA stores draw distance on the model, not the placement. When one
    -- copy uses the low-LOD object distance multiplier, every pair sharing
    -- that target model must use the same object path. MTA also requires
    -- both ends of a native LOD link to have the same element type.
    for _, placement in ipairs(elementList) do
        local target = placement.lodParent or placement.id
        if placement.uniqueID and lowLODObjects[target] then
            placement.type = "object"
            placement.forceObject = "true"
        end
    end

    -- Then definitions. Reuse the already-parsed `maps` list (the zone names are
    -- the same lines) so the stripped #offset header isn't reintroduced by a
    -- second read of the file.
    for _, zone in ipairs(maps) do
        local definitions = loadZone(resourceName, zone)
        if not definitions then
            lodIDsByResource[resourceName] = nil
            return
        end
        for _, v in ipairs(definitions) do
            if not (resourceLODIDs[v.id] and highDefLODs) then
                v.eagleLowLODObject = lowLODObjects[v.id]
                table.insert(definitionList, v)
            end
        end
    end

    if #elementList == 0 then
        outputDebugString("Eagle: no placements found for " .. resourceName, 1)
        lodIDsByResource[resourceName] = nil
        return
    end

    local customIDs = {}
    for _, definition in ipairs(definitionList) do
        customIDs[definition.id] = true
    end
    mapStockModelIDs[resourceName] = {}
    for _, placement in ipairs(elementList) do
        if not customIDs[placement.id] then
            local stockID = defaultIDs[placement.id] or tonumber(placement.id)
            if isSAModelID(stockID) then
                mapStockModelIDs[resourceName][stockID] = true
            end
        end
    end

    mapLoadStartTicks[resourceName] = getTickCount()
    resourceLoaded[resourceName] = true
    createCrashZoneMarkers(resourceName)

    local lastDef = definitionList[#definitionList]
    loadMapDefinitions(resourceName, definitionList, lastDef and lastDef.id or true, function()
        -- Definitions now exist, so create each placement directly with its
        -- final model and initialize it in the same pass.
        ensureBuildingPoolCapacity(elementList, resourceName)
        mapElements[resourceName] = streamMapElements(
            resourceName,
            elementList,
            offsetX,
            offsetY,
            offsetZ,
            true
        )
        local counts = { building = 0, object = 0 }
        for _, element in ipairs(mapElements[resourceName]) do
            local kind = getElementType(element)
            counts[kind] = counts[kind] + 1
        end
        outputDebugString(string.format(
            "Eagle: %s created %d buildings and %d objects from %d placements.",
            resourceName, counts.building, counts.object, #elementList
        ))
        local hasWater = fileExists(waterFilePath)
        removeWorldMapConfirm(hasWater or resourceName == "vcs")
        if hasWater then
            parseWaterDat(waterFilePath, resourceName, waterOffsetX, waterOffsetY, waterOffsetZ)
        end
        return true
    end)
end

addEventHandler("onClientResourceStart", root, onResourceStartTimer)

addEventHandler("onClientResourceStop", root, function(stoppedResource)
    local resourceName = getResourceName(stoppedResource)
    destroyCrashZoneMarkers(resourceName)
    lodIDsByResource[resourceName] = nil
    if resourceName == "vcs" then vcsArchiveRetries = nil end
end)
