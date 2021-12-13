DGS = exports.dgs
--DGS:dgsCreateImage(0,0,1,1,"refer.png",true,_,tocolor(255,255,255,255))

local function appyHeaderStyle(label)
    DGS:dgsSetFont(label,"beckett")
    DGS:dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),true})
    DGS:dgsSetProperty(label,"textSize",{2,1.8})
end
local function appyLabel(label)
    local font = dxCreateFont('tip.ttf', 14, false, 'proof') or 'default'

    DGS:dgsSetFont(label,font)
    --DGS:dgsSetProperty(label,"shadow",{1,1,tocolor(0,0,0,255),false})
    DGS:dgsSetProperty(label,"textSize",{0.75,1})
end
local function appyWeek(label)
    --local font = dxCreateFont('tip.ttf', 14, false, 'proof') or 'default'

    DGS:dgsSetFont(label,"pricedown")
    DGS:dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),true})
    DGS:dgsSetProperty(label,"textSize",{1.8,0.85})
    DGS:dgsSetProperty(label,"alignment",{"right"})
end
local function appyBar(bar)
    DGS:dgsSetProperty(bar,"bgColor",tocolor(100,100,100,255))
    DGS:dgsSetProperty(bar,"outline",{"out",2,tocolor(0,0,0,255)})
    DGS:dgsSetProperty(bar,"indicatorColor",tocolor(255,255,255,255))
    return bar
end

Status = {}

Status.Status = DGS:dgsCreateImage(0.415,0.05,0.17,0.2,_,true,_,tocolor(0,0,0,180))
Status.Header = DGS:dgsCreateLabel(0.05,-0.15,0.94,0.92,"Stats",true,Status.Status)
appyHeaderStyle(Status.Header)
Status.lb_respect = DGS:dgsCreateLabel(0.06,0.16,0.94,0.92,"Respect",true,Status.Status)
appyLabel(Status.lb_respect)
Status.lb_respect = DGS:dgsCreateLabel(0.06,0.29,0.94,0.92,"Stamina",true,Status.Status)
appyLabel(Status.lb_respect)
Status.lb_respect = DGS:dgsCreateLabel(0.06,0.42,0.94,0.92,"Muscle",true,Status.Status)
appyLabel(Status.lb_respect)
Status.lb_respect = DGS:dgsCreateLabel(0.06,0.55,0.94,0.92,"Fat",true,Status.Status)
appyLabel(Status.lb_respect)
Status.lb_respect = DGS:dgsCreateLabel(0.06,0.68,0.94,0.92,"Sex appeal",true,Status.Status)
appyLabel(Status.lb_respect)
Status.lb_week = DGS:dgsCreateLabel(-0.00,0.805,0.94,0.92,"Wed",true,Status.Status)
appyWeek(Status.lb_week)
Status.respect_bar =DGS:dgsCreateProgressBar(0.53, 0.19, 0.4, 0.065, true,Status.Status)    
appyBar(Status.respect_bar)
Status.stamina_bar =DGS:dgsCreateProgressBar(0.53, 0.32, 0.4, 0.065, true,Status.Status)    
appyBar(Status.stamina_bar)
Status.muscle_bar =DGS:dgsCreateProgressBar(0.53, 0.45, 0.4, 0.065, true,Status.Status)    
appyBar(Status.muscle_bar)
Status.fat_bar =DGS:dgsCreateProgressBar(0.53, 0.58, 0.4, 0.065, true,Status.Status)    
appyBar(Status.fat_bar)
Status.sex_bar =DGS:dgsCreateProgressBar(0.53, 0.71, 0.4, 0.065, true,Status.Status)    
appyBar(Status.sex_bar)

DGS:dgsSetVisible(Status.Status,false)

function showStatusBar(respect,stamina,muscle,fat,sex,week)
    DGS:dgsSetVisible(Status.Status,true)

    DGS:dgsSetProperty(Status.respect_bar,"progress",respect)
    DGS:dgsSetProperty(Status.stamina_bar,"progress",stamina)
    DGS:dgsSetProperty(Status.muscle_bar,"progress",muscle)
    DGS:dgsSetProperty(Status.fat_bar,"progress",fat)
    DGS:dgsSetProperty(Status.sex_bar,"progress",sex)
    DGS:dgsSetProperty(Status.lb_week,"text",week)
    
end
function hideStatusBar()
    DGS:dgsSetVisible(Status.Status,false)
end

