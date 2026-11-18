local style = {size = 19, align = "right", maxLines = 1}

function showBottomRightText(text, duration)
    return Hud.set("bottomRight", text, math.max(0, Hud.number(duration, 3000)), style)
end

addEvent("showClientBottomRightText", true)
addEventHandler("showClientBottomRightText", localPlayer, showBottomRightText, false)

Hud.onRender(function(screen, now)
    local entry, opacity = Hud.message("bottomRight", now)
    if entry then
        Hud.text(screen, entry, screen.width - screen.margin, screen.height * 0.94,
            math.min(screen.width * 0.27, 390), opacity)
    end
end)
