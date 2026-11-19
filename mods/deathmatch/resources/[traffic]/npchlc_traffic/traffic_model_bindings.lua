TrafficModelBindings = {}

local bindings, nativePeds, steeringLimits
local providerName

local function activeProvider()
    local resource = type(providerName) == "string" and getResourceFromName(providerName)
    return resource and getResourceState(resource) == "running" and resource
end

function TrafficModelBindings.hasCatalog()
    return activeProvider() or nativePeds and true or next(bindings and bindings.ped or {}) ~= nil
end

function TrafficModelBindings.load(graph, configuredProvider)
    providerName = graph.modelProvider
    if type(configuredProvider) == "string" and configuredProvider ~= "" and configuredProvider ~= "auto" then
        providerName = configuredProvider ~= "none" and configuredProvider or nil
    end
    bindings = {ped = {}, vehicle = {}}
    steeringLimits = graph.vehicleSteeringLimits or {}
    for _, entry in ipairs(graph.modelBindings or {}) do
        local group = bindings[entry.kind or "vehicle"]
        if group and entry.originalId ~= nil then group[entry.originalId] = entry end
    end
    nativePeds = nil
    if graph.modelIdSpace == "mta" then
        nativePeds = {}
        for _, model in ipairs(getValidPedModels()) do nativePeds[model] = true end
    end
end

local function resolve(originalId, kind)
    if type(originalId) ~= "number" then return false end
    local provider = activeProvider()
    if provider then
        local model, name = call(provider, "getTrafficModelBase", originalId, kind)
        if model then return model, name end
    end
    local entry = bindings and bindings[kind][originalId]
    if entry then return entry.model, entry.name end
    if nativePeds and (kind == "ped" and nativePeds[originalId]
        or kind == "vehicle" and originalId % 1 == 0 and originalId >= 400 and originalId <= 611) then
        return originalId
    end
    return false
end

function TrafficModelBindings.getPedestrian(originalId)
    return resolve(originalId, "ped")
end

function TrafficModelBindings.get(originalId)
    return resolve(originalId, "vehicle")
end

function TrafficModelBindings.tag(element, originalId)
    local kind = getElementType(element)
    local provider = activeProvider()
    if provider and type(originalId) == "number" and call(provider, "getTrafficModelBase", originalId, kind) then
        setElementData(element, "npchlc_traffic:modelProvider", providerName, "broadcast", "deny")
    end
    if kind == "vehicle" then
        local limit = steeringLimits and steeringLimits[tostring(originalId)]
        if type(limit) == "number" and limit > 0 and limit <= 1 then
            setElementData(element, "npchlc_traffic:steeringLimit", limit, "broadcast", "deny")
        end
    end
    setElementData(element, "npchlc_traffic:originalModel", originalId, "broadcast", "deny")
end
