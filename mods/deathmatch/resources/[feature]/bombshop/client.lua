local tutorialKey = "bombshop:helpSeen"
local pickup
local bombs = {}
local function showActivationPrompt()
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not vehicle or getVehicleOccupant(vehicle, 0) ~= localPlayer or bombs[vehicle] ~= "fitted" then return end
    local bindings = getBoundKeys("fire") or {}
    local keys = {}
    for key in pairs(bindings) do
        keys[#keys + 1] = key
    end
    table.sort(keys)
    if #keys == 0 then
        exports.frontend:showTextBox("Bind the Fire control in MTA Settings to activate the ignition bomb.", 8000)
        return
    end
    local key = bindings.mouse1 and "mouse1" or keys[1]
    local control = "#1EFFFF" .. key:upper() .. "#FFFFFF (Fire)"
    exports.frontend:showTextBox("Press " .. control .. " to activate the ignition bomb. It will explode when the next driver enters.", 8000)
end
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
        .. "will be fitted with a #1EFFFFignition bomb#FFFFFF.\nCost: #1EFFFF$500.", 8000)
end)

addEvent("bombshop:text", true)
addEventHandler("bombshop:text", resourceRoot, function(key)
    local text = garageText[key] and (exports.frontend:getVcsText(key) or garageText[key])
    if text then exports.frontend:showGameText(text, "garage", 4000) end
end, false)

addEvent("bombshop:state", true)
addEventHandler("bombshop:state", resourceRoot, function(vehicle, state, installed)
    bombs[vehicle] = state or nil
    if installed then dismissTutorial() end
    if state == "active" then
        exports.frontend:showTextBox("Bomb activated. Exit the vehicle. The next driver to enter will trigger the bomb - including you.", 8000)
    elseif state == "fitted" then
        showActivationPrompt()
    end
end, false)

addEventHandler("onClientPlayerVehicleEnter", localPlayer, showActivationPrompt)
addEventHandler("onClientElementDestroy", root, function() bombs[source] = nil end)

addEventHandler("onClientKey", root, function(key, pressed)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not pressed or not vehicle or bombs[vehicle] ~= "fitted" or isPedDead(localPlayer)
        or getVehicleOccupant(vehicle, 0) ~= localPlayer
        or isCursorShowing() or isChatBoxInputActive() or isConsoleActive() or isMainMenuActive() then return end
    local fireKeys = getBoundKeys("fire")
    if not fireKeys or not fireKeys[key] then return end
    cancelEvent()
    triggerServerEvent("bombshop:activate", resourceRoot)
end)
