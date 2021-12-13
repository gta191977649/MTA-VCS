DGS = exports.dgs

local marginRight = 0.03
local width= 0.1
local height = 0.025
local xoff = 0.04
-- Create UI
local pLabel = {}
local progressbar = {}


local function applyProgressStyle(label,bar) 
    local font = dxCreateFont('bankgothic.ttf', 20, false, 'proof') or 'default'
    DGS:dgsSetFont ( label,font)
    DGS:dgsSetProperty(label,"textColor",tocolor(200,215,238, 255))
    DGS:dgsSetProperty(label,"textSize",{1,1})
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),2})

    DGS:dgsSetProperty(label,"alignment",{"right","top"})
    DGS:dgsSetProperty(bar,"padding",{4,4})    
    DGS:dgsSetProperty(bar,"indicatorColor",tocolor(200,215,238, 255))   
    --DGS:dgsSetProperty(bar,"outline",{"center",3,tocolor(0,0,0,255)})
    DGS:dgsSetVisible(label,false)
    DGS:dgsSetVisible(bar,false)
end

pLabel[1] = DGS:dgsCreateLabel(1-(width+marginRight+0.01), 0.492 -xoff,0,0,"GTASA",true)
progressbar[1] = DGS:dgsCreateProgressBar(1-(width+marginRight),0.5 - xoff,width,height, true)
applyProgressStyle(pLabel[1],progressbar[1]) 

pLabel[2] = DGS:dgsCreateLabel(1-(width+marginRight+0.01), 0.492,0,0,"GTASA",true)
progressbar[2] = DGS:dgsCreateProgressBar(1-(width+marginRight),0.5,width,height, true)
applyProgressStyle(pLabel[2],progressbar[2]) 

pLabel[3] = DGS:dgsCreateLabel(1-(width+marginRight+0.01), 0.492 + xoff,0,0,"GTASA",true)
progressbar[3] = DGS:dgsCreateProgressBar(1-(width+marginRight),0.5 + xoff,width,height, true)
applyProgressStyle(pLabel[3],progressbar[3]) 


-- Create Left Text

function showProgressBarForPlayer(text,amount,place)
    place = place or 1
    DGS:dgsSetProperty(pLabel[place],"text",text)
    DGS:dgsProgressBarSetProgress(progressbar[place],amount)
    DGS:dgsSetVisible(pLabel[place],true)
    DGS:dgsSetVisible(progressbar[place],true)
end

function hideProgressBarForPlayer(place)
    place = place or 1
    DGS:dgsSetVisible(pLabel[place],false)
    DGS:dgsSetVisible(progressbar[place],false)
end