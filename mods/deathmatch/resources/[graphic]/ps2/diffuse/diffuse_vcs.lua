local buildingPipeline = dxCreateShader("fx/building_vcs.fx", 0, 0, false, "object")

function enableDiffuse()
    print("VCS Diffuse Enabled")
    engineApplyShaderToWorldTexture(buildingPipeline, "*")
    for k,v in pairs({"coronastar", "sitem16", "unnamed", "white64", "*radar*", "font1", "fist", "ak47icon", "brassknuckleicon", "golfclubicon", "nitestickicon", "knifecuricon", "baticon", "shovelicon", "poolcueicon", "katanaicon", "chnsawicon", "gun_dildo1icon", "gun_dildo2icon", "gun_vibe1icon", "floweraicon", "gun_caneicon", "grenadeicon", "teargasicon", "molotovicon", "colt45icon", "silencedicon", "desert_eagleicon", "chromegunicon", "sawnofficon", "shotgspaicon", "micro_uziicon", "mp5lngicon", "m4icon", "tec9icon", "cuntgunicon", "snipericon", "rocketlaicon", "heatseekicon", "flameicon", "minigunicon", "satchelicon", "bombicon", "spraycanicon", "fire_exicon", "cameraicon", "nvgogglesicon", "irgogglesicon", "gun_paraicon","*txgrass*","*neon*","*water*","*particleskid*","*smoke*","*wind*","washdecowall2256","cj_w_grad"}) do
        engineRemoveShaderFromWorldTexture(buildingPipeline, v)
    end
    appyIgnorelist()
end
function appyIgnorelist() 
    local f = fileOpen("diffuse/diffuse_exclude.txt")
    local lines = fileRead(f, fileGetSize(f))
    lines = split(lines,"\n")
    for k,txd in ipairs(lines) do 
        txd = string.gsub(txd,"\r","")
        engineRemoveShaderFromWorldTexture(buildingPipeline, txd)
    end
    
end



function disableDiffuse()
    print("VCS Diffuse Disabled")
    engineRemoveShaderFromWorldTexture(buildingPipeline,"*")

end