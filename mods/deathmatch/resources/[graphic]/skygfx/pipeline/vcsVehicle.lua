VCSVehicle = {}

local mapSize = 128
local scene, reflection, mapShader, coronaStar, glass
local mapScene
local reflectors = {}
local mapValid = false
local previousSunGlare
local active = false
-- The engine owns the streamed vehicle. Its Lua userdata wrapper can be
-- collected before stream-out. Keep it until the matching removal event.
local bindings = {}
local nativeVehicles = {}
local reflectionShaders = {}
local lensShaders = {}
local emergencyVehicles = {}
local captures, failures = 0, 0

local function unbindVehicle(vehicle)
    emergencyVehicles[vehicle] = nil
    nativeVehicles[vehicle] = nil
    local bound = bindings[vehicle]
    if not bound then return end
    if isElement(vehicle) then
        for texture, shader in pairs(bound.textures) do
            engineRemoveShaderFromWorldTexture(shader, texture, vehicle)
        end
    end
    bindings[vehicle] = nil
end

local function materialSet(name, model, ignored)
    if name == ignored then return end
    local provider = getResourceFromName(name)
    if provider and getResourceState(provider) == "running" then
        return call(provider, "getVcsVehicleRenderMaterials", model)
    end
end

local function updateLenses(vehicle, bound)
    local activeSiren = getVehicleSirensOn(vehicle)
    if activeSiren == bound.sirenOn then return end
    bound.sirenOn = activeSiren
    for name, shader in pairs(bound.lenses) do
        if activeSiren then
            if engineApplyShaderToWorldTexture(shader, name, vehicle, false) then
                bound.textures[name] = shader
            else
                failures = failures + 1
                outputDebugString("SkyGfx VCS: emergency lens binding failed " .. bound.model .. "/" .. name, 2)
            end
        elseif bound.textures[name] then
            engineRemoveShaderFromWorldTexture(shader, name, vehicle)
            bound.textures[name] = nil
        end
    end
end

local function bindVehicle(vehicle, ignored)
    if not active or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
            or not isElementStreamedIn(vehicle) then return end
    local model = getElementModel(vehicle)
    if bindings[vehicle] and bindings[vehicle].model == model then return end
    unbindVehicle(vehicle)
    local primary, fallback = "vcs_model", "npchlc_traffic"
    if getElementData(vehicle, "npchlc_traffic:modelProvider", false) == fallback then
        primary, fallback = fallback, primary
    end
    local materials = materialSet(primary, model, ignored)
    if type(materials) ~= "table" then
        primary = fallback
        materials = materialSet(primary, model, ignored)
    end
    if type(materials) ~= "table" then
        nativeVehicles[vehicle] = true
        return
    end
    local bound = {model = model, provider = primary, textures = {}, reflective = false}
    for name in pairs(materials) do
        local coefficient = name:match("^vcsenv_(%d+)_")
        local shader = coefficient and reflectionShaders[tonumber(coefficient)]
            or (name:match("^vcsglass_") and glass)
        local lens = lensShaders[name]
        if lens then
            bound.lenses = bound.lenses or {}
            bound.lenses[name] = lens
        end
        if shader and engineApplyShaderToWorldTexture(shader, name, vehicle, false) then
            bound.textures[name] = shader
            if name:match("^vcsenv_") then bound.reflective = true end
        elseif shader then
            failures = failures + 1
            outputDebugString("SkyGfx VCS: vehicle material binding failed " .. model .. "/" .. name, 2)
        end
    end
    if bound.lenses then
        emergencyVehicles[vehicle] = bound
        updateLenses(vehicle, bound)
    end
    if bound.lenses or next(bound.textures) then bindings[vehicle] = bound end
end

local function onVehicleStreamIn()
    bindVehicle(source)
end

local function onVehicleRemoved()
    unbindVehicle(source)
end

local function onVehicleModelChanged()
    if getElementType(source) ~= "vehicle" then return end
    unbindVehicle(source)
    bindVehicle(source)
end

local function onVehicleAssetLoaded()
    if getElementType(source) ~= "vehicle" then return end
    onVehicleModelChanged()
end

local function onModelResourceStopped(resource)
    local name = getResourceName(resource)
    if name ~= "vcs_model" and name ~= "npchlc_traffic" then return end
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        if bindings[vehicle] and bindings[vehicle].provider == name then
            unbindVehicle(vehicle)
            bindVehicle(vehicle, name)
        end
    end
end

local function onModelResourceChanged(resource)
    local name = getResourceName(resource)
    if name ~= "vcs_model" and name ~= "npchlc_traffic" then return end
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        unbindVehicle(vehicle)
        bindVehicle(vehicle)
    end
end

function VCSVehicle.prepare()
    for vehicle, bound in pairs(emergencyVehicles) do updateLenses(vehicle, bound) end
end

local function setMapValid(valid)
    if mapValid == valid then return end
    mapValid = valid
    for shader, weight in pairs(reflectors) do
        dxSetShaderValue(shader, "ReflectionWeight", valid and weight or 0)
    end
end

function VCSVehicle.invalidate()
    setMapValid(false)
end

function VCSVehicle.start()
    if active then return end
    active = true
    captures, failures = 0, 0
    addEvent("npc_hlc:onVehicleGroundGeometry", false)
    addEventHandler("npc_hlc:onVehicleGroundGeometry", root, onVehicleAssetLoaded)
    addEventHandler("onClientElementStreamIn", root, onVehicleStreamIn)
    addEventHandler("onClientElementStreamOut", root, onVehicleRemoved)
    addEventHandler("onClientElementDestroy", root, onVehicleRemoved)
    addEventHandler("onClientElementModelChange", root, onVehicleModelChanged)
    addEventHandler("onClientResourceStart", root, onModelResourceChanged)
    addEventHandler("onClientResourceStop", root, onModelResourceStopped)
    previousSunGlare = isWorldSpecialPropertyEnabled("vehiclesunglare")
    setWorldSpecialPropertyEnabled("vehiclesunglare", SKYGFX.sunGlare)
    glass = dxCreateShader("shader/vcsVehicle.fx", {VCS_GLASS="1"}, 12, 0, false, "vehicle")
    if not glass then
        outputDebugString("SkyGfx VCS: could not bind blue vehicle glass", 2)
    end
    for index, name in ipairs({"vcssiren_left", "vcssiren_right"}) do
        local shader = dxCreateShader("shader/vcsVehicle.fx", {VCS_SIREN_LENS="1"}, 12, 0, false, "vehicle")
        if shader and dxSetShaderValue(shader, "LensPhase", (index-1)*0.5) then
            lensShaders[name] = shader
        else
            if shader then destroyElement(shader) end
            outputDebugString("SkyGfx VCS: could not bind emergency lens " .. name, 2)
        end
    end

    scene = dxCreateScreenSource(mapSize, mapSize)
    if not scene then
        outputDebugString("SkyGfx VCS: vehicle reflection capture unavailable", 2)
        for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do bindVehicle(vehicle) end
        return
    end
    reflection = dxCreateRenderTarget(mapSize, mapSize)
    coronaStar = dxCreateTexture("txd/vcs-coronastar.png", "argb", false, "clamp")
    mapShader = dxCreateShader("shader/vcsVehicle.fx", {VCS_REFLECTION_MAP="1"})
    local map = scene
    if reflection and coronaStar and mapShader and dxSetShaderValue(mapShader, "ReflectionScene", scene)
            and dxSetShaderValue(mapShader, "CoronaStar", coronaStar) then
        map = reflection
        mapScene = scene
    else
        if mapShader then destroyElement(mapShader) end
        if reflection then destroyElement(reflection) end
        if coronaStar then destroyElement(coronaStar) end
        reflection, mapShader, coronaStar = nil, nil, nil
        outputDebugString("SkyGfx VCS: vehicle reflection coronas unavailable", 2)
    end

    for _, coefficient in ipairs({5, 10, 20, 30, 50, 100}) do
        local shader = dxCreateShader("shader/vcsVehicle.fx", 12, 0, false, "vehicle")
        if shader and dxSetShaderValue(shader, "Reflection", map)
                and dxSetShaderValue(shader, "ReflectionWeight", 0) then
            -- VCS's half-strength coefficient expressed as a GS FIX value.
            reflectors[shader] = math.floor(coefficient * 128 / 200) / 128
            reflectionShaders[coefficient] = shader
        else
            if shader then destroyElement(shader) end
            outputDebugString("SkyGfx VCS: could not bind vehicle reflection " .. coefficient, 2)
        end
    end
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do bindVehicle(vehicle) end
end

function VCSVehicle.capture(postScene)
    if not next(reflectors) then return end
    local visible = false
    for vehicle, bound in pairs(bindings) do
        if bound.reflective and isElementOnScreen(vehicle) then
            visible = true
            break
        end
    end
    if not visible then
        setMapValid(false)
        return
    end
    -- Both effects sample the pre-HUD scene. Downsample it directly while
    -- drawing the reflection map when post-processing has already captured it.
    local input = mapShader and postScene or scene
    if mapShader and input ~= mapScene then
        if not dxSetShaderValue(mapShader, "ReflectionScene", input) then
            setMapValid(false)
            return
        end
        mapScene = input
    end
    if input == scene and not dxUpdateScreenSource(scene, true) then
        failures = failures + 1
        setMapValid(false)
        return
    end
    captures = captures + 1
    if mapShader then
        -- 0x35c9e0 rotates both coronastar quads with camera heading.
        local x, y, _, lookX, lookY = getCameraMatrix()
        local heading = math.floor((math.atan2(x - lookX, lookY - y) / (2 * math.pi) + 0.5) * mapSize)
        if not dxSetShaderValue(mapShader, "CoronaLeft", (heading + 25)/mapSize, (heading + 115)/mapSize)
                or not dxSetRenderTarget(reflection) then
            setMapValid(false)
            return
        end
        local previousBlend = dxGetBlendMode()
        dxSetBlendMode("overwrite")
        local drawn = dxDrawImage(0, 0, mapSize, mapSize, mapShader)
        dxSetBlendMode(previousBlend)
        dxSetRenderTarget()
        setMapValid(drawn)
    else
        setMapValid(true)
    end
end

function VCSVehicle.update(values)
    local red = (values[16] + 2*values[19])/765
    local green = (values[17] + 2*values[20])/765
    local blue = (values[18] + 2*values[21])/765
    local near, far = getFogDistance(), getFarClipDistance()
    for shader in pairs(reflectors) do
        dxSetShaderValue(shader, "FogColor", red, green, blue)
        dxSetShaderValue(shader, "FogRange", near, far)
    end
end

function VCSVehicle.stop()
    if not active then return end
    active = false
    removeEventHandler("npc_hlc:onVehicleGroundGeometry", root, onVehicleAssetLoaded)
    removeEventHandler("onClientElementStreamIn", root, onVehicleStreamIn)
    removeEventHandler("onClientElementStreamOut", root, onVehicleRemoved)
    removeEventHandler("onClientElementDestroy", root, onVehicleRemoved)
    removeEventHandler("onClientElementModelChange", root, onVehicleModelChanged)
    removeEventHandler("onClientResourceStart", root, onModelResourceChanged)
    removeEventHandler("onClientResourceStop", root, onModelResourceStopped)
    for vehicle in pairs(bindings) do unbindVehicle(vehicle) end
    nativeVehicles, reflectionShaders = {}, {}
    if previousSunGlare ~= nil then
        setWorldSpecialPropertyEnabled("vehiclesunglare", previousSunGlare)
        previousSunGlare = nil
    end
    for shader in pairs(reflectors) do destroyElement(shader) end
    for _, shader in pairs(lensShaders) do destroyElement(shader) end
    lensShaders = {}
    for _, element in pairs({scene, reflection, mapShader, coronaStar, glass}) do
        destroyElement(element)
    end
    scene, reflection, mapShader, coronaStar, glass, mapScene = nil, nil, nil, nil, nil, nil
    reflectors, mapValid = {}, false
end

function VCSVehicle.getStats()
    local vehicles, materials, shaders, native, lenses = 0, 0, 0, 0, 0
    for _, bound in pairs(bindings) do
        vehicles = vehicles + 1
        for name in pairs(bound.textures) do
            materials = materials + 1
            if lensShaders[name] then lenses = lenses + 1 end
        end
    end
    for _ in pairs(reflectors) do shaders = shaders + 1 end
    for _ in pairs(nativeVehicles) do native = native + 1 end
    return {active=active, vehicles=vehicles, materials=materials, shaders=shaders,
        nativeVehicles=native, litLensMaterials=lenses,
        glass=isElement(glass), reflectionReady=mapValid, captures=captures, failures=failures,
        width=mapSize, height=mapSize}
end
