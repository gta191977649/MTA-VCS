local component = "wing_lr_dummy"
local angles = {}

local function track(vehicle)
    if getElementType(vehicle) ~= "vehicle" then return end
    if getElementModel(vehicle) == 424 then
        angles[vehicle] = angles[vehicle] or 0
    elseif angles[vehicle] then
        angles[vehicle] = nil
    end
end

local function forget()
    angles[source] = nil
end

addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementModelChange", root, function()
    if getElementType(source) == "vehicle" and isElementStreamedIn(source) then track(source) end
end)
addEventHandler("onClientElementStreamOut", root, forget)
addEventHandler("onClientElementDestroy", root, forget)
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do track(vehicle) end
end)

-- SLUS-21590, CAutomobile::PreRender, 0x14BE88..0x14C170.
-- The rear pulley occupies automobile node 17 and turns around its parent's Y axis.
addEventHandler("onClientPreRender", root, function(elapsed)
    local step = elapsed * getGameSpeed() / 20
    for vehicle, angle in pairs(angles) do
        -- Both model providers replace slot 424 globally, including untagged parked cars.
        -- Inspect the live pivot since the replacement can arrive after stream-in.
        local x, y, z = getVehicleComponentPosition(vehicle, component, "parent")
        if x and math.abs(x) < 0.001 and math.abs(y + 2.28127) < 0.001 and math.abs(z - 0.16380) < 0.001
                and getVehicleEngineState(vehicle) and not isVehicleBlown(vehicle) then
            local driver = getVehicleOccupant(vehicle)
            local powered = driver and (getPedControlState(driver, "accelerate")
                or (getPedAnalogControlState(driver, "accelerate") or 0) > 0
                or (getVehicleCurrentGear(vehicle) == 0 and getPedControlState(driver, "brake_reverse")))
            angle = (angle + math.deg(powered and 0.2 or 0.1) * step) % 360
            angles[vehicle] = angle
            setVehicleComponentRotation(vehicle, component, 0, angle, 0, "parent")
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for vehicle, angle in pairs(angles) do
        if angle ~= 0 then resetVehicleComponentRotation(vehicle, component) end
    end
end)
