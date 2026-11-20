addEvent("vcs_vehicle:onWatercraftBoardRequest", false)

local transferring = {}

-- Server-only. Compare the seat again immediately before taking it.
function transferWatercraftSeat(player, vehicle, driver)
    if not isElement(player) or getElementType(player) ~= "player" or isPedDead(player)
        or getPedOccupiedVehicle(player) or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
        or getVehicleType(vehicle) ~= "Boat" or isVehicleLocked(vehicle) or isVehicleBlown(vehicle)
        or getElementDimension(player) ~= getElementDimension(vehicle)
        or getElementInterior(player) ~= getElementInterior(vehicle)
        or (getVehicleOccupant(vehicle,0) or false) ~= (driver or false)
        or transferring[vehicle] or driver and getElementType(driver) ~= "ped" then return false end
    transferring[vehicle] = true
    local owner = getElementSyncer(vehicle)
    local vacated = not driver or removePedFromVehicle(driver)
    local boarded = vacated and warpPedIntoVehicle(player,vehicle,0) and getVehicleOccupant(vehicle,0) == player
    if boarded and getElementSyncer(vehicle) ~= player then
        boarded = setElementSyncer(vehicle,player,false)
    end
    if not boarded then
        if getPedOccupiedVehicle(player) == vehicle then removePedFromVehicle(player) end
        if vacated and driver and not getVehicleOccupant(vehicle,0) then warpPedIntoVehicle(driver,vehicle,0) end
        if getElementSyncer(vehicle) ~= owner then setElementSyncer(vehicle,isElement(owner) and owner or true,false) end
        transferring[vehicle] = nil
        return false
    end
    transferring[vehicle] = nil
    return true
end

-- A swimming SA player cannot start the native boat-enter task. Validate the
-- synchronized exterior positions before handing the actual driver seat over.
addEvent("vcs_vehicle:boardWatercraft",true)
addEventHandler("vcs_vehicle:boardWatercraft",resourceRoot,function(vehicle)
    local player = client
    if source ~= resourceRoot or not isElement(player) or getElementType(player) ~= "player"
        or isPedDead(player) or getPedOccupiedVehicle(player) or not isControlEnabled(player,"enter_exit")
        or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
        or getVehicleType(vehicle) ~= "Boat" or isVehicleLocked(vehicle) or isVehicleBlown(vehicle)
        or getElementDimension(player) ~= getElementDimension(vehicle)
        or getElementInterior(player) ~= getElementInterior(vehicle) then return end
    local distance,deck,right = CBoat.boardingReach(player,vehicle)
    if not distance then return end
    local x,y,z = getElementPosition(vehicle)
    if not isElementInWater(player) and getPedContactElement(player)~=vehicle and not deck then return end
    local unclaimed = triggerEvent("vcs_vehicle:onWatercraftBoardRequest", vehicle, player)
    if unclaimed then
        local driver = getVehicleOccupant(vehicle, 0)
        -- A mission NPC belongs to its spawning script. Population owners
        -- explicitly handle their occupied boats in the request event.
        if driver or not (isBoundVcsVehicle(vehicle) or CVehicle.isLegacyJetSki(vehicle)) then return end
        if not transferWatercraftSeat(player, vehicle, false) then return end
    end
    if getVehicleOccupant(vehicle, 0) == player and CVehicle.resolve(vehicle) == CJetSki then
        triggerClientEvent(getElementsWithinRange(x,y,z,200,"player",getElementInterior(vehicle),
            getElementDimension(vehicle)),"vcs_vehicle:jetSkiMounted",vehicle,player,right)
    end
end,false)
