local defaultHudVisible
local activeVehicle
local reloadSnapshot = "leeds_engine:vehicleNameHud"
-- VCS game-text keys for dispatched vehicles. Their SA parents can have different names.
local dispatchNames = {
    [191]="ELECTRP", [193]="FBICAR", [204]="VICECHE", [207]="POLICEM",
    [218]="BARRCKS", [219]="PREDATR", [234]="ENFORCR", [246]="RHINO", [261]="POLMAV",
}

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
        local original=getElementData(source,"npchlc_traffic:originalModel",false)
            or getElementData(source,"vcs_vehicle:originalModel",false)
        local key=dispatchNames[original]
        local name=key and exports.frontend:getVcsText(key)
        exports.frontend:showGameText(name or getVehicleName(source), "VEHICLE_NAME", 3000)
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
