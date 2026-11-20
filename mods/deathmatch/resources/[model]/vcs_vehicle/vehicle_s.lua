-- External scripts can bind a native hull or construct one using the converted
-- model catalog. The synchronized identity survives controller resource restarts.
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

function bindVcsVehicle(vehicle, originalId)
    if not matchesHull(vehicle, originalId) then return false end
    return setElementData(vehicle, CVehicle.modelKey, originalId, "broadcast", "deny")
end

function isBoundVcsVehicle(vehicle)
    return isElement(vehicle) and matchesHull(vehicle, getElementData(vehicle, CVehicle.modelKey, false))
end

local createdFor = setmetatable({}, {__mode="k"})
addEventHandler("onResourceStop",root,function(owner)
    for vehicle, creator in pairs(createdFor) do
        if creator == owner and isElement(vehicle) then destroyElement(vehicle) end
    end
end)

function createVcsVehicle(originalId, x, y, z, rx, ry, rz)
    local owner = sourceResource
    if type(x) ~= "number" or type(y) ~= "number"
        or type(z) ~= "number" then return false end
    local assets = getResourceFromName("vcs_model")
    if not assets or getResourceState(assets) ~= "running" then return false end
    local base = call(assets, "getVcsModelBase", originalId, "vehicle")
    if not base then return false end
    local vehicle = createVehicle(base, x, y, z, rx or 0, ry or 0, rz or 0)
    if not vehicle then return false end
    if not bindVcsVehicle(vehicle, originalId) then destroyElement(vehicle) return false end
    createdFor[vehicle] = owner
    return vehicle
end
