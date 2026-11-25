VCSGraphics = {}
local world, prop, propAlpha, foliage, threshold, blurCross, blurDiagonal, compose
local solidProp, shopProp
local thresholdUsesDepth
local scene, bloomA, bloomB, historyA, historyB
local width, height, bloomWidth, bloomHeight
local lastValues, historyReady, lastCamera, previousInterior, previousDimension
local bloomCamera, bloomValues
local previousCameraInterior
local composedValues, boundHistory
local mode = SKYGFX.vcsReducedEffects and "reduced" or "full"
local settings, modeOverride
local reloadSnapshot = "leeds_engine:postFx"
local stats = {}

-- Streamed GTA3.IMG props use their own TXD names, outside the vcsw_* namespace.
-- These tree trunks and pole materials have opaque TXD rasters.
local solidPropTextures = {
    "t542db70025f0f771", "t88a7e6fbcc409c9e", "t7ef2fc8988af150c", -- trunks
    "teaba6a6d12faada1", "tc5936e95064be926",                      -- traffic signals
    "t6fcd84d4113dd66d", "t547372f1044a3442", "tc38f7fb209510439",
    "tbcb484c57e148c44", "t21e1eebec47c6228",
}
-- Glass inherits its native blend and depth state.
local propTextures = {"taed6cbc2a90c9328", "t05d769aae6ec4f43"}
local foliageTextures = {"t74b33c6b1464e0e7", "tc83ca87425fa0a90", "t6ff82561bbf6cdfa"}
local propAlphaTextures = {
    "tba7ab4be6c600554", "t54995f7792f61092", "t6f8c48ce1384d18c", "tc1fbb27d3adc2df1",
    "te90727e269978d30", "t149f8253748a40b1", "t164e69046a26c760", "tae568bc58333b1f1",
}
local function release(element)
    if isElement(element) then destroyElement(element) end
end

local function clearHistory()
    historyReady, lastCamera = false, nil
    bloomCamera, bloomValues = nil, nil
end

local function releaseTargets()
    release(scene)
    release(bloomA)
    release(bloomB)
    release(historyA)
    release(historyB)
    scene, bloomA, bloomB, historyA, historyB = nil, nil, nil, nil, nil
    composedValues, boundHistory = nil, nil
    clearHistory()
end

local function ensureTargets(w, h)
    if w == width and h == height then return end
    releaseTargets()
    width, height = w, h
    if mode == "off" or not compose then return end
    scene = dxCreateScreenSource(w, h)
    if not scene then
        outputDebugString("SkyGfx VCS: unable to allocate the scene capture", 2)
        return
    end
    dxSetShaderValue(compose, "Scene", scene)
    if threshold and blurCross and blurDiagonal then
        bloomWidth, bloomHeight = 256, 128
        if mode == "reduced" then bloomWidth, bloomHeight = 128, 64 end
        bloomA = dxCreateRenderTarget(bloomWidth, bloomHeight)
        bloomB = dxCreateRenderTarget(bloomWidth, bloomHeight)
        if not (bloomA and bloomB) then
            release(bloomA)
            release(bloomB)
            bloomA, bloomB = nil, nil
        else
            dxSetShaderValue(threshold, "Scene", scene)
            if thresholdUsesDepth then
                dxSetShaderValue(threshold, "SceneSize", w, h)
                dxSetShaderValue(threshold, "SceneTexel", 1/w, 1/h)
            end
            dxSetShaderValue(blurCross, "Scene", bloomA)
            dxSetShaderValue(blurCross, "Step", 1/bloomWidth, 1/bloomHeight)
            dxSetShaderValue(blurDiagonal, "Scene", bloomB)
            dxSetShaderValue(blurDiagonal, "Step", 1/bloomWidth, 1/bloomHeight)
        end
    end
    if mode == "full" then
        historyA = dxCreateRenderTarget(w, h)
        historyB = dxCreateRenderTarget(w, h)
        if not (historyA and historyB) then
            release(historyA)
            release(historyB)
            historyA, historyB = nil, nil
        end
    end
end

local function createMaterialShader(textures, macros)
    if #textures == 0 then return nil end
    local shader = dxCreateShader("shader/vcsWorld.fx", macros, 11, 0, false, "world,object")
    if not shader then return nil end
    for _, name in ipairs(textures) do
        if not engineApplyShaderToWorldTexture(shader, name, nil, false) then
            destroyElement(shader)
            return nil
        end
    end
    return shader
end

local function startShopProps()
    local manifest = fileOpen("models/vcsShopTextures.txt", true)
    if not manifest then
        outputDebugString("SkyGfx VCS: shop prop material manifest unavailable", 1)
        return
    end
    local contents = fileRead(manifest, fileGetSize(manifest))
    fileClose(manifest)
    local textures, seen = {}, {}
    for line in (contents or ""):gmatch("[^\r\n]+") do
        local texture = line:match("^%s*(t%x+)%s*$")
        if texture and not seen[texture] then
            textures[#textures+1], seen[texture] = texture, true
        end
    end
    -- Script-spawned furniture is streamed prop geometry, including its damaged
    -- atomic. It must use expanded prelight, rather than the world RGB555 path.
    -- Transparency and depth now follow the native model/material draw state.
    shopProp = createMaterialShader(textures, {VCS_WORLD_PROP="1"})
    stats.shopTextures = shopProp and #textures or 0
    if not shopProp then outputDebugString("SkyGfx VCS: shop prop shader unavailable", 1) end
end

local function updateWorldShader(shader, v, isProp)
    if not shader then return end
    CPointLights.Register(shader)
    -- VCSPC's prop pipeline consumes expanded prelight and scales ambient by 128/255.
    -- The streamed world sectors use the original RGB555 integer calculation.
    local divisor = isProp and 255 or 248
    local ambientScale = isProp and 128/255 or 0.5
    dxSetShaderValue(shader, "PrelightScale", math.floor(v[1])/divisor, math.floor(v[2])/divisor, math.floor(v[3])/divisor)
    dxSetShaderValue(shader, "PrelightOffset", math.floor(v[7])*ambientScale, math.floor(v[8])*ambientScale, math.floor(v[9])*ambientScale)
    dxSetShaderValue(shader, "FogColor", (v[16]+2*v[19])/765, (v[17]+2*v[20])/765, (v[18]+2*v[21])/765)
    dxSetShaderValue(shader, "FogRange", getFogDistance(), getFarClipDistance())
end

local function updateWorld(v)
    if not v or v == lastValues then return end
    lastValues = v
    updateWorldShader(world, v)
    updateWorldShader(prop, v, true)
    updateWorldShader(shopProp, v, true)
    updateWorldShader(solidProp, v, true)
    updateWorldShader(propAlpha, v, true)
    updateWorldShader(foliage, v, true)
    VCSVehicle.update(v)
    VCSWater.update(v, getTimeCycleValue("waterWind"))
end

local function prepareWorld()
    local v = getTimeCycleValue("values")
    updateWorld(v)
    VCSVehicle.prepare()
    VCSWater.prepare()
    VCSBoatWake.prepare(v)
    CParticle.Render()
    VCSSun.prepare(v)
end

local function restoreGraphics()
    clearHistory()
    VCSVehicleTrails.reset()
    VCSVehicle.invalidate()
    VCSWater.restoreGraphics()
    VCSSun.resetVisibility()
end

local function checkCamera(now)
    local interior, dimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local cameraInterior = getCameraInterior()
    local x, y, z, lx, ly, lz, roll, fov = getCameraMatrix()
    local dx, dy, dz = lx-x, ly-y, lz-z
    local length = math.max(math.sqrt(dx*dx+dy*dy+dz*dz), 0.0001)
    dx, dy, dz = dx/length, dy/length, dz/length
    local prev = lastCamera
    if interior ~= previousInterior or dimension ~= previousDimension or cameraInterior ~= previousCameraInterior or
        (prev and ((x-prev[1])^2 + (y-prev[2])^2 + (z-prev[3])^2 > 35^2
                   or dx*prev[4]+dy*prev[5]+dz*prev[6] < 0.5 or now-prev[9] > 150)) then
        clearHistory()
    end
    lastCamera = {x,y,z,dx,dy,dz,roll,fov,now}
    previousInterior, previousDimension, previousCameraInterior = interior, dimension, cameraInterior
end

local function drawTarget(target, w, h, shader)
    if not dxSetRenderTarget(target) then return false end
    local ok = dxDrawImage(0, 0, w, h, shader)
    dxSetRenderTarget()
    return ok
end

local function canReuseBloom(v)
    if not bloomCamera or not lastCamera or v ~= bloomValues then return false end
    local age = lastCamera[9] - bloomCamera[9]
    if age < 0 or age >= 33 then return false end
    for i = 1, 8 do
        if lastCamera[i] ~= bloomCamera[i] then return false end
    end
    return true
end

local function renderBloom(v)
    if not SKYGFX.doRadiosity or not bloomA or v[36] < 1 then
        bloomCamera = nil
        return false
    end
    -- Bloom is a blurred 256x128 image. Reuse it briefly at a stationary
    -- camera, while the scene, sun, reflections and trails still update live.
    if canReuseBloom(v) then return true end
    bloomCamera = nil
    if not drawTarget(bloomA, bloomWidth, bloomHeight, threshold) then return false end
    for _ = 1, 2 do
        if not drawTarget(bloomB, bloomWidth, bloomHeight, blurCross) then return false end
        if not drawTarget(bloomA, bloomWidth, bloomHeight, blurDiagonal) then return false end
    end
    stats.bloomPasses = 5
    bloomCamera, bloomValues = lastCamera, v
    return true
end

local function bindHistory(target, weight)
    if target == boundHistory then return end
    dxSetShaderValue(compose, "History", target)
    dxSetShaderValue(compose, "HistoryWeight", weight)
    boundHistory = target
end

local function renderPost()
    -- Submit lamp streaks before capturing the scene, including in post-FX off mode.
    VCSVehicleTrails.render()
    stats.hudFrames = (stats.hudFrames or 0) + 1
    stats.captures, stats.fullscreen, stats.bloomPasses, stats.historyWrites = 0, 0, 0, 0
    if isMainMenuActive() then
        clearHistory()
        VCSVehicle.invalidate()
        return
    end
    local w, h = guiGetScreenSize()
    if mode == "off" or not compose or not lastValues then
        VCSVehicle.capture()
        return
    end
    ensureTargets(w, h)
    if not scene or not dxUpdateScreenSource(scene, true) then
        VCSVehicle.capture()
        return
    end
    stats.captures = 1
    VCSVehicle.capture(scene)
    local now = getTickCount()
    if historyA then checkCamera(now) end

    local v = lastValues
    if v ~= composedValues then
        if threshold then dxSetShaderValue(threshold, "Threshold", math.floor(v[37]/2)/255) end
        dxSetShaderValue(compose, "TrailsColor", math.floor(v[48])/255, math.floor(v[49])/255, math.floor(v[50])/255)
        local offset = math.floor(v[56])
        dxSetShaderValue(compose, "SmearOffset", offset / w, offset / h)
        dxSetShaderValue(compose, "SmearWeight", math.floor(math.floor(v[55])*0.8)/255)
    end
    local bloomEnabled = renderBloom(v)
    if v ~= composedValues or bloomEnabled ~= stats.boundBloom then
        dxSetShaderValue(compose, "Bloom", bloomEnabled and bloomA or scene)
        -- VCSPC draws the same radiosity buffer twice with intensity * 4.
        dxSetShaderValue(compose, "BloomWeight", bloomEnabled and math.floor(v[36]) * (8/255) or 0)
        composedValues, stats.boundBloom = v, bloomEnabled
    end
    bindHistory(historyReady and historyA or scene, historyReady and 32/255 or 0)
    local output = compose
    if historyB and drawTarget(historyB, w, h, compose) then
        historyA, historyB = historyB, historyA
        historyReady = true
        stats.historyWrites = 1
        output = historyA
    else
        historyReady = false
    end
    if dxDrawImage(0, 0, w, h, output) then stats.fullscreen = 1 end
end

function setVcsPostProcessing(value)
    if value ~= "off" and value ~= "reduced" and value ~= "full" then return false end
    modeOverride = value
    if mode ~= value then
        mode = value
        releaseTargets()
        width, height = nil, nil
        stats.captures, stats.fullscreen, stats.bloomPasses, stats.historyWrites = 0, 0, 0, 0
    end
    return true
end

function getVcsGraphicsStats()
    return {
        world=isElement(world), alphaTextures=0, -- No separate alpha-state overrides.
        props=isElement(prop) and isElement(solidProp), propAlpha=isElement(propAlpha), foliage=isElement(foliage),
        shopProps=isElement(shopProp), shopTextures=stats.shopTextures or 0,
        post=isElement(compose), mode=mode, sun=VCSSun.getStats(), water=VCSWater.getStats(), vehicles=VCSVehicle.getStats(),
        vehicleTrails=VCSVehicleTrails.getStats(), particles=CParticle.GetStats(),
        captures=stats.captures, fullscreen=stats.fullscreen,
        hudFrames=stats.hudFrames or 0,
        bloomPasses=stats.bloomPasses, historyWrites=stats.historyWrites,
        bloomWidth=bloomA and bloomWidth or 0, bloomHeight=bloomA and bloomHeight or 0,
        historyWidth=historyA and width or 0, historyHeight=historyA and height or 0,
    }
end

function VCSGraphics.start()
    CPointLights.Initialise()
    world = dxCreateShader("shader/vcsWorld.fx", 10, 0, false, "world,object")
    if world and not engineApplyShaderToWorldTexture(world, "vcsw_*", nil, false) then
        release(world)
        world = nil
    end
    startShopProps()
    prop = createMaterialShader(propTextures, {VCS_WORLD_PROP="1"})
    solidProp = createMaterialShader(solidPropTextures, {VCS_WORLD_PROP="1"})
    propAlpha = createMaterialShader(propAlphaTextures, {VCS_WORLD_PROP="1"})
    foliage = createMaterialShader(foliageTextures, {VCS_WORLD_PROP="1", VCS_WORLD_FOLIAGE="1"})
    if not (prop and solidProp and propAlpha) then outputDebugString("SkyGfx VCS: prop shaders unavailable", 2) end
    if not foliage then outputDebugString("SkyGfx VCS: foliage shader unavailable", 2) end
    VCSSun.start()
    VCSVehicle.start()
    VCSVehicleTrails.start()
    VCSWater.start()
    if CParticle.Initialise() then
        ObjectParticles.start()
        CExplosion.start()
        ParticleEmitters.start()
    else
        outputDebugString("SkyGfx could not create the VCS particle materials", 1)
    end
    compose = dxCreateShader("shader/vcsPost.fx")
    if compose then
        if dxGetStatus().DepthBufferFormat ~= "unknown" then
            threshold = dxCreateShader("shader/vcsPost.fx", {VCS_THRESHOLD="1", VCS_SKY_MASK="1"})
            thresholdUsesDepth = not not threshold
        end
        if not threshold then
            threshold = dxCreateShader("shader/vcsPost.fx", {VCS_THRESHOLD="1"})
        end
        blurCross = dxCreateShader("shader/vcsPost.fx", {VCS_BLUR="1"})
        blurDiagonal = dxCreateShader("shader/vcsPost.fx", {VCS_BLUR="1", VCS_DIAGONAL="1"})
    end
    -- Keep SA's post processing disabled even if the VCS shader fails to load.
    settings = getElementData(localPlayer, reloadSnapshot, false)
    if settings then
        modeOverride = settings.modeOverride
        mode = modeOverride or mode
        setElementData(localPlayer, reloadSnapshot, nil, false)
    else
        settings = {filter={getColorFilter(false)}, blur=getBlurLevel()}
        local original = {getColorFilter(true)}
        settings.customFilter = false
        for i = 1, 8 do
            if original[i] ~= settings.filter[i] then settings.customFilter = true end
        end
    end
    setColorFilter(0,0,0,0,0,0,0,0)
    setBlurLevel(0)
    outputDebugString(("SkyGfx VCS: world=%s alphaTextures=%d shopTextures=%d post=%s bloom=%s"):format(
        tostring(isElement(world)), 0, stats.shopTextures or 0, tostring(isElement(compose)),
        tostring(isElement(threshold) and isElement(blurCross) and isElement(blurDiagonal))))
    addEventHandler("onClientPreRender", root, prepareWorld, false, "high-1")
    addEventHandler("onClientHUDRender", root, renderPost, false, "high")
    addEventHandler("onClientRestore", root, restoreGraphics)
    updateWorld(getTimeCycleValue("values"))
end

function VCSGraphics.stop(reloading)
    CPointLights.Shutdown()
    removeEventHandler("onClientPreRender", root, prepareWorld)
    removeEventHandler("onClientHUDRender", root, renderPost)
    removeEventHandler("onClientRestore", root, restoreGraphics)
    releaseTargets()
    VCSSun.stop(reloading)
    VCSVehicle.stop()
    VCSVehicleTrails.stop()
    ObjectParticles.stop()
    CExplosion.stop()
    ParticleEmitters.stop()
    CParticle.Shutdown()
    VCSWater.stop()
    release(world)
    release(prop)
    release(shopProp)
    release(solidProp)
    release(propAlpha)
    release(foliage)
    release(compose)
    release(threshold)
    release(blurCross)
    release(blurDiagonal)
    world, compose, threshold, blurCross, blurDiagonal = nil, nil, nil, nil, nil
    prop, solidProp, propAlpha, foliage = nil, nil, nil, nil
    shopProp = nil
    thresholdUsesDepth = nil
    width, height, lastValues, previousInterior, previousDimension = nil, nil, nil, nil, nil
    previousCameraInterior = nil
    stats = {}
    if not settings then return end
    if reloading then
        settings.modeOverride = modeOverride
        setElementData(localPlayer, reloadSnapshot, settings, false)
    else
        if settings.customFilter then setColorFilter(unpack(settings.filter)) else resetColorFilter() end
        setBlurLevel(settings.blur)
    end
    settings = nil
end

addCommandHandler("vcsfx", function(_, value)
    if setVcsPostProcessing(value) then
        outputChatBox("VCS post-processing: " .. value)
    else
        outputChatBox("Usage: /vcsfx full|reduced|off")
    end
end)
