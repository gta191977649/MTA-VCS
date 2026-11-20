-- Common handling fields of JETSKI; the subtype-specific resistance lives in
-- CJetSki:ApplyWaterResistance. Save the individual donor's values on attach.
local profile = {
    mass=978.94458, turnMass=CJetSki.turnMass, dragCoeff=0.1, percentSubmerged=17,
    tractionMultiplier=1, tractionLoss=0.1, tractionBias=0.15,
    -- MTA sends the value straight to ConvertDataToGameUnits, bypassing
    -- handling.cfg's parser (which multiplies acceleration by 0.4 first).
    -- GAME.DTZ 4C13A0+48 = 0.000256: 1.28 / 2500 / 2 for rear drive.
    numberOfGears=1, maxVelocity=194.2, engineAcceleration=1.28, engineInertia=17,
    brakeDeceleration=10, brakeBias=0.02, steeringLock=40, centerOfMass={0,0,0},
    suspensionForceLevel=0.2, suspensionDamping=3, suspensionUpperLimit=0.1,
    suspensionLowerLimit=0.1, suspensionFrontRearBias=0,
}
local originals = setmetatable({}, {__mode="k"})

local function setPropulsion(vehicle, driver)
    -- SA applies thrust at the inflatable's lower, forward-shifted propeller.
    -- The player's CJetSki simulates the original jet at its own mount.
    local playerDriven = driver and getElementType(driver) == "player"
    setVehicleHandling(vehicle, "engineAcceleration", playerDriven and 0 or profile.engineAcceleration)
end

local function restore(vehicle)
    local previous = originals[vehicle]
    if not previous then return end
    for field, value in pairs(previous) do setVehicleHandling(vehicle, field, value) end
    originals[vehicle] = nil
end

local function refresh(vehicle)
    if getElementType(vehicle) ~= "vehicle" then return end
    if CVehicle.resolve(vehicle) ~= CJetSki or getVehicleType(vehicle) ~= "Boat" then
        restore(vehicle)
        return
    end
    if originals[vehicle] then return end
    local handling = getVehicleHandling(vehicle)
    if not handling then return end
    local previous = {}
    for field, value in pairs(profile) do
        if setVehicleHandling(vehicle, field, value) then previous[field] = handling[field] end
    end
    originals[vehicle] = previous
    setPropulsion(vehicle, getVehicleOccupant(vehicle, 0))
end

addEventHandler("onElementDataChange",root,function(key)
    if key == CVehicle.modelKey or key == "npchlc_traffic:originalModel" or key == "mod.model" then refresh(source) end
end)
addEventHandler("onVehicleEnter",root,function(driver, seat)
    if seat == 0 and originals[source] then setPropulsion(source, driver) end
end)
addEventHandler("onVehicleExit",root,function(_, seat)
    if seat == 0 and originals[source] then setPropulsion(source, nil) end
end)
addEventHandler("onResourceStart",resourceRoot,function()
    for _, vehicle in ipairs(getElementsByType("vehicle")) do refresh(vehicle) end
end,false)
addEventHandler("onResourceStop",resourceRoot,function()
    for vehicle in pairs(originals) do if isElement(vehicle) then restore(vehicle) end end
end,false)
