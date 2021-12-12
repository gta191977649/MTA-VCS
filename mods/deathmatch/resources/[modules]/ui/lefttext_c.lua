DGS = exports.dgs

local marginRight = 0.03
local width= 0.1
local height = 0.025
local xoff = 0.04
local leftLabel = {}
local font = dxCreateFont('bankgothic.ttf', 20, false, 'proof') or 'default'

local function applyProgressStyle(label) 
    DGS:dgsSetFont (label, font)
    DGS:dgsSetProperty(label,"textSize",{1,1})
    DGS:dgsSetProperty(label,"textColor",tocolor(200,215,238, 255))
    DGS:dgsSetProperty(label,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),2})
    DGS:dgsSetProperty(label,"alignment",{"right","top"})
    DGS:dgsSetProperty(label,"colorcoded",true)

    --DGS:dgsSetProperty(label,"PixelInt",true)
    --DGS:dgsSetAlpha(label,0)
    DGS:dgsSetVisible(label,false)
end

leftLabel[1] = {}
leftLabel[2] = {}
leftLabel[3] = {}

leftLabel[1].title = DGS:dgsCreateLabel(1-marginRight-0.11, 0.492 -xoff,0,0,"GTASA",true)
applyProgressStyle(leftLabel[1].title)
leftLabel[2].title = DGS:dgsCreateLabel(1-marginRight-0.11, 0.492 ,0,0,"GTASA",true)
applyProgressStyle(leftLabel[2].title)
leftLabel[3].title = DGS:dgsCreateLabel(1-marginRight-0.11, 0.492 +xoff,0,0,"GTASA",true)
applyProgressStyle(leftLabel[3].title)

leftLabel[1].val = DGS:dgsCreateLabel(1-marginRight, 0.492 -xoff,0,0,"GTASA",true)
applyProgressStyle(leftLabel[1].val)
leftLabel[2].val = DGS:dgsCreateLabel(1-marginRight, 0.492 ,0,0,"GTASA",true)
applyProgressStyle(leftLabel[2].val)
leftLabel[3].val = DGS:dgsCreateLabel(1-marginRight, 0.492 +xoff,0,0,"GTASA",true)
applyProgressStyle(leftLabel[3].val)

function showLeftTextForPlayer(title,val,place) 
    local type = type(val) == "number" and 1 or 2 
    local place = place or 1
    if type == 1 then
        place = val
    end
    if type == 1 then
        title = string.gsub(title,"~r~", "#d40000")
        title = string.gsub(title,"~y~", "#ffaa01")
        title = string.gsub(title,"~l~", "#c8d7ee")
        title = string.gsub(title,"~b~", "#303a66")
        title = string.gsub(title,"~g~", "#2e6124")
        title = string.gsub(title,"~w~", "#ffffff")

        DGS:dgsSetProperty(leftLabel[place].title,"text","")
        DGS:dgsSetProperty(leftLabel[place].val,"text",title)
    else 
        title = string.gsub(title,"~r~", "#d40000")
        title = string.gsub(title,"~y~", "#ffaa01")
        title = string.gsub(title,"~l~", "#c8d7ee")
        title = string.gsub(title,"~b~", "#303a66")
        title = string.gsub(title,"~g~", "#2e6124")
        title = string.gsub(title,"~w~", "#ffffff")
        val = string.gsub(val,"~r~", "#d40000")
        val = string.gsub(val,"~y~", "#ffaa01")
        val = string.gsub(val,"~l~", "#c8d7ee")
        val = string.gsub(val,"~b~", "#303a66")
        val = string.gsub(val,"~g~", "#2e6124")
        val = string.gsub(val,"~w~", "#ffffff")
        DGS:dgsSetProperty(leftLabel[place].title,"text",title)
        DGS:dgsSetProperty(leftLabel[place].val,"text",val)
    end
    
    --[[
    DGS:dgsSetAlpha(leftLabel[place].title,1)
    DGS:dgsSetAlpha(leftLabel[place].val,1)
    ]]
    DGS:dgsSetVisible(leftLabel[place].title,true)
    DGS:dgsSetVisible(leftLabel[place].val,true)
    --DGS:dgsAlphaTo(leftLabel[place],1,false,"OutQuad",500)
end

addEvent( "showClientLeftTextForPlayer", true )
addEventHandler( "showClientLeftTextForPlayer", localPlayer, showLeftTextForPlayer )


function hideLeftTextForPlayer(place)
    place = place or 1
    DGS:dgsSetVisible(leftLabel[place].title,false)
    DGS:dgsSetVisible(leftLabel[place].val,false)
    --[[
    DGS:dgsSetAlpha(leftLabel[place].title,0)
    DGS:dgsSetAlpha(leftLabel[place].val,0)
    ]]
    --DGS:dgsAlphaTo(leftLabel[place],0,false,"OutQuad",500)
end


addEvent( "hideClientLeftTextForPlayer", true )
addEventHandler( "hideClientLeftTextForPlayer", localPlayer, hideLeftTextForPlayer )