local controls
local visible = false
local dgs = exports.dgs

local function updateUI()
    local h, m = getTime()
    dgs:dgsSetProperty(controls.cycle, "text", ("TIME CYCLE: %02d:%02d"):format(h, m))
    dgs:dgsSetProperty(controls.hour, "text", h)
    dgs:dgsSetProperty(controls.minute, "text", m)
    dgs:dgsSetProperty(controls.interpolation, "text", ("INTERPOLATION: %f"):format(VCSWeather.interpolation))
    dgs:dgsSetProperty(controls.oldWeather, "text", "CURRENT WEATHER: "..VCSWeather.old)
    dgs:dgsSetProperty(controls.newWeather, "text", "BLEND WEATHER: "..VCSWeather.new)
end

local function createWindow()
    local resource = getResourceFromName("dgs")
    if not resource or getResourceState(resource) ~= "running" then return false end

    local window = dgs:dgsCreateWindow(0.15, 0.33, 0.3, 0.34, "SKYGFX - DEBUG", true)
    if not isElement(window) then return false end
    local h, m = getTime()
    dgs:dgsCreateLabel(0.02, 0.04, 0.01, 0.1, "HOUR:MIN", true, window)
    controls = {
        window=window,
        hour=dgs:dgsCreateEdit(0.02, 0.1, 0.1, 0.1, h, true, window),
        minute=dgs:dgsCreateEdit(0.13, 0.1, 0.1, 0.1, m, true, window),
        oldWeather=dgs:dgsCreateLabel(0.4, 0.04, 0.1, 0.1, "", true, window),
        newWeather=dgs:dgsCreateLabel(0.7, 0.04, 0.1, 0.1, "", true, window),
        cycle=dgs:dgsCreateLabel(0.02, 0.22, 0.1, 0.1, "", true, window),
        interpolation=dgs:dgsCreateLabel(0.02, 0.4, 0.1, 0.1, "", true, window),
    }

    local oldWeatherInput = dgs:dgsCreateEdit(0.4, 0.1, 0.25, 0.1, VCSWeather.old, true, window)
    local newWeatherInput = dgs:dgsCreateEdit(0.7, 0.1, 0.25, 0.1, VCSWeather.new, true, window)
    local timeSlider = dgs:dgsCreateScrollBar(0.02, 0.28, 0.96, 0.08, true, true, window)
    local blendSlider = dgs:dgsCreateScrollBar(0.02, 0.46, 0.96, 0.08, true, true, window)
    dgs:dgsSetProperty(timeSlider, "map", {0, 1439})
    dgs:dgsSetProperty(blendSlider, "map", {0, 1})

    addEventHandler("onDgsElementScroll", timeSlider, function()
        local time = math.floor(dgs:dgsScrollBarGetScrollPosition(source))
        setTime(math.floor(time / 60), time % 60)
    end, false)
    addEventHandler("onDgsElementScroll", blendSlider, function()
        VCSWeather.seekBlend(dgs:dgsScrollBarGetScrollPosition(source))
    end, false)
    addEventHandler("onDgsTextChange", oldWeatherInput, function()
        setVcsWeather(tonumber(dgs:dgsGetText(source)))
    end, false)
    addEventHandler("onDgsTextChange", newWeatherInput, function()
        setVcsWeatherBlended(tonumber(dgs:dgsGetText(source)))
    end, false)
    addEventHandler("onClientElementDestroy", window, function()
        controls = nil
        if visible then showCursor(false) end
        visible = false
    end, false)
    updateUI()
    return true
end

addCommandHandler("skygfx", function()
    if not controls or not isElement(controls.window) then
        visible = false
        if not createWindow() then return end
    end
    visible = not visible
    dgs:dgsSetVisible(controls.window, visible)
    showCursor(visible)
end)

addEventHandler("onClientRender", root, function()
    if visible and controls and isElement(controls.window) then updateUI() end
end)
