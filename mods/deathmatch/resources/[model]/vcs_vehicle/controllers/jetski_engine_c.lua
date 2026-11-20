-- SLUS_215.90 0019C200 gives model 233 vehicle type 2. The audio dispatcher
-- at 001B5D68 sends it to 001BD438, which selects bank 0, sample 16.
local skis = {}
local playerFrequency = 5000
local engineSlot, bank, sample = 7, 0, 16
local boatEngine = 2 -- AE_SOUND_BOAT_ENGINE
-- VCS sample 16 is 0.53 dB louder (RMS) than the SA inboard reference.
local samples = {[sample]={Path="audio/jetski_engine.wav",Headroom=0.53}}

local function remove(vehicle)
    if skis[vehicle] then
        StopGenericEngineSound(vehicle,boatEngine)
        skis[vehicle] = nil
    end
end

local function track(vehicle)
    if getElementType(vehicle) ~= "vehicle" then return end
    if isElementStreamedIn(vehicle) and CVehicle.resolve(vehicle) == CJetSki then
        if not skis[vehicle] and BindVehicleSoundBank(vehicle,engineSlot,bank,samples) then
            skis[vehicle] = {lean=0,dryFrames=0}
        end
    else
        remove(vehicle)
    end
end

local function input(name)
    return isControlEnabled(name) and getAnalogControlState(name) or 0
end

local function playerPitch(vehicle, state, ms, frames)
    local vx, vy, vz = getElementVelocity(vehicle)
    local speed = math.min(1, math.sqrt(vx*vx + vy*vy + vz*vz))
    local targetLean = input("steer_forward") - input("steer_back")
    state.lean = state.lean + (targetLean - state.lean) * math.min(1, ms*0.01)
    local targetHz = (state.lean > 0.5 and 5500 or 5000) + math.floor(3000*speed)
    playerFrequency = math.max(playerFrequency - 100*frames, math.min(playerFrequency + 25*frames, targetHz))
    return playerFrequency
end

local function hasPassenger(vehicle)
    -- 003E9700 scans the passenger pointers at +388. Seat zero is +384.
    for seat, passenger in pairs(getVehicleOccupants(vehicle)) do
        if seat > 0 and isElement(passenger) then return true end
    end
    return false
end

local function pedal(driver, name)
    local value = getPedAnalogControlState(driver, name)
    if value and value > 0 then return value end
    return getPedControlState(driver, name) and 1 or 0
end

local function update(vehicle, state, submerged, dimension, interior, ms)
    local driver = getVehicleOccupant(vehicle, 0)
    if submerged or not driver or isPedDead(driver) or isVehicleBlown(vehicle) or not getVehicleEngineState(vehicle)
        or getElementDimension(vehicle) ~= dimension or getElementInterior(vehicle) ~= interior then
        state.lean, state.dryFrames, state.propSpeed = 0, 0, 0
        StopGenericEngineSound(vehicle,boatEngine)
        return
    end
    if driver ~= localPlayer and getElementAlpha(driver) == 0 and not hasPassenger(vehicle) then
        StopGenericEngineSound(vehicle,boatEngine)
        return
    end
    local frames = ms * 0.03
    state.dryFrames = isElementInWater(vehicle) and 0 or math.min(5, state.dryFrames + frames)
    local gas = pedal(driver, "accelerate")
    local brake = pedal(driver, "brake_reverse")
    local hz
    if driver == localPlayer then
        hz = playerPitch(vehicle, state, ms, frames)
    else
        state.lean = 0
        hz = 5000 + math.floor(3000 * math.max(gas, brake))
    end
    -- CBoat::ProcessControl propeller speed feeds ProcessBoatEngine (0x5003A0).
    local throttle = gas > 0 and gas or -brake
    local target = throttle > 0 and 0.18 + 0.16 * throttle
        or throttle < 0 and 0.18 + 0.13 * throttle or 0
    local response = throttle == 0 and 0.01 or 0.05
    state.propSpeed = target + ((state.propSpeed or 0) - target) * (1 - response)^(ms/20)
    local engineDb = -3 + 3 * math.min(1, 3 * state.propSpeed)
    -- WAV nominal rate is rebased from 2000 Hz to the sample's idle pitch.
    local speed = (hz + (state.dryFrames >= 5 and 1500 or 0)) / 5000
    UpdateBoatSound(vehicle,boatEngine,engineSlot,sample,speed,engineDb)
end

addEventHandler("onClientPreRender", root, function(elapsed)
    if not next(skis) then return end
    local cx, cy, cz = getCameraMatrix()
    local water = getWaterLevel(cx, cy, cz, true)
    local submerged = water and cz < water
    local dimension, interior = getElementDimension(localPlayer), getElementInterior(localPlayer)
    local ms = math.min(elapsed, 100) * getGameSpeed()
    for vehicle, state in pairs(skis) do
        update(vehicle, state, submerged, dimension, interior, ms)
    end
end)

-- onClientWorldSound reports the allocated dummy *slot* (7..16), not
-- the inboard bank ID (21). The underwater loop uses native slot 19.
addEventHandler("onClientWorldSound", root, function(group, index)
    if index == 0 and group >= 7 and group <= 16 and CVehicle.resolve(source)==CJetSki then
        cancelEvent()
    end
end)

addEventHandler("onClientVehicleExit", root, function(_, seat)
    local state = skis[source]
    if seat == 0 and state then
        state.lean, state.dryFrames, state.propSpeed = 0, 0, 0
        StopGenericEngineSound(source,boatEngine)
    end
end)
addEventHandler("onClientElementStreamIn", root, function() track(source) end)
addEventHandler("onClientElementStreamOut", root, function() remove(source) end)
addEventHandler("onClientElementDestroy", root, function() remove(source) end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key == CVehicle.modelKey or key == "mod.model" or key == "npchlc_traffic:originalModel" then track(source) end
end)
addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do track(vehicle) end
end, false)
addEventHandler("onClientResourceStop", resourceRoot, function()
    for vehicle in pairs(skis) do remove(vehicle) end
end, false)
