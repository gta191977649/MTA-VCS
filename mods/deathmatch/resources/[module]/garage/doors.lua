local doors, byModel = {}, {}
for _, config in ipairs(VCS_GARAGES) do
    if config.door then
        local entry = {config = config}
        doors[config.id] = entry
        byModel[config.door] = entry
    end
end

local function enabled(entry)
    return getElementData(resourceRoot, garageTypeKey(entry.config.kind), false) == true
end

local function stopMotor(entry)
    if isElement(entry.motor) then destroyElement(entry.motor) end
    entry.motor = nil
end

local function stopSounds(entry)
    stopMotor(entry)
    if isElement(entry.endpoint) then destroyElement(entry.endpoint) end
    entry.endpoint = nil
end

-- SLUS-21590 0x1C6070: SFX0 sample 162 at 13961 Hz during motion.
-- Events 0x4A (closed) and 0x4B (opened) play sample 104 at 18000 and 22000 Hz.
local soundRange = 80
-- The WAV contains the original intro followed by 42 repeats of its ADPCM loop.
local motorPath = "audio/shutter_move.wav"
local openedPath, closedPath = "audio/shutter_opened.wav", "audio/shutter_closed.wav"

local function canHearDoor(entry, x, y, z)
    if not enabled(entry) or not garageInWorld(entry.config, localPlayer) then return false end
    local cx, cy, cz = getCameraMatrix()
    return getDistanceBetweenPoints3D(cx, cy, cz, x, y, z) < soundRange
end

local function playDoorSound(entry, path, x, y, z, volume)
    local config = entry.config
    local sound = playSound3D(path, x, y, z, false)
    if not sound then return end
    setElementDimension(sound, config.dimension)
    setElementInterior(sound, config.interior)
    setSoundMaxDistance(sound, soundRange)
    setSoundVolume(sound, volume)
    return sound
end

local function doorCoordinates(config, opening)
    local x, y, z = unpack(config.doorPosition)
    return x, y, z + opening * config.lift
end

local function positionDoor(entry, opening)
    if isElement(entry.object) then setElementPosition(entry.object, doorCoordinates(entry.config, opening)) end
end

local function updateDoor(entry, now)
    local movement = entry.movement
    if not movement then return end
    local progress = math.min((now - movement.start) / movement.duration, 1)
    local opening = movement.from + (movement.to - movement.from) * progress
    local x, y, z = doorCoordinates(entry.config, opening)
    positionDoor(entry, opening)
    local audible = canHearDoor(entry, x, y, z)
    if progress >= 1 then
        entry.movement = nil
        stopMotor(entry)
        if audible then
            if isElement(entry.endpoint) then destroyElement(entry.endpoint) end
            local path = movement.to == 1 and openedPath or closedPath
            entry.endpoint = playDoorSound(entry, path, x, y, z, 60 / 127)
        end
    elseif not audible then
        stopMotor(entry)
    elseif isElement(entry.motor) then
        setElementPosition(entry.motor, x, y, z)
    else
        entry.motor = playDoorSound(entry, motorPath, x, y, z, 1)
        if entry.motor and now > movement.motorStart then
            setSoundPosition(entry.motor, (now - movement.motorStart) / 1000)
        end
    end
end

local function attachDoor(object)
    if not isElement(object) or getElementType(object) ~= "object" then return end
    local entry = byModel[getElementID(object)]
    if not entry then return end
    entry.object = object
    if entry.movement then
        updateDoor(entry, getTickCount())
    else
        positionDoor(entry, entry.target or 1)
    end
end

addEvent("garage:door", true)
addEventHandler("garage:door", resourceRoot, function(id, from, target, duration, motorElapsed)
    local entry = doors[id]
    if not entry then return end
    local now = getTickCount()
    entry.target = target
    if duration > 0 then
        local motorStart = now - motorElapsed
        if motorElapsed == 0 and entry.movement then
            -- A fresh motor run means the server reached the previous endpoint.
            updateDoor(entry, math.max(now, entry.movement.start + entry.movement.duration))
        elseif entry.movement then
            motorStart = entry.movement.motorStart
        end
        entry.movement = {from = from, to = target, start = now, duration = duration, motorStart = motorStart}
    else
        stopSounds(entry)
        entry.movement = nil
    end
    if not isElement(entry.object) then attachDoor(getElementByID(entry.config.door)) end
    if entry.movement then updateDoor(entry, getTickCount()) else positionDoor(entry, target) end
end, false)

addEventHandler("onClientElementStreamIn", root, function() attachDoor(source) end)
addEventHandler("onClientResourceStart", resourceRoot, function()
    local function findDoors()
        for _, entry in pairs(doors) do
            if not isElement(entry.object) then attachDoor(getElementByID(entry.config.door)) end
        end
    end
    findDoors()
    setTimer(findDoors, 1000, 0)
end)

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    for _, entry in pairs(doors) do
        if entry.movement then updateDoor(entry, now) end
    end
end)

addEventHandler("onClientResourceStop", root, function(stopped)
    if stopped ~= getThisResource() and getResourceName(stopped) ~= "vcs" then return end
    for _, entry in pairs(doors) do
        entry.movement, entry.target = nil, 1
        stopSounds(entry)
        positionDoor(entry, 1)
    end
end)
