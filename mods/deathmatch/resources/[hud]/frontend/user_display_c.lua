CUserDisplay = {}
COnscreenTimer = {}
CPager = {}

local timerStyle = {size = 27, align = "right", maxLines = 1}
local pagerStyle = {face = "pagertext", size = 15, color = {0, 0, 0}, maxLines = 1, shadow = false}
local pagerOffset = 128
local lastFrame
local displayedPager

function showVcsPager(text, duration)
    duration = Hud.number(duration, 3000)
    if duration <= 0 or not Hud.set("pager", text, duration, pagerStyle) then return false end
    CAudioEngine:reportFrontendAudioEvent("pager")
    return true
end

function hideVcsPager()
    return Hud.clear("pager", Hud.owner())
end

function CPager:draw(screen, now)
    local entry = Hud.message("pager", now)
    local dt = lastFrame and math.min((now - lastFrame) % 4294967296, 100) or 0
    lastFrame = now
    displayedPager = entry or (pagerOffset < 128 and displayedPager or nil)
    if not displayedPager then return end
    local step = math.max(2, pagerOffset * 0.06) * dt / 20
    pagerOffset = math.max(0, math.min(128, pagerOffset + (entry and -step or step)))
    local texture = CFont:texture("pager")
    if not texture then return end
    local _, sx, sy = CWidescreenSupport:playerHud()
    local x = (28 - pagerOffset) * sx
    local y = math.max(18.6667 * sy, (screen.helpBottom or 0) * screen.scale)
    dxDrawImage(x, y, 128 * sx, 44.9167 * sy, texture)
    Hud.text(screen, displayedPager, (x + 14 * sx) / screen.scale, (y + 10 * sy) / screen.scale,
        105 * sx / screen.scale, 1)
end

local function remainingTime(entry, now)
    return entry.duration - (now - entry.started) % 4294967296
end

-- A bonus can move a countdown backwards into a previously displayed second.
function COnscreenTimer:warnAtSecond(seconds, previous, threshold)
    if seconds and seconds > 0 and seconds < (threshold or 11) and (not previous or seconds < previous) then
        CAudioEngine:reportFrontendAudioEvent("timer")
    end
    return seconds
end

function COnscreenTimer:updateSound(now)
    local entry = Hud.message("timer", now)
    if not entry then return end
    local seconds = math.ceil(remainingTime(entry, now) / 1000)
    entry.lastSecond = self:warnAtSecond(seconds, entry.lastSecond, entry.warningSeconds)
end

function showVcsCountdown(label, duration, warningSeconds)
    duration = Hud.number(duration)
    warningSeconds = Hud.number(warningSeconds, 11)
    if not duration or duration <= 0 or warningSeconds < 0 or type(label) ~= "string" then return false end
    local now = getTickCount()
    local previous = Hud.message("timer", now)
    label = label == "" and " " or label
    if not Hud.set("timer", label, duration, timerStyle) then return false end
    local entry = Hud.message("timer", now)
    if not entry then return true end
    if previous and previous.owner == entry.owner and previous.text == label then
        entry.lastSecond = previous.lastSecond
    end
    entry.warningSeconds = warningSeconds
    COnscreenTimer:updateSound(now)
    return true
end

function hideVcsCountdown()
    return Hud.clear("timer", Hud.owner())
end

function COnscreenTimer:draw(screen, now)
    local entry = Hud.message("timer", now)
    if not entry or Hud.message("garage", now) then return end
    local remaining = remainingTime(entry, now)
    local seconds = math.ceil(remaining / 1000)
    local flashing = seconds < entry.warningSeconds
    local phase = remaining % 1000
    if flashing and remaining >= 750 and (phase >= 750 or phase <= 250) then return end
    local value = ("%02d:%02d"):format(math.floor(seconds / 60), seconds % 60)
    local x, y = screen.width - 48, screen.height * 87 / 272
    Hud.text(screen, {text = value, style = timerStyle}, x, y, 140, 1)
    Hud.text(screen, entry, x - 111, y, 440, 1)
end

function CUserDisplay:draw(screen, now)
    CPager:draw(screen, now)
    COnscreenTimer:draw(screen, now)
end

Hud.onRender(function(screen, now) CUserDisplay:draw(screen, now) end)
addEventHandler("onClientPreRender", root, function() COnscreenTimer:updateSound(getTickCount()) end)
