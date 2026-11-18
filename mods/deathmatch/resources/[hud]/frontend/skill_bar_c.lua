local theme = getHudTheme()
local style = {size = 20, panel = true, accent = true, fadeOut = 500}

function showSkillBar(title, old, new, duration)
    old, new = Hud.number(old), Hud.number(new)
    if type(title) ~= "string" or not old or not new then return false end
    local text = ("%s  %d%% → %d%%"):format(title, old, new)
    if not Hud.set("skill", text, math.max(0, Hud.number(duration, 3000)), style) then return false end
    local entry = Hud.message("skill", getTickCount())
    entry.before, entry.after = Hud.clamp(old / 100), Hud.clamp(new / 100)
    CAudioEngine:reportFrontendAudioEvent("help")
    return true
end

Hud.onRender(function(screen, now)
    local entry, opacity = Hud.message("skill", now)
    if not entry then return end
    local x, y = screen.margin + 10, screen.helpBottom
    local width = math.min(screen.width * 0.31, 360)
    y = y + Hud.text(screen, entry, x, y, width, opacity) + 9
    local low, high = math.min(entry.before, entry.after), math.max(entry.before, entry.after)
    local color = entry.after >= entry.before and theme.accent or theme.danger
    Hud.rect(screen, x, y, width, 6, theme.track, opacity * 255)
    if low > 0 then Hud.rect(screen, x, y, width * low, 6, theme.foreground, opacity * 255) end
    if high > low then Hud.rect(screen, x + width * low, y, width * (high - low), 6, color, opacity * 255) end
end)
