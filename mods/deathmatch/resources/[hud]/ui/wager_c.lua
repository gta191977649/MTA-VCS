DGS = exports.dgs
--DGS:dgsCreateImage(0,0,1,1,"sa-mp-000.png",true,_,tocolor(255,255,255,255))
local font = dxCreateFont('tip.ttf', 27, false, 'proof') or 'default'
local font2 = dxCreateFont('ahronbd.ttf', 40, false, 'proof') or 'default'


local function appyHeaderStyle(label)
    DGS:dgsSetFont(label,"beckett")
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor(0,0,0,255),true})
    DGS:dgsSetProperty(label,"textSize",{3,3})
end
local function applySubStyle(label)
    DGS:dgsSetFont(label,font)
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor(0,0,0,255),false})
    DGS:dgsSetProperty(label,"textSize",{0.8,0.9})
    DGS:dgsSetProperty(label,"textColor",tocolor(123,143,170))
end
local function applyTextStyle(label)
    DGS:dgsSetFont(label,font2)
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor(0,0,0,255),false})
    DGS:dgsSetProperty(label,"textSize",{0.8,0.9})
    DGS:dgsSetProperty(label,"textColor",tocolor(161,161,161))
end

Wager = {
    val = {
        max = 0,
        min = 0,
        total = 0,
    }
}
Wager.main = DGS:dgsCreateImage(0.044,0.31,0.205,0.425,_,true,_,tocolor(0,0,0,180))
Wager.header = DGS:dgsCreateLabel(0.05,-0.1,0.94,0.92,"Wager",true,Wager.main)
appyHeaderStyle(Wager.header)
Wager.sub_1 = DGS:dgsCreateLabel(0.07,0.13,0.94,0.92,"Total Wager",true,Wager.main)
applySubStyle(Wager.sub_1)
Wager.total = DGS:dgsCreateLabel(0.07,0.2,0.94,0.92,"$1",true,Wager.main)
applyTextStyle(Wager.total)
Wager.sub_2 = DGS:dgsCreateLabel(0.07,0.40,0.94,0.92,"Min Wager",true,Wager.main)
applySubStyle(Wager.sub_2)
Wager.min = DGS:dgsCreateLabel(0.07,0.465,0.94,0.92,"$1",true,Wager.main)
applyTextStyle(Wager.min)
Wager.sub_3 = DGS:dgsCreateLabel(0.07,0.66,0.94,0.92,"Max Wager",true,Wager.main)
applySubStyle(Wager.sub_3)
Wager.max = DGS:dgsCreateLabel(0.07,0.725,0.94,0.92,"$100",true,Wager.main)
applyTextStyle(Wager.max)
DGS:dgsSetVisible(Wager.main,false)



local function onKeyPress(btn,press)
    if btn == "lshift" and Wager.val.total < Wager.val.max then 
        local total = Wager.val.total + 1
        updateValue(Wager.val.max,Wager.val.min,total)
        triggerEvent ( "onWagerPlaced", Wager.main,total)
    end
    if btn == "lctrl" and Wager.val.total > 0 then 
        local total = Wager.val.total - 1
        updateValue(Wager.val.max,Wager.val.min,total)
        triggerEvent ( "onWagerPlaced", Wager.main,total)
    end
    if btn == "space" and press and Wager.val.total > 0 then 
        if Wager.val.total < Wager.val.min then 
            playSoundFrontEnd(4)
            return
        end
        triggerEvent ( "onWagerComfirm", Wager.main,Wager.val.total)
        playSoundFrontEnd(1)
        outputChatBox(string.format("Total:%d",Wager.val.total))
    end
    if btn == "f" and press then 
        triggerEvent ( "onWagerExit", Wager.main)
        playSoundFrontEnd(2)
        outputChatBox("exit")
    end
end
function updateValue(max,min,total)
    Wager.val.total = total
    Wager.val.max = max
    Wager.val.min = min
    DGS:dgsSetProperty(Wager.total,"text","$"..Wager.val.total)
    DGS:dgsSetProperty(Wager.min,"text","$"..Wager.val.min)
    DGS:dgsSetProperty(Wager.max,"text","$"..Wager.val.max)
end
function showWager(max,min) 
    Wager.val.total = 0
    Wager.val.max = max
    Wager.val.min = min

    DGS:dgsSetProperty(Wager.total,"text","$"..Wager.val.total)
    DGS:dgsSetProperty(Wager.min,"text","$"..Wager.val.min)
    DGS:dgsSetProperty(Wager.max,"text","$"..Wager.val.max)
    DGS:dgsSetVisible(Wager.main,true)
    showCaptionForPlayer("Press LSHIFT to increase wager, LCTRL to \r\ndecrease wager, SPACE to process and RETURN to exit.",0) 
    addEventHandler("onClientKey",root,onKeyPress)
end
function hideWager()
    DGS:dgsSetVisible(Wager.main,false)
    removeEventHandler("onClientKey",root,onKeyPress)
    hideCaptionForPlayer()
end
function getWager()
    return Wager.main
end
addEvent ( "onWagerPlaced", true  )
addEvent ( "onWagerExit", true  )
addEvent ( "onWagerComfirm", true  )
