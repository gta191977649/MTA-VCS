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
local lastSample, blendStart, lastMinute
local interiorWeather, colour
local lastCameraInterior, outdoorClouds
local customSun = false
local lightProperties = {"SpriteSize", "SpriteBrightness", "LightsOnGround"}
VCSWeather = {old=initialWeather, new=initialWeather, interpolation=1, data={}}

local function readTable()
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
    local progress = math.min((now - blendStart) / 60000, 1)
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
        and (not blendStart or now - lastSample < 100) then return end
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
                value = value + weight * (a + (b-a) * minute / 60)
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
    local clip = indoors and v[34] or 2000
    local fog = math.min(v[35], clip - 1)
    local waterWind = 0
    for weather, weight in pairs(weights) do
        waterWind = waterWind + weight * waterWinds[weather]
    end
    VCSWeather.data = {
        values=v, indoors=indoors, amb=rgb(1), amb_obj=rgb(4), amb_bl=rgb(7), amb_obj_bl=rgb(10),
        directional=rgb(13), dirMult=1, sky_top=rgb(16), sky_bot=rgb(19),
        sun_core=rgb(22), sun_corona=rgb(25), sun_size=v[28],
        sprite_size=v[29], sprite_brightness=v[30], farClp=clip, fogSt=fog, fogginess=weights[3] or 0,
        radiosityIntensity=v[36], radiosityLimit=v[37], lightOnGround=v[38],
        cloud=rgb(39), fluffy_top=rgb(42), fluffy_bot=rgb(45),
        blur=rgb(48), blurAlpha=v[55], blurOffset=v[56],
        postfx1={0,0,0,v[55]}, postfx2={v[48],v[49],v[50],v[55]},
        water={v[51],v[52],v[53],v[54]},
        waterWind=math.min(waterWind, 1),
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
    setWorldProperty("SpriteSize", v[29])
    -- VCS uses a unit RGB multiplier. SA divides this property by 10
    -- before converting the corona and its ground contribution to bytes.
    setWorldProperty("SpriteBrightness", math.min(v[30], 1) * 10)
    setWorldProperty("LightsOnGround", v[38])
    setFogDistance(fog)
    setFarClipDistance(clip)
    setWaterColor(v[51],v[52],v[53],v[54])
    setRainLevel(not indoors and math.min(1, (weights[2] or 0)*0.65 + (weights[5] or 0)) or 0)
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
    nativeSetWeather(nativeWeathers[weather])
    update(true)
    return true
end

function setVcsWeatherBlended(weather)
    if #rows ~= 192 or not validWeather(weather) then return false end
    updateBlend(getTickCount())
    fromWeights, blendStart = {}, getTickCount()
    for id, weight in pairs(weights) do fromWeights[id] = weight end
    VCSWeather.new, VCSWeather.interpolation = weather, 0
    update(true)
    return true
end

function getOutdoorWeather()
    if #rows ~= 192 then return false end
    return VCSWeather.old, blendStart and VCSWeather.new or nil
end

function getVcsWeather()
    if VCSWeather.data.indoors then return interiorWeather or EXTRA_COLOURS end
    return getOutdoorWeather()
end

function VCSWeather.seekBlend(fraction)
    if not blendStart or type(fraction) ~= "number" then return end
    blendStart = getTickCount() - math.max(0, math.min(1, fraction)) * 60000
    update(true)
end

function VCSWeather.start()
    if not readTable() then
        rows = {}
        outputDebugString("VCS timecycle requires 192 rows of 56 numeric fields", 1)
        return false
    end
    local saved = getElementData(localPlayer, reloadSnapshot, false)
    local previous = saved and saved.original
    snapshot(nativeGetWeather, nativeSetWeather, previous)
    snapshot(getSkyGradient, setSkyGradient, previous)
    snapshot(getSunColor, setSunColor, previous)
    snapshot(getSunSize, setSunSize, previous)
    snapshot(getFogDistance, setFogDistance, previous)
    snapshot(getFarClipDistance, setFarClipDistance, previous)
    snapshot(getWaterColor, setWaterColor, previous)
    snapshot(getRainLevel, setRainLevel, previous)
    -- SA renders water fog as separate geometry around the swimmer.
    -- VCS water already uses the timecycle fog in its surface shader.
    setWorldProperty("WaterFog", 0)
    if saved then
        VCSWeather.reloaded = true
        VCSWeather.old, VCSWeather.new = saved.old, saved.new
        weights, fromWeights, blendStart = saved.weights, saved.fromWeights, saved.blendStart
        setElementData(localPlayer, reloadSnapshot, nil, false)
    else
        nativeSetWeather(nativeWeathers[initialWeather])
    end
    addEventHandler("onClientInteriorChanged", localPlayer, interiorChanged, false, "high")
    interiorChanged(exports.interior:getInteriorState())
    update(true)
    addEventHandler("onClientPreRender", root, function() update(false) end, false, "high")
    return true
end

function VCSWeather.stop(reloading)
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
        }, false)
        return
    end
    if #rows == 192 then
        resetWorldProperty("WaterFog")
        for _, property in ipairs(lightProperties) do
            resetWorldProperty(property)
        end
    end
    for _, state in ipairs(restore) do state[1](unpack(state[2])) end
end

