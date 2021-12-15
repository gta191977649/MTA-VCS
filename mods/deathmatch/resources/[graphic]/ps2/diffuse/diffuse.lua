Timer = nil
local shader = nil
local shaderv = nil
local shaderfix = nil
local myScreenSource = nil
local sx,sy = guiGetScreenSize()
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
local pcBuggyTextures = {
    "flmngo05_256",
    "flmngo04_256",
}
local function getEasingValueFromTime(from, hour, minutes)
    local minutes = minutes/60
    local iminutes = 1-minutes
    if type(from[hour]) == "number" then
        return from[hour]*iminutes + (from[hour + 1]*minutes)
    else
        local r = from[hour][1]*iminutes + from[hour + 1][1]*minutes
        local g = from[hour][2]*iminutes + from[hour + 1][2]*minutes
        local b = from[hour][3]*iminutes + from[hour + 1][3]*minutes
        return r,g,b
    end
end

local function updateWorldDiffuse()
    local int = getElementInterior(localPlayer)
    local hour, minute = getTime()
    if timeLast ~= minute then
        if int == 0  then 
            -- first apply ps2 world diffuse
            --print(minute)
            local r, g, b = getEasingValueFromTime(worldDiffuse, hour, minute)
            dxSetShaderValue(shader, "WorldDiffuse", {r/255, g/255, b/255})
            dxSetShaderValue(shader, "Intensity",1.55)
            -- apply ps2 vehicle diffuse
            local inten = 60
            local r = r + inten < 255 and r+ inten or r 
            local g = g + inten < 255 and g+ inten or g 
            local b = b + inten < 255 and b+ inten or b 
            
            dxSetShaderValue(shaderv, "WorldDiffuse", {r/255, g/255, b/255})
            dxSetShaderValue(shaderv, "Intensity",1.1)

            
        else
            dxSetShaderValue(shader, "WorldDiffuse", {1, 1, 1})
            dxSetShaderValue(shaderv, "Intensity", 1)
        end
    end
    timeLast = minute
end
local function processDiffuse()
    if myScreenSource then
        updateWorldDiffuse()
        dxUpdateScreenSource( myScreenSource,true )
        dxDrawImage(0,  0,  sx, sy, shader )
    end
end

function enableDiffuse()
    -- start world shader
    shader = dxCreateShader("fx/worldDiffuse.fx", 0, 0, false, "world,object,ped")
    myScreenSource = dxCreateScreenSource (sx, sy) 
    dxSetShaderValue(shader, "Tex0",myScreenSource)
    -- diffuse fix shader
    shaderfix = dxCreateShader("fx/car_Diffuse.fx", 0, 0, false)
    for idx,val in ipairs(pcBuggyTextures) do
        engineApplyShaderToWorldTexture(shaderfix,val)
    end
    -- start vehicle shader
    shaderv = dxCreateShader("fx/car_Diffuse.fx", 0, 0, false, "vehicle")
    engineApplyShaderToWorldTexture(shaderv, "*")
    engineRemoveShaderFromWorldTexture(shaderv, "unnamed")
    dxSetShaderValue(shaderv, "Vehicle", true)
    -- add process handle
    addEventHandler( "onClientHUDRender", root,processDiffuse)

    --Timer = setTimer(updateWorldDiffuse, 1000, 0)
    print("PS2 Diffuse Enabled")
end
function disableDiffuse()
    removeEventHandler( "onClientHUDRender", root,processDiffuse)
    if isTimer(Timer) then killTimer(Timer) end
    --engineRemoveShaderFromWorldTexture(shaderv,"*")
    if isElement(shader) then
        destroyElement(shader)
    end
    if isElement(shaderfix) then
        destroyElement(shaderfix)
    end
    if isElement(shaderv) then
        destroyElement(shaderv)
    end
    if isElement(myScreenSource) then
        destroyElement(myScreenSource)
    end
    
    print("PS2 Diffuse Disabled")

end
--[[
addEventHandler("onClientResourceStart", resourceRoot,
    function()
        enableDiffuse()
        --disableDiffuse()
    end
)
]]
