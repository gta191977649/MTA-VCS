local price = 100
local repairThreshold = 970
local paroleTime = 20000
local paroleKey = "nspray:paroleStars"
local parole = {}

local roadTypes = {Automobile = true, Bike = true, BMX = true, Quad = true}
local refusedModels = {
    [407] = true, [416] = true, [427] = true, [432] = true, [433] = true,
    [437] = true, [470] = true, [490] = true, [523] = true, [528] = true,
    [544] = true, [596] = true, [597] = true, [598] = true, [599] = true, [601] = true,
}
local paintColors = {
    {137, 25, 39}, {217, 103, 24}, {224, 191, 92}, {39, 88, 68},
    {19, 94, 129}, {42, 45, 117}, {103, 57, 117}, {143, 149, 158},
    {215, 209, 189}, {49, 48, 57},
}

local function garageMessage(player, key, dismissHelp)
    triggerClientEvent(player, "nspray:garageMessage", resourceRoot, key, dismissHelp == true)
end

local function canSpray(vehicle)
    return roadTypes[getVehicleType(vehicle)] and not refusedModels[getElementModel(vehicle)]
end

local function getPrice(vehicle, wanted)
    return (wanted > 0 or getElementHealth(vehicle) < repairThreshold) and price or 0
end

local function clearParole(player)
    parole[player] = nil
    removeElementData(player, paroleKey)
end

local function startParole(player, wanted, now)
    if wanted == 0 then return end
    local traffic = getResourceFromName("npchlc_traffic")
    if traffic and getResourceState(traffic) == "running" and call(traffic, "suspendPlayerWanted", player) then
        parole[player] = nil
        return
    end
    if not setPlayerWantedLevel(player, 0) then return end
    parole[player] = {stars = wanted, expires = now + paroleTime}
    setElementData(player, paroleKey, wanted, "broadcast", "deny")
end

local function updateParole(now)
    for player, state in pairs(parole) do
        if not isElement(player) then
            parole[player] = nil
        elseif now >= state.expires or isPedDead(player) then
            clearParole(player)
        else
            local wanted = getPlayerWantedLevel(player)
            if wanted > 0 then
                clearParole(player)
                if wanted < state.stars then
                    setPlayerWantedLevel(player, state.stars)
                end
            end
        end
    end
end

local function settle(id, player, vehicle)
    local wanted = getPlayerWantedLevel(player)
    local cost = getPrice(vehicle, wanted)
    if cost > 0 and (getPlayerMoney(player) < cost or not takePlayerMoney(player, cost)) then
        garageMessage(player, "GA_3")
        return
    end
    if not fixVehicle(vehicle) then
        if cost > 0 then givePlayerMoney(player, cost) end
        return
    end

    local colors = {getVehicleColor(vehicle, true)}
    local paint
    repeat
        paint = paintColors[math.random(#paintColors)]
    until paint[1] ~= colors[1] or paint[2] ~= colors[2] or paint[3] ~= colors[3]
    colors[1], colors[2], colors[3] = unpack(paint)
    setVehicleColor(vehicle, unpack(colors))
    local garage = exports.garage:getGarage(id)
    triggerClientEvent(root, "nspray:sprayEffect", resourceRoot, player,
        garage.bay, garage.floor, garage.interior, garage.dimension, paint)
    startParole(player, wanted, getTickCount())
    local key
    if cost > 0 then
        key = getVehicleType(vehicle) == "BMX" and "GA_2B" or "GA_2"
    else
        key = math.random(2) == 1 and "GA_15" or "GA_16"
    end
    garageMessage(player, key, SPRAY_SHOPS[id].helpPickup ~= nil)
    return true
end

function sprayGarageService(stage, id, player, vehicle)
    if sourceResource ~= getResourceFromName("garage") or not SPRAY_SHOPS[id] then return false end
    if not canSpray(vehicle) then
        garageMessage(player, "GA_1")
        return false
    end
    if stage == "commit" then return settle(id, player, vehicle) end
    if stage ~= "quote" then return false end
    local cost = getPrice(vehicle, getPlayerWantedLevel(player))
    if cost > 0 and getPlayerMoney(player) < cost then
        garageMessage(player, "GA_3")
        return false
    end
    return true
end

local function register()
    if not exports.garage:registerGarageType(5, "sprayGarageService") then
        outputDebugString("nspray: failed to register garage type 5", 1)
    end
end

addEventHandler("onResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == "garage" then register() end
end)

addEventHandler("onResourceStart", resourceRoot, function()
    for _, config in pairs(SPRAY_SHOPS) do
        local x, y, z = unpack(config.blip)
        local blip = createBlip(x, y, z, 63, 2, 255, 255, 255, 255, 0, 350)
        if blip then setElementData(blip, "mradar:shortRange", true, "broadcast", "deny") end
    end
    setTimer(function() updateParole(getTickCount()) end, 100, 0)
end)

addEventHandler("onPlayerQuit", root, function() parole[source] = nil end)
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(parole) do clearParole(player) end
end)

