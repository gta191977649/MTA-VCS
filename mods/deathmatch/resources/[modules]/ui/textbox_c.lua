DGS = exports.dgs
local DGSTimer = false

function calcWrapLines(str)
    local idx = 1
    local words = 0
    for c in string.gmatch(str, ".") do
        --outputChatBox(c)
        if words >= 20 then
            idx = idx +1
            words = 0
        end
        words = words +1
    end

    return idx
end

--[[
function calcWrapLines(str)
    local numOflines =  math.ceil( (string.len(str) -1) / 20 )
    -- find all \n
    for c in string.gmatch(str, "\n") do
        outputChatBox("yes")
        numOflines = numOflines + 1
    end
    return numOflines
end
--]]
function showTextBox(msg,timer)
    if isElement(tip) then 
        destroyElement(tip)
    end
    local timer = tonumber(timer) or 1000
    if isTimer(DGSTimer) then 
        killTimer( DGSTimer )
    end
    if isTimer(DestoryTimer) then 
        killTimer( DestoryTimer )
    end
    if msg == false then 
        return
    end
    msg = string.gsub(msg,"~r~", "#d40000")
    msg = string.gsub(msg,"~y~", "#ffaa01")
    msg = string.gsub(msg,"~l~", "#c8d7ee")
    msg = string.gsub(msg,"~b~", "#303a66")
    msg = string.gsub(msg,"~g~", "#2e6124")
    msg = string.gsub(msg,"~p~", "#8470ff")
    msg = string.gsub(msg,"~w~", "#ffffff")

    local text = msg
    local padding = 5

    local font = getFont("tip")

    --DGS:dgsSetSize (memo,370,height * lines, false )
    --DGS:dgsSetProperty(memo,"text","")
    --DGS:dgsSetProperty(memo,"text",msg)
    tip = DGS:dgsCreateMemo(25, 183, 450,50,text,false)
    DGS:dgsSetProperty(tip,"bgColor",tocolor(255, 255,255, 170))
    DGS:dgsSetProperty(tip,"bgColor",tocolor(0, 0, 0, 170))
    DGS:dgsSetProperty(tip,"font",font)
    DGS:dgsSetProperty(tip,"textSize",{1,1})

    DGS:dgsSetProperty(tip,"wordWrap",2)
    DGS:dgsSetProperty(tip,"padding",{padding,padding})
    DGS:dgsMemoSetScrollBarState(tip,false,false)
    DGS:dgsSetProperty(tip,"textColor",tocolor(255,255,255,230))
    --outputChatBox(text)
    --DGS:dgsMemoSetCaretPosition(tip,1,0)
    --DGS:dgsSetText(tip,text)
   -- DGS:dgsSetAlpha(tip,0.9)
    -- Fixed height
    local lines = DGS:dgsMemoGetLineCount(tip)
    local height = dxGetFontHeight(1,font)
    local tip_height = (lines * height) +padding * 2
    DGS:dgsSetSize(tip,400, tip_height)
    --DGS:dgsSetAlpha (tip, 1)
    --DGS:dgsSetVisible(tip,true)

    DGSTimer = setTimer(function() 
        DGS:dgsAlphaTo(tip,0,false,"OutQuad",500) 
    end,timer,1)
    DestoryTimer = setTimer(function() 
        destroyElement(tip)
    end,timer+500,1)

    playSoundFrontEnd(11)
end

addEvent( "showClientTextBox", true )
addEventHandler( "showClientTextBox", localPlayer, showTextBox )