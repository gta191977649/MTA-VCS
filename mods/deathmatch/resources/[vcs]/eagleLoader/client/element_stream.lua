-- =========================
-- Event Handling
-- =========================

function initializeObjects(resourceName)
    local allElements = resourceName and mapElements[resourceName] or {}

    if not resourceName then
        for _, object in ipairs(getElementsByType("object")) do
            table.insert(allElements, object)
        end
        for _, building in ipairs(getElementsByType("building")) do
            table.insert(allElements, building)
        end
    end

    for _, element in ipairs(allElements) do
        if isElement(element) then
            local id = getElementID(element)
            if id then
                setElementStream(element, id, true, true)
            end
        end
    end
end

-- =========================
-- Streaming
-- =========================

selfLODList = {}
lodChildrenByTarget = {}
lodChildrenByID = {}
lodTargetByChild = setmetatable({}, { __mode = "k" })
placementOverrides = setmetatable({}, { __mode = "k" })
unbreakableObjects = setmetatable({}, { __mode = "k" })
physicsInitializedObjects = setmetatable({}, { __mode = "k" })
eagleElementOwners = setmetatable({}, { __mode = "k" })
eagleElementMapTypes = setmetatable({}, { __mode = "k" })
eagleLowLODElements = setmetatable({}, { __mode = "k" })
local itemIDListIndex = setmetatable({}, { __mode = "k" })
local placementStreamHandlerInstalled = false
local retainSimulatedObjectModelGroup
local objectDamageStates = setmetatable({}, { __mode = "k" })

local PLACEHOLDER_MODEL = 1337
-- 1337 is useful as an invisible/temporary object model, but BinNt07_LA has
-- no object.dat entry and therefore no physical-properties group. Use stock
-- objects that GTA actually defines as dynamic when a static custom model
-- needs a group during createObject. The first choice (barrel1) has no
-- explosion or special collision response.
local PHYSICS_TEMPLATE_MODELS = { 1218, 1217, 1222, 1252 }
local physicsModelGroups = {}

function hideStreamPlaceholder(element)
    if not isElement(element) then return end
    setElementAlpha(element, 0)
    setElementCollisionsEnabled(element, false)
end

function applyPlacementOverrides(element, overrides)
    overrides = overrides or placementOverrides[element]
    if not (isElement(element) and overrides) then
        return
    end

    local function applyOverride(name, setter, ...)
        if not setter then
            if streamDebug then
                outputDebugString2(string.format("Placement override '%s' is unavailable for %s.", name, tostring(getElementID(element))), 2)
            end
            return
        end

        local ok = setter(...)
        if ok == false and streamDebug then
            outputDebugString2(string.format(
                "Placement override '%s' failed for %s (%s model %s).",
                name,
                tostring(getElementID(element)),
                tostring(getElementType(element)),
                tostring(getElementModel(element))
            ), 2)
        end
    end

    if overrides.doubleSided ~= nil then
        applyOverride("doubleSided", setElementDoubleSided, element, overrides.doubleSided)
    end

    if overrides.collisionsEnabled ~= nil then
        applyOverride("collisionsEnabled", setElementCollisionsEnabled, element, overrides.collisionsEnabled)
    end

    if overrides.breakable ~= nil and getElementType(element) == "object" then
        -- setObjectBreakable can reject custom models on some client builds.
        -- Keep the native call as the preferred path, and also track explicit
        -- unbreakable objects for the cancelable pre-break event below.
        if overrides.breakable then
            unbreakableObjects[element] = nil
        else
            unbreakableObjects[element] = true
        end
        if setObjectBreakable then
            applyOverride("breakable", setObjectBreakable, element, overrides.breakable)
        end
    end

    if overrides.frozen ~= nil then
        applyOverride("frozen", setElementFrozen, element, overrides.frozen)
    end

    if overrides.simulated == true
        and overrides.frozen ~= true
        and not physicsInitializedObjects[element]
    then
        -- A zero-velocity write wakes GTA's physical object without imparting
        -- motion. Only do this once; placement override retries must not stop
        -- an object that has already begun moving.
        if setElementVelocity then
            applyOverride("wake", setElementVelocity, element, 0, 0, 0)
        end
        physicsInitializedObjects[element] = true
    end

    if overrides.respawn ~= nil
        and getElementType(element) == "object"
        and toggleObjectRespawn
    then
        applyOverride("respawn", toggleObjectRespawn, element, overrides.respawn)
    end

    if overrides.streamable ~= nil then
        applyOverride("streamable", setElementStreamable, element, overrides.streamable)
    end

    if overrides.scale ~= nil and getElementType(element) == "object" and setObjectScale then
        applyOverride("scale", setObjectScale, element, overrides.scale)
    end

    if overrides.objectProperties ~= nil and getElementType(element) == "object" then
        if not setObjectProperty then
            if streamDebug then
                outputDebugString2(string.format(
                    "Object physical properties are unavailable for %s.",
                    tostring(getElementID(element))
                ), 2)
            end
        else
            for property, value in pairs(overrides.objectProperties) do
                if property == "center_of_mass" then
                    applyOverride(
                        property,
                        setObjectProperty,
                        element,
                        property,
                        value[1],
                        value[2],
                        value[3]
                    )
                else
                    applyOverride(property, setObjectProperty, element, property, value)
                end
            end
        end
    end

    if overrides.alpha ~= nil and getElementModel(element) ~= PLACEHOLDER_MODEL then
        applyOverride("alpha", setPlacementAlpha, element, overrides.alpha)
    end
end

local function placementOverrideNeedsRetry(element, overrides)
    if not (isElement(element) and overrides) then
        return false
    end

    if overrides.doubleSided ~= nil and isElementDoubleSided then
        return isElementDoubleSided(element) ~= overrides.doubleSided
    end

    return false
end

function queuePlacementOverrideReapply(element, retries)
    local overrides = placementOverrides[element]
    if not (isElement(element) and overrides and overrides.doubleSided ~= nil) then
        return
    end

    retries = retries or 3
    setTimer(function(target)
        if not isElement(target) then
            return
        end

        local targetOverrides = placementOverrides[target]
        if not targetOverrides then
            return
        end

        applyPlacementOverrides(target, targetOverrides)

        if streamDebug and placementOverrideNeedsRetry(target, targetOverrides) then
            outputDebugString2(string.format(
                "Placement override retry still pending for %s (%s model %s).",
                tostring(getElementID(target)),
                tostring(getElementType(target)),
                tostring(getElementModel(target))
            ), 2)
        end
    end, 100, retries, element)
end

function setElementPlacementOverrides(element, overrides, defer)
    if not isElement(element) then
        return
    end

    placementOverrides[element] = overrides or nil
    if not overrides then
        unbreakableObjects[element] = nil
        physicsInitializedObjects[element] = nil
    end
    if overrides then
        if not placementStreamHandlerInstalled then
            addEventHandler("onClientElementStreamIn", root, function()
                if placementOverrides[source] then
                    applyPlacementOverrides(source)
                    queuePlacementOverrideReapply(source, 2)
                end
            end)
            placementStreamHandlerInstalled = true
        end
        if not defer then
            applyPlacementOverrides(element, overrides)
            queuePlacementOverrideReapply(element, 2)
        end
    end
end

local function lodUniqueKey(uniqueID)
    return uniqueID == nil and false or tostring(uniqueID)
end

local function addPendingLODChild(element, lodID, uniqueID)
    if not (isElement(element) and lodID) then
        return
    end

    lodChildrenByID[lodID] = lodChildrenByID[lodID] or {}
    local key = lodUniqueKey(uniqueID or uniqueIDs[element])
    lodChildrenByID[lodID][key] = lodChildrenByID[lodID][key] or {}
    lodChildrenByID[lodID][key][element] = true
end

local function removePendingLODChild(element, lodID, uniqueID)
    local groups = lodID and lodChildrenByID[lodID]
    if not groups then
        return
    end

    local key = lodUniqueKey(uniqueID or uniqueIDs[element])
    local children = groups[key]
    if not children then return end

    children[element] = nil
    if next(children) == nil then
        groups[key] = nil
    end
    if next(groups) == nil then
        lodChildrenByID[lodID] = nil
    end
end

local function cleanupElementTracking(element, elementID)
    local idList = itemIDList[elementID]
    local listIndex = itemIDListIndex[element]
    if idList and listIndex and idList[listIndex] == element then
        local lastIndex = #idList
        local lastElement = idList[lastIndex]
        idList[listIndex] = lastElement
        idList[lastIndex] = nil
        if lastElement and lastElement ~= element then
            itemIDListIndex[lastElement] = listIndex
        end
        if #idList == 0 then
            itemIDList[elementID] = nil
        end
    end
    itemIDListIndex[element] = nil

    local uniqueList = itemIDListUnique[elementID]
    if uniqueList then
        local uid = uniqueIDs[element]
        if uid ~= nil and uniqueList[uid] == element then
            uniqueList[uid] = nil
        end
        if next(uniqueList) == nil then
            itemIDListUnique[elementID] = nil
        end
    end

    if selfLODList[element] then
        if isElement(selfLODList[element]) then
            destroyElement(selfLODList[element])
        end
        selfLODList[element] = nil
    end

    local lodParent = lodParents[element]
    removePendingLODChild(element, lodParent)

    local lodTarget = lodTargetByChild[element]
    if lodTarget and lodChildrenByTarget[lodTarget] then
        lodChildrenByTarget[lodTarget][element] = nil
        if next(lodChildrenByTarget[lodTarget]) == nil then
            lodChildrenByTarget[lodTarget] = nil
        end
    end

    lodParents[element] = nil
    uniqueIDs[element] = nil
    lodChildrenByTarget[element] = nil
    lodTargetByChild[element] = nil
    placementOverrides[element] = nil
    unbreakableObjects[element] = nil
    physicsInitializedObjects[element] = nil
    eagleElementOwners[element] = nil
    eagleElementMapTypes[element] = nil
    eagleLowLODElements[element] = nil
end

local function showStreamedElement(element)
    if not isElement(element) then return end
    setPlacementAlpha(element, 255)
    setElementCollisionsEnabled(element, not eagleLowLODElements[element])
end

local function getLODTargetElement(lodID, uniqueID)
    return (itemIDListUnique[lodID] or {})[uniqueID or 0] or (itemIDList[lodID] or {})[1]
end

local function linkElementLOD(highElement, lodElement, lodID)
    if not (isElement(highElement) and isElement(lodElement)) then
        return false
    end

    if highElement == lodElement then
        return false
    end

    local previousTarget = lodTargetByChild[highElement]
    if previousTarget and previousTarget ~= lodElement and lodChildrenByTarget[previousTarget] then
        lodChildrenByTarget[previousTarget][highElement] = nil
    end

    if not setLowLODElement(highElement, lodElement) then
        outputDebugString("Eagle: failed to link LOD " .. tostring(lodID), 2)
        return false
    end
    setElementCollisionsEnabled(lodElement, false)

    if lodAttach and lodAttach[lodID] then
        attachElements(lodElement, highElement)
    end

    local highOverrides = placementOverrides[highElement]
    if highOverrides then
        applyPlacementOverrides(lodElement, {
            alpha = highOverrides.alpha,
            doubleSided = highOverrides.doubleSided,
            scale = highOverrides.scale
        })
    end

    lodChildrenByTarget[lodElement] = lodChildrenByTarget[lodElement] or {}
    lodChildrenByTarget[lodElement][highElement] = true
    lodTargetByChild[highElement] = lodElement
    removePendingLODChild(highElement, lodID)
    return true
end

local function tryLinkElementLOD(element, lodParent, uniqueID)
    if not lodParent then
        return false
    end

    if string.lower(lodParent) == "self" then
        setupSelfLOD(element, getElementType(element))
        return true
    end

    lodParents[element] = lodParent
    local lodElement = getLODTargetElement(lodParent, uniqueID)
    if lodElement then
        return linkElementLOD(element, lodElement, lodParent)
    end

    addPendingLODChild(element, lodParent, uniqueID)
    return false
end

local function relinkLODChildrenForTarget(lodElement, lodID, uniqueID)
    local pendingGroups = lodChildrenByID[lodID]
    if not pendingGroups then
        return
    end

    local function linkGroup(pendingChildren)
        for highElement in pairs(pendingChildren or {}) do
            if isElement(highElement) then
                linkElementLOD(highElement, lodElement, lodID)
            else
                pendingChildren[highElement] = nil
            end
        end
    end

    if uniqueID then
        linkGroup(pendingGroups[lodUniqueKey(uniqueID)])
    else
        -- Preserve legacy behavior for LOD targets without a unique ID.
        local groups = {}
        for _, pendingChildren in pairs(pendingGroups) do
            table.insert(groups, pendingChildren)
        end
        for _, pendingChildren in ipairs(groups) do
            linkGroup(pendingChildren)
        end
    end
end

function setElementStream(element, newModel, _streamNew, _initial, lodParent, uniqueID, finalModelAlreadySet)
    if not isElement(element) or not newModel then
        outputDebugString2("Error: Invalid element or model specified.")
        return
    end

    uniqueID = uniqueID or uniqueIDs[element]

    local id = getElementID(element) or newModel
    if not id then
        outputDebugString2("Error: Could not determine element ID.")
        return
    end

    local ownerResource = eagleElementOwners[element]
    local cachedModel = getResourceModelID(ownerResource, id)
    local damage = objectDamageStates[element]
    if damage and damage.remaining <= 0 then
        cachedModel = damage.model
        finalModelAlreadySet = getElementModel(element) == cachedModel
    end
    local streamed = false

    if cachedModel then
        if uniqueID then
            uniqueIDs[element] = uniqueID
        end

        if not finalModelAlreadySet then
            retainSimulatedObjectModelGroup(
                cachedModel,
                placementOverrides[element],
                eagleElementOwners[element]
            )
            setElementModel(element, cachedModel)
        end

        
        setElementID(element, id)
        if not finalModelAlreadySet then
            showStreamedElement(element)
        end

        -- Register element in tracking lists
        if uniqueID then
            itemIDListUnique[id] = itemIDListUnique[id] or {}
            itemIDListUnique[id][uniqueID] = element
        else
            if not itemIDListIndex[element] then
                itemIDList[id] = itemIDList[id] or {}
                table.insert(itemIDList[id], element)
                itemIDListIndex[element] = #itemIDList[id]
            end
        end

        relinkLODChildrenForTarget(element, id, uniqueID)

        -- Setup custom properties
        local properties = ownerResource
            and resourceDefinedProperties[ownerResource]
            and resourceDefinedProperties[ownerResource][id]
        if not ownerResource then properties = definedProperties[id] end
        for i, v in pairs(properties or {}) do
            setupProperties(element, i, v)
        end

        -- LOD Parenting Logic

        if (not disableLOD) then
            lodParent = lodParents[element] or lodParent
            if highDefLODs and lodParent then
                setupSelfLOD(element, getElementType(element))
            else
                if lodParent then
                    tryLinkElementLOD(element, lodParent, uniqueID)
                end
            end
        end
        streamed = true
    else
        local model = defaultIDs[id] or tonumber(id)
        if model then
            if not finalModelAlreadySet then
                retainSimulatedObjectModelGroup(
                    model,
                    placementOverrides[element],
                    eagleElementOwners[element]
                )
                setElementModel(element, model)
            end
            setElementID(element, id)
            if not finalModelAlreadySet then
                showStreamedElement(element)
            end
            local properties = ownerResource
                and resourceDefinedProperties[ownerResource]
                and resourceDefinedProperties[ownerResource][id]
            if not ownerResource then properties = definedProperties[id] end
            for i, v in pairs(properties or {}) do
                setupProperties(element, i, v)
            end
            streamed = true
        else
            if streamDebug then
                outputDebugString2(string.format("Error: Model ID %s not found in cache (Default).", id))
            end
        end
    end

    if streamed then
        applyPlacementOverrides(element)
        prepTime(element, id)
        queuePlacementOverrideReapply(element, 3)
    end
end

addEvent("setElementStream", true)
addEventHandler("setElementStream", resourceRoot, setElementStream)

function setupSelfLOD(element, type)
    if selfLODList[element] then
        destroyElement(selfLODList[element])
    end

    local x, y, z    = getElementPosition(element)
    local xr, yr, zr = getElementRotation(element)

    -- match streamElement logic: only use createBuilding when:
    -- type == 'building' AND within valid bounds AND NOT forceObject
    local validBuilding = (x > -3000 and x < 3000 and y > -3000 and y < 3000)
    local isBuilding = ((type == 'building') and validBuilding and (not forceObject))

    local createFun = isBuilding and createBuilding or createObject

    local build = createFun(1337, x, y, z, xr, yr, zr,isBuilding and (getElementInterior(element) or 0) or true)

    -- keep LOD in same interior/dimension as the source element
    setElementInterior(build, getElementInterior(element) or 0)
    setElementDimension(build, getPlacementDimension(element) or 0)

    setElementModel(build, getElementModel(element))
    -- Self LODs are separate elements.  Preserve map ownership so the unload
    -- sweep can destroy them before their custom model is released.
    local owner = eagleElementOwners[element]
    if owner then
        eagleElementOwners[build] = owner
        eagleElementMapTypes[build] = "selfLOD"
    end
    setLowLODElement(element, build)
    selfLODList[element] = build
    setElementCollisionsEnabled(build, false)

    local sourceOverrides = placementOverrides[element]
    if sourceOverrides then
        applyPlacementOverrides(build, {
            alpha = sourceOverrides.alpha,
            doubleSided = sourceOverrides.doubleSided,
            scale = sourceOverrides.scale
        })
    end
    prepTime(build, getElementModel(element))

    return build
end


function setupProperties(element, property, setting)
    if property then
        local propertyFun =
            (property == "collisions_disabled" and setElementCollisionsEnabled) or
            (property == "disable_collisions" and setElementCollisionsEnabled) or
            (property == "no_stream" and setElementStreamable) or
            setElementCollisionsEnabled

        propertyFun(element, setting)
    end
end

-- =========================
-- Element Creation
-- =========================

-- Buildings are only valid inside the SA world bounds; outside this range
-- (and when forceObject is set) the element is created as a regular object.
local WORLD_LIMIT = 3000

-- A model without a physical-properties group is instantiated as a static
-- object even when the resulting element is unfrozen. For explicitly
-- simulated placements, temporarily give static models the same group as
-- a stock dynamic object's group while createObject runs.
-- Restoring immediately afterwards keeps this a per-placement choice when
-- static and simulated instances share one model.
local function getDynamicPhysicalPropertiesGroup(preferredModel)
    preferredModel = tonumber(preferredModel)
    if preferredModel then
        local ok, group = pcall(engineGetModelPhysicalPropertiesGroup, preferredModel)
        group = ok and tonumber(group) or nil
        if group and group ~= -1 then
            return group
        end
        return
    end

    for _, templateModel in ipairs(PHYSICS_TEMPLATE_MODELS) do
        local ok, group = pcall(engineGetModelPhysicalPropertiesGroup, templateModel)
        group = ok and tonumber(group) or nil
        if group and group ~= -1 then
            return group
        end
    end
end

retainSimulatedObjectModelGroup = function(modelID, overrides, ownerResource)
    if not (overrides
        and (overrides.simulated == true or overrides.physicsRoot ~= nil)
        and engineGetModelPhysicalPropertiesGroup
        and engineSetModelPhysicalPropertiesGroup)
    then
        return
    end

    local okCurrent, currentGroup = pcall(engineGetModelPhysicalPropertiesGroup, modelID)
    currentGroup = okCurrent and tonumber(currentGroup) or nil
    if not currentGroup then
        return
    end
    if currentGroup ~= -1 and overrides.physicsRoot == nil then
        return
    end

    local targetGroup = getDynamicPhysicalPropertiesGroup(overrides.physicsRoot)
    if not targetGroup then
        outputDebugString2(string.format(
            "Could not enable simulation for model %s: physics root %s has no dynamic physical-properties group.",
            tostring(modelID),
            tostring(overrides.physicsRoot or "fallback")
        ), 2)
        return
    end

    local retained = physicsModelGroups[modelID]
    if not retained then
        retained = {
            originalGroup = currentGroup,
            owners = {}
        }
        physicsModelGroups[modelID] = retained
    end
    if ownerResource then retained.owners[ownerResource] = true end

    if currentGroup == targetGroup then
        retained.activeGroup = targetGroup
        return true
    end

    local okSet, changed = pcall(engineSetModelPhysicalPropertiesGroup, modelID, targetGroup)
    if not okSet or changed == false then
        outputDebugString2(string.format(
            "Could not enable simulation for model %s.",
            tostring(modelID)
        ), 2)
        return
    end

    retained.activeGroup = targetGroup
    return true
end

-- Physical-properties groups are model state in MTA, not a one-time
-- createObject input. Keep the selected group installed while the owning map
-- is active; restoring it immediately after creation makes the live object
-- static again. Map unload calls this before releasing/restoring its models.
function restorePhysicsModelGroupsForResource(resourceName)
    for modelID, retained in pairs(physicsModelGroups) do
        if resourceName then retained.owners[resourceName] = nil end
        if not resourceName or not next(retained.owners) then
            local okRestore, restored = pcall(
                engineSetModelPhysicalPropertiesGroup,
                modelID,
                retained.originalGroup
            )
            if (not okRestore or restored == false)
                and engineRestoreModelPhysicalPropertiesGroup
            then
                pcall(engineRestoreModelPhysicalPropertiesGroup, modelID)
            end
            physicsModelGroups[modelID] = nil
        end
    end
end

function streamElement(
    id,
    elementType,
    pos,
    rot,
    interior,
    dimension,
    parentLOD,
    uniqueID,
    ignoreStream,
    isLowLODElement,
    preferBuilding,
    ownerResource,
    mapType,
    overrides
)
    -- In crash-debug mode nothing is created here; IDs are just queued.
    if modelCrashDebug then
        addToSpawnList(id)
        return
    end

    if not id then
        outputDebugString2("Error: Trying to create invalid element.")
        return
    end

    local x, y, z    = unpack(pos)
    local xr, yr, zr = unpack(rot)
    interior  = tonumber(interior)  or 0
    dimension = tonumber(dimension) or 0

    local inWorldBounds = (x > -WORLD_LIMIT and x < WORLD_LIMIT and y > -WORLD_LIMIT and y < WORLD_LIMIT)
    local requiresObjectPhysics = overrides
        and (overrides.simulated == true
            or overrides.physicsRoot ~= nil
            or overrides.objectProperties ~= nil
            or overrides.breakable ~= nil
            or overrides.respawn ~= nil)
    local isBuilding = inWorldBounds and dimension == 0 and not forceObject and not requiresObjectPhysics
        and (elementType == 'building' or (preferStaticBuildings and preferBuilding))
    local resolvedModel = getResourceModelID(ownerResource, id)
        or defaultIDs[id]
        or tonumber(id)
    local initialModel = ignoreStream and PLACEHOLDER_MODEL or resolvedModel or PLACEHOLDER_MODEL
    local finalModelReady = not ignoreStream and resolvedModel ~= nil

    local element
    if isBuilding then
        -- createBuilding can throw when the building pool is exhausted. A
        -- regular object is a safe fallback and preserves map availability.
        local ok, building = pcall(createBuilding, initialModel, x, y, z, xr, yr, zr, interior)
        element = ok and building or nil
    end
    if not element then
        isBuilding = false
        -- createObject's final arg is isLowLOD. Only actual LOD target rows
        -- should use it; high-detail children with lodParent should not.
        if finalModelReady then
            retainSimulatedObjectModelGroup(initialModel, overrides, ownerResource)
        end
        local okObject, object = pcall(
            createObject,
            initialModel,
            x,
            y,
            z,
            xr,
            yr,
            zr,
            isLowLODElement and true or false
        )
        element = okObject and object or nil
    end

    if not element then
        outputDebugString2(string.format("Error: Failed to create element for ID %s.", tostring(id)))
        return
    end

    -- Buildings already receive their interior at creation and do not support
    -- dimensions. Avoid two native calls for the overwhelmingly common 0/0.
    if not isBuilding then
        if interior ~= 0 then setElementInterior(element, interior) end
        if dimension ~= 0 then setElementDimension(element, dimension) end
    end
    if isLowLODElement then
        setElementCollisionsEnabled(element, false)
        eagleLowLODElements[element] = true
    end
    if not ignoreStream and not finalModelReady then
        hideStreamPlaceholder(element)
    end

    if ownerResource then eagleElementOwners[element] = ownerResource end
    if mapType then eagleElementMapTypes[element] = mapType end
    setElementPlacementOverrides(element, overrides, true)
    if uniqueID then uniqueIDs[element] = uniqueID end
    if parentLOD then
        lodParents[element] = parentLOD
        if ignoreStream then
            addPendingLODChild(element, parentLOD, uniqueID)
        end
    end

    if not ignoreStream then
        setElementStream(element, id, true, nil, parentLOD, uniqueID, finalModelReady)
    else
        hideStreamPlaceholder(element)
    end

    if ignoreStream or not finalModelReady then
        setElementID(element, id)
    end

    return element
end

function streamObject(id, x, y, z, xr, yr, zr, interior, dimension, parentLOD, uniqueID, ignoreStream)
    return streamElement(id, 'object',
        {tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0},
        {tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0},
        interior, dimension, parentLOD, uniqueID, ignoreStream)
end

function streamBuilding(id, x, y, z, xr, yr, zr, interior, parentLOD, uniqueID, ignoreStream)
    -- Buildings have no dimension of their own, so pass nil for that slot to
    -- keep parentLOD/uniqueID/ignoreStream aligned with streamElement.
    return streamElement(id, 'building',
        {tonumber(x) or 0, tonumber(y) or 0, tonumber(z) or 0},
        {tonumber(xr) or 0, tonumber(yr) or 0, tonumber(zr) or 0},
        interior, nil, parentLOD, uniqueID, ignoreStream)
end

-- =========================
-- Destroy Events
-- =========================

local function handleElementDestroy()
    local elementID   = getElementID(source)
    local elementType = getElementType(source)
    if (elementType == "object" or elementType == "building")
        and (eagleElementOwners[source] or (elementID and idCache[elementID]))
    then
        cleanupElementTracking(source, elementID)
    end
end
addEventHandler("onClientElementDestroy", root, handleElementDestroy)

addEvent("onClientEagleObjectDamageEffect", false)

addEventHandler("onClientObjectDamage", root, function(loss)
    local overrides = placementOverrides[source]
    if not (overrides and overrides.damageModel and loss > 0) then return end
    local state = objectDamageStates[source]
    if not state then
        local model = getResourceModelID(eagleElementOwners[source], overrides.damageModel)
        if not model then return end
        state = { model = model, remaining = overrides.objectHealth }
        objectDamageStates[source] = state
    end
    cancelEvent()
    if state.remaining <= 0 then return end
    state.remaining = state.remaining - loss
    local damageModel = overrides.damageModel
    if state.remaining > 0 then
        triggerEvent("onClientEagleObjectDamageEffect", source, eagleElementOwners[source], damageModel)
        return
    end
    -- Apply after the game's damage callback has returned.
    setTimer(function(object)
        if isElement(object) and objectDamageStates[object] == state then
            setElementStream(object, getElementID(object), true)
            if getElementModel(object) == state.model then
                triggerEvent("onClientEagleObjectDamageEffect", object,
                    eagleElementOwners[object], damageModel)
            end
        end
    end, 0, 1, source)
end)

addEventHandler("onClientElementDimensionChange", localPlayer, function(previous)
    for object, state in pairs(objectDamageStates) do
        if isElement(object) and getElementDimension(object) == previous then
            objectDamageStates[object] = nil
            if state.remaining <= 0 then
                setElementStream(object, getElementID(object), true)
            end
        end
    end
end)

-- This event fires before GTA destroys the intact object. Canceling it is a
-- reliable fallback for custom models where setObjectBreakable(false) is not
-- accepted by the client.
addEventHandler("onClientObjectBreak", root, function()
    if unbreakableObjects[source] then
        cancelEvent()
    end
end)
