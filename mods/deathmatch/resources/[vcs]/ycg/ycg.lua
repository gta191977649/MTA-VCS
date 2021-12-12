local ygcshader = dxCreateShader("ycg.fx")

for idx, txdName in ipairs(YCG_Name) do 
    engineApplyShaderToWorldTexture(ygcshader,txdName,nil,false)
    --print(txdName)
end
setFarClipDistance(2000)