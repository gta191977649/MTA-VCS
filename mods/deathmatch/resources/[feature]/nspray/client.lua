local helpKey = "nspray:helpSeen"
local helpPickups = {}
local garageText = {
    GA_1 = "No way, man! I don't touch those!",
    GA_2 = "New engine and paint job: $100",
    GA_2B = "New paint job: $100",
    GA_3 = "$100 to respray.",
    GA_15 = "Hope you like the new color.",
    GA_16 = "Respray is complimentary.",
}

local function dismissHelp()
    setElementData(localPlayer, helpKey, true, false)
    for pickup in pairs(helpPickups) do
        if isElement(pickup) then destroyElement(pickup) end
        helpPickups[pickup] = nil
    end
end

local function createHelpPickups()
    if getElementData(localPlayer, helpKey, false) then return end
    for _, shop in pairs(SPRAY_SHOPS) do
        if shop.helpPickup then
            local x, y, z = unpack(shop.helpPickup)
            local pickup = createPickup(x, y, z, 3, 1239)
            if pickup then helpPickups[pickup] = true end
        end
    end
end

addEventHandler("onClientResourceStart", resourceRoot, createHelpPickups)

-- MAIN.SCM PUHELP: collect either INFO pickup once for H_PNS01.
addEventHandler("onClientPickupHit", root, function(player, matchingDimension)
    if player ~= localPlayer or not matchingDimension or not helpPickups[source]
        or getElementInterior(player) ~= 0 then return end
    dismissHelp()
    exports.frontend:showTextBox(
        exports.frontend:getVcsText("H_PNS01") or
            "Park in a Pay 'n' Spray to clear your wanted level and repair and respray your vehicle. Cost: $100.",
        8000)
end)

addEvent("nspray:garageMessage", true)
addEventHandler("nspray:garageMessage", resourceRoot, function(key, shouldDismissHelp)
    if shouldDismissHelp then dismissHelp() end
    local message = garageText[key] and (exports.frontend:getVcsText(key) or garageText[key])
    if message then exports.frontend:showGameText(message, "garage", 4000) end
end, false)
