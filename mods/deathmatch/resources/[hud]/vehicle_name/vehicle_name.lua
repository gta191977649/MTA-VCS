local defaultHudVisible
local activeVehicle
local reloadSnapshot = "leeds_engine:vehicleNameHud"

addEventHandler("onClientResourceStart", resourceRoot, function()
    local previous = getElementData(localPlayer, reloadSnapshot, false)
    defaultHudVisible = previous and previous.visible
    if previous then
        setElementData(localPlayer, reloadSnapshot, nil, false)
    else
        defaultHudVisible = isPlayerHudComponentVisible("vehicle_name")
    end
    setPlayerHudComponentVisible("vehicle_name", false)
end, false)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if defaultHudVisible == nil then return end
    if getElementData(root, "leeds_engine:reloading", false) then
        setElementData(localPlayer, reloadSnapshot, {visible = defaultHudVisible}, false)
    else
        setPlayerHudComponentVisible("vehicle_name", defaultHudVisible)
    end
end, false)

addEventHandler("onClientVehicleEnter", root, function(player)
    if player == localPlayer then
        activeVehicle = source
        exports.frontend:showGameText(getVehicleName(source), "VEHICLE_NAME", 3000)
    end
end)

local function clearVehicleName()
    if activeVehicle ~= source then return end
    activeVehicle = nil
    exports.frontend:hideGameText("VEHICLE_NAME")
end

addEventHandler("onClientVehicleExit", root, function(player)
    if player == localPlayer then clearVehicleName() end
end)
addEventHandler("onClientElementDestroy", root, clearVehicleName)
