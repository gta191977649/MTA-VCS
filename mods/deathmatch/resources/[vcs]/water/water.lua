SHADER = {}


addEventHandler( "onClientResourceStart", root,function() 
    SHADER.water = dxCreateShader("fx/water.fx")
    SHADER.txd = dxCreateTexture("waterclear256.png")
    if SHADER.water then
        dxSetShaderValue(SHADER.water,"waterTxd",SHADER.txd)
        engineApplyShaderToWorldTexture(SHADER.water,"waterclear256")
    end
    print("water load")
end)
