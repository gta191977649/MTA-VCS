local price = 500
local owners, bombs = {}, {}

local function sendMessage(player, key)
    triggerClientEvent(player, "bombshop:text", resourceRoot, key)
end

local function removeBomb(vehicle)
    local bomb = bombs[vehicle]
    if not bomb then return end
    bombs[vehicle] = nil
    if isTimer(bomb.timer) then killTimer(bomb.timer) end
    local player = bomb.owner
    local inventory = owners[player]
    inventory.vehicles[vehicle] = nil
    if not next(inventory.vehicles) then owners[player] = nil end
    if isElement(player) then
        triggerClientEvent(player, "bombshop:state", resourceRoot, vehicle, false)
    end
end

local function removeOwnersBombs(player)
    local inventory = owners[player]
    if not inventory then return end
    for vehicle in pairs(inventory.vehicles) do removeBomb(vehicle) end
end

function bombGarageService(stage, id, player, vehicle)
    if sourceResource ~= getResourceFromName("garage") or id ~= 920 then return false end
    if getVehicleType(vehicle) ~= "Automobile" then
        sendMessage(player, "GA_22")
        return false
    end
    if bombs[vehicle] then
        sendMessage(player, "GA_5")
        return false
    end
    if getPlayerMoney(player) < price then
        sendMessage(player, "GA_4")
        return false
    end
    if stage == "quote" then return true end
    if stage ~= "commit" then return false end
    if not takePlayerMoney(player, price) then
        sendMessage(player, "GA_4")
        return false
    end

    local inventory = owners[player]
    if not inventory then
        inventory = {vehicles = {}}
        owners[player] = inventory
    end
    inventory.vehicles[vehicle] = true
    bombs[vehicle] = {owner = player, active = false}
    sendMessage(player, "GA_23")
    triggerClientEvent(player, "bombshop:state", resourceRoot, vehicle, "fitted", true)
    return true
end

addEvent("bombshop:activate", true)
addEventHandler("bombshop:activate", resourceRoot, function()
    if not client or isPedDead(client) then return end
    local vehicle = getPedOccupiedVehicle(client)
    local bomb = bombs[vehicle]
    if not bomb or bomb.owner ~= client or bomb.active or getVehicleOccupant(vehicle, 0) ~= client
        or isVehicleBlown(vehicle) then return end
    bomb.active = true
    triggerClientEvent(client, "bombshop:state", resourceRoot, vehicle, "active")
end, false)

-- SLUS-21590 0x0013A7C8: an armed ignition bomb starts a 1000 ms fuse
-- when a driver next occupies the car. The driver who armed it is not exempt.
addEventHandler("onVehicleEnter", root, function(ped, seat)
    local vehicle = source
    local bomb = bombs[vehicle]
    if not bomb then return end
    if seat == 0 and bomb.active and not bomb.timer then
        bomb.timer = setTimer(function()
            if bombs[vehicle] ~= bomb or not isElement(vehicle) then return end
            local owner = bomb.owner
            removeBomb(vehicle)
            if blowVehicle(vehicle) and isElement(owner) then
                exports.wanted:reportWantedEvent(owner, 13, vehicle)
            end
        end, 1000, 1)
    elseif ped == bomb.owner and seat == 0 then
        triggerClientEvent(ped, "bombshop:state", resourceRoot, vehicle, bomb.active and "active" or "fitted")
    end
end)

addEventHandler("onVehicleExplode", root, function() removeBomb(source) end)
addEventHandler("onVehicleRespawn", root, function() removeBomb(source) end)
addEventHandler("onElementDestroy", root, function() removeBomb(source) end)
addEventHandler("onPlayerQuit", root, function() removeOwnersBombs(source) end)
addEventHandler("onPlayerWasted", root, function() removeOwnersBombs(source) end)

addEventHandler("onPlayerResourceStart", root, function(resource)
    if resource == getThisResource() and owners[source] then
        for vehicle in pairs(owners[source].vehicles) do
            triggerClientEvent(source, "bombshop:state", resourceRoot, vehicle, bombs[vehicle].active and "active" or "fitted")
        end
    end
end)

addEventHandler("onResourceStart", root, function(resource)
    if resource ~= getThisResource() and getResourceName(resource) ~= "garage" then return end
    if not exports.garage:registerGarageType(4, "bombGarageService") then
        outputDebugString("bombshop: failed to register garage type 4", 1)
    end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    -- SLUS-21590 MAIN.SCM sprite 10 coordinates.
    local blip = createBlip(-900.4, 1114.9, 11.1, 27, 2, 255, 255, 255, 255, 0, 350)
    if blip then
        setElementData(blip, "mradar:vcsIcon", "radar_bomb", "broadcast", "deny")
        setElementData(blip, "mradar:shortRange", true, "broadcast", "deny")
    end
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(owners) do removeOwnersBombs(player) end
end)
