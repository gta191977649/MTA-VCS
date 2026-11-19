local PROVIDER_KEY = "npchlc_traffic:modelProvider"
local provider = getResourceName(getThisResource())
local MODEL_KEY = "npchlc_traffic:originalModel"
local models = VCS_TRAFFIC_MODEL_CATALOG
local archives = {}
local vehicleBindings = setmetatable({}, {__mode = "k"})
local lampShaders = {}
local lampBindings = setmetatable({}, {__mode = "k"})
local replacedVehicleModels = {}
local vehicleRenderMaterials = {}
local lampTextures = {
    vehiclelights128 = "vehiclelights128.png",
    vehiclelightson128 = "vehiclelightson128.png",
}
addEvent("npc_hlc:onVehicleGroundGeometry", false)

function getVcsVehicleRenderMaterials(modelId)
    return vehicleRenderMaterials[tonumber(modelId)] or false
end

local function loadLampShaders()
    for name, path in pairs(lampTextures) do
        local texture = dxCreateTexture(path)
        local shader = texture and dxCreateShader("vehicle_lamps.fx", 15, 0, false, "vehicle")
        if shader and dxSetShaderValue(shader, "LampAtlas", texture) then
            lampShaders[name] = shader
        else
            if shader then destroyElement(shader) end
            if texture then destroyElement(texture) end
            outputDebugString("[vcs_model] Could not load the " .. name .. " lamp atlas.", 2)
        end
    end
end

local function bindVehicleLamps(vehicle, enabled)
    if (lampBindings[vehicle] == true) == enabled then return end
    lampBindings[vehicle] = enabled or nil
    for name, shader in pairs(lampShaders) do
        if enabled then
            engineApplyShaderToWorldTexture(shader, name, vehicle, false)
        else
            engineRemoveShaderFromWorldTexture(shader, name, vehicle)
        end
    end
end

local function updateVehicleLamps(vehicle)
    if getElementType(vehicle) ~= "vehicle" then return end
    bindVehicleLamps(vehicle, replacedVehicleModels[getElementModel(vehicle)] == true)
end

function getVcsVehicleGroundGeometry(vehicle)
    local original = vehicleBindings[vehicle]
    local model = original and models[original]
    if model and model.id == getElementModel(vehicle) then return VCS_VEHICLE_GROUND[original] end
    return false
end

getTrafficVehicleGroundGeometry = getVcsVehicleGroundGeometry

local function readChunk(image, index)
    local data = engineImageGetFile(image, index)
    if type(data) ~= "string" or #data < 12 then return false end
    local a, b, c, d = data:byte(5, 8)
    local length = 12 + a + b * 256 + c * 65536 + d * 16777216
    if length > #data then return false end
    return data:sub(1, length)
end

local function loadModel(model)
    local archive = archives[model.kind]
    local dff = archive.indices[model.name .. ".dff"]
    local txd = archive.indices[model.name .. ".txd"]
    if dff == nil or txd == nil then return false end
    -- The catalog only accepts unique native vehicle slots. Preserve their
    -- collision and handling while replacing the RenderWare assets.
    local id = model.kind == "vehicle" and model.base or engineRequestModel("ped", model.base)
    if not id then return false end
    -- MTA's replacement path initializes the native ped/vehicle model info.
    local textureData = readChunk(archive.image, txd)
    local texture = textureData and engineLoadTXD(textureData)
    local modelData = readChunk(archive.image, dff)
    local geometry
    if texture and modelData and (model.kind == "ped" or engineImportTXD(archive.shared, id))
            and engineImportTXD(texture, id) then
        geometry = engineLoadDFF(modelData)
    end
    local hasGlass = model.kind == "vehicle" and modelData and modelData:find("vcsglass_", 1, true) ~= nil
    if not geometry or not engineReplaceModel(geometry, id, hasGlass == true) then
        if model.kind == "ped" then engineFreeModel(id) end
        if texture then destroyElement(texture) end
        if geometry then destroyElement(geometry) end
        return false
    end
    model.id = id
    if model.kind == "ped" then
        model.jawPivot = getTrafficJawBindPivot(modelData)
    else
        replacedVehicleModels[id] = true
        local materials = {}
        for name in modelData:gmatch("(vcsenv_%d+_[%w_]+)%z") do materials[name] = true end
        for name in modelData:gmatch("(vcsglass_[%x]+)%z") do materials[name] = true end
        vehicleRenderMaterials[id] = materials
        for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
            if getElementModel(vehicle) == id then bindVehicleLamps(vehicle, true) end
        end
    end
    return true
end

local function applyModel(element)
    local kind = getElementType(element)
    if not archives[kind] then return end
    if getElementData(element, PROVIDER_KEY, false) ~= provider then return end
    local originalId = getElementData(element, MODEL_KEY, false)
    local model = models[originalId]
    if not model or model.kind ~= kind or model.failed then return end
    if not model.id and not loadModel(model) then
        model.failed = true
            outputDebugString("[vcs_model] Could not load " .. model.name .. " from " .. kind .. ".img.", 1)
        return
    end
    if getElementModel(element) ~= model.id and not setElementModel(element, model.id) then return end
    if kind == "ped" then
        applyVcsTrafficLocomotion(element, originalId)
        trackTrafficJaw(element, model.id, model.jawPivot)
    end
    if kind == "vehicle" and vehicleBindings[element] ~= originalId then
        vehicleBindings[element] = originalId
        triggerEvent("npc_hlc:onVehicleGroundGeometry", element)
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    loadLampShaders()
    for _, kind in ipairs({"ped", "vehicle"}) do
        local image = engineLoadIMG(kind .. ".img")
        local files = image and engineImageGetFiles(image)
        if type(files) == "table" and engineAddImage(image) then
            local indices = {}
            for index, name in ipairs(files) do indices[name:lower()] = index - 1 end
            local archive = {image = image, indices = indices}
            if kind == "vehicle" and indices["vehshare.txd"] then
                local data = readChunk(image, indices["vehshare.txd"])
                archive.shared = data and engineLoadTXD(data)
            end
            if kind == "vehicle" and not archive.shared then
                engineRemoveImage(image)
                outputDebugString("[vcs_model] Could not load vehshare.txd from vehicle.img.", 1)
            else
                archives[kind] = archive
                for _, element in ipairs(getElementsByType(kind, root, true)) do applyModel(element) end
            end
        else
            outputDebugString("[vcs_model] Could not mount " .. kind .. ".img.", 1)
        end
    end
end, false)

addEventHandler("onClientElementStreamIn", root, function()
    applyModel(source)
    updateVehicleLamps(source)
end)
addEventHandler("onClientElementStreamOut", root, function()
    bindVehicleLamps(source, false)
end)
addEventHandler("onClientElementModelChange", root, function()
    if isElementStreamedIn(source) then updateVehicleLamps(source) end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if (key == MODEL_KEY or key == PROVIDER_KEY) and isElementStreamedIn(source) then
        if vehicleBindings[source] then
            vehicleBindings[source] = nil
            triggerEvent("npc_hlc:onVehicleGroundGeometry", source)
        end
        applyModel(source)
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, model in pairs(models) do
        if model.id then
            if model.kind == "ped" then engineFreeModel(model.id)
            else engineRestoreModel(model.id) end
        end
    end
    for _, archive in pairs(archives) do engineRemoveImage(archive.image) end
end, false)
