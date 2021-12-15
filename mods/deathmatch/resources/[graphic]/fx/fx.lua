FX = {
    textures = {
        ["coronastar"] = "src/coronastar.png",
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
