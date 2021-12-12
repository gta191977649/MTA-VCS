
showBottomRightLabel = false
vLabelTimer = nil
labelText = ""
function showBottomRightText(msg,time)
    labelText = msg
    time = time or 3000
    showBottomRightLabel = true

    if not vLabelTimer == nil then
        killTimer(vLabelTimer)
        vLabelTimer = nil
    end
    vLabelTimer = setTimer (function()
        showBottomRightLabel = false
    end, time, 1)
end

addEvent( "showClientBottomRightText", true )
addEventHandler( "showClientBottomRightText", localPlayer, showTextBox )

addEventHandler("onClientRender", root,
    function()
        if not showBottomRightLabel then return end
        local aX, aY, aW, aH = convertFitRatio(1220, 799, 1565, 862)
        dxDrawText(labelText, aX+1, aY+1, aW+1, aH+1, tocolor(0, 0, 0, 255), 3.00, "sans", "right", "center", false, false, false, false, false)
        dxDrawText(labelText, aX, aY, aW, aH, tocolor(255, 255, 255, 255), 3.00, "sans", "right", "center", false, false, false, false, false)
    end
)

function convertFitRatio(gX, gY, gW, gH)
    local myX, myY = 1600, 900 -- The resolution you've used for making the guis
    local sX, sY = guiGetScreenSize() -- The resolution of the player
    local rX = gX / myX -- (0.3906) We obtain the relative position, for making it equal in all screen resolutions
    local rY = gY / myY -- (0.4883)
    local rW = gW / myX -- (0.1953)
    local rH = gH / myY -- (0.0488)

    local aX = sX * rX -- Now we multiply the relative position obtained previously by the client resolution for having an absolute position from the client screen
    local aY = sY * rY
    local aW = sX * rW
    local aH = sY * rH
    return aX, aY, aW, aH
end
