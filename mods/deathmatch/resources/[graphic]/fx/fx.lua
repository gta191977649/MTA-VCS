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
local nativeCoronas = {"coronamoon", "coronaringa", "coronaringb"}

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
end
init()
