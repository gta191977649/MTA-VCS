local visibility = TrafficVisibility
local pending = {}
local deadPeds = {}
local corpseLifetimeMs = 3000
local retirementMs = visibility.fadeOutMs + 50

function visibility.track(element, profile)
    setElementData(element, visibility.profileKey, profile, "broadcast", "deny")
end

function visibility.detach(element)
    setElementData(element, visibility.profileKey, false, "broadcast", "deny")
    if getElementData(element, visibility.retiringKey, false) then
        setElementData(element, visibility.retiringKey, false, "broadcast", "deny")
    end
end

function visibility.hasPlayerOccupant(vehicle)
    for _, occupant in pairs(getVehicleOccupants(vehicle) or {}) do
        if isElement(occupant) and getElementType(occupant) == "player" then return true end
    end
    return false
end

local function finish(element)
    local entry = pending[element]
    if not entry then return end
    pending[element] = nil
    if isTimer(entry.timer) then killTimer(entry.timer) end
    entry.finish()
end

function visibility.retire(element, companion, callback)
    if pending[element] then return end
    setElementData(element, visibility.retiringKey, true, "broadcast", "deny")
    if isElement(companion) and not deadPeds[companion] then
        setElementData(companion, visibility.retiringKey, true, "broadcast", "deny")
    end
    -- Leave one server tick for the fade-out state to reach existing viewers.
    pending[element] = {finish = callback, timer = setTimer(function() finish(element) end, retirementMs, 1)}
end

function visibility.keepDeadPed(ped)
    if deadPeds[ped] then return end
    local entry = pending[ped]
    if entry then
        if isTimer(entry.timer) then killTimer(entry.timer) end
        pending[ped] = nil
    end
    if getElementData(ped, visibility.retiringKey, false) then
        setElementData(ped, visibility.retiringKey, false, "broadcast", "deny")
    end
    deadPeds[ped] = setTimer(function()
        if not isElement(ped) then return end
        visibility.retire(ped, nil, function()
            if isElement(ped) then destroyElement(ped) end
        end)
    end, corpseLifetimeMs - retirementMs, 1)
end

function visibility.releasePed(ped)
    if not isElement(ped) then return end
    if isPedDead(ped) and getElementData(ped, visibility.profileKey, false) then
        visibility.keepDeadPed(ped)
    else
        destroyElement(ped)
    end
end

addEventHandler("onPedWasted", root, function()
    if getElementData(source, visibility.profileKey, false) then visibility.keepDeadPed(source) end
end)

local function clearDeadPed(ped)
    local timer = deadPeds[ped]
    if timer and isTimer(timer) then killTimer(timer) end
    deadPeds[ped] = nil
end

addEventHandler("onElementDestroy", root, function()
    if deadPeds[source] then clearDeadPed(source) end
end)

addEventHandler("onVehicleEnter", root, function(occupant)
    if pending[source] and getElementType(occupant) == "player" then finish(source) end
end)

function visibility.stop()
    for element in pairs(pending) do finish(element) end
    for ped in pairs(deadPeds) do
        clearDeadPed(ped)
        if isElement(ped) then destroyElement(ped) end
    end
end
