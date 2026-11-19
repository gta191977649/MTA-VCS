FX = {
    textures = {
        ["coronastar"] = "src/coronastar.png",
        ["cloud1"] = "src/cloud1.png",
        ["cloud2"] = "src/cloud2.png",
        ["cloud3"] = "src/cloud3.png",
        ["cloudhilit"] = "src/cloudhilit.png",
        ["cloudmasked"] = "src/cloudmasked.png",
        ["cloudhigh"] = "src/cloudmasked.png",
        ["collisionsmoke"] = "src/collisionsmoke.png",
        ["waterclear256"] = "src/waterclear256.png",
        ["waterwake"] = "src/waterwake.png",
        ["waterreflection2"] = "src/waterreflection2.png",
        ["collisionsmoke"] = "src/collisionsmoke.png",
        ["pointlight"] = "src/pointlight.png",
        ["smoke"] = "src/smoke.png",
        ["waterspark_16"] = "src/waterspark_16.png",
    },
    total = 62,
    size = 100 -- 100x100
}
local circularReplacements = {coronastar=true, pointlight=true}
local nativeCoronas = {"coronaringa", "coronaringb"}

local function initMoon()
    -- MTA uses the world draw category for the native moon's entity-free sprites.
    local disc = dxCreateShader("coronaAspect.fx", {ORIGINAL_TEXTURE="1"}, 1, 0, false, "world")
    if not disc then return end
    if not engineApplyShaderToWorldTexture(disc, "coronamoon", nil, false) then
        destroyElement(disc)
        return
    end

    local mask = dxCreateShader("coronaAspect.fx", {ORIGINAL_TEXTURE="1", MOON_MASK="1"}, 1, 0, false, "world")
    if not mask then return end
    if not engineApplyShaderToWorldTexture(mask, "lunar", nil, false) then
        destroyElement(mask)
        return
    end

    local centerValid = false
    addEventHandler("onClientPreRender", root, function()
        local hour = getTime()
        local screenX, screenY
        if hour >= 20 or hour < 4 then
            -- CClouds positions the moon at this offset from the camera.
            local x, y, z = getCameraMatrix()
            screenX, screenY = getScreenFromWorldPosition(x, y - 100, z + 15, 1)
        end
        local valid = not not screenX
        if valid then dxSetShaderValue(mask, "MoonCenter", screenX, screenY) end
        if valid ~= centerValid then
            dxSetShaderValue(mask, "MoonCenterValid", valid)
            centerValid = valid
        end
    end)
end

local function init()
    for name, path in pairs(FX.textures) do
        local texture = dxCreateTexture(path)
        if texture then
            local shader = dxCreateShader("texreplace.fx")
            if shader then
                dxSetShaderValue(shader, "gTexture", texture)
                engineApplyShaderToWorldTexture(shader, name, nil, false)
            end
            local round = circularReplacements[name] and dxCreateShader("coronaAspect.fx", 1, 0, false, "other")
            if round then
                dxSetShaderValue(round, "CoronaTexture", texture)
                engineApplyShaderToWorldTexture(round, name, nil, false)
            end
        end
    end
    local native = dxCreateShader("coronaAspect.fx", {ORIGINAL_TEXTURE="1"}, 1, 0, false, "other")
    if native then
        for _, name in ipairs(nativeCoronas) do
            engineApplyShaderToWorldTexture(native, name, nil, false)
        end
    end
    initMoon()
end
init()
