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
function init() 
    for key, val in pairs(FX.textures) do
        local txd = dxCreateTexture(val)
        local shader = dxCreateShader ( "texreplace.fx" )
        dxSetShaderValue ( shader, "gTexture", txd )
        engineApplyShaderToWorldTexture ( shader,key)
        print(key)
    end
end
init() 
