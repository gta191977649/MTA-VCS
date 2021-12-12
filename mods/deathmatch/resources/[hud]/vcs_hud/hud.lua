loadstring(exports.dgs:dgsImportFunction())()
FONT = exports.font
-- render refer
--dgsCreateImage(0,0,1,1,"frontend/hud.png",true)

HUD_SCALE = 0.165
HUD = {
    weapon_icon = dgsCreateImage(0.9,0.04,0.5 * HUD_SCALE,1 * HUD_SCALE,"frontend/hud/fists.png",true),
    time = {},
    --time = dgsCreateLabel(0.845,0.03,0.04,0.5,"10:11",true),
    cash = dgsCreateLabel(0.919,0.158,0.04,0.5,"$000000000",true),
}
function apply_ui_style(label,color,align)
    align = align or "right"
    dgsSetProperty(label,"alignment",{align,"top"})
    dgsSetFont(label,FONT:getDxFont("HUD"))
    dgsSetProperty(label,"textSize",{1.1,1.1})
    dgsSetProperty(label,"textColor",color)
    dgsSetProperty(label,"shadow",{2,2,tocolor(0,0,0,255),2})
end

function renderHUDText(text,color,offset,align,x,y) 
    align = align or "center"
    local elements = {}
    for i = 1, #text do
        local c = text:sub(i,i)
        local ele = dgsCreateLabel(x+(offset*(i-1)),y,0.04,0.5,c,true)
        apply_ui_style(ele,color,align)
        
        table.insert(elements,ele)
    end
    return elements
end

function updateHUDText(hud,text) 
    for idx,element in ipairs(hud) do 
        local c = text:sub(idx,idx)
        dgsSetProperty(element,"text",c)
    end
end

HUD.time = renderHUDText("18:01",tocolor(175,134,50,255),0.013,"center",0.812,0.03)
apply_ui_style(HUD.cash,tocolor(54,104,44,255))
--updateHUDText(HUD.time,"18:05") 


setPlayerHudComponentVisible ("all",false)
-- update time
setTimer(function() 
    local h,m = getTime()

    updateHUDText(HUD.time,string.format("%02d:%02d",h,m)) 
end,500,0)