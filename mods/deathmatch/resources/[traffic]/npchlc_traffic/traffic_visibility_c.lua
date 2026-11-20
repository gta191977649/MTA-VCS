local visibility = TrafficVisibility
local visible = {}
local ROAD_FADE_WIDTH = 26
local distances = {
    pedestrian = {60, visibility.pedestrianRange},
    road = {visibility.roadRange - ROAD_FADE_WIDTH, visibility.roadRange},
    aircraft = {215, 245},
}
local cameraRange = distances.aircraft
local SAMPLE_MS = 33

local function updateRoadRange()
    local limit = getElementData(resourceRoot, visibility.roadRangeKey, false)
    if type(limit) ~= "number" or limit < 50 or limit > visibility.roadRange then limit = visibility.roadRange end
    distances.road[1], distances.road[2] = limit - ROAD_FADE_WIDTH, limit
end

local function ease(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function distanceAlpha(distanceSquared, range)
    if distanceSquared <= range[1] ^ 2 then return 1 end
    if distanceSquared >= range[2] ^ 2 then return 0 end
    return ease((range[2] - math.sqrt(distanceSquared)) / (range[2] - range[1]))
end

local function forget(element, restore)
    local state = visible[element]
    if not state then return end
    visible[element] = nil
    if restore and isElement(element) then setElementAlpha(element, state.base) end
end

local function track(element)
    local profile = getElementData(element, visibility.profileKey, false)
    if profile == "aircraft" and type(getElementData(element, "npchlc_traffic:flightSlot", false)) == "number" then
        forget(element, true)
        return
    end
    local range = distances[profile]
    if not range then forget(element, true) return end
    local state = visible[element]
    if state then
        if profile ~= state.profile then
            state.profile, state.range, state.sample = profile, range, nil
        end
        return
    end
    if not isElementStreamedIn(element) then return end
    local kind = getElementType(element)
    if kind ~= "ped" and kind ~= "vehicle" then return end
    visible[element] = {base = getElementAlpha(element), alpha = 0, start = getTickCount(),
        profile = profile, range = range}
    if getElementData(element, visibility.retiringKey, false) then
        visible[element].retiredAt, visible[element].retiredAlpha = getTickCount(), 0
    end
    setElementAlpha(element, 0)
end

addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() forget(source, true) end)
addEventHandler("onClientElementDestroy", root, function() forget(source, false) end)
addEventHandler("onClientElementModelChange", root, function()
    local state = visible[source]
    if state then setElementAlpha(source, state.alpha) end
end)
addEventHandler("onClientElementDataChange", root, function(name)
    if source == resourceRoot and name == visibility.roadRangeKey then updateRoadRange() end
    if name == visibility.profileKey or name == "npchlc_traffic:flightSlot" then track(source) end
    if name == visibility.retiringKey and isElementStreamedIn(source) then
        local state = visible[source]
        if getElementData(source, visibility.retiringKey, false) then
            if state and not state.retiredAt then
                state.retiredAt, state.retiredAlpha = getTickCount(), state.alpha
            elseif not state then
                track(source)
            end
        elseif state then
            state.retiredAt = nil
        end
    end
end)

local function updateAlpha(element, state, now, cx, cy, cz, px, py, pz, occupied, pedestrianScaleSquared)
    local alpha
    if element == occupied then
        alpha = state.base
    elseif state.retiredAt then
        alpha = state.retiredAlpha * (1 - ease((now - state.retiredAt) % 4294967296 / visibility.fadeOutMs))
    else
        if not state.sample or (now - state.sample) % 4294967296 >= SAMPLE_MS then
            state.sample = now
            local x, y, z = getElementPosition(element)
            local camera = distanceAlpha((x - cx) ^ 2 + (y - cy) ^ 2 + (z - cz) ^ 2, cameraRange)
            state.distance = camera
            if state.profile ~= "aircraft" then
                local horizontal = (x - px) ^ 2 + (y - py) ^ 2
                local distanceSquared = state.profile == "pedestrian" and horizontal / pedestrianScaleSquared
                    or horizontal + (z - pz) ^ 2
                state.distance = math.min(camera, distanceAlpha(distanceSquared, state.range))
            end
        end
        alpha = state.base * state.distance * ease((now - state.start) % 4294967296 / visibility.fadeInMs)
    end
    alpha = math.floor(alpha + 0.5)
    if alpha ~= state.alpha then
        state.alpha = alpha
        setElementAlpha(element, alpha)
    end
end

addEventHandler("onClientPreRender", root, function()
    if not next(visible) then return end
    local now = getTickCount()
    local cx, cy, cz = getCameraMatrix()
    local px, py, pz = getElementPosition(localPlayer)
    local occupied = getPedOccupiedVehicle(localPlayer)
    local pedestrianScaleSquared = visibility.pedestrianScale(localPlayer) ^ 2
    for element, state in pairs(visible) do
        updateAlpha(element, state, now, cx, cy, cz, px, py, pz, occupied, pedestrianScaleSquared)
    end
end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    updateRoadRange()
    for _, kind in ipairs({"vehicle", "ped"}) do
        for _, element in ipairs(getElementsByType(kind, root, true)) do track(element) end
    end
end, false)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for element in pairs(visible) do forget(element, true) end
end, false)
