local shader = dxCreateShader("fx/worldDiffuse_old.fx", 0, 0, false, "world,object,ped")
local shaderv = dxCreateShader("fx/car_Diffuse.fx", 0, 0, false, "vehicle")
local timeLast = 0
local worldDiffuse = {
    [0] = {100, 130, 150},
    [1] = {100, 130, 150},
    [2] = {100, 130, 150},
    [3] = {100, 130, 150},
    [4] = {100, 130, 150},
    [5] = {150, 180, 200},
    [6] = {255, 200, 150},
    [7] = {255, 200, 150},
    [8] = {220, 170, 130},
    [9] = {220, 170, 130},
    [10] = {255, 180, 100},
    [11] = {255, 180, 100},
    [12] = {255, 180, 100},
    [13] = {255, 180, 100},
    [14] = {255, 180, 100},
    [15] = {255, 180, 100},
    [16] = {255, 180, 100},
    [17] = {255, 180, 100},
    [18] = {255, 180, 100},
    [19] = {255, 180, 100},
    [20] = {255, 150, 70},
    [21] = {255, 180, 100},
    [22] = {255, 160, 100},
    [23] = {255, 180, 100},
    [24] = {100, 150, 200},
}

function getEasingValueFromTime(from, hour, minutes)
    local minutes = minutes/60
    local iminutes = 1-minutes
    if type(from[hour]) == "number" then
        return from[hour]*iminutes + (from[hour + 1]*minutes)
    else
        
        --[[
        local c = {}
        Async:setPriority("low")
        Async:foreach(from[hour],function(v,k) 
            c[k] = v*iminutes + from[hour + 1][k]*minutes
        end)

        for k,v in pairs(from[hour]) do
            c[k] = v*iminutes + from[hour + 1][k]*minutes
        end
        ]]
        
        local r = from[hour][1]*iminutes + from[hour + 1][1]*minutes
        local g = from[hour][2]*iminutes + from[hour + 1][2]*minutes
        local b = from[hour][3]*iminutes + from[hour + 1][3]*minutes
        
        return r,g,b
    end
end
function updateWorldDiffuse()
    local hour, minute = getTime()
    if timeLast ~= minute then
        local int = getElementInterior(localPlayer)
        if int == 0 then 
            local hour, minute = getTime()
            local r, g, b = getEasingValueFromTime(worldDiffuse, hour, minute)
            dxSetShaderValue(shader, "WorldDiffuse", {r/255, g/255, b/255})
            dxSetShaderValue(shader, "Intensity",2)
            local inten = 0
            local r = r + inten < 255 and r+ inten or r 
            local g = g + inten < 255 and g+ inten or g 
            local b = b + inten < 255 and b+ inten or b 
            
            dxSetShaderValue(shaderv, "WorldDiffuse", {r/255, g/255, b/255})
            dxSetShaderValue(shaderv, "Intensity", 1.2)
        else
            dxSetShaderValue(shader, "WorldDiffuse", {1, 1, 1})
            dxSetShaderValue(shaderv, "Intensity",1.35)
            dxSetShaderValue(shaderv, "Intensity",1.25)
        end
    end
    timeLast = minute
end

function enableDiffuse()
    print("PS2 Diffuse Enabled")
    engineApplyShaderToWorldTexture(shader, "*")
    for k,v in pairs({"coronastar", "sitem16", "unnamed", "white64", "*radar*", "font1", "fist", "ak47icon", "brassknuckleicon", "golfclubicon", "nitestickicon", "knifecuricon", "baticon", "shovelicon", "poolcueicon", "katanaicon", "chnsawicon", "gun_dildo1icon", "gun_dildo2icon", "gun_vibe1icon", "floweraicon", "gun_caneicon", "grenadeicon", "teargasicon", "molotovicon", "colt45icon", "silencedicon", "desert_eagleicon", "chromegunicon", "sawnofficon", "shotgspaicon", "micro_uziicon", "mp5lngicon", "m4icon", "tec9icon", "cuntgunicon", "snipericon", "rocketlaicon", "heatseekicon", "flameicon", "minigunicon", "satchelicon", "bombicon", "spraycanicon", "fire_exicon", "cameraicon", "nvgogglesicon", "irgogglesicon", "gun_paraicon","*txgrass*"}) do
        engineRemoveShaderFromWorldTexture(shader, v)
    end
    engineApplyShaderToWorldTexture(shaderv, "*")
    engineRemoveShaderFromWorldTexture(shaderv, "unnamed")
    dxSetShaderValue(shaderv, "Vehicle", true)
    -- add process handle
    addEventHandler( "onClientHUDRender", root,updateWorldDiffuse,false,"low")
end

function disableDiffuse()
    print("PS2 Diffuse Disabled")
    removeEventHandler( "onClientHUDRender", root,updateWorldDiffuse)
    engineRemoveShaderFromWorldTexture(shader,"*")
    engineRemoveShaderFromWorldTexture(shaderv,"*")
end
--addEventHandler ( "onClientPreRender", root, updateCamera )