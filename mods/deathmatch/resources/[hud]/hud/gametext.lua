loadstring(exports.dgs:dgsImportFunction())()
FONT = exports.font

GameText = {}
GameTextType = {
    ["VEHICLE_NAME"] = {
        color = tocolor(255,255,255,255),
        pos = {0.919,0.85,0.04,0.5},
        font = "GAME_TEXT_NAME",
        align = {"right","top"},
        textSize = {1.1,1.1},
        shadow = {3,3,tocolor(0,0,0,255),3},
    },
    ["LOCATION_NAME"] = {
        color = tocolor(255,255,255,255),
        pos = {0.919,0.9,0.04,0.5},
        font = "GAME_TEXT_NAME",
        align = {"right","top"},
        textSize = {1.1,1.1},
        shadow = {3,3,tocolor(0,0,0,255),3},
    },
}


function showGameText(text,type,time) 
    time = time or 2000
    if GameTextType[type] then 
        -- create label
        local x,y,w,h = unpack(GameTextType[type].pos)
        if not GameText[type] then
            GameText[type] = {
                label = dgsCreateLabel(x,y,w,h,text,true)
            }
            -- set style
            dgsSetFont(GameText[type].label,FONT:getDxFont(GameTextType[type].font))
            dgsSetProperty(GameText[type].label,"alignment",GameTextType[type].align)
            dgsSetProperty(GameText[type].label,"textSize",GameTextType[type].textSize)
            dgsSetProperty(GameText[type].label,"shadow",GameTextType[type].shadow)
        end
        dgsSetProperty(GameText[type].label,"text",text)

        if isTimer(GameText[type].timer) then killTimer(GameText[type].timer) end
        -- set timeout
        dgsSetAlpha(GameText[type].label,1)
        GameText[type].timer = setTimer(function() 
            dgsAlphaTo(GameText[type].label,0,false,"OutQuad",500)
        end,time,0)
    end

   
end

--showGameText("Streetfighter","VEHICLE_NAME",3000) 
--showGameText("Escobar International Airport","LOCATION_NAME",3000) 
