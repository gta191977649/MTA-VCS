function getVcsModelBase(originalId, kind)
    local model = VCS_TRAFFIC_MODEL_CATALOG[originalId]
    if model and model.kind == kind then return model.base, model.name end
    return false
end

getTrafficModelBase = getVcsModelBase

-- Resolve against the live catalog so consumers do not copy model indexes.
function getVcsModelIdByName(name, kind)
    if type(name) ~= "string" then return false end
    name = name:lower()
    for id, model in pairs(VCS_TRAFFIC_MODEL_CATALOG) do
        if model.name == name and (not kind or model.kind == kind) then return id end
    end
    return false
end
