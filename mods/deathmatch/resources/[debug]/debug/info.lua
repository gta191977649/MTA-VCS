DGS = exports.dgs
function formatLabel(label,color)
    color = color or tocolor(255,255,255,255)
    DGS:dgsSetProperty(label,"font","bankgothic")
    DGS:dgsSetProperty(label,"textColor",color)
    DGS:dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),2})
    DGS:dgsSetProperty(label,"textSize",{0.8,1})
end
local build_info = DGS:dgsCreateLabel(0.01,0.965,0,0,"",true)
local debug_info = DGS:dgsCreateLabel(0.99,0.02,0,0,"STREAMING: LOADING...",true)
local pos_info = DGS:dgsCreateLabel(0.01,0.02,0,0,"POS: LOADING...",true)
DGS:dgsSetProperty(debug_info,"alignment",{"right","center"})
DGS:dgsSetProperty(pos_info,"alignment",{"left","center"})

formatLabel(build_info)
formatLabel(debug_info,tocolor(209, 157, 0,255))
formatLabel(pos_info,tocolor(209, 157, 0,255))

local debug_memo = DGS:dgsCreateMemo(0.5,0.3,0.45,0.5,"",true,Window)
DGS:dgsSetProperty(debug_memo,"font","sans")
DGS:dgsSetProperty(debug_memo,"textSize",{1.2,1.2})
DGS:dgsSetProperty(debug_memo,"bgColor",tocolor(209, 157, 0,0))
DGS:dgsSetProperty(debug_memo,"textColor",tocolor(255, 255, 255,255))

setTimer(function() 
    local net_info = getNetworkStats ()
    local x,y,z = getElementPosition(localPlayer)
    DGS:dgsSetProperty(build_info,"text",string.format("VICE CITY STORIES FREEROAM - DEV BUILD"))
    DGS:dgsSetProperty(debug_info,"text",string.format("WEA: %d STREAMING: %d KB FPS: %d",getWeather(),engineStreamingGetUsedMemory() * 0.001,getCurrentFPS()))
    DGS:dgsSetProperty(pos_info,"text",string.format("%f %f %f",x,y,z))

end,100,0)

function addDebugMessage(msg)
    DGS:dgsMemoInsertText(debug_memo,0,1,msg)
end
setWaveHeight(1)
-- Stream debug
--[[
addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if getElementType( source ) == "object" then
            local model = getElementModel(source)
            local dffName = getElementID (source) 
            local txt = string.format("DFF: %s ID:%d streamed",dffName,model)
            outputDebugString(txt)
            outputConsole(txt)
        end
    end
)
addEventHandler( "onClientElementStreamOut", root,
    function ( )
        if getElementType( source ) == "object" then
            setElementAlpha(source,255)
        end
    end
)
setCloudsEnabled(false)
setFarClipDistance( 9999 ) 
setFogDistance(9999)
]]

