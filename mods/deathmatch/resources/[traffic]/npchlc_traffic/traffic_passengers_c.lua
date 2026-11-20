addEvent("npchlc_traffic:reclaimDriverSeat", true)
addEventHandler("npchlc_traffic:reclaimDriverSeat", resourceRoot, function(ped, vehicle, jacker)
    if not isElement(ped) or not isElement(vehicle) or not isElementSyncer(ped)
        or not isElementStreamedIn(vehicle) or isPedDead(ped) or isPedInVehicle(ped) then return end
    local driver = getVehicleOccupant(vehicle, 0)
    if not driver or driver == jacker then setPedEnterVehicle(ped, vehicle, false) end
end, false)

addEvent("npchlc_traffic:occupantExit", true)
addEventHandler("npchlc_traffic:occupantExit", resourceRoot, function(ped, vehicle, seat, target, actor, x, y, z, stamp)
    if stamp and (not isElement(ped) or getElementData(ped,"npchlc_traffic:exitStamp",false)~=stamp) then return end
    if target then
        if not isElement(vehicle) or not isElement(target) or (getPedOccupiedVehicle(target) or target) ~= actor
            or getDistanceBetweenPoints3D(x, y, z, getElementPosition(actor)) > 1
            or not canTrafficPursuerExit(vehicle, target) then return end
        local vx, vy, vz = getElementVelocity(vehicle)
        if vx*vx + vy*vy + vz*vz > 0.05^2 then return end
    end
    if isElement(ped) and isElementSyncer(ped) and isElement(vehicle)
        and getPedOccupiedVehicle(ped) == vehicle and getPedOccupiedVehicleSeat(ped) == seat then
        setPedExitVehicle(ped)
    end
end, false)

addEventHandler("onClientVehicleDamage", root, function(attacker, weapon, loss)
    if isElement(attacker) and type(weapon) == "number" and weapon >= 22 and weapon <= 38
        and loss and loss > 0 and (attacker == localPlayer or isElementSyncer(source))
        and getElementData(source, TrafficVisibility.profileKey) == "road" then
        triggerServerEvent("npchlc_traffic:vehicleGunHit", resourceRoot, source, attacker, weapon)
    end
end)
