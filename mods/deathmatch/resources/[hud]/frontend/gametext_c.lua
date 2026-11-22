local theme = getHudTheme()

local gold = {220, 172, 2}
-- VCSPC CDraw.cpp BaseColors and CHud's area, vehicle and radio drawing routines.
local nameWhite, radioBlue, radioTuningBlue = {248, 248, 248}, {75, 152, 207}, {0, 100, 150}
-- SLUS vehicle and zone routines (0x320338 / 0x320710) draw FancyText at 1.0.
local title = {face = "fancytext", y = 210, nativeScale = 1, color = nameWhite,
    align = "right", fadeIn = 200, fadeDelay = 500, fadeOut = 500}
local location = {face = "fancytext", y = 234, nativeScale = 1, color = nameWhite,
    align = "right", fadeIn = 500, fadeOut = 500}

-- CHud's independent styled text buffers start at 0x21E, with a 0x200-byte stride.
-- PS2 coordinates are in the game's 480 x 272 logical space.
local styles = {
    [0] = {slot = "big0", face = "bigtext", y = 110, nativeScale = 1, color = theme.accent, fadeIn = 500, fadeOut = 500},
    [1] = {slot = "big1", face = "fancytext", y = 268, nativeScale = 1.2, color = gold,
        align = "right", valign = "bottom", fadeIn = 300, fadeOut = 500},
    [2] = {slot = "big2", face = "bigtext", y = 76, nativeScale = 1, color = {0, 220, 135}, fadeIn = 650},
    [3] = {slot = "big3", y = 196, nativeScale = 1, color = {0, 106, 164}},
    [4] = {slot = "big4", y = 196, nativeScale = 1, color = {8, 143, 59}},
    [5] = {slot = "big5", y = 200, nativeScale = 1, fadeIn = 500, fadeOut = 500},
    [6] = {slot = "big6", face = "fancytext", y = 268, nativeScale = 1, color = gold,
        align = "right", valign = "bottom", fadeIn = 500, fadeOut = 500},
    [7] = {slot = "big7", y = 150, nativeScale = 1, color = theme.accent},
    [8] = location,
    VEHICLE_NAME = title,
    LOCATION_NAME = location,
    missionPassed = {slot = "missionPassed", face = "bigtext", y = 136, nativeScale = 1,
        align = "center", valign = "center", fadeIn = 500, fadeOut = 500},
    missionResult = {slot="missionResult",y=136,face="bigtext",nativeScale=1,color=theme.accent,
        align="center",valign="center",fadeIn=500,fadeOut=500},
    garage = {slot = "garage", y = 175, nativeScale = 1},
    raceCountdown = {slot="raceCountdown",face="bigtext",y=150,nativeScale=1},
    radio = {slot = "radio", face = "fancytext", y = 7, nativeScale = 1, color = radioBlue},
    radioTuning = {slot = "radio", face = "fancytext", y = 7, nativeScale = 1, color = radioTuningBlue},
}

title.slot, location.slot = "vehicle", "location"
for _, style in pairs(styles) do
    style.align = style.align or "center"
    style.maxLines = style.align == "right" and 2 or 4
end

function showGameTextForPlayer(text, styleId, timer)
    local style = styles[Hud.number(styleId)]
    if not style then return false end
    return Hud.set(style.slot, text, math.max(0, Hud.number(timer, 1000)), style)
end

function showGameText(text, styleName, duration)
    if type(styleName) ~= "string" then return false end
    local style = styles[styleName]
    if not style then return false end
    duration = Hud.number(duration, 3000)
    if duration < 0 then return false end
    if duration == 0 then duration = nil end
    return Hud.set(style.slot, text, duration, style)
end

local resultReason = {face="gametext",nativeScale=0.8,color=theme.accent,align="center",maxLines=3}

function showVehicleMissionResult(passed,reason)
    if type(reason)~="string" or reason=="" then return false end
    local title = passed and (getVcsText("M_PASSN") or "MISSION PASSED!")
        or (getVcsText("M_FAIL") or "MISSION FAILED!")
    local style=styles.missionResult
    Hud.set(style.slot,title,4000,style)
    Hud.message(style.slot,getTickCount()).reason={text=reason,style=resultReason}
    if passed then CAudioEngine:playMissionPassedMusic() end
    return true
end

function hideGameText(styleName)
    local style = styles[styleName]
    return style and Hud.clear(style.slot, Hud.owner()) or false
end

function showVcsGarageGameText(text, duration)
    duration = Hud.number(duration)
    if not duration or duration <= 0 then return false end
    return showGameText(text, "garage", duration)
end

addEvent("showClientGameText", true)
addEventHandler("showClientGameText", localPlayer, showGameTextForPlayer, false)

local drawOrder = {"location", "vehicle", "garage", "radio", "big3", "big4", "big5", "big1",
    "big0", "raceCountdown", "big7", "big2", "big6", "missionPassed", "missionResult"}

function Hud.hasPriorityGameText(now)
    return Hud.message("big2", now) ~= nil or Hud.message("big0", now) ~= nil or Hud.message("missionPassed", now) ~= nil or Hud.message("missionResult", now) ~= nil
end

Hud.onRender(function(screen, now)
    local priority = Hud.hasPriorityGameText(now)
    local big1, big6 = Hud.message("big1", now), Hud.message("big6", now)
    for _, slot in ipairs(drawOrder) do
        local entry, opacity = Hud.message(slot, now)
        local overlaps = (priority and (slot == "location" or slot == "vehicle"))
            or (big1 and slot == "big6") or ((big1 or big6) and (slot == "big4" or slot == "big5"))
        if entry and not overlaps then
            local right = entry.style.align == "right"
            local x = right and screen.width - 24 * screen.fontScaleY * screen.textAspect or screen.width / 2
            local y = entry.style.y * screen.fontScaleY
            if slot == "vehicle" or slot == "location" then
                y = screen.height - (272 - entry.style.y) * screen.fontScaleY
            end
            local width = math.min(screen.width - 96, 864)
            if slot == "missionPassed" then
                y = screen.height / 2
            elseif slot == "big0" then
                if Hud.message("big2", now) then y = screen.height * 135 / 272 end
                y = y - (1 - opacity) * 90
            elseif slot == "big7" and Hud.message("big2", now) then
                y = screen.height * 175 / 272
            end
            if slot=="missionResult" then
                y=screen.height*0.46
                local height=Hud.text(screen,entry,x,y,screen.width*0.92,opacity)
                if entry.reason then
                    Hud.text(screen,entry.reason,x,y+height/2+2*screen.fontScaleY,screen.width*0.92,opacity)
                end
            else
                Hud.text(screen, entry, x, y, width, opacity)
            end
        end
    end
end)
