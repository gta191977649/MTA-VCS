local handlingData
function getVcsHandlingData()
    if not handlingData then
        local file = fileOpen("data/handling.dat", true)
        if not file then return false end
        handlingData = fileRead(file, fileGetSize(file))
        fileClose(file)
    end
    return handlingData
end

-- Scripts can bind a native hull or construct one from the converted catalog.
-- The synchronized identity survives controller resource restarts.
local restoringIdentity = false
addEventHandler("onElementDataChange",root,function(key,previous)
    if client and not restoringIdentity and key == CVehicle.modelKey and getElementType(source) == "vehicle" then
        restoringIdentity = true
        setElementData(source, key, previous or false, "broadcast", "deny")
        restoringIdentity = false
    end
end)

local function matchesHull(vehicle, originalId)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    local class = CVehicle.forModel(originalId)
    if class and class.nativeType ~= getVehicleType(vehicle) then return false end
    local assets = getResourceFromName("vcs_model")
    local base
    if assets and getResourceState(assets) == "running" then
        base = call(assets, "getVcsModelBase", originalId, "vehicle")
    elseif class then
        -- Binding an existing native hull is also supported without the asset provider.
        base = class.baseModel or (class.baseModels and class.baseModels[originalId])
    end
    return base and getElementModel(vehicle) == base or false
end

local dashboardBeacon = {[193]={.38,.74,.23}, [204]={.36,.57,.16}}
addEvent("vcs_vehicle:setDriverSiren", true)
addEventHandler("vcs_vehicle:setDriverSiren", root, function(enabled)
    if client and type(enabled) == "boolean" and CVehicle.hasPoliceSiren(source)
        and getVehicleOccupant(source, 0) == client and isControlEnabled(client, "horn") then
        setVehicleSirensOn(source, enabled)
    end
end)

function configureVcsDashboardBeacon(vehicle, originalId)
    local position = dashboardBeacon[originalId]
    if not position or not addVehicleSirens(vehicle,1,2,true,false,false,false) then return false end
    return setVehicleSirens(vehicle,1,position[1],position[2],position[3],255,24,16,255,0)
end

-- Keep spawn settings on the server so a controller reload or repeat bind
-- preserves an existing respray. Clients receive the native MTA RGB colors.
local paintKey = "vcs_vehicle:spawnPaint"
local cursors = {}
local unpainted = {5,5,5}

local function applyRGB(vehicle, primary, secondary)
    return setVehicleColor(vehicle, primary[1], primary[2], primary[3],
        secondary[1], secondary[2], secondary[3])
end

local function applyVariation(vehicle, model, pair)
    local first, second = pair[1], pair[2]
    return applyRGB(vehicle, model.colors[first] or VcsPaint.palette[first],
        model.colors[second] or VcsPaint.palette[second])
end

local function nextVariation(id, model)
    local index = ((cursors[id] or model.cursor) + 1) % model.count
    cursors[id] = index
    return index
end

local function factoryPaint(vehicle, id, normal, alternate, previous)
    local model = VcsPaint.models[id]
    if not model then return false end
    local pair, index
    -- The vehicle constructor advances the factory sequence even when the
    -- SCM generator subsequently replaces both channels with a fixed pair.
    if model.count > 0 then
        index = nextVariation(id, model)
        if model.count > 1 and index == previous then index = nextVariation(id, model) end
        pair = model.pairs[index + 1]
    else
        index = 100 -- Sentinel used by the original zero-variation chooser.
    end
    if normal >= 0 then
        index, pair = normal, model.pairs[normal + 1]
    elseif alternate >= 0 then
        index, pair = -1, model.alternate[alternate + 1]
    end
    local ok
    if pair then ok = applyVariation(vehicle, model, pair)
    else ok = applyRGB(vehicle, unpainted, unpainted) end
    return ok, index
end

local function validSlot(index, slots)
    return index == -1 or type(index) == "number" and index >= 0 and index % 1 == 0 and slots[index+1] ~= nil
end

-- The PS2 Taxi has rule 0x1F10 at model +0x150. 00394F60 chooses
-- exactly one of extra1/extra2, the two roof signs. The Cabbie has a
-- fixed sign in its chassis mesh. Availability lighting is independent.
local function ensureTaxiRoof(vehicle, id)
    if id ~= 226 and (id or getElementModel(vehicle) ~= 420) then return end
    local first, second = getVehicleVariant(vehicle)
    if second == 255 and (first == 0 or first == 1) then return end
    setVehicleVariant(vehicle, math.random(0,1), 255)
end

local function initializePaint(vehicle, id, normal, alternate)
    local model = VcsPaint.models[id]
    if not model or not validSlot(normal, model.pairs) or not validSlot(alternate, model.alternate) then return false end
    local ok, index = factoryPaint(vehicle, id, normal, alternate)
    if ok then
        setElementData(vehicle, paintKey, {id,normal,alternate,index}, "local", "deny")
        ensureTaxiRoof(vehicle,id)
    end
    return ok
end

-- Some legacy models use their own DFF on a different SA hull.
-- Bind only the original paint identity for those server-created vehicles.
function bindVcsVehiclePaint(vehicle, originalId)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" or not VcsPaint.models[originalId] then return false end
    local settings = getElementData(vehicle,paintKey,false)
    if settings and settings[1] == originalId then return true end
    return initializePaint(vehicle,originalId,-1,-1)
end

local function paintModel(vehicle)
    local id = CVehicle.originalModel(vehicle)
    if id then return id end
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    local settings = getElementData(vehicle,paintKey,false)
    return settings and settings[1]
end

local function repaint(vehicle, avoidCurrent)
    local id = paintModel(vehicle)
    if not VcsPaint.models[id] then return false end
    local settings = getElementData(vehicle, paintKey, false)
    if not settings or settings[1] ~= id then settings = {id,-1,-1} end
    local ok,index = factoryPaint(vehicle,id,-1,-1,avoidCurrent and settings[4])
    if ok then
        settings[4]=index
        setElementData(vehicle,paintKey,settings,"local","deny")
    end
    return ok
end

function setVcsVehiclePaint(vehicle, primary, secondary)
    if primary == -1 and secondary == -1 then return repaint(vehicle,false) end
    if not VcsPaint.models[paintModel(vehicle)] then return false end
    -- SCM 0150 addresses the shared vehicle palette directly.
    local first, second = VcsPaint.palette[primary], VcsPaint.palette[secondary]
    if not first or not second then return false end
    return applyRGB(vehicle,first,second)
end

function resprayVcsVehicle(vehicle)
    return repaint(vehicle,true)
end

function bindVcsVehicle(vehicle, originalId, normal, alternate)
    if not matchesHull(vehicle, originalId) then return false end
    local settings = getElementData(vehicle, paintKey, false)
    if not settings or settings[1] ~= originalId then
        if not initializePaint(vehicle,originalId,normal or -1,alternate or -1) then return false end
    end
    if dashboardBeacon[originalId] then configureVcsDashboardBeacon(vehicle, originalId) end
    if getElementData(vehicle, CVehicle.modelKey, false) == originalId then return true end
    return setElementData(vehicle, CVehicle.modelKey, originalId, "broadcast", "deny")
end

function isBoundVcsVehicle(vehicle)
    return isElement(vehicle) and matchesHull(vehicle, getElementData(vehicle, CVehicle.modelKey, false))
end

local createdFor = setmetatable({}, {__mode="k"})

addEventHandler("onVehicleRespawn",root,function()
    local settings = getElementData(source,paintKey,false)
    if settings then initializePaint(source,settings[1],settings[2],settings[3])
    elseif getElementModel(source)==420 then ensureTaxiRoof(source,paintModel(source)) end
end)

addEventHandler("onResourceStart",resourceRoot,function()
    for _,vehicle in ipairs(getElementsByType("vehicle")) do
        local id = paintModel(vehicle)
        ensureTaxiRoof(vehicle,id)
        if VcsPaint.models[id] and not getElementData(vehicle,paintKey,false) then
            initializePaint(vehicle,id,-1,-1)
        end
    end
end)

-- The VCS Taxi also replaces native slot 420 for ordinary MTA spawns.
addEventHandler("onElementStartSync",root,function()
    if getElementType(source)=="vehicle" and getElementModel(source)==420 then
        ensureTaxiRoof(source,paintModel(source))
    end
end)

addEventHandler("onResourceStop",root,function(owner)
    for vehicle, creator in pairs(createdFor) do
        if creator == owner and isElement(vehicle) then destroyElement(vehicle) end
    end
end)

function createVcsVehicle(originalId, x, y, z, rx, ry, rz, normalVariation, alternateVariation)
    local owner = sourceResource
    if type(x) ~= "number" or type(y) ~= "number"
        or type(z) ~= "number" then return false end
    local assets = getResourceFromName("vcs_model")
    if not assets or getResourceState(assets) ~= "running" then return false end
    local base = call(assets, "getVcsModelBase", originalId, "vehicle")
    if not base then return false end
    local vehicle = createVehicle(base, x, y, z, rx or 0, ry or 0, rz or 0)
    if not vehicle then return false end
    if not bindVcsVehicle(vehicle, originalId, normalVariation, alternateVariation) then destroyElement(vehicle) return false end
    createdFor[vehicle] = owner
    return vehicle
end
