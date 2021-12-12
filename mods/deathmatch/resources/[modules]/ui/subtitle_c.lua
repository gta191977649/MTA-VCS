DGS = exports.dgs --shorten the export function prefix
local label = nil
local DGSTimer = nil


function showCaptionForPlayer(text,timer) 
    local timer = tonumber(timer) or 1000
    if label then destroyElement(label) end
    if isTimer(DGSTimer) then killTimer( DGSTimer ) end
    -- samp embed color replace
    text = string.gsub(text,"~r~", "#d40000")
    text = string.gsub(text,"~y~", "#eedd82")
    text = string.gsub(text,"~l~", "#9aafcb")
    text = string.gsub(text,"~b~", "#303a66")
    text = string.gsub(text,"~g~", "#2e6124")
    text = string.gsub(text,"~w~", "#ffffff")
    
    local font = getFont("subtitle")
    label = DGS:dgsCreateLabel(0.5, 0.85,0,0,text,true) --create a label
    DGS:dgsSetFont ( label, font )
    DGS:dgsSetProperty(label,"alignment",{"center","center"})
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),false})
    DGS:dgsSetProperty(label,"colorcoded",true)
    DGS:dgsSetProperty(label,"textSize",{1,1.1})
    DGS:dgsSetAlpha(label,1) 
   
    DGSTimer = setTimer(function() 
        --DGS:dgsAlphaTo(label,0,false,"OutQuad",500)
        DGS:dgsSetAlpha(label,0) 
    end,timer,1)
end

addEvent( "showClientCaption", true )
addEventHandler( "showClientCaption", localPlayer, showCaptionForPlayer )


function hideCaptionForPlayer()
    if isTimer(DGSTimer) then killTimer( DGSTimer ) end
    DGS:dgsSetAlpha(label,0)
end
addEvent( "hideClientCaption", true )
addEventHandler( "hideClientCaption", localPlayer, hideCaptionForPlayer )