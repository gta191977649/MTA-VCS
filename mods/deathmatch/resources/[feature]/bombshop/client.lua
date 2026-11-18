local tutorialKey = "bombshop:helpSeen"
local pickup, armed
local garageText = {
    GA_4 = "Car bombs are $500 each.",
    GA_5 = "That vehicle's already fitted with a bomb.",
    GA_22 = "You cannot fit a bomb to this type of vehicle.",
    GA_23 = "Car bomb fitted - parts and labor: $500",
}

local function dismissTutorial()
    setElementData(localPlayer, tutorialKey, true, false)
    if isElement(pickup) then destroyElement(pickup) end
    pickup = nil
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    if not getElementData(localPlayer, tutorialKey, false) then
        pickup = createPickup(-900.4, 1114.9, 11.1, 3, 1239)
    end
end)

addEventHandler("onClientPickupHit", root, function(player, matchingDimension)
    if source ~= pickup or player ~= localPlayer or not matchingDimension or getElementInterior(player) ~= 0 then return end
    dismissTutorial()
    exports.frontend:showTextBox("Any car you drive into this garage\n"
        .. "will be fitted with a #1EFFFFremote bomb#FFFFFF.\nCost: #1EFFFF$500.", 8000)
end)

addEvent("bombshop:text", true)
addEventHandler("bombshop:text", resourceRoot, function(key)
    local text = garageText[key] and (exports.frontend:getVcsText(key) or garageText[key])
    if text then exports.frontend:showGameText(text, "garage", 4000) end
end, false)

addEvent("bombshop:armed", true)
addEventHandler("bombshop:armed", resourceRoot, function(state, installed)
    armed = state
    if installed then
        dismissTutorial()
        exports.frontend:showTextBox(exports.frontend:getVcsText("GA_8") or
            "Use the detonator to activate the bomb.", 4000)
    end
end, false)

addEventHandler("onClientKey", root, function(key, pressed)
    if not pressed or not armed or getPedWeapon(localPlayer) ~= 40 or isPedInVehicle(localPlayer)
        or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    local fireKeys = getBoundKeys("fire")
    if not fireKeys or not fireKeys[key] then return end
    -- The game must not consume the SA satchel detonator before the server checks it.
    cancelEvent()
    triggerServerEvent("bombshop:detonate", resourceRoot)
end)
