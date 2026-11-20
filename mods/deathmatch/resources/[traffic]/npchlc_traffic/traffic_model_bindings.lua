TrafficModelBindings = {}

local bindings, nativePeds, steeringLimits
local providerName, streetModels
-- The traffic archive contains the FBI and Vice variants. The other
-- fallbacks keep ordinary patrols available while a model provider restarts.
local policeVariants = {
    [191]={523,"electrap"}, [193]={598,"fbicar"}, [204]={597,"vicechee"},
    [207]={596,"policem"}, [218]={433,"barracks"}, [219]={430,"predator"}, [234]={427,"enforce"},
    [246]={432,"rhino"}, [261]={497,"polmav"},
}

-- vehicles.ide handling names. The police Maverick uses the flight mission
-- controller; MTA's per-vehicle handling does not affect helicopters.
local handlingIds={ELECTRAP=191,FBICAR=193,CHEETAH=204,POLICEM=207,BARRACKS=218,
    PREDATOR=219,ENFORCER=234,RHINO=246}
local columns={"mass","turnMass","dragCoeff","centerOfMass",false,false,"percentSubmerged",
    "tractionMultiplier","tractionLoss","tractionBias","numberOfGears","maxVelocity","engineAcceleration",
    "engineInertia","driveType","engineType","brakeDeceleration","brakeBias",false,"steeringLock",
    "suspensionForceLevel","suspensionDamping","suspensionHighSpeedDamping","suspensionUpperLimit",
    "suspensionLowerLimit","suspensionFrontRearBias","suspensionAntiDiveMultiplier","seatOffsetDistance",
    "collisionDamageMultiplier"}
local driveTypes={R="rwd",F="fwd",["4"]="awd"}
local engineTypes={P="petrol",D="diesel",E="electric"}
local pursuitHandling={}

local function loadPursuitHandling()
    local data=exports.vcs_vehicle:getVcsHandlingData()
    if not data then
        outputDebugString("[npchlc_traffic] Could not read vcs_vehicle/data/handling.dat",1)
        return
    end
    for line in data:gmatch("[^\r\n]+") do
        local name,values=line:match("^%s*(%w+)%s+(.+)")
        local id=handlingIds[name]
        if id then
            local row,profile={},{}
            for token in values:gmatch("%S+") do row[#row+1]=token end
            for i,field in ipairs(columns) do
                -- The connected client retains native bike/boat suspension.
                -- PREDATOR's 0.05 brake is below the 0.1 wheel setter minimum.
                local fixedSuspension=(id==191 or id==219) and i>=21 and i<=27
                if field and not fixedSuspension and not (id==219 and i==17) then
                    local value=tonumber(row[i])
                    if i==4 then value={value,tonumber(row[5]),tonumber(row[6])}
                    -- tHandlingData::InitFromData scales the file's acceleration
                    -- before handing the record to ConvertDataToGameUnits.
                    elseif i==13 then value=value*.4
                    elseif i==15 then value=driveTypes[row[i]]
                    elseif i==16 then value=engineTypes[row[i]] end
                    profile[field]=value
                end
            end
            pursuitHandling[id]=profile
        end
    end
end

local function sameHandling(a,b)
    if type(b)=="number" then return type(a)=="number" and math.abs(a-b)<0.0001 end
    if type(b)=="table" then
        return type(a)=="table" and sameHandling(a[1],b[1]) and sameHandling(a[2],b[2]) and sameHandling(a[3],b[3])
    end
    return a==b
end

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
    pursuitHandling={}
    if graph.edition=="SLUS-21590 USA v1.00" then loadPursuitHandling() end
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
    if streetModels and kind=="vehicle" and policeVariants[originalId] then
        return unpack(policeVariants[originalId])
    end
    if nativePeds and (kind == "ped" and nativePeds[originalId]
        or kind == "vehicle" and originalId % 1 == 0 and originalId >= 400 and originalId <= 611) then
        return originalId
    end
    return false
end

function TrafficModelBindings.getPedestrian(originalId)
    return resolve(originalId, "ped")
end

function TrafficModelBindings.pedProfileModel(ped)
    if nativePeds then return end
    local original = getElementData(ped, "npchlc_traffic:originalModel", false)
    if PedAIModels[original] then return original end
end

function TrafficModelBindings.get(originalId)
    return resolve(originalId, "vehicle")
end

function TrafficModelBindings.tag(element, originalId, scripted, populationType)
    local kind = getElementType(element)
    local provider = activeProvider()
    local street = kind == "ped" and streetModels and streetModels[originalId]
    if street and (providerName == "vcs_model" or not providerName) then
        setElementData(element, "npchlc_traffic:modelProvider", getResourceName(getThisResource()), "broadcast", "deny")
    elseif provider and type(originalId) == "number" and call(provider, "getTrafficModelBase", originalId, kind) then
        setElementData(element, "npchlc_traffic:modelProvider", providerName, "broadcast", "deny")
    elseif kind=="vehicle" and streetModels and (originalId==193 or originalId==204) then
        setElementData(element,"npchlc_traffic:modelProvider",getResourceName(getThisResource()),"broadcast","deny")
    elseif street and not (bindings and bindings.ped[originalId]) then
        setElementData(element, "npchlc_traffic:modelProvider", getResourceName(getThisResource()), "broadcast", "deny")
    end
    local pedModel = not nativePeds and kind == "ped" and PedAIModels and PedAIModels[originalId]
    if pedModel then
        local stat, group = PedAIStats[pedModel[2]],PedAITypes[populationType or pedModel[1]]
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
        if streetModels and (originalId == 193 or originalId == 204) then
            exports.vcs_vehicle:configureVcsDashboardBeacon(element, originalId)
        end
        local profile=pursuitHandling[originalId]
        if profile then
            local current=getVehicleHandling(element)
            for field,value in pairs(profile) do
                if not sameHandling(current[field],value) then setVehicleHandling(element,field,value) end
            end
        end
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
