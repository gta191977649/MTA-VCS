local style = {face = "gametext", nativeScale = 0.61, align = "center", maxLines = 4}

function showCaptionForPlayer(text, timer)
    local duration = Hud.number(timer, 1000)
    if duration < 0 then return false end
    if duration == 0 then duration = nil end
    return Hud.set("caption", text, duration, style)
end

function hideCaptionForPlayer()
    return Hud.clear("caption")
end

addEvent("showClientCaption", true)
addEventHandler("showClientCaption", localPlayer, showCaptionForPlayer, false)
addEvent("hideClientCaption", true)
addEventHandler("hideClientCaption", localPlayer, hideCaptionForPlayer, false)

Hud.onRender(function(screen, now)
    local entry, opacity = Hud.message("caption", now)
    if entry then
        local _, sx, sy = CWidescreenSupport:playerHud()
        Hud.text(screen, entry, screen.width / 2, 221 * sy / screen.scale, 432 * sx / screen.scale, opacity)
    end
end)
