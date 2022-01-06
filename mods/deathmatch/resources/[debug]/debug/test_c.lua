UI = exports.ui
LANG = exports.language
DGS = exports.dgs
CAM = exports.freecam
WEA = exports.timecyc
addCommandHandler("sound",function(cmd,id) 
    outputChatBox( id )
    playSoundFrontEnd ( id )   
end)


addCommandHandler("sound2",function(cmd,id) 
    outputChatBox( id )
    playSFX("STREAM", 1, 1  )
end)
addCommandHandler("setint",function(cmd,id) 
    setElementInterior(localPlayer,id)
end)

addCommandHandler("setwea",function(cmd,id) 
    setWeather( id )
end)
addCommandHandler("sett",function(cmd,id) 
    setTime(id, 0 )
end)
addCommandHandler("sid",function(cmd,id) 
    setElementModel(localPlayer,id)
end)


--[[
function addObjectOnClick (  button, state, absoluteX, absoluteY, worldX, worldY, worldZ, clickedElement ) 
    if getElementType(clickedElement) == "object" then 
        local x,y,z = getElementPosition(clickedElement)
        outputConsole(string.format("%f,%f,%f",x,y,z))
    end
end 
addEventHandler ( "onClientClick", getRootElement(), addObjectOnClick ) 
]]



function getPositionInFrontOfElement(element)
	local matrix = getElementMatrix ( element )
	local offX = 0 * matrix[1][1] + 5 * matrix[2][1] + 0 * matrix[3][1] + matrix[4][1]
	local offY = 0 * matrix[1][2] + 5 * matrix[2][2] + 0 * matrix[3][2] + matrix[4][2]
	local offZ = 0 * matrix[1][3] + 5 * matrix[2][3] + 0 * matrix[3][3] + matrix[4][3]
	return offX, offY, offZ
end



addCommandHandler("camrestore",function(cmd,id) 
    removeEventHandler ("onClientPreRender",getRootElement(),camera3)
    playSFX("STREAM", 1, 1  )
end)


addCommandHandler("lang",function(cmd,lang) 
    LANG:setLanguage(lang)
    UI:showTextBox(string.format(LANG:translateText("LANGUAGE_SET"),LANG:getLanguageName()),3000)
end)
addCommandHandler("fix",function(cmd,lang) 
    local veh = getPedOccupiedVehicle(localPlayer)
    if veh then 
        fixVehicle(veh)
        UI.showTextBox(_,"Veh fixed",3000)
    end
    
end)
addCommandHandler("getlang",function(cmd,lang) 
    outputChatBox(LANG:getLangugae())
    UI.showTextBox(_,"LANG SET",3000)
end)
local god = false

addCommandHandler("god",function(cmd) 
    god = true
    setElementData(localPlayer,"god",true)
    UI:showTextBox("Godemode",3000)
end) 

local freecam = false
addCommandHandler("freecam",function(cmd) 
    freecam = not freecam
    if freecam == true then 
        CAM:setFreecamEnabled()
        setPlayerHudComponentVisible ("radar", false )
        setPlayerHudComponentVisible ("armour", false )
        setPlayerHudComponentVisible ("breath", false )
        setPlayerHudComponentVisible ("clock", false )
        setPlayerHudComponentVisible ("health", false )
        setPlayerHudComponentVisible ("money", false )
        setPlayerHudComponentVisible ("wanted", false )
    else
        CAM:setFreecamDisabled()
        setCameraTarget (localPlayer)
        setPlayerHudComponentVisible ("radar", true )
        setPlayerHudComponentVisible ("armour", true )
        setPlayerHudComponentVisible ("breath", true )
        setPlayerHudComponentVisible ("clock", true )
        setPlayerHudComponentVisible ("health", true )
        setPlayerHudComponentVisible ("money", true )
        setPlayerHudComponentVisible ("wanted", true )
    end
    UI:showTextBox(freecam == true and "Freecam Enabled" or "Freecam Disabled",3000)

end) 


function stopDamage ()
    if god == true then 
        cancelEvent()
    end
end
addEventHandler ( "onClientPlayerDamage", getRootElement(), stopDamage )

addCommandHandler("dev",
    function()
        setDevelopmentMode(true)
        UI:showTextBox("Dev mode on",3000)
    end
)
addCommandHandler("wea",
    function(_,id)
        WEA:setTimecycWeather(id)
        UI:showTextBox("Weather Set.",3000)
    end
)
addCommandHandler("anim",function() 
    setPedAnimation(localPlayer,"ped","walk_doorpartial")
end)

function disableFilter()
    setColorFilter(0, 0, 0, 0, 0, 0, 0, 0)
end
addCommandHandler("colorfilter", disableFilter)

--[[
local id = engineRequestModel("object")
local dff = engineLoadDFF("MaintenanceDoors1.dff")
local txd = engineLoadTXD("maint1.txd")
engineImportTXD(txd, id)
engineReplaceModel(dff, id)

local obj createObject(id,0,0,5)
local matShader = dxCreateShader( "shader.fx" )
dxSetShaderValue ( matShader, "gColor", 1,1,1,1);
local t = dxCreateTexture("ab_maintDoors.png")
dxSetShaderValue ( matShader, "gTexture", t );
engineApplyShaderToWorldTexture ( matShader,"ab_maintDoors",obj)
function toggleWaterDrawnLast ()
	local bWaterDrawnLast = not isWaterDrawnLast()
	outputChatBox (string.format('setWaterDrawnLast: %s', tostring(bWaterDrawnLast)))
	return setWaterDrawnLast (bWaterDrawnLast)
end
addCommandHandler ('togglewater', toggleWaterDrawnLast)
]]
local clickElement = false
local click_myShader, tec = dxCreateShader ( "fx/tex_names.fx", 1, 0, false, "all" )
addCommandHandler("obj",function() 
    clickElement = not clickElement
    showCursor(clickElement)
end)


function addLabelOnClick ( button, state, absoluteX, absoluteY, worldX, worldY, worldZ, clickedElement )
    --if an element was clicked on screen
    if not clickElement then return end
    engineRemoveShaderFromWorldTexture ( click_myShader, "*" )
    if clickedElement and  getElementType ( clickedElement ) == "object"  then
        local name = getElementID(clickedElement)
        textures = engineGetModelTextures(getElementModel(clickedElement))
        engineApplyShaderToWorldTexture ( click_myShader, "*",clickedElement )
        setClipboard( name )
        outputChatBox(name)
        outputChatBox(getElementModel(clickedElement))
        showCursor(false)
    end
end
addEventHandler ( "onClientClick", root, addLabelOnClick )