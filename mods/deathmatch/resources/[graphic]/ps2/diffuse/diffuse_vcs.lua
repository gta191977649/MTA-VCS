local buildingVS = dxCreateShader("fx/buildingvs_vcs.fx", 0, 0, false, "world,object,ped")

function enableDiffuse()
    print("VCS Diffuse Enabled")
    engineApplyShaderToWorldTexture(buildingVS, "*")
    for k,v in pairs({"coronastar", "sitem16", "unnamed", "white64", "*radar*", "font1", "fist", "ak47icon", "brassknuckleicon", "golfclubicon", "nitestickicon", "knifecuricon", "baticon", "shovelicon", "poolcueicon", "katanaicon", "chnsawicon", "gun_dildo1icon", "gun_dildo2icon", "gun_vibe1icon", "floweraicon", "gun_caneicon", "grenadeicon", "teargasicon", "molotovicon", "colt45icon", "silencedicon", "desert_eagleicon", "chromegunicon", "sawnofficon", "shotgspaicon", "micro_uziicon", "mp5lngicon", "m4icon", "tec9icon", "cuntgunicon", "snipericon", "rocketlaicon", "heatseekicon", "flameicon", "minigunicon", "satchelicon", "bombicon", "spraycanicon", "fire_exicon", "cameraicon", "nvgogglesicon", "irgogglesicon", "gun_paraicon","*txgrass*","*neon*","*water*"}) do
        engineRemoveShaderFromWorldTexture(buildingVS, v)
    end
end

function disableDiffuse()
    print("VCS Diffuse Disabled")
    engineRemoveShaderFromWorldTexture(buildingVS,"*")

end