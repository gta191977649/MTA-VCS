--DGS:dgsCreateImage(0,0,1,1,"IbMhI0w.jpg",true,_,tocolor(255,255,255,255))


local function applyUIFront(label,size)
    local font = dxCreateFont('ahronbd.ttf', size, false, 'proof') or 'default'
    DGS:dgsSetFont(label,font)
    DGS:dgsSetProperty(label,"textColor",tocolor(131,156,186,255))
end

RacePos = {}
RacePos.board = DGS:dgsCreateImage(0.867,0.735,0.09,0.125,_,true,_,tocolor(131,156,186,255))
DGS:dgsSetProperty(RacePos.board,"outline",{"center",3,tocolor(0,0,0,255)})
RacePos.bk = DGS:dgsCreateImage(0.06,0.06,0.9,0.9,_,true,RacePos.board,tocolor(0,0,0,255))
RacePos.lb_pos = DGS:dgsCreateLabel(0.13,-0.18,0.94,0.92,"1",true,RacePos.bk)
applyUIFront(RacePos.lb_pos,50)
DGS:dgsSetProperty(RacePos.lb_pos,"textSize",{0.8,1.08})
RacePos.lb_st= DGS:dgsCreateLabel(0.55,-0.055,0.94,0.92,"ST",true,RacePos.bk)
applyUIFront(RacePos.lb_st,26)
RacePos.lb_slash= DGS:dgsCreateLabel(0.55,0.23,0.94,0.92,"/",true,RacePos.bk)
applyUIFront(RacePos.lb_slash,26)
RacePos.lb_total = DGS:dgsCreateLabel(0.705,0.27,0.94,0.92,"4",true,RacePos.bk)
applyUIFront(RacePos.lb_total,23)
RacePos.lb_time = DGS:dgsCreateLabel(0.18,0.53,0.94,0.92,"1:05",true,RacePos.bk)
applyUIFront(RacePos.lb_time,30)
DGS:dgsSetProperty(RacePos.lb_time,"textSize",{0.85,1})
DGS:dgsSetVisible(RacePos.board,false)

function showRacePos(current_pos,total_pos,time) 
    DGS:dgsSetProperty(RacePos.lb_pos,"text",current_pos)
    DGS:dgsSetProperty(RacePos.lb_total,"text",total_pos)
    DGS:dgsSetProperty(RacePos.lb_time,"text",time)
    DGS:dgsSetVisible(RacePos.board,true)
end
function hideRacePos(current_pos,total_pos,time) 
    DGS:dgsSetVisible(RacePos.board,false)
end

--showRacePos(1,9,"3:29") 