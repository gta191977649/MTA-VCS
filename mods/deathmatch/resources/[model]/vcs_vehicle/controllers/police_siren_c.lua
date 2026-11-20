-- Native long horn presses retain their normal behavior. A brief key press can
-- fall between two GTA input polls even though MTA received both key events.
local press, pending

local function canDrive(vehicle)
    return isElement(vehicle) and getVehicleOccupant(vehicle, 0) == localPlayer
        and CVehicle.hasPoliceSiren(vehicle) and isControlEnabled("horn")
        and not isMTAWindowActive() and not isCursorShowing()
end

addEventHandler("onClientKey", root, function(key, down)
    if not down and press and key == press.key then
        local tap = press
        press = nil
        if getTickCount() - tap.started > 400 or not canDrive(tap.vehicle) then return end
        pending = tap
        setTimer(function()
            if pending ~= tap then return end
            pending = nil
            if canDrive(tap.vehicle) and getVehicleSirensOn(tap.vehicle) ~= tap.desired then
                triggerServerEvent("vcs_vehicle:setDriverSiren", tap.vehicle, tap.desired)
            end
        end, 80, 1)
    elseif down and not press then
        local vehicle = getPedOccupiedVehicle(localPlayer)
        if not canDrive(vehicle) then return end
        local keys = getBoundKeys("horn")
        if not keys or not keys[key] then return end
        local on = getVehicleSirensOn(vehicle)
        if pending and pending.vehicle == vehicle then on = pending.desired end
        pending = nil
        press = {key=key, vehicle=vehicle, started=getTickCount(), desired=not on}
    end
end)

local function reset()
    press, pending = nil, nil
end
addEventHandler("onClientPlayerVehicleExit", localPlayer, reset)
addEventHandler("onClientMinimize", root, reset)
