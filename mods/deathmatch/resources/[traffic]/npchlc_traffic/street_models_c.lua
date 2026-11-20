local provider = getResourceName(getThisResource())
local modelKey, providerKey = "npchlc_traffic:originalModel", "npchlc_traffic:modelProvider"
local animationBlock = TrafficAnimationBanks.street
local archive, animation
local files, loaded = {}, {}

local function chunk(filename)
    local index = files[filename]
    local bytes = index and engineImageGetFile(archive, index)
    if type(bytes) ~= "string" or #bytes < 12 then return end
    local a, b, c, d = bytes:byte(5, 8)
    local size = 12 + a + 256 * b + 65536 * c + 16777216 * d
    if size <= #bytes then return bytes:sub(1, size) end
end

local function loadSkin(model)
    local geometry = chunk(model.name .. ".dff")
    local dict = chunk(model.name .. ".txd")
    if not geometry or not dict then return false end
    local id = engineRequestModel("ped", model.base)
    if not id then return false end
    local txd = engineLoadTXD(dict)
    local dff = txd and engineImportTXD(txd, id) and engineLoadDFF(geometry)
    if dff and engineReplaceModel(dff, id) then
        return {id = id, pivot = getTrafficJawBindPivot(geometry)}
    end
    if dff then destroyElement(dff) end
    if txd then destroyElement(txd) end
    engineFreeModel(id)
    return false
end

local function apply(ped)
    if not archive or getElementType(ped) ~= "ped" or getElementData(ped, providerKey, false) ~= provider then return end
    local original = getElementData(ped, modelKey, false)
    local model = StreetPedModels[original]
    if not model then return end
    if loaded[original] == nil then
        loaded[original] = loadSkin(model)
        if not loaded[original] then outputDebugString("[npchlc_traffic] Could not load skin " .. model.name, 1) end
    end
    local skin = loaded[original]
    if not skin or not setElementModel(ped, skin.id) then return end
    setPedVoice(ped,"PED_TYPE_DISABLED")
    trackTrafficJaw(ped, skin.id, skin.pivot)
    if animation and original == 12 then engineReplaceAnimation(ped,"medic","cpr",animationBlock,"service_cpr") end
    if animation and original == 8 then engineReplaceAnimation(ped,"ped","arrestgun",animationBlock,"service_arrest") end
    local moves = VCS_TRAFFIC_LOCOMOTION_GROUPS[VCS_TRAFFIC_PEDESTRIAN_GROUPS[original]]
    if animation and moves then
        for i, native in ipairs(VCS_TRAFFIC_NATIVE_LOCOMOTION) do
            if model.base == 280 and native == "run_civi" then native = "swat_run" end
            engineReplaceAnimation(ped, "ped", native, animationBlock, moves[i])
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    archive = engineLoadIMG("ped_models/street.img")
    local entries = archive and engineImageGetFiles(archive)
    if type(entries) ~= "table" then
        outputDebugString("[npchlc_traffic] Could not read ped_models/street.img", 1)
        return
    end
    for i, name in ipairs(entries) do files[name:lower()] = i - 1 end
    animation = TrafficAnimationBanks.load(animationBlock, "ped_models/street.ifp")
    for _, ped in ipairs(getElementsByType("ped", root, true)) do apply(ped) end
end, false)
addEventHandler("onClientElementStreamIn", root, function() apply(source) end)
addEventHandler("onClientElementDataChange", root, function(key)
    if (key == modelKey or key == providerKey) and isElementStreamedIn(source) then apply(source) end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, skin in pairs(loaded) do if skin then engineFreeModel(skin.id) end end
end, false)
