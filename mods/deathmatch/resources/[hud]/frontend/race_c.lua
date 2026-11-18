local style = {size = 18, align = "right", panel = true, accent = true, maxLines = 1}

function showRacePos(position, total, time)
    if position == nil or total == nil or time == nil then return false end
    return Hud.set("race", ("%s / %s  ·  %s"):format(tostring(position), tostring(total), tostring(time)), nil, style)
end

function hideRacePos()
    return Hud.clear("race")
end

Hud.onRender(function(screen, now)
    local entry, opacity = Hud.message("race", now)
    if entry then
        Hud.text(screen, entry, screen.width - screen.margin - 10, screen.height * 0.265, 225, opacity)
    end
end)
