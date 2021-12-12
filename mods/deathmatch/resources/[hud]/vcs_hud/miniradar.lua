RADAR = {
    textures = {
        ["radardisc"] = "frontend/hud/radardisc.png",
        ["radar_north"] = "frontend/hud/radar_north.png",
    },
    total = 62,
    size = 100 -- 100x100
}
OFFSET = 0
function init() 
    -- replace tiles
    for i=0,RADAR.total do
        local filename = string.format("frontend/radar/radar%02d.png",i)
        local texture = dxCreateTexture(filename)
        if texture then
            local shader = dxCreateShader ( "shader/texreplace.fx" )
            dxSetShaderValue ( shader, "gTexture", texture )
            local replaceTxd =  string.format("radar%02d",i+ OFFSET ) 
            --engineRemoveShaderFromWorldTexture ( shader,replaceTxd)
            engineApplyShaderToWorldTexture ( shader,replaceTxd)
            print(replaceTxd)
        end
    end

    -- replace ui
    for key, val in pairs(RADAR.textures) do
        local txd = dxCreateTexture(val)
        local shader = dxCreateShader ( "shader/texreplace.fx" )
        dxSetShaderValue ( shader, "gTexture", txd )
        engineApplyShaderToWorldTexture ( shader,key)
        print(key)
    end
end
init() 
--[[
addEventHandler( "onClientKey", root, function(button,press)
    if button == "mouse_wheel_up" and press then
        OFFSET = OFFSET+1 < RADAR.total and OFFSET + 1 or 0 
    end
    if button == "mouse_wheel_down" and press then
        OFFSET = OFFSET-1 > 0 and OFFSET - 1 or RADAR.total 
    end
    init() 
    outputChatBox(OFFSET)
end)
]]