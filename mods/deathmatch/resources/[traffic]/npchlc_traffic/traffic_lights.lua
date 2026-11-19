TrafficLights = {}

local timer
local previousState
local previousLock
local lastState
local cycleMs = 32768
local wind = 0
local forceGreen = false

-- US PS2 0x003132B0 / 0x00313318 compare (gameClock & 0x7fff) >> 1.
-- The original renderer classifies group 1 as north/south at 0x003155C0.
-- The state numbers below are MTA's combined north/south and east/west signals.
function TrafficLights.normalState(clockMs)
    local phase = clockMs % cycleMs
    if phase < 10000 then
        return 0, 10000 - phase
    elseif phase < 12000 then
        return 1, 12000 - phase
    elseif phase < 22000 then
        return 3, 22000 - phase
    elseif phase < 24000 then
        return 4, 24000 - phase
    end
    return 2, cycleMs - phase
end

function TrafficLights.state(clockMs, windValue, forced)
    -- 0x00313390 and 0x003133F0 flash both directions above the original wind threshold.
    if windValue > 1.1 then
        local phase = clockMs % 2048
        if phase < 1024 then return 6, 1024 - phase end
        return 9, 2048 - phase
    end
    if forced then return 5, cycleMs end
    return TrafficLights.normalState(clockMs)
end

local function update()
    local clock = getTickCount() % 4294967296
    local state, delay = TrafficLights.state(clock, wind, forceGreen)
    if lastState ~= state then
        setTrafficLightState(state)
        lastState = state
    end
    timer = setTimer(update, delay, 1)
end

function setTrafficSignalConditions(windValue, forced)
    if type(windValue) ~= "number" or not (windValue >= 0 and windValue < math.huge)
        or type(forced) ~= "boolean" then return false end
    if wind == windValue and forceGreen == forced then return true end
    wind, forceGreen = windValue, forced
    if isTimer(timer) then
        killTimer(timer)
        update()
    end
    return true
end

function TrafficLights.start()
    previousState = getTrafficLightState()
    previousLock = areTrafficLightsLocked()
    setTrafficLightsLocked(true)
    update()
end

function TrafficLights.stop()
    if not timer then
        return
    end
    killTimer(timer)
    if areTrafficLightsLocked() and getTrafficLightState() == lastState then
        setTrafficLightState(previousState)
        setTrafficLightsLocked(previousLock)
    end
    timer, previousState, previousLock, lastState = nil, nil, nil, nil
end
