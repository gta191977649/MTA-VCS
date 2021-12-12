DGS = exports.dgs --shorten the export function prefix
LANG = exports.language
local label = {label_center = nil,label_bottom = nil,label_title = nil} 
--DGS:dgsCreateImage(0,0,1,1,"gametext.png",true,_,tocolor(255,255,255,255))
function isAsianLanugage(code)
    return code == "cn_ZH" or code == "ja_JP"
end

function setFont(element,type)
    if type == 0 then 
        return DGS:dgsSetFont ( element, "pricedown" )
    elseif type == 1 then
        return DGS:dgsSetFont (element, "pricedown" )
    elseif type == 2 then
        return DGS:dgsSetFont (element, "diploma" )
    elseif type == 3 then
        return DGS:dgsSetFont (element, "bankgothic" )
    elseif type == 4 then
        return DGS:dgsSetFont (element, "bankgothic" )
    elseif type == 5 then
        return DGS:dgsSetFont (element, "bankgothic" )
    elseif type == 6 then
        return DGS:dgsSetFont (element, "pricedown" )
    end
end
function showGameTextForPlayer(text,type,timer) 
    local timer = tonumber(timer) or 1000
    if type == 1 then 
        if isElement(label.label_title) then 
            destroyElement(label.label_title)
        end
    end
    if type < 7 and type ~= 1 then 
        if isElement(label.label_center) then destroyElement(label.label_center) end
    elseif type >= 7 then
        if isElement(label.label_bottom) then destroyElement(label.label_bottom) end
    end

    
    -- samp embed color replace
    text = string.gsub(text,"~r~", "#d40000")
    text = string.gsub(text,"~y~", "#7F550B")
    text = string.gsub(text,"~l~", "#c8d7ee")
    text = string.gsub(text,"~b~", "#303a66")
    text = string.gsub(text,"~g~", "#2e6124")
    text = string.gsub(text,"~w~", "#BFC2C2")

    
    if type == 0 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.5,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{3,3})
        DGS:dgsSetProperty(label.label_center,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
    elseif type == 1 then 
        label.label_title = DGS:dgsCreateLabel(0.95, 0.85,0,0,text,true) --create a label
        setFont(label.label_title,type)
        DGS:dgsSetProperty(label.label_title,"alignment",{"right","center"})
        DGS:dgsSetProperty(label.label_title,"textSize",{3,2.5})
        DGS:dgsSetProperty(label.label_title,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
        DGS:dgsSetProperty(label.label_title,"textColor",tocolor( 159, 123, 39, 255))

    elseif type == 2 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.5,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{4,4})
        DGS:dgsSetProperty(label.label_center,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
    elseif type == 3 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.37,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{1.1,1.6})
        DGS:dgsSetProperty(label.label_center,"shadow",{3.2,3.2,tocolor( 0, 0, 0, 255 ),2})
    elseif type == 4 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.3,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{1.1,1.6})
        DGS:dgsSetProperty(label.label_center,"shadow",{3.2,3.2,tocolor( 0, 0, 0, 255 ),2})
    elseif type == 5 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.5,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{1.1,1.6})
        DGS:dgsSetProperty(label.label_center,"shadow",{4,4,tocolor( 0, 0, 0, 255 ),2})
    elseif type == 6 then 
        label.label_center = DGS:dgsCreateLabel(0.5, 0.2,0,0,text,true) --create a label
        setFont(label.label_center,type)
        DGS:dgsSetProperty(label.label_center,"alignment",{"center","center"})
        DGS:dgsSetProperty(label.label_center,"textSize",{3,3})
        DGS:dgsSetProperty(label.label_center,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
    elseif type == 7 then -- added for zone name display style 
        label.label_bottom = DGS:dgsCreateLabel(0.95, 0.9,0,0,text,true) --create a label
        if isAsianLanugage(LANG:getLanguageName()) then 
            local font = dxCreateFont('asian.ttf', 22, false, 'proof') or 'default'
            DGS:dgsSetFont ( label.label_bottom, font)
        else 
            DGS:dgsSetFont ( label.label_bottom, "beckett" )
        end
        DGS:dgsSetProperty(label.label_bottom,"alignment",{"right","center"})
        DGS:dgsSetProperty(label.label_bottom,"textSize",{3,3})
        DGS:dgsSetProperty(label.label_bottom,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
    elseif type == 8 then -- added for zone name display style 
        label.label_bottom = DGS:dgsCreateLabel(0.95, 0.9,0,0,text,true) --create a label
        if isAsianLanugage(LANG:getLanguageName()) then 
            local font = dxCreateFont('asian.ttf', 22, false, 'proof') or 'default'
            DGS:dgsSetFont ( label.label_bottom, font)
        else 
            DGS:dgsSetFont ( label.label_bottom, "bankgothic" )
        end
        DGS:dgsSetProperty(label.label_bottom,"alignment",{"right","center"})
        DGS:dgsSetProperty(label.label_bottom,"textSize",{2,2})
        DGS:dgsSetProperty(label.label_bottom,"shadow",{3,3,tocolor( 0, 0, 0, 255 ),true})
    end

    
    if type < 7 and type ~= 1 then 
        DGS:dgsSetProperty(label.label_center,"colorcoded",true)
        DGS:dgsSetAlpha(label.label_center,0)
        DGS:dgsAlphaTo(label.label_center,1,false,"OutQuad",500)  --set alpha with animation effect.

        setTimer(function() 
            if isElement(label.label_center) then
                DGS:dgsAlphaTo(label.label_center,0,false,"OutQuad",500) 
            end
        end,500+timer,1)

        setTimer(function() 
            if isElement(label.label_center) then
                destroyElement(label.label_center)
            end
        end,1000+timer,1)

    elseif type >= 7 then
        DGS:dgsSetProperty(label.label_bottom,"colorcoded",true)
        DGS:dgsSetAlpha(label.label_bottom,0)
        DGS:dgsAlphaTo(label.label_bottom,1,false,"OutQuad",500)  --set alpha with animation effect.

        setTimer(function() 
            if isElement(label.label_bottom) then
                DGS:dgsAlphaTo(label.label_bottom,0,false,"OutQuad",500) 
            end
        end,500+timer,1)

        setTimer(function() 
            if isElement(label.label_bottom) then
                destroyElement(label.label_bottom)
            end
        end,1000+timer,1)
    end
    if type == 1 then 
        DGS:dgsSetProperty(label.label_title,"colorcoded",true)
        DGS:dgsSetAlpha(label.label_title,0)
        DGS:dgsAlphaTo(label.label_title,1,false,"OutQuad",200)  --set alpha with animation effect.

        setTimer(function() 
            if isElement(label.label_title) then
                DGS:dgsAlphaTo(label.label_title,0,false,"OutQuad",500) 
            end
        end,500+timer,1)

        setTimer(function() 
            if isElement(label.label_title) then
                destroyElement(label.label_title)
            end
        end,1000+timer,1)
    end
end

addEvent( "showClientGameText", true )
addEventHandler( "showClientGameText", root, showGameTextForPlayer )