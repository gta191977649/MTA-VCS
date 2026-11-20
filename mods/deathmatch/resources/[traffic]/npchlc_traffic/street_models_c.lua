local provider = getResourceName(getThisResource())
local modelKey, providerKey = "npchlc_traffic:originalModel", "npchlc_traffic:modelProvider"
local animationBlock = TrafficAnimationBanks.street
local archive, officerArchive, animation
local officerFiles = {}
local files, loaded = {}, {}

local function chunk(filename, image, indices)
    local index = (indices or files)[filename]
    local bytes = index and engineImageGetFile(image or archive, index)
    if type(bytes) ~= "string" or #bytes < 12 then return end
    local a, b, c, d = bytes:byte(5, 8)
    local size = 12 + a + 256 * b + 65536 * c + 16777216 * d
    if size <= #bytes then return bytes:sub(1, size) end
end

local function loadSkin(model)
    local name=model.name..".dff"
    local supplemental=officerFiles[name]~=nil
    local image=supplemental and officerArchive or archive
    local index=supplemental and officerFiles or files
    local geometry = chunk(name,image,index)
    local dict = chunk(model.name .. ".txd",image,index)
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

local arrestSkins = {[8]=true,[9]=true,[10]=true,[11]=true,[117]=true,[118]=true,[119]=true}
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
    if animation and arrestSkins[original] then engineReplaceAnimation(ped,"ped","arrestgun",animationBlock,"service_arrest") end
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
    officerArchive=engineLoadIMG("ped_models/police.img")
    local officers=officerArchive and engineImageGetFiles(officerArchive)
    for i,name in ipairs(officers or {}) do officerFiles[name:lower()]=i-1 end
    animation = TrafficAnimationBanks.load(animationBlock, "ped_models/street.ifp")
    for _, ped in ipairs(getElementsByType("ped", root, true)) do apply(ped) end
end, false)
addEventHandler("onClientElementStreamIn", root, function() apply(source) end)
addEventHandler("onClientElementDataChange", root, function(key,previous)
    if key=="npchlc_traffic:stinger" and animation and isElementStreamedIn(source) and getElementType(source)=="ped" then
        local strip=getElementData(source,key,false)
        if type(strip)=="table" and strip[6]==0 and not previous then
            -- 0039DF08 adds group 0, clip 0x3A directly to the officer.
            setPedAnimation(source,animationBlock,"weapon_throwu",-1,false,false,false,false,0)
        end
    end
    if (key == modelKey or key == providerKey) and isElementStreamedIn(source) then apply(source) end
end)
addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, skin in pairs(loaded) do if skin then engineFreeModel(skin.id) end end
    if isElement(officerArchive) then destroyElement(officerArchive) end
    if isElement(archive) then destroyElement(archive) end
end, false)

-- Keep the actual emergency model ID for native lights and siren audio.
local variants = {[193]={name="fbicar",base=598},[204]={name="vicechee",base=597}}
local policeMaterials = {}
function getVcsVehicleRenderMaterials(id)
    return policeMaterials[id] or false
end

addEvent("npc_hlc:onVehicleGroundGeometry", false)
local policeArchive, policeFiles
local function loadVariant(model)
    if not policeArchive then
        policeArchive=engineLoadIMG("police_models.img")
        local entries=policeArchive and engineImageGetFiles(policeArchive)
        if not entries then return false end
        policeFiles={}
        for i,name in ipairs(entries) do policeFiles[name:lower()]=i-1 end
    end
    if not policeFiles then return false end
    local tx=chunk(model.name..".txd",policeArchive,policeFiles)
    local mesh=chunk(model.name..".dff",policeArchive,policeFiles)
    if not tx or not mesh then return false end
    local id=model.base
    local txd=engineLoadTXD(tx)
    local dff=txd and engineImportTXD(txd,id) and engineLoadDFF(mesh)
    local hasGlass = mesh:find("vcsglass_", 1, true) ~= nil
    if dff and engineReplaceModel(dff, id, hasGlass) then
        local materials = {}
        for name in mesh:gmatch("(vcsenv_%d+_[%w_]+)%z") do materials[name] = true end
        for name in mesh:gmatch("(vcsglass_[%x]+)%z") do materials[name] = true end
        for name in mesh:gmatch("(vcssiren_[%w_]+)%z") do materials[name] = true end
        policeMaterials[id] = materials
        return id
    end
    if dff then destroyElement(dff) end
    if txd then destroyElement(txd) end
    return false
end

local function bindPoliceVehicle(car)
    if getElementType(car)~="vehicle" then return end
    local original=getElementData(car,modelKey,false)
    local model=getElementData(car,providerKey,false)==provider and variants[original]
    if not model or getElementModel(car)~=model.base then return end
    if model.id==nil then
        model.id=loadVariant(model)
        if not model.id then outputDebugString("[npchlc_traffic] Could not load "..model.name,1) end
    end
    if model.id then triggerEvent("npc_hlc:onVehicleGroundGeometry", car) end
end

addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,car in ipairs(getElementsByType("vehicle",root,true)) do bindPoliceVehicle(car) end
end,false)
addEventHandler("onClientElementStreamIn",root,function() bindPoliceVehicle(source) end)
addEventHandler("onClientElementDataChange",root,function(key)
    if (key==modelKey or key==providerKey) and isElementStreamedIn(source) then bindPoliceVehicle(source) end
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for _,model in pairs(variants) do if model.id then engineRestoreModel(model.id) end end
    if isElement(policeArchive) then destroyElement(policeArchive) end
end,false)
