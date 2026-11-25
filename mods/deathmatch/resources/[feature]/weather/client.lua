local latest
local concertOverride = "phill_concert:weatherOverride"

local function apply()
    if not latest or getElementData(localPlayer, concertOverride, false) then return end
    local elapsed = math.max(0, getTickCount() - latest.received)
    local phase = math.min(1, latest.phase + elapsed / latest.duration)
    exports.skygfx:setVcsWeatherBlended(latest.target, latest.old, phase, latest.duration, latest.rain)
end

addEvent("weather:state", true)
addEventHandler("weather:state", resourceRoot, function(revision, old, target, phase, duration, rain)
    if latest and revision <= latest.revision then return end
    latest = {revision=revision, old=old, target=target, phase=phase, duration=duration,
        rain=rain, received=getTickCount()}
    apply()
end, false)

addEventHandler("onClientResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == "skygfx" then
        triggerServerEvent("weather:requestState", resourceRoot)
    end
end)

addEventHandler("onClientElementDataChange", localPlayer, function(key)
    if key == concertOverride then apply() end
end, false)
