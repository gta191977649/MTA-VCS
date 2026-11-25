-- The script generator Z is a ground/water reference, not a vehicle centre.
-- Hold new hulls until a nearby client has loaded the model and map collision.
local SPAWN_LIFT = 4
local RESPAWN_DELAY = 60000
local IDLE_RESPAWN_DELAY = 300000
local parkedSpaces = setmetatable({}, {__mode = "k"})
local pending = {}
local resting = setmetatable({}, {__mode = "k"})
local generation = 0
local function occupied(vehicle)
    for _, ped in pairs(getVehicleOccupants(vehicle)) do
        if isElement(ped) then return true end
    end
    return false
end

local function Setup(vehicle, space)
    generation = generation + 1
    pending[vehicle] = {space = space, generation = generation}
    resting[vehicle] = nil
    setElementFrozen(vehicle, true)
    setElementAlpha(vehicle, 0)
    setElementData(vehicle, "placement:parking", {space.x, space.y, space.z, generation}, "broadcast", "deny")
end

addEvent("placement:placeOnRoad", true)
addEventHandler("placement:placeOnRoad", resourceRoot, function(vehicle, serial, ground, clearance)
    local entry = pending[vehicle]
    if not client or not entry or serial ~= entry.generation or not isElement(vehicle) then return end
    local space = entry.space
    if type(ground) ~= "number" or ground ~= ground or math.abs(ground-space.z) > 8
        or type(clearance) ~= "number" or clearance ~= clearance or clearance < 0.05 or clearance > 8
        or getElementInterior(client) ~= space.interior or getElementDimension(client) ~= space.dimension
        or occupied(vehicle) then return end
    local px, py, pz = getElementPosition(client)
    if getDistanceBetweenPoints3D(px, py, pz, space.x, space.y, space.z) > 120 then return end
    local z = ground + clearance + 0.02
    pending[vehicle] = nil
    setElementPosition(vehicle, space.x, space.y, z)
    setElementRotation(vehicle, 0, 0, space.angle)
    setElementVelocity(vehicle, 0, 0, 0)
    setElementAngularVelocity(vehicle, 0, 0, 0)
    setVehicleRespawnPosition(vehicle, space.x, space.y, z, 0, 0, space.angle)
    setElementData(vehicle, "placement:parking", false, "broadcast", "deny")
    setElementAlpha(vehicle, 255)
    -- Keep unused parked hulls at the measured contact height. In particular,
    -- a helicopter's native suspension can otherwise lift converted skids.
    local boat = getVehicleType(vehicle) == "Boat"
    resting[vehicle] = not boat or nil
    setElementFrozen(vehicle, not boat)
end)

local function releaseVehicle()
    if resting[source] then
        resting[source] = nil
        setElementFrozen(source, false)
    end
end
addEventHandler("onVehicleStartEnter", root, releaseVehicle)
addEventHandler("onVehicleEnter", root, releaseVehicle)
addEventHandler("onVehicleDamage", root, releaseVehicle)
-- Warp/seat-transfer APIs can bypass the normal entry events.
setTimer(function()
    for vehicle in pairs(resting) do
        if isElement(vehicle) and occupied(vehicle) then
            resting[vehicle] = nil
            setElementFrozen(vehicle, false)
        end
    end
end, 500, 0)

addEventHandler("onElementDestroy", root, function() pending[source] = nil end)

local function restoreSpace(vehicle, space)
    setElementInterior(vehicle, space.interior)
    setElementDimension(vehicle, space.dimension)
end

-- Respawning must return a vehicle to the same room as its parking point.
addEventHandler("onVehicleRespawn", root, function()
    local space = parkedSpaces[source]
    if space then
        restoreSpace(source, space)
        setElementPosition(source, space.x, space.y, space.z + SPAWN_LIFT)
        Setup(source, space)
    end
end)

local function spawnParked(row)
    local line, global, name, x, y, z, angle, generations = unpack(row)
    local id = exports.vcs_model:getVcsModelIdByName(name, "vehicle")
    if not id then return false, "unavailable model " .. name end
    local base = exports.vcs_model:getVcsModelBase(id, "vehicle")
    if not base then return false, "unavailable model " .. name end
    local vehicle = exports.vcs_vehicle:createVcsVehicle(id, x, y, z + SPAWN_LIFT, 0, 0, angle, row[9], row[10])
    if not vehicle then return false, "creation failed for " .. name end
    local space = {interior = row.interior or 0, dimension = row.dimension or 0,
        x = x, y = y, z = z, angle = angle}
    parkedSpaces[vehicle] = space
    -- vcs_vehicle retains ownership for cleanup; parent under this resource so
    -- its respawn events reach the placement handlers as well.
    setElementParent(vehicle, resourceRoot)
    restoreSpace(vehicle, space)
    Setup(vehicle, space)
    setVehicleEngineState(vehicle, false)
    setVehicleRespawnPosition(vehicle, x, y, z + SPAWN_LIFT, 0, 0, angle)
    setVehicleRespawnDelay(vehicle, RESPAWN_DELAY)
    setVehicleIdleRespawnDelay(vehicle, IDLE_RESPAWN_DELAY)
    toggleVehicleRespawn(vehicle, true)
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    local missing, created = {}, 0
    for _, row in ipairs(CAR_PARK_SPAWNS) do
        -- SAFEHOU_4601 enables generator $995 for the Prawn Island studio.
        -- The standalone world exposes its Crash! activity without a story save.
        if row[8] > 0 or row[2] == 995 then
            local ok, reason = spawnParked(row)
            if ok then created = created + 1 else missing[reason] = (missing[reason] or 0) + 1 end
        end
    end
    outputDebugString("[car_park] Spawned " .. created .. " script generators.")
    for reason, count in pairs(missing) do
        outputDebugString("[car_park] " .. reason .. " (" .. count .. " locations)", 2)
    end
end)
