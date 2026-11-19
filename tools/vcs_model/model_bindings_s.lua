function getVcsModelBase(originalId, kind)
    local model = VCS_TRAFFIC_MODEL_CATALOG[originalId]
    if model and model.kind == kind then return model.base, model.name end
    return false
end

getTrafficModelBase = getVcsModelBase
