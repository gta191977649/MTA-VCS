loadstring(exports.dgs:dgsImportFunction())()
setPlayerHudComponentVisible ("all",false)
setPlayerHudComponentVisible ("radar",true)

FONT = exports.font
-- render refer
--dgsCreateImage(0,0,1,1,"frontend/hud.png",true)
COLOR = {
    ["HP"] = tocolor(255,152,206,200),
    ["AP"] = tocolor(0,255,255,200),
    ["OXY"] = tocolor(0,128,192,200),
}
HUD_SCALE = 0.165
BAR_SCALE = 0.068
HUD = {
    weapon_icon = dgsCreateImage(0.9,0.04,0.5 * HUD_SCALE,1 * HUD_SCALE,"frontend/hud/fists.png",true),
    time = {},
    --time = dgsCreateLabel(0.845,0.03,0.04,0.5,"10:11",true),
    cash = dgsCreateLabel(0.919,0.16,0.04,0.5,"$000000000",true),
    hp = {},
    ap = {},
}
--HUD.hp.bar_bk = dgsCreateImage(0.824,0.126,1.01 * BAR_SCALE,0.55*BAR_SCALE ,"frontend/hud/bar.png",true)
HUD.hp.bar = dgsCreateProgressBar(0.827,0.13,0.91 * BAR_SCALE,0.43*BAR_SCALE, true)
HUD.hp.bar_bk = dgsCreateImage(-0.022,-0.08,1.07,1.22,"frontend/hud/bar.png",true,HUD.hp.bar)
HUD.ap.bar = dgsCreateProgressBar(0.827,0.09,0.91 * BAR_SCALE,0.43*BAR_SCALE, true)
HUD.ap.bar_bk = dgsCreateImage(-0.022,-0.08,1.07,1.22,"frontend/hud/bar.png",true,HUD.ap.bar)

--
dgsSetProperty(HUD.hp.bar,"indicatorColor",COLOR["HP"])

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


-- update time

function HUD_Update() 
    local hp = getElementHealth(localPlayer)
    dgsProgressBarSetProgress(HUD.hp.bar,hp)
    -- display armour or oxygen if swim
    local ap = getPedArmor(localPlayer)
    if isElementInWater(localPlayer) then
        dgsSetVisible(HUD.ap.bar,true)
        dgsSetProperty(HUD.ap.bar,"indicatorColor",COLOR["OXY"])
        local o2 = getPedOxygenLevel(localPlayer)
        -- wrap to 0-100 scale 
        dgsProgressBarSetProgress(HUD.ap.bar,o2 * 0.1)
    elseif ap > 0 then
        dgsSetVisible(HUD.ap.bar,true)
        dgsSetProperty(HUD.ap.bar,"indicatorColor",COLOR["AP"])
        dgsProgressBarSetProgress(HUD.ap.bar,ap)
    else -- hide 
        dgsSetVisible(HUD.ap.bar,false)
    end
    local cash = getPlayerMoney(localPlayer)
    dgsSetProperty(HUD.cash,"text",string.format("$%09d",cash))

    local h,m = getTime()
    updateHUDText(HUD.time,string.format("%02d:%02d",h,m)) 
end
addEventHandler("onClientHUDRender", root,HUD_Update)

