-- SLUS DrawHelpText draws with fixed text/panel alpha. The game's transition
-- timer controls message state and does not interpolate the rendered opacity.
local helpStyle = {face = "gametext", nativeScale = 0.6, panel = true, maxLines = 5}
function showTextBox(text, duration, playCue)
    if text == false then return Hud.clear("help", Hud.owner()) end
    duration = Hud.number(duration, 1000)
    if duration < 0 then return false end
    if duration == 0 then duration = nil end
    local previous = Hud.message("help", getTickCount())
    if previous and previous.text == text and previous.owner == Hud.owner() then
        previous.duration = duration
    elseif not Hud.set("help", text, duration, helpStyle) then
        return false
    end
    if playCue ~= false then CAudioEngine:reportFrontendAudioEvent("help") end
    return true
end

addEvent("showClientTextBox", true)
addEventHandler("showClientTextBox", localPlayer, showTextBox, false)

Hud.onRender(function(screen, now)
    local _, sx, sy = CWidescreenSupport:playerHud()
    local y, x = 20 * sy / screen.scale, 28 * sx / screen.scale
    local width = 220 * sx / screen.scale
    local entry, opacity = Hud.message("help", now)
    if entry and opacity > 0 and not Hud.hasPriorityGameText(now) then
        y = y + Hud.text(screen, entry, x, y, width, opacity) + 18
    end
    screen.helpBottom = y
end)
