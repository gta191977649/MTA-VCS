local price = 500
local detonator = 40
local owners, bombs = {}, {}

local function sendMessage(player, key)
    triggerClientEvent(player, "bombshop:text", resourceRoot, key)
end

local function removeBomb(vehicle)
    local player = bombs[vehicle]
    if not player then return end
    bombs[vehicle] = nil
    local inventory = owners[player]
    inventory.vehicles[vehicle] = nil
    if next(inventory.vehicles) then return end
    owners[player] = nil
    if isElement(player) then
        if inventory.issued and getPedWeapon(player, 8) ~= 39 and getPedWeapon(player, 12) == detonator then
            takeWeapon(player, detonator)
        end
        triggerClientEvent(player, "bombshop:armed", resourceRoot, false)
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

    local hasDetonator = getPedWeapon(player, 12) == detonator
    if not hasDetonator and not giveWeapon(player, detonator, 1, false) then
        givePlayerMoney(player, price)
        return false
    end
    local inventory = owners[player]
    if not inventory then
        inventory = {vehicles = {}, issued = not hasDetonator}
        owners[player] = inventory
    elseif not hasDetonator then
        inventory.issued = true
    end
    inventory.vehicles[vehicle] = true
    bombs[vehicle] = player
    sendMessage(player, "GA_23")
    triggerClientEvent(player, "bombshop:armed", resourceRoot, true, true)
    return true
end

addEvent("bombshop:detonate", true)
addEventHandler("bombshop:detonate", resourceRoot, function()
    if not client or not owners[client] or isPedDead(client) or isPedInVehicle(client)
        or getPedWeapon(client) ~= detonator then return end

    local worldInterior, worldDimension = getElementInterior(client), getElementDimension(client)
    local targets = {}
    for vehicle in pairs(owners[client].vehicles) do
        if isElement(vehicle) and not isVehicleBlown(vehicle)
            and getElementInterior(vehicle) == worldInterior and getElementDimension(vehicle) == worldDimension then
            targets[#targets + 1] = vehicle
        end
    end
    for _, vehicle in ipairs(targets) do
        removeBomb(vehicle)
        blowVehicle(vehicle)
    end
end, false)

addEventHandler("onVehicleExplode", root, function() removeBomb(source) end)
addEventHandler("onVehicleRespawn", root, function() removeBomb(source) end)
addEventHandler("onElementDestroy", root, function() removeBomb(source) end)
addEventHandler("onPlayerQuit", root, function() removeOwnersBombs(source) end)
addEventHandler("onPlayerWasted", root, function() removeOwnersBombs(source) end)

addEventHandler("onPlayerResourceStart", root, function(resource)
    if resource == getThisResource() and owners[source] then
        triggerClientEvent(source, "bombshop:armed", resourceRoot, true)
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
