-- CWeather::Init, SLUS_215.90 003E3638.
local old, target, forced, index = 4, 4, nil, 0
local hurricaneEnabled = true
local saved, clock, minuteStart, minuteLength
local phase, rain, revision = 0, 0, 0
local anchorTick, anchorPhase

local function snapshot(player)
    revision = revision + 1
    triggerClientEvent(player or root, "weather:state", resourceRoot,
        revision, old, target, phase, minuteLength * 60, rain)
end

local function rainLevel(now)
    if target ~= 2 and target ~= 5 then return 0 end
    local pulse = math.floor(now / 16384) % 2
    if old == 2 or old == 5 then return pulse * 0.33 end
    if phase < 0.4 then return 0.5 end
    return 0.25 + pulse * 0.25
end

local function update()
    local now = getTickCount()
    local hour, minute = getTime()
    local current = hour * 60 + minute
    local length = math.max(1, getMinuteDuration())
    local changed = clock ~= current
    local discontinuity = clock == nil or (changed and current ~= (clock + 1) % 1440)
    if changed then
        minuteStart = now
    elseif length ~= minuteLength then
        minuteStart = now - math.min((now - minuteStart) / minuteLength, 1) * length
    end
    local nextPhase = (minute + math.max(0, math.min((now - minuteStart) / length, 0.999999))) / 60
    -- Update compares fractions of an hour, including after SCM clock changes.
    local rollover = nextPhase < phase
    if rollover then
        old = target
        if forced then
            target = forced
        else
            index = (index + 1) % #WeatherTypes
            target = WeatherTypes[index + 1]
            if target == 5 and not hurricaneEnabled then target = 2 end
        end
    end
    local rateChanged = length ~= minuteLength
    clock, phase, minuteLength = current, nextPhase, length
    local previousRain = rain
    rain = rainLevel(now)
    -- Correct accumulated drift when the server clock and timer diverge.
    if discontinuity or rollover or rateChanged or rain ~= previousRain or
            math.abs(phase - (anchorPhase + (now - anchorTick) / (length * 60))) * 60 > 0.25 then
        anchorTick, anchorPhase = now, phase
        snapshot()
    end
end

local function valid(id)
    return type(id) == "number" and id >= 0 and id <= 7 and id == math.floor(id)
end

function ForceWeather(id)
    if not valid(id) then return false end
    update()
    forced = id
    return true
end

function ForceWeatherNow(id)
    if not ForceWeather(id) then return false end
    old, target = id, id
    rain = rainLevel(getTickCount())
    snapshot()
    return true
end

function ReleaseWeather()
    update()
    forced = nil
    return true
end

function SetHurricaneEnabled(enabled)
    if type(enabled) ~= "boolean" then return false end
    update()
    hurricaneEnabled = enabled
    return true
end

function StoreWeather()
    update()
    saved = {old, target, phase, rain}
    return true
end

function RestoreWeather()
    if not saved then return false end
    update()
    old, target, phase, rain = unpack(saved)
    anchorPhase, anchorTick = phase, getTickCount()
    snapshot()
    return true
end

function GetWeatherState()
    update()
    return old, target, phase, index, forced, rain
end

addEvent("weather:requestState", true)
addEventHandler("weather:requestState", resourceRoot, function()
    if client and source == resourceRoot then
        update()
        snapshot(client)
    end
end, false)

addEventHandler("onResourceStart", resourceRoot, function()
    update()
    setTimer(update, 50, 0)
end)
