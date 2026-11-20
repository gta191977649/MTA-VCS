TrafficModelBindings = {}

local bindings, nativePeds, steeringLimits
local providerName, streetModels

local function activeProvider()
    local resource = type(providerName) == "string" and getResourceFromName(providerName)
    return resource and getResourceState(resource) == "running" and resource
end

function TrafficModelBindings.hasCatalog()
    return activeProvider() or streetModels ~= nil or nativePeds and true or next(bindings and bindings.ped or {}) ~= nil
end

function TrafficModelBindings.load(graph, configuredProvider)
    providerName = graph.modelProvider
    if type(configuredProvider) == "string" and configuredProvider ~= "" and configuredProvider ~= "auto" then
        providerName = configuredProvider ~= "none" and configuredProvider or nil
    end
    bindings = {ped = {}, vehicle = {}}
    streetModels = graph.edition == "SLUS-21590 USA v1.00" and StreetPedModels or nil
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
    local street = kind == "ped" and streetModels and streetModels[originalId]
    if street and (providerName == "vcs_model" or not providerName) then
        return street.base, street.name
    end
    local provider = activeProvider()
    if provider then
        local model, name = call(provider, "getTrafficModelBase", originalId, kind)
        if model then return model, name end
    end
    local entry = bindings and bindings[kind][originalId]
    if entry then return entry.model, entry.name end
    if street then return street.base, street.name end
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

function TrafficModelBindings.tag(element, originalId, scripted)
    local kind = getElementType(element)
    local provider = activeProvider()
    local street = kind == "ped" and streetModels and streetModels[originalId]
    if street and (providerName == "vcs_model" or not providerName) then
        setElementData(element, "npchlc_traffic:modelProvider", getResourceName(getThisResource()), "broadcast", "deny")
    elseif provider and type(originalId) == "number" and call(provider, "getTrafficModelBase", originalId, kind) then
        setElementData(element, "npchlc_traffic:modelProvider", providerName, "broadcast", "deny")
    elseif street and not (bindings and bindings.ped[originalId]) then
        setElementData(element, "npchlc_traffic:modelProvider", getResourceName(getThisResource()), "broadcast", "deny")
    end
    local pedModel = not nativePeds and kind == "ped" and PedAIModels and PedAIModels[originalId]
    if pedModel then
        local stat, group = PedAIStats[pedModel[2]],PedAITypes[pedModel[1]]
        -- 001ED840 starts a civilian at 100; 001D7940 scales incoming damage.
        -- Express the same damage budget in native MTA health units so synced
        -- hits, including lethal hits, keep their original attacker and order.
        if not scripted and pedModel[1]>=4 and stat.damageScale and stat.damageScale~=1
            and not getElementData(element,"npchlc_traffic:originalModel",false) then
            local hp=100/stat.damageScale
            if hp>100 then setPedStat(element,24,math.ceil(hp/0.176)) end
            setElementData(element,"npchlc_traffic:spawnHealth",hp,false)
            setElementHealth(element,hp)
        end
        local yields = stat.temper <= stat.fear or stat.temper < 51
        setElementData(element,"npchlc_traffic:passing",{group.identity,yields and group.avoid or 0},"broadcast","deny")
    end
    if kind == "vehicle" then
        local vehicleType = getVehicleType(element)
        if vehicleType == "Boat" or vehicleType == "Plane" then
            exports.vcs_vehicle:bindVcsVehicle(element, originalId)
        end
        local limit = steeringLimits and steeringLimits[tostring(originalId)]
        if type(limit) == "number" and limit > 0 and limit <= 1 then
            setElementData(element, "npchlc_traffic:steeringLimit", limit, "broadcast", "deny")
        end
    end
    setElementData(element, "npchlc_traffic:originalModel", originalId, "broadcast", "deny")
end
