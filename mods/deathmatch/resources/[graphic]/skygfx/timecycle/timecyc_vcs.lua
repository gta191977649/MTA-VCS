local nativeWeathers = {[0]=0, 4, 8, 9, 1, 8, 6, 1}
local EXTRA_COLOURS = 6
local DEFAULT_COLOUR = 0
-- SLUS-21590 weather wind table at 0x48a0f8.
local waterWinds = {[0]=0.25, 0.7, 1, 0, 0, 2, 0, 0}
local function nativeGetWeather()
    return exports.interior:getOutdoorWeather()
end

local function nativeSetWeather(weather, target)
    return exports.interior:setOutdoorWeather(weather, target)
end

local initialWeather = ({[4]=1,[8]=2,[9]=3,[1]=4,[6]=6})[nativeGetWeather()] or 0
local rows, restore = {}, {}
local reloadSnapshot = "leeds_engine:weather"
local weights, fromWeights = {[initialWeather]=1}, nil
local blendDuration, syncedRain = 60000, nil
local lastSample, blendStart, lastMinute
local interiorWeather, colour
local lastCameraInterior, outdoorClouds
local customSun = false
local worldProperties = {"AmbientColor", "AmbientObjColor", "DirectionalColor", "Illumination",
    "SpriteSize", "SpriteBrightness", "LightsOnGround", "PoleShadowStrength", "ShadowStrength",
    "ShadowsOffset", "BottomCloudsColor", "CloudsAlpha", "LowCloudsColor", "WetRoads",
    "Foggyness", "Fog", "RainFog", "WaterFog", "Rainbow", "Sandstorm"}
local minuteTick, minuteFraction, clockFrozen, minuteDuration
local running = false
VCSWeather = {old=initialWeather, new=initialWeather, interpolation=1, data={}}

local function readTable()
    rows = {}
    local file = fileOpen("timecycle/timecyc_vcs.dat", true)
    if not file then return false end
    local source = fileRead(file, fileGetSize(file))
    fileClose(file)
    if type(source) ~= "string" then return false end
    for line in source:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")
        if line ~= "" and line:sub(1, 2) ~= "//" then
            local values = {}
            for token in line:gmatch("%S+") do
                local value = tonumber(token)
                if not value or value ~= value or math.abs(value) == math.huge then return false end
                values[#values+1] = value
            end
            if #values ~= 56 then return false end
            rows[#rows+1] = values
        end
    end
    return #rows == 8 * 24
end

local function sampleMinute(now, clock)
    local frozen, duration = isTimeFrozen(), math.max(getMinuteDuration(), 1)
    if lastMinute ~= clock or not minuteTick then
        minuteTick, minuteFraction = now, 0
    elseif clockFrozen ~= frozen or minuteDuration ~= duration then
        minuteTick = now - minuteFraction * duration
    end
    if not frozen then minuteFraction = math.min((now - minuteTick) / duration, 0.999999) end
    clockFrozen, minuteDuration = frozen, duration
    return minuteFraction
end

local function weatherEffects(clock, indoors)
    local wet = (weights[2] or 0) + (weights[5] or 0)
    local fog = weights[3] or 0
    local extraSunny = (weights[4] or 0) + (weights[7] or 0)
    local rainbow = 0
    local progress = VCSWeather.interpolation
    -- SLUS-21590 003E3720: cloudy -> sunny, before halfway, 07:00..20:59.
    if blendStart and (VCSWeather.new == 0 or VCSWeather.new == 4 or VCSWeather.new == 7)
            and progress < 0.5 and clock >= 420 and clock < 1260 then
        rainbow = (fromWeights[1] or 0) * (1 - math.abs(progress - 0.25) * 4)
    end
    if indoors then return 0, 0, 0, 0 end
    -- 0018CE80 uses alpha 160 * (1 - max(extra sunnyness, foggyness)).
    return wet, fog, rainbow, 160 * (1 - math.max(extraSunny, fog))
end

local function snapshot(getter, setter, previous)
    local index = #restore + 1
    restore[index] = {setter, previous and previous[index] or {getter()}}
end

local function applySun(values)
    setSunColor(values[22], values[23], values[24], values[25], values[26], values[27])
    setSunSize(values[28])
end

function VCSWeather.setCustomSun(enabled)
    local values = VCSWeather.data.values
    if not values then return false end
    if enabled then
        if not setSunSize(0) or not setSunColor(0, 0, 0, 0, 0, 0) then
            applySun(values)
            return false
        end
    else
        applySun(values)
    end
    customSun = enabled
    return true
end

local function updateBlend(now)
    if not blendStart then return end
    local progress = math.min((now - blendStart) / blendDuration, 1)
    VCSWeather.interpolation = progress
    for weather = 0, 7 do
        weights[weather] = (fromWeights[weather] or 0) * (1-progress)
            + (weather == VCSWeather.new and progress or 0)
    end
    if progress == 1 then
        VCSWeather.old = VCSWeather.new
        nativeSetWeather(nativeWeathers[VCSWeather.new])
        blendStart, fromWeights = nil, nil
    end
end

local function update(force)
    if #rows ~= 192 then return end
    local cameraInterior = getCameraInterior()
    local indoorColour = colour
    if indoorColour == nil and cameraInterior ~= 0 then indoorColour = DEFAULT_COLOUR end
    local indoors = indoorColour ~= nil
    local now = getTickCount()
    local hour, minute = getTime()
    local clock = hour * 60 + minute
    if not force and lastCameraInterior == cameraInterior and lastMinute == clock
        and lastSample and now - lastSample < 100 then return end
    local fraction = sampleMinute(now, clock)
    local hourFraction = (minute + fraction) / 60
    lastSample, lastMinute, lastCameraInterior = now, clock, cameraInterior
    updateBlend(now)
    local v = {}
    for field = 1, 56 do
        local value = 0
        for weather = 0, 7 do
            local weight = weights[weather] or 0
            if weight > 0 then
                local a = rows[weather * 24 + hour + 1][field]
                local b = rows[weather * 24 + (hour + 1) % 24 + 1][field]
                value = value + weight * (a + (b-a) * hourFraction)
            end
        end
        v[field] = value
    end
    if indoors then
        local extra = rows[(interiorWeather or EXTRA_COLOURS) * 24 + indoorColour + 1]
        for field = 1, 15 do v[field] = extra[field] end
        -- The MTA sky should use the room's actual gradient, including black.
        for field = 16, 21 do v[field] = extra[field] end
        for field = 29, 38 do v[field] = extra[field] end
        for field = 48, 50 do v[field] = extra[field] end
        -- SLUS-21590 001CCF20 gates the remaining sky-dependent colours.
        if extra[16] ~= 0 or extra[17] ~= 0 or extra[18] ~= 0 then
            for field = 39, 47 do v[field] = extra[field] end
            for field = 51, 54 do v[field] = extra[field] end
        end
        for field = 22, 28 do v[field] = 0 end
    end
    local function rgb(i) return {v[i], v[i+1], v[i+2]} end
    local clip = math.max(v[34], 1)
    local fog = math.min(v[35], clip - 1)
    local wetRoads, fogginess, rainbow, cloudsAlpha = weatherEffects(clock + fraction, indoors)
    local waterWind = 0
    for weather, weight in pairs(weights) do
        waterWind = waterWind + weight * waterWinds[weather]
    end
    VCSWeather.data = {
        values=v, indoors=indoors, amb=rgb(1), amb_obj=rgb(4), amb_bl=rgb(7), amb_obj_bl=rgb(10),
        directional=rgb(13), dirMult=1, sky_top=rgb(16), sky_bot=rgb(19),
        sun_core=rgb(22), sun_corona=rgb(25), sun_size=v[28],
        sprite_size=v[29], sprite_brightness=v[30], farClp=clip, fogSt=fog, fogginess=fogginess,
        wetRoads=wetRoads, rain=indoors and 0 or (syncedRain or 0.5*wetRoads), rainbow=rainbow, cloudsAlpha=cloudsAlpha,
        radiosityIntensity=v[36], radiosityLimit=v[37], lightOnGround=v[38],
        cloud=rgb(39), fluffy_top=rgb(42), fluffy_bot=rgb(45),
        blur=rgb(48), blurAlpha=v[55], blurOffset=v[56],
        postfx1={0,0,0,v[55]}, postfx2={v[48],v[49],v[50],v[55]},
        water={v[51],v[52],v[53],v[54]},
        wind=waterWind, waterWind=math.min(waterWind, 1),
    }
    if indoors and outdoorClouds == nil then
        outdoorClouds = getCloudsEnabled()
        setCloudsEnabled(false)
    elseif not indoors and outdoorClouds ~= nil then
        setCloudsEnabled(outdoorClouds)
        outdoorClouds = nil
    end
    setSkyGradient(v[16],v[17],v[18],v[19],v[20],v[21])
    if not customSun then applySun(v) end
    -- SLUS-21590 001A6310 installs the directional RGB and 001A7000
    -- selects object ambient for the native vehicle and pedestrian draws.
    setWorldProperty("AmbientColor", v[1], v[2], v[3])
    setWorldProperty("AmbientObjColor", v[4], v[5], v[6])
    setWorldProperty("DirectionalColor", v[13], v[14], v[15])
    setWorldProperty("Illumination", 1)
    setWorldProperty("SpriteSize", v[29])
    -- VCS uses a unit RGB multiplier. SA divides this property by 10
    -- before converting the corona and its ground contribution to bytes.
    setWorldProperty("SpriteBrightness", math.min(v[30], 1) * 10)
    setWorldProperty("LightsOnGround", v[38])
    setWorldProperty("ShadowStrength", math.floor(v[31] + 0.5))
    setWorldProperty("PoleShadowStrength", math.floor(v[33] + 0.5))
    -- The VCS table has no SA particle-fog channels.
    setWorldProperty("LowCloudsColor", v[39], v[40], v[41])
    setWorldProperty("BottomCloudsColor", v[45], v[46], v[47])
    setWorldProperty("CloudsAlpha", math.floor(cloudsAlpha + 0.5))
    setWorldProperty("WetRoads", wetRoads)
    setWorldProperty("Foggyness", fogginess)
    setWorldProperty("Fog", fogginess)
    setWorldProperty("RainFog", 0)
    setWorldProperty("WaterFog", 0)
    setWorldProperty("Rainbow", rainbow)
    setWorldProperty("Sandstorm", 0)
    setFogDistance(fog)
    setFarClipDistance(clip)
    setWaterColor(v[51],v[52],v[53],v[54])
    -- PS2 Update clamps rainy/hurricane rain to 0.5. Blend its endpoints here.
    setRainLevel(VCSWeather.data.rain)
    -- Keep SA heat distortion disabled throughout the VCS weather pipeline.
    setHeatHaze(0)
end

local function renderWeather()
    update(false)
end

local function interiorChanged(_, _, weather, row)
    interiorWeather, colour = weather, row
    lastMinute = nil
end

function getTimeCycleValue(key)
    return VCSWeather.data[key]
end

local function validWeather(weather)
    return type(weather) == "number" and nativeWeathers[weather] ~= nil
end

function setVcsWeather(weather)
    if #rows ~= 192 or not validWeather(weather) then return false end
    VCSWeather.old, VCSWeather.new, VCSWeather.interpolation = weather, weather, 1
    weights, fromWeights, blendStart = {[weather]=1}, nil, nil
    blendDuration, syncedRain = 60000, nil
    nativeSetWeather(nativeWeathers[weather])
    update(true)
    return true
end

function setVcsWeatherBlended(weather, oldWeather, phase, duration, rain)
    if #rows ~= 192 or not validWeather(weather) then return false end
    if oldWeather ~= nil then
        if not validWeather(oldWeather) or type(phase) ~= "number" or not (phase >= 0 and phase <= 1)
                or type(duration) ~= "number" or not (duration > 0 and duration < math.huge)
                or type(rain) ~= "number" or not (rain >= 0 and rain <= 1) then return false end
        if nativeGetWeather() ~= nativeWeathers[oldWeather] then nativeSetWeather(nativeWeathers[oldWeather]) end
        VCSWeather.old, VCSWeather.new = oldWeather, weather
        syncedRain, blendDuration = rain, duration
        fromWeights = {[oldWeather]=1}
        blendStart = getTickCount() - phase * duration
        update(true)
        return true
    end
    updateBlend(getTickCount())
    syncedRain, blendDuration = nil, 60000
    fromWeights, blendStart = {}, getTickCount()
    for id, weight in pairs(weights) do fromWeights[id] = weight end
    VCSWeather.new, VCSWeather.interpolation = weather, 0
    update(true)
    return true
end

function getOutdoorWeather()
    if #rows ~= 192 then return false end
    return VCSWeather.old, blendStart and (syncedRain == nil or VCSWeather.old ~= VCSWeather.new) and VCSWeather.new or nil
end

function getVcsWeather()
    if VCSWeather.data.indoors then return interiorWeather or EXTRA_COLOURS end
    return getOutdoorWeather()
end

function VCSWeather.seekBlend(fraction)
    if not blendStart or type(fraction) ~= "number" then return end
    blendStart = getTickCount() - math.max(0, math.min(1, fraction)) * blendDuration
    update(true)
end

function VCSWeather.start()
    if running then return true end
    if not readTable() then
        rows = {}
        outputDebugString("VCS timecycle requires 192 rows of 56 numeric fields", 1)
        return false
    end
    local saved = getElementData(localPlayer, reloadSnapshot, false)
    local previous = saved and saved.original
    -- Projected streetlights and headlights need MTA's positive height bias.
    -- Zero makes the native shadow polygons fight the road's depth buffer.
    resetWorldProperty("ShadowsOffset")
    restore = {}
    lastSample, lastMinute, minuteTick, minuteFraction = nil, nil, nil, nil
    snapshot(nativeGetWeather, nativeSetWeather, previous)
    snapshot(getSkyGradient, setSkyGradient, previous)
    snapshot(getSunColor, setSunColor, previous)
    snapshot(getSunSize, setSunSize, previous)
    snapshot(getFogDistance, setFogDistance, previous)
    snapshot(getFarClipDistance, setFarClipDistance, previous)
    snapshot(getWaterColor, setWaterColor, previous)
    snapshot(getRainLevel, setRainLevel, previous)
    snapshot(getHeatHaze, setHeatHaze, previous)
    if saved then
        VCSWeather.reloaded = true
        VCSWeather.old, VCSWeather.new = saved.old, saved.new
        weights, fromWeights, blendStart = saved.weights, saved.fromWeights, saved.blendStart
        blendDuration, syncedRain = saved.blendDuration or 60000, saved.syncedRain
        setElementData(localPlayer, reloadSnapshot, nil, false)
    else
        nativeSetWeather(nativeWeathers[initialWeather])
    end
    addEventHandler("onClientInteriorChanged", localPlayer, interiorChanged, false, "high")
    interiorChanged(exports.interior:getInteriorState())
    update(true)
    addEventHandler("onClientPreRender", root, renderWeather, false, "high")
    running = true
    return true
end

function VCSWeather.stop(reloading)
    if not running then return end
    running = false
    removeEventHandler("onClientPreRender", root, renderWeather)
    removeEventHandler("onClientInteriorChanged", localPlayer, interiorChanged)
    if outdoorClouds ~= nil then
        setCloudsEnabled(outdoorClouds)
        outdoorClouds = nil
    end
    if reloading and #rows == 192 then
        local original = {}
        for index, state in ipairs(restore) do original[index] = state[2] end
        setElementData(localPlayer, reloadSnapshot, {
            original = original, old = VCSWeather.old, new = VCSWeather.new,
            weights = weights, fromWeights = fromWeights, blendStart = blendStart,
            blendDuration = blendDuration, syncedRain = syncedRain,
        }, false)
        return
    end
    if #rows == 192 then
        for _, property in ipairs(worldProperties) do
            resetWorldProperty(property)
        end
    end
    for _, state in ipairs(restore) do state[1](unpack(state[2])) end
    restore = {}
    lastSample, lastMinute, minuteTick, minuteFraction = nil, nil, nil, nil
end
