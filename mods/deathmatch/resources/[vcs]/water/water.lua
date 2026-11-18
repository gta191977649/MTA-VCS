local shader
local texture

addEventHandler("onClientResourceStart", resourceRoot, function()
    shader = dxCreateShader("fx/water.fx", 0, 0, false, "world")
    texture = dxCreateTexture("waterclear256.png")
    if not shader or not texture then
        outputDebugString("VCS water: could not create the shader or its texture.", 1)
        return
    end
    dxSetShaderValue(shader, "waterTxd", texture)
    engineApplyShaderToWorldTexture(shader, "waterclear256")
end)
