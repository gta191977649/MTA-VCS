DGS = exports.dgs
function formatLabel(label,color)
    color = color or tocolor(255,255,255,255)
    DGS:dgsSetProperty(label,"font","bankgothic")
    DGS:dgsSetProperty(label,"textColor",color)
    DGS:dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),2})
    DGS:dgsSetProperty(label,"textSize",{0.6,0.8})
end
local info = DGS:dgsCreateLabel(0.01,0.94,0,0,"2DFX: 0",true)
formatLabel(info,tocolor(188,188,255,255))

setTimer(function() 
    DGS:dgsSetProperty(info,"text",string.format("2DFX: %d/%d",RENDERED,TOTAL))

end,100,0)