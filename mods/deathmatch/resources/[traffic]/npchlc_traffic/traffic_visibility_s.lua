local visibility = TrafficVisibility
local pending = {}
local deadPeds = {}
local wrecks = {}
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

function visibility.retire(element, companion, callback, cancellable)
    if pending[element] then return end
    setElementData(element, visibility.retiringKey, true, "broadcast", "deny")
    if isElement(companion) and not deadPeds[companion] then
        setElementData(companion, visibility.retiringKey, true, "broadcast", "deny")
    end
    -- Leave one server tick for the fade-out state to reach existing viewers.
    local entry = {finish = callback, companion = companion, cancellable = cancellable}
    pending[element] = entry
    entry.timer = setTimer(function()
        if pending[element] == entry then finish(element) end
    end, retirementMs, 1)
end

function visibility.cancelRetirement(element)
    local entry = pending[element]
    if not entry or not entry.cancellable then return false end
    pending[element] = nil
    if isTimer(entry.timer) then killTimer(entry.timer) end
    setElementData(element, visibility.retiringKey, false, "broadcast", "deny")
    if isElement(entry.companion) and not deadPeds[entry.companion] then
        setElementData(entry.companion, visibility.retiringKey, false, "broadcast", "deny")
    end
    return true
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
    local function expire()
        if PedServices and PedServices.keepCasualty(ped) then deadPeds[ped]=setTimer(expire,1000,1) return end
        if not isElement(ped) then return end
        visibility.retire(ped, nil, function()
            if isElement(ped) then destroyElement(ped) end
        end)
    end
    deadPeds[ped]=setTimer(expire,corpseLifetimeMs-retirementMs,1)
end

function visibility.isWreck(vehicle)
    return wrecks[vehicle]~=nil
end

function visibility.keepWreck(vehicle,profile)
    if wrecks[vehicle] then return end
    wrecks[vehicle]=true
    if pending[vehicle] then finish(vehicle) end
    if not isElement(vehicle) then return end
    visibility.track(vehicle,profile)
    setElementData(vehicle,visibility.retiringKey,false,"broadcast","deny")
    setTimer(function()
        if not isElement(vehicle) then return end
        visibility.retire(vehicle,nil,function()
            if isElement(vehicle) then destroyElement(vehicle) end
        end)
    end,corpseLifetimeMs-retirementMs,1)
end

addEventHandler("onVehicleExplode",root,function()
    if getElementData(source,visibility.profileKey,false)=="aircraft" then
        visibility.keepWreck(source,"aircraft")
    end
end)

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
    wrecks[source]=nil
    if deadPeds[source] then clearDeadPed(source) end
end)

addEventHandler("onVehicleEnter", root, function(occupant)
    local entry = pending[source]
    if entry and not entry.cancellable and getElementType(occupant) == "player" then finish(source) end
end)

function visibility.stop()
    for element in pairs(pending) do finish(element) end
    for ped in pairs(deadPeds) do
        clearDeadPed(ped)
        if isElement(ped) then destroyElement(ped) end
    end
end
