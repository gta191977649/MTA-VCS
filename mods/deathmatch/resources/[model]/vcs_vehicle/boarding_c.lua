local nativeStarted, pending
addEventHandler("onClientVehicleStartEnter",root,function(ped)
    if ped == localPlayer then nativeStarted = getTickCount() end
end)

local function canBoard()
    return not getPedOccupiedVehicle(localPlayer) and not isPedDead(localPlayer)
        and isControlEnabled("enter_exit")
end

local function boardNearby()
    if pending or not canBoard() then return end
    local px,py,pz = getElementPosition(localPlayer)
    local nearest, best
    for _,vehicle in ipairs(getElementsWithinRange(px,py,pz,10,"vehicle",getElementInterior(localPlayer),
        getElementDimension(localPlayer))) do
        local distance = CBoat.boardingReach(localPlayer,vehicle)
        if distance and (not best or distance<best) and getVehicleType(vehicle)=="Boat"
            and not isVehicleLocked(vehicle) and not isVehicleBlown(vehicle) then
            local driver = getVehicleOccupant(vehicle,0)
            if not driver or getElementType(driver) ~= "player" then nearest,best=vehicle,distance end
        end
    end
    if not nearest then return end
    local function fallback()
        if isElement(nearest) and canBoard() and CBoat.boardingReach(localPlayer,nearest) then
            triggerServerEvent("vcs_vehicle:boardWatercraft",resourceRoot,nearest)
        end
    end
    if isElementInWater(localPlayer) and getPedContactElement(localPlayer) ~= nearest then fallback() return end
    -- Give GTA's enter key the first frame on deck. Explicitly ask for the
    -- ordinary boarding task when invoked from /boardboat instead of a key.
    pending=true
    setTimer(function()
        pending=false
        if not canBoard() or not isElement(nearest) or not CBoat.boardingReach(localPlayer,nearest)
            or nativeStarted and (getTickCount()-nativeStarted)%4294967296<350 then return end
        local previous=nativeStarted
        if setPedEnterVehicle(localPlayer,nearest,false) then
            -- Some tasks are accepted but never begin (unreachable deck).
            -- Respect any actual native entry, including a player's cancellation.
            pending=true
            setTimer(function()
                pending=false
                if nativeStarted==previous then fallback() end
            end,900,1)
        else
            fallback()
        end
    end,100,1)
end
addCommandHandler("boardboat",boardNearby)
addCommandHandler("boardjetski",boardNearby)
bindKey("enter_exit","down",function()
    if not isChatBoxInputActive() and not isConsoleActive() and not isMTAWindowActive() then boardNearby() end
end)
