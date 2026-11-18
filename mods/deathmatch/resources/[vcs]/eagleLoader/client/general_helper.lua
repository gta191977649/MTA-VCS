------------------------------
-- Model Time Streaming Logic
------------------------------

local timeTable     = {}
local streamTimes   = {}
local streamTimeObj = setmetatable({}, { __mode = "k" })
local lodRangeVisibility = setmetatable({}, { __mode = "k" })
local extendedRangeObjects = setmetatable({}, { __mode = "k" })

local function updateExtendedObjectRange(element, entry, x, y, z, interior, dimension, farClip)
    local ex, ey, ez = getElementPosition(element)
    local distance = math.min(entry.distance, farClip) + (entry.resident and 100 or 50)
    local resident = interior == getElementInterior(element) and dimension == getElementDimension(element)
        and (x-ex)^2 + (y-ey)^2 + (z-ez)^2 <= distance*distance
    if resident ~= entry.resident and setElementStreamable(element, not resident) then
        entry.resident = resident
    end
end

function registerExtendedObjectRange(element, distance, lowLOD)
    -- MTA's normal/low-LOD object streamers stop at 500/1700 m even when
    -- the model's render distance is longer.
    if distance <= (lowLOD and 1700 or 500) or not isElementStreamable(element) then return end
    local entry = {distance = distance, resident = false}
    extendedRangeObjects[element] = entry
    local x, y, z = getCameraMatrix()
    updateExtendedObjectRange(element, entry, x, y, z, getElementInterior(localPlayer),
        getElementDimension(localPlayer), getFarClipDistance())
end

local function getPlacementAlpha(element)
    local lod = lodRangeVisibility[element]
    return lod and lod.alpha or getElementAlpha(element)
end

function setPlacementAlpha(element, alpha)
    local lod = lodRangeVisibility[element]
    if lod then
        lod.alpha = alpha
        if lod.hidden then return end
    end
    setElementAlpha(element, alpha)
end

function registerRangeLOD(element, distance, minX, minY, maxX, maxY)
    local lod = {
        alpha = getElementAlpha(element), distance = distance,
        minX = minX, minY = minY, maxX = maxX, maxY = maxY
    }
    lodRangeVisibility[element] = lod
    local x, y = getCameraMatrix()
    local dx = math.max(lod.minX - x, 0, x - lod.maxX)
    local dy = math.max(lod.minY - y, 0, y - lod.maxY)
    lod.hidden = dx*dx + dy*dy <= distance*distance
    if lod.hidden then setElementAlpha(element, 0) end
end

setTimer(function()
    local x, y, z = getCameraMatrix()
    if next(extendedRangeObjects) then
        local interior, dimension, farClip = getElementInterior(localPlayer), getElementDimension(localPlayer),
            getFarClipDistance()
        for element, entry in pairs(extendedRangeObjects) do
            if isElement(element) then
                updateExtendedObjectRange(element, entry, x, y, z, interior, dimension, farClip)
            else
                extendedRangeObjects[element] = nil
            end
        end
    end
    for element, lod in pairs(lodRangeVisibility) do
        if not isElement(element) then
            lodRangeVisibility[element] = nil
        else
            local dx = math.max(lod.minX - x, 0, x - lod.maxX)
            local dy = math.max(lod.minY - y, 0, y - lod.maxY)
            local distance = lod.distance + (lod.hidden and 15 or 0)
            local hidden = dx*dx + dy*dy <= distance*distance
            if hidden ~= lod.hidden then
                lod.hidden = hidden
                setElementAlpha(element, hidden and 0 or lod.alpha)
            end
        end
    end
end, 100, 0)

local function restoreTimedElement(element)
    local state = streamTimeObj[element]
    if state then
        setPlacementAlpha(element, state.alpha)
        setElementCollisionsEnabled(element, state.collisions)
        if state.dimension ~= nil then setElementDimension(element, state.dimension) end
    end
    streamTimeObj[element] = nil
end

function getPlacementDimension(element)
    local state = streamTimeObj[element]
    return state and state.dimension or getElementDimension(element)
end

-- Set streaming time for a model or by name
function setModelStreamTime(model, name, sIn, sOut)
    if model then streamTimes[model] = {sIn, sOut} end
    streamTimes[name] = {sIn, sOut}
end

-- Remove a stored streaming-time entry (called during map unload)
function clearModelStreamTime(key)
    if key ~= nil then streamTimes[key] = nil end
end

local function applyTimedVisibility(element, window, hour, hiddenDimension)
    local first, last = window[1], window[2]
    local active
    if first <= last then
        active = first <= hour and hour < last
    else
        active = first <= hour or hour < last
    end
    if active then
        restoreTimedElement(element)
        return
    end

    local state = streamTimeObj[element]
    if not state then
        state = {
            alpha = getPlacementAlpha(element),
            collisions = getElementCollisionsEnabled(element),
            dimension = getElementType(element) == "object" and getElementDimension(element) or nil
        }
        streamTimeObj[element] = state
        setPlacementAlpha(element, 0)
    end
    if getElementCollisionsEnabled(element) then
        setElementCollisionsEnabled(element, false)
    end
    -- Building alpha can be lost on a native stream-in. Objects outside
    -- the viewer's dimension have no native render or collision instance.
    if state.dimension ~= nil and getElementDimension(element) ~= hiddenDimension then
        setElementDimension(element, hiddenDimension)
    end
end

local function inactiveDimension()
    return getElementDimension(localPlayer) == 65534 and 65533 or 65534
end

local function updateTimedElements()
    local hour, hiddenDimension = getTime(), inactiveDimension()
    for element, window in pairs(timeTable) do
        if isElement(element) then
            applyTimedVisibility(element, window, hour, hiddenDimension)
        else
            timeTable[element] = nil
            streamTimeObj[element] = nil
        end
    end
end
setTimer(updateTimedElements, 100, 0)
addEventHandler("onClientElementDimensionChange", localPlayer, updateTimedElements, false)

function prepTime(element, id)
    local time = streamTimes[id]
    if time and time[1] and time[2] then
        timeTable[element] = time
        applyTimedVisibility(element, time, getTime(), inactiveDimension())
    else
        timeTable[element] = nil
        restoreTimedElement(element)
    end
end

------------------------------
-- Object Flags
------------------------------

local flagsTableNew = {}
objectFlags = {
    {bit = 0,  dec = 1,      hex = "0x1",        name = "is_road",                      description = "This model is a road."},
    {bit = 2,  dec = 4,      hex = "0x4",        name = "draw_last",                    description = "Model is transparent. Render after opaque objects."},
    {bit = 3,  dec = 8,      hex = "0x8",        name = "additive",                     description = "Render with additive blending."},
    {bit = 6,  dec = 64,     hex = "0x40",       name = "no_zbuffer_write",             description = "Disable writing to z-buffer."},
    {bit = 7,  dec = 128,    hex = "0x80",       name = "dont_receive_shadows",         description = "Do not draw shadows on this object."},
    {bit = 9,  dec = 512,    hex = "0x200",      name = "is_glass_type_1",              description = "Breakable glass type 1."},
    {bit = 10, dec = 1024,   hex = "0x400",      name = "is_glass_type_2",              description = "Breakable glass type 2."},
    {bit = 11, dec = 2048,   hex = "0x800",      name = "is_garage_door",               description = "Indicates a garage door."},
    {bit = 12, dec = 4096,   hex = "0x1000",     name = "is_damagable",                 description = "Model with ok/dam states."},
    {bit = 13, dec = 8192,   hex = "0x2000",     name = "is_tree",                      description = "Trees and some plants."},
    {bit = 14, dec = 16384,  hex = "0x4000",     name = "is_palm",                      description = "Palms."},
    {bit = 15, dec = 32768,  hex = "0x8000",     name = "does_not_collide_with_flyer",  description = "No collision with flyer."},
    {bit = 20, dec = 1048576,hex = "0x100000",   name = "is_tag",                       description = "This model is a tag."},
    {bit = 21, dec = 2097152,hex = "0x200000",   name = "disable_backface_culling",     description = "Disables backface culling."},
    {bit = 22, dec = 4194304,hex = "0x400000",   name = "is_breakable_statue",          description = "Statue not usable as cover."},
    {bit = 50, dec = 0,      hex = "0x000000",   name = "disable_collisions",           description = "Disable collisions.",    custom = true,  value = false}
}

for _, data in ipairs(objectFlags) do
    flagsTableNew[data.bit] = data.name
    flagsTableNew[data.name] = data.name
end

-- Split comma-separated flags into a table
local function splitFlags(flags)
    if type(flags) ~= "string" then return {} end
    local list = {}
    for value in string.gmatch(flags, "([^,]+)") do
        value = value:gsub("^%s*(.-)%s*$", "%1")
        table.insert(list, value)
    end
    return list
end

-- Add named flag keys to attribute table
function getFlags(attribute)
    for _, flag in ipairs(splitFlags(attribute.flags)) do
        local key = tonumber(flag) or flag
        if flagsTableNew[key] then
            attribute[flagsTableNew[key]] = true
        end
    end
end

local function parseBoolean(value)
    if type(value) == "boolean" then
        return value
    end

    if type(value) == "number" then
        return value ~= 0
    end

    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s*(.-)%s*$", "%1"):lower()
    if value == "true" or value == "1" or value == "yes" or value == "on" or value == "enabled" then
        return true
    end
    if value == "false" or value == "0" or value == "no" or value == "off" or value == "disabled" then
        return false
    end
end

local function firstBooleanAttribute(attribute, names)
    for _, name in ipairs(names) do
        if attribute[name] ~= nil then
            local parsed = parseBoolean(attribute[name])
            if parsed ~= nil then
                return parsed
            end
        end
    end
end

local function firstAttribute(attribute, names)
    for _, name in ipairs(names) do
        if attribute[name] ~= nil then
            return attribute[name]
        end
    end
end

local function firstNumberAttribute(attribute, names)
    local value = firstAttribute(attribute, names)
    return value ~= nil and tonumber(value) or nil
end

local function parseVectorAttribute(value)
    if type(value) ~= "string" then
        return
    end

    local x, y, z = value:match(
        "^%s*([^,%s]+)%s*[, ]%s*([^,%s]+)%s*[, ]%s*([^,%s]+)%s*$"
    )
    x, y, z = tonumber(x), tonumber(y), tonumber(z)
    if x and y and z then
        return { x, y, z }
    end
end

local function collectPlacementFlagTokens(attribute)
    local tokens = {}

    local function collect(source)
        if source == nil then return end
        for _, flag in ipairs(splitFlags(source)) do
            local normalized = flag:gsub("^%s*(.-)%s*$", "%1"):lower()
            if normalized ~= "" then
                tokens[normalized] = true
            end
        end
    end

    -- Do not put these two optional values in an ipairs table: when `flags`
    -- is nil Lua stops iteration before reaching the editor's overrideFlags.
    collect(attribute.flags)
    collect(firstAttribute(attribute, {
        "overrideFlags",
        "overrideflags",
        "override_flags"
    }))

    return tokens
end

local function hasPlacementFlag(tokens, names)
    for _, name in ipairs(names) do
        if tokens[name] then
            return true
        end
    end
end

function getPlacementOverrides(attribute)
    local overrides = {}
    local hasOverrides = false
    local tokens = collectPlacementFlagTokens(attribute)
    local parsedFlags = {}

    if attribute.flags then
        parsedFlags.flags = attribute.flags
        getFlags(parsedFlags)
    end
    local overrideFlagsValue = firstAttribute(attribute, {
        "overrideFlags",
        "overrideflags",
        "override_flags"
    })
    if overrideFlagsValue then
        local overrideFlags = {
            flags = overrideFlagsValue
        }
        getFlags(overrideFlags)
        for key, value in pairs(overrideFlags) do
            parsedFlags[key] = value
        end
    end

    local doubleSided = firstBooleanAttribute(attribute, {
        "doubleSided",
        "double_sided",
        "doublesided",
        "double-sided",
        "disableBackfaceCulling",
        "disablebackfaceculling",
        "disable_backface_culling",
        "noBackfaceCulling",
        "nobackfaceculling",
        "no_backface_culling"
    })
    if doubleSided == nil and (parsedFlags.disable_backface_culling or hasPlacementFlag(tokens, {
        "21",
        "double_sided",
        "doublesided",
        "double-sided",
        "disable_backface_culling",
        "no_backface_culling"
    })) then
        doubleSided = true
    end
    if doubleSided ~= nil then
        overrides.doubleSided = doubleSided
        hasOverrides = true
    end

    local collisions = firstBooleanAttribute(attribute, {
        "collisions",
        "collision",
        "collisionsEnabled",
        "collisionsenabled",
        "collisions_enabled"
    })
    if collisions == nil and firstBooleanAttribute(attribute, {
        "noCollisions",
        "nocollisions",
        "no_collisions",
        "collisionsDisabled",
        "collisionsdisabled",
        "collisions_disabled",
        "disableCollisions",
        "disablecollisions",
        "disable_collisions"
    }) then
        collisions = false
    end
    if collisions == nil and (parsedFlags.disable_collisions or parsedFlags.collisions_disabled or hasPlacementFlag(tokens, {
        "50",
        "no_collisions",
        "nocollisions",
        "collisions_disabled",
        "disable_collisions"
    })) then
        collisions = false
    end
    if collisions ~= nil then
        overrides.collisionsEnabled = collisions
        hasOverrides = true
    end

    local breakable = firstBooleanAttribute(attribute, {
        "breakable",
        "objectBreakable",
        "objectbreakable",
        "object_breakable"
    })
    if breakable == nil then
        if hasPlacementFlag(tokens, { "breakable" }) then
            breakable = true
        elseif hasPlacementFlag(tokens, { "unbreakable", "not_breakable", "no_break" }) then
            breakable = false
        end
    end
    if breakable ~= nil then
        overrides.breakable = breakable
        hasOverrides = true
    end

    local damageModel = attribute.damageModel
    local health = tonumber(attribute.objectHealth)
    if type(damageModel) == "string" and damageModel ~= "" and health and health > 0 then
        overrides.damageModel = damageModel
        overrides.objectHealth = health
        hasOverrides = true
    end

    local physicsRoot = firstNumberAttribute(attribute, {
        "physicsRoot",
        "physicsRootModel",
        "physics_root",
        "physics_root_model",
        "physicalPropsRoot",
        "physical_props_root"
    })
    if physicsRoot ~= nil then
        physicsRoot = math.floor(physicsRoot)
        if physicsRoot >= 0 and physicsRoot <= 19999 then
            overrides.physicsRoot = physicsRoot
            hasOverrides = true
        else
            physicsRoot = nil
        end
    end

    local simulated = firstBooleanAttribute(attribute, {
        "simulated",
        "simulate",
        "physicsEnabled",
        "physicsenabled",
        "physics_enabled"
    })
    -- dynamic="true" is an existing eagleLoader opt-out from the building
    -- pool. Treat that established true value as simulated, while preserving
    -- the old meaning of dynamic="false" (no placement override).
    if simulated == nil and firstBooleanAttribute(attribute, { "dynamic" }) == true then
        simulated = true
    end
    -- Selecting a GTA:SA physics root is itself an explicit request for
    -- simulation unless the placement also explicitly disables it.
    if simulated == nil and physicsRoot ~= nil then
        simulated = true
    end
    if simulated ~= nil then
        -- Keep this marker even when an explicit frozen value wins below.
        -- map_loader.lua uses it to keep simulated placements out of the
        -- building pool, whose elements cannot participate in object physics.
        overrides.simulated = simulated
        hasOverrides = true
    end

    local frozen = firstBooleanAttribute(attribute, {
        "frozen",
        "freeze"
    })
    if frozen == nil and hasPlacementFlag(tokens, { "frozen", "freeze" }) then
        frozen = true
    end
    if frozen == nil and simulated ~= nil then
        frozen = not simulated
    end
    if frozen ~= nil then
        overrides.frozen = frozen
        hasOverrides = true
    end

    local respawn = firstBooleanAttribute(attribute, {
        "respawn",
        "objectRespawn",
        "objectrespawn",
        "object_respawn",
        "respawnable"
    })
    if respawn ~= nil then
        overrides.respawn = respawn
        hasOverrides = true
    end

    local streamable = firstBooleanAttribute(attribute, {
        "streamable",
        "streamed"
    })
    local noStream = firstBooleanAttribute(attribute, {
        "no_stream",
        "noStream",
        "nostream"
    })
    if streamable == nil and (noStream or hasPlacementFlag(tokens, { "no_stream", "nostream" })) then
        streamable = false
    end
    if streamable ~= nil then
        overrides.streamable = streamable
        hasOverrides = true
    end

    local alpha = tonumber(attribute.alpha)
    if alpha then
        overrides.alpha = math.max(0, math.min(255, alpha))
        hasOverrides = true
    end

    local scaleValue = firstAttribute(attribute, {
        "scale",
        "objectScale",
        "objectscale",
        "object_scale"
    })
    local scale = scaleValue and tonumber(scaleValue)
    if scale then
        overrides.scale = scale
        hasOverrides = true
    end

    -- These are the complete per-object physical properties exposed by
    -- MTA's setObjectProperty API. Air resistance is the closest GTA/MTA
    -- equivalent to linear damping, so accept common damping spellings too.
    local objectProperties = {}
    local physicalPropertyAttributes = {
        mass = {
            "mass"
        },
        turn_mass = {
            "turnMass",
            "turnmass",
            "turn_mass",
            "rotationalMass",
            "rotationalmass",
            "rotational_mass"
        },
        air_resistance = {
            "airResistance",
            "airresistance",
            "air_resistance",
            "damping",
            "dampening",
            "linearDamping",
            "lineardamping",
            "linear_damping"
        },
        elasticity = {
            "elasticity",
            "restitution",
            "bounciness"
        },
        buoyancy = {
            "buoyancy"
        }
    }

    for property, names in pairs(physicalPropertyAttributes) do
        local value = firstNumberAttribute(attribute, names)
        if value ~= nil then
            objectProperties[property] = value
        end
    end

    local centerOfMass = parseVectorAttribute(firstAttribute(attribute, {
        "centerOfMass",
        "centerofmass",
        "center_of_mass"
    }))
    if not centerOfMass then
        local centerX = firstNumberAttribute(attribute, {
            "centerOfMassX",
            "centerofmassx",
            "center_of_mass_x"
        })
        local centerY = firstNumberAttribute(attribute, {
            "centerOfMassY",
            "centerofmassy",
            "center_of_mass_y"
        })
        local centerZ = firstNumberAttribute(attribute, {
            "centerOfMassZ",
            "centerofmassz",
            "center_of_mass_z"
        })
        if centerX ~= nil or centerY ~= nil or centerZ ~= nil then
            centerOfMass = {
                centerX or 0,
                centerY or 0,
                centerZ or 0
            }
        end
    end
    if centerOfMass then
        objectProperties.center_of_mass = centerOfMass
    end

    if next(objectProperties) then
        overrides.objectProperties = objectProperties
        hasOverrides = true
    end

    return hasOverrides and overrides or nil
end

-- Definition-level physics uses the same canonical attributes as placements,
-- but only the physics subset is inherited by every placement of that ID.
function getPhysicsOverrides(attribute)
    local parsed = getPlacementOverrides(attribute)
    if not parsed then
        return
    end

    local overrides = {}
    if parsed.simulated ~= nil then
        overrides.simulated = parsed.simulated
    end
    if parsed.frozen ~= nil then
        overrides.frozen = parsed.frozen
    end
    if parsed.physicsRoot ~= nil then
        overrides.physicsRoot = parsed.physicsRoot
    end
    if parsed.breakable ~= nil then
        overrides.breakable = parsed.breakable
    end
    if parsed.respawn ~= nil then
        overrides.respawn = parsed.respawn
    end
    if parsed.objectProperties ~= nil then
        overrides.objectProperties = parsed.objectProperties
    end
    return next(overrides) and overrides or nil
end

function mergePlacementOverrides(globalOverrides, placementOverrides)
    if not globalOverrides then
        return placementOverrides
    end
    if not placementOverrides then
        return globalOverrides
    end

    local merged = {}
    for key, value in pairs(globalOverrides) do
        merged[key] = value
    end
    for key, value in pairs(placementOverrides) do
        if key ~= "objectProperties" then
            merged[key] = value
        end
    end

    if globalOverrides.objectProperties or placementOverrides.objectProperties then
        local objectProperties = {}
        for property, value in pairs(globalOverrides.objectProperties or {}) do
            objectProperties[property] = value
        end
        for property, value in pairs(placementOverrides.objectProperties or {}) do
            objectProperties[property] = value
        end
        merged.objectProperties = objectProperties
    end

    return merged
end

------------------------------
-- IMG Asset Utilities
------------------------------

local function toNum(v, default)
    return tonumber(v) or default
end

local function splitCSV(str)
    local t = {}
    if type(str) ~= "string" then return t end
    for token in str:gmatch("([^,]+)") do
        token = token:gsub("^%s*(.-)%s*$", "%1")
        if token ~= "" then table.insert(t, token) end
    end
    return t
end

local function getXmlAttr(node, name)
    return node and xmlNodeGetAttribute(node, name) or nil
end

local mapResourceIMGConfig = {}

-- outputDebugString2 is defined later (debug_helper.lua); these functions only
-- run at map-load time, so it is always available by then. Fall back just in case.
local function imgDebug(str, level)
    if outputDebugString2 then
        outputDebugString2(str, level or 3)
    else
        outputDebugString(str, level or 3)
    end
end

local function getResourceIMGConfig(resourceName)
    if mapResourceIMGConfig[resourceName] then
        return mapResourceIMGConfig[resourceName].archives
    end

    local config = { archives = {} }
    for _, name in ipairs(IMGNames) do
        table.insert(config.archives, { name = name, max = maxIMG })
    end

    -- Per-resource IMG name override. Without it eagleLoader only knows the
    -- built-in names (dff/col/txd/custom); maps with non-standard archive names
    -- ship an eagleLoader-imgs.xml listing their own names.
    local configPath = string.format(":%s/eagleLoader-imgs.xml", resourceName)
    if not fileExists(configPath) then
        -- No override: this is normal for standard maps.
        mapResourceIMGConfig[resourceName] = config
        return config.archives
    end

    local xml = xmlLoadFile(configPath)
    if not xml then
        imgDebug(string.format(
            "eagleLoader: '%s' exists but could not be parsed; falling back to default IMG names {%s}.",
            configPath, table.concat(IMGNames, ", ")), 2)
        mapResourceIMGConfig[resourceName] = config
        return config.archives
    end

    local archives = {}
    local function addNames(value, nodeMax)
        for _, name in ipairs(splitCSV(value)) do
            table.insert(archives, { name = name, max = nodeMax })
        end
    end

    local function readImgNode(imgNode)
        local nodeMax = toNum(getXmlAttr(imgNode, "max"), maxIMG)
        -- `names` supports a comma-separated list; `name` supports one archive
        -- per node, allowing each archive to have a separate max value.
        addNames(getXmlAttr(imgNode, "names"), nodeMax)
        addNames(getXmlAttr(imgNode, "name"), nodeMax)
    end

    if xmlNodeGetName(xml) == "img" then
        readImgNode(xml)
    else
        local i = 0
        while true do
            local imgNode = xmlFindChild(xml, "img", i)
            if not imgNode then break end
            readImgNode(imgNode)
            i = i + 1
        end
    end

    if #archives > 0 then
        config.archives = archives
        imgDebug(string.format(
            "eagleLoader: applied IMG name override for '%s' (%d archive entries).",
            resourceName, #config.archives), 3)
    else
        imgDebug(string.format(
            "eagleLoader: '%s' has no valid <img name=\"...\" /> or <img names=\"...\" /> node; falling back to default IMG names {%s}.",
            configPath, table.concat(IMGNames, ", ")), 2)
    end
    xmlUnloadFile(xml)

    mapResourceIMGConfig[resourceName] = config
    return config.archives
end

function findImg(assetType, resourceName)
    resourceImages[resourceName] = resourceImages[resourceName] or {}
    if not resourceImages[resourceName][assetType] then
        local path = string.format(":%s/imgs/%s.img", resourceName, assetType)
        local img = engineLoadIMG(path)
        if not isElement(img) then
            imgDebug("eagleLoader: failed to load IMG archive " .. path, 1)
            return false
        end
        if not engineAddImage(img) then
            destroyElement(img)
            imgDebug("eagleLoader: failed to add IMG archive to the streamer: " .. path, 1)
            return false
        end
        resourceImages[resourceName][assetType] = img
    end
    return resourceImages[resourceName][assetType], string.format(":%s/imgs/%s.img", resourceName, assetType)
end

function inIMGAsset(assetName, assetType, resourceName)
    return getIMGAsset(assetName, assetType, resourceName) and true or false
end

function getIMGAsset(assetName, assetType, resourceName)
    if not (imageFiles[resourceName] and imageFilePaths[resourceName]) then return false end

    local requestedPath = string.format("%s.%s", assetName, assetType)
    local lookupPath = imageFilePaths[resourceName][requestedPath] or imageFilePaths[resourceName][requestedPath:lower()]
    if not lookupPath then return false end

    return imageFiles[resourceName][lookupPath], lookupPath, imageFileIndices[resourceName][lookupPath]
end

function prepIMGFiles(img, resourceName)
    if not isElement(img) then return false end
    local filesInArchive = engineImageGetFiles(img)
    if type(filesInArchive) ~= "table" then
        imgDebug("eagleLoader: failed to enumerate an IMG archive for " .. tostring(resourceName), 1)
        return false
    end
    for i = 1, #filesInArchive do
        local assetPath = filesInArchive[i]
        imageFiles[resourceName][assetPath] = img
        imageFileIndices[resourceName][assetPath] = i - 1
        imageFilePaths[resourceName][assetPath] = assetPath
        imageFilePaths[resourceName][assetPath:lower()] = assetPath

    end
    return true
end

function prepIMGContainers(resourceName)
    local resourceIMGArchives = getResourceIMGConfig(resourceName)
    imageFiles[resourceName] = {}
    imageFilePaths[resourceName] = {}
    imageFileIndices[resourceName] = {}
    local loadedCount = 0
    for _, archive in ipairs(resourceIMGArchives) do
        local v = archive.name
        local archiveMax = archive.max
        local found = false
        for i = 0, archiveMax do
            local img

            if i == 0 then
                if fileExists(string.format(":%s/imgs/%s.img", resourceName, v)) then
                    img = findImg(v, resourceName)
                end
            end
            if not img then
                if fileExists(string.format(":%s/imgs/%s_%s.img", resourceName, v, i)) then
                    img = findImg(v .. "_" .. i, resourceName)
                elseif fileExists(string.format(":%s/imgs/%s%s.img", resourceName, v, i)) then
                    img = findImg(v .. i, resourceName)
                end
            end

            if img then
                if prepIMGFiles(img, resourceName) then
                    found = true
                    loadedCount = loadedCount + 1
                end
            end
        end
        if not found then
            imgDebug(string.format(
                "eagleLoader: no IMG archive found for configured name '%s' in '%s' (looked for :%s/imgs/%s.img). " ..
                "If you expected an override, check eagleLoader-imgs.xml is a <file> in the map's meta.xml.",
                v, resourceName, resourceName, v), 2)
        end
    end

    local fileCount = 0
    for _ in pairs(imageFiles[resourceName]) do fileCount = fileCount + 1 end
    imgDebug(string.format(
        "eagleLoader: prepared %d IMG archive(s) / %d file entries for '%s'.",
        loadedCount, fileCount, resourceName), 3)
    return loadedCount
end

function unloadResourceIMGs(resourceName)
    if not resourceName then
        return
    end

    local removed = {}
    for _, img in pairs(resourceImages[resourceName] or {}) do
        if isElement(img) and not removed[img] then
            if eagleLoaderStopTrace then eagleLoaderStopTrace(resourceName, "img-remove") end
            engineRemoveImage(img)
            -- engineRemoveImage only disables streaming. The IMG element still
            -- owns the archive handle, so destroy it before the source map
            -- resource is allowed to unload its files.
            if isElement(img) then
                if eagleLoaderStopTrace then eagleLoaderStopTrace(resourceName, "img-destroy") end
                destroyElement(img)
            end
            removed[img] = true
        end
    end

    imageFiles[resourceName] = nil
    imageFilePaths[resourceName] = nil
    imageFileIndices[resourceName] = nil
    resourceImages[resourceName] = nil
    -- A map's meta/config may change while eagleLoader stays running. Drop the
    -- parsed archive-name list so the next map start reads eagleLoader-imgs.xml
    -- again instead of retaining the old default names.
    mapResourceIMGConfig[resourceName] = nil
end

------------------------------
-- General Utilities
------------------------------

function splitString(str, sep)
    if type(str) ~= "string" or str == "" or not string.find(str, sep, 1, true) then
        return false
    end
    local result = {}
    for token in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(result, token)
    end
    return #result > 0 and result or false
end

------------------------------
-- Show Nearby Building/Object Utilities
------------------------------

local function showNearby(typeName, commandName, elementType)
    addCommandHandler(commandName, function(_, radius)
        radius = tonumber(radius) or 35
        local px, py, pz = getElementPosition(localPlayer)
        local elements = getElementsByType(elementType)
        local count = 0

        outputChatBox(string.format("#0066CC[Nearby %s]#FFFFFF Scanning within #FFFF00%d m#FFFFFF...", typeName, radius), 255,255,255,true)
        for _, elem in ipairs(elements) do
            local ox, oy, oz = getElementPosition(elem)
            local dist = getDistanceBetweenPoints3D(px, py, pz, ox, oy, oz)
            if dist <= radius then
                local model = getElementModel(elem)
                local id = getElementID(elem) or "N/A"
                local zone = definitionZones[id] or "Unknown"
                outputChatBox(string.format(
                    "#CCCCCC • #00BFFFModel: #FFFFFF%s  #AAAAAA|  #00BFFFID: #FFFFFF%s  #AAAAAA|  #00BFFFZone: #FFFFFF%s  #AAAAAA|  #00BFFFDist: #FFFFFF%dm",
                    model, id, zone, math.floor(dist)
                ), 255,255,255,true)
                count = count + 1
            end
        end

        if count == 0 then
            outputChatBox(string.format("#FF4444No %s found within #FFFF00%d m#FF4444.", typeName:lower(), radius), 255,255,255,true)
        else
            outputChatBox(string.format("#00FF00Total %s found: #FFFFFF%d", typeName:lower(), count), 255,255,255,true)
        end
    end)
end

showNearby("Buildings", "nearbybuildings", "building")
showNearby("Objects", "nearbyobjects", "object")

local function countTableEntries(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end

local function findDefinitionForID(id)
    for resourceName, definitions in pairs(resourceDefinitions or {}) do
        local definition = definitions and definitions[id]
        if definition then
            return resourceName, definition
        end
    end
end

local function outputFindIDLine(text)
    outputChatBox("#0066CC[findid]#FFFFFF " .. text, 255, 255, 255, true)
    outputConsole("[findid] " .. text)
end

local function describeElement(element, label)
    if not isElement(element) then
        return
    end

    local x, y, z = getElementPosition(element)
    local model = getElementModel(element)
    local alpha = getElementAlpha(element)
    local elementType = getElementType(element)
    outputFindIDLine(string.format(
        "%s: type=%s model=%s alpha=%s pos=%.2f, %.2f, %.2f interior=%s dimension=%s",
        label,
        tostring(elementType),
        tostring(model),
        tostring(alpha),
        x, y, z,
        tostring(getElementInterior(element)),
        tostring(getElementDimension(element))
    ))
end

addCommandHandler("findid", function(_, id)
    id = tostring(id or ""):gsub("^%s*(.-)%s*$", "%1")
    if id == "" then
        outputFindIDLine("Usage: /findid <building/object id>")
        return
    end

    local requestedModel = idCache and idCache[id]
    local defaultModel = defaultIDs and defaultIDs[id]
    local resourceName, definition = findDefinitionForID(id)

    outputFindIDLine(string.format(
        "id=%s requestedSA=%s defaultSA=%s defaultPhysics=%s resource=%s zone=%s",
        id,
        tostring(requestedModel or "none"),
        tostring(defaultModel or "none"),
        tostring(defaultModel and isSAPhysicsObjectID(defaultModel) or false),
        tostring(resourceName or "unknown"),
        tostring((definition and definition.zone) or definitionZones[id] or "unknown")
    ))

    if definition then
        outputFindIDLine(string.format(
            "definition: dff=%s txd=%s col=%s lodDistance=%s flags=%s",
            tostring(definition.dff or definition.id or "none"),
            tostring(definition.txd or "none"),
            tostring(definition.col or definition.id or "none"),
            tostring(definition.lodDistance or "none"),
            tostring(definition.flags or "none")
        ))
    end

    local listed = 0
    for index, element in ipairs(itemIDList[id] or {}) do
        listed = listed + 1
        describeElement(element, "element[" .. index .. "]")
    end

    for uniqueID, element in pairs(itemIDListUnique[id] or {}) do
        listed = listed + 1
        describeElement(element, "unique[" .. tostring(uniqueID) .. "]")
    end

    if listed == 0 then
        for _, elementType in ipairs({"building", "object"}) do
            for _, element in ipairs(getElementsByType(elementType)) do
                if getElementID(element) == id then
                    listed = listed + 1
                    describeElement(element, "world[" .. listed .. "]")
                end
            end
        end
    end

    outputFindIDLine(string.format(
        "liveElements=%d tracked=%d uniqueTracked=%d",
        listed,
        #(itemIDList[id] or {}),
        countTableEntries(itemIDListUnique[id])
    ))
end)
