-- Class methods live on the registered controller. Runtime MTA model IDs
-- may change on stream-in, so dispatch uses the original VCS model ID.
CVehicle = {name="CVehicle", modelKey="vcs_vehicle:originalModel"}
local classes = {}

function CVehicle.derive(name, parent)
    local class = setmetatable({name=name}, {__index=parent})
    class.__index = class
    return class
end

function CVehicle:New(hull)
    return setmetatable({vehicle=hull}, self)
end

CAutomobile = CVehicle.derive("CAutomobile", CVehicle)

function CVehicle.register(originalId, class)
    assert(not classes[originalId], "Duplicate VCS vehicle controller for model "..originalId)
    classes[originalId] = class
end

function CVehicle.forModel(originalId)
    return classes[originalId]
end

function CVehicle.isLegacyJetSki(vehicle)
    return getElementData(vehicle, "mod.model", false) == "JETSKI"
end

function CVehicle.originalModel(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    return getElementData(vehicle, CVehicle.modelKey, false)
        or getElementData(vehicle, "npchlc_traffic:originalModel", false)
        or (CVehicle.isLegacyJetSki(vehicle) and 233) or false
end

function CVehicle.resolve(vehicle)
    return classes[CVehicle.originalModel(vehicle)]
end

local policeParents = {[191]=523, [193]=598, [204]=597, [207]=596, [234]=427, [268]=490}
function CVehicle.hasPoliceSiren(vehicle)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" then return false end
    return policeParents[CVehicle.originalModel(vehicle)] == getElementModel(vehicle)
end

function getVcsVehicleClass(vehicle)
    local class = CVehicle.resolve(vehicle)
    return class and class.name or false
end
