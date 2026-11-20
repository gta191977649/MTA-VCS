-- The script generator Z is a ground/water reference, not a vehicle centre.
-- A small initial lift lets SA physics settle land vehicles onto the loaded map.
local SPAWN_LIFT = 1
local RESPAWN_DELAY = 60000
local IDLE_RESPAWN_DELAY = 300000
local parkedSpaces = setmetatable({}, {__mode = "k"})

local function restoreSpace(vehicle, space)
    setElementInterior(vehicle, space.interior)
    setElementDimension(vehicle, space.dimension)
end

-- Respawning must return a vehicle to the same room as its parking point.
addEventHandler("onVehicleRespawn", resourceRoot, function()
    local space = parkedSpaces[source]
    if space then restoreSpace(source, space) end
end)

local function spawnParked(row)
    local line, global, name, x, y, z, angle, generations = unpack(row)
    local id = exports.vcs_model:getVcsModelIdByName(name, "vehicle")
    if not id then return false, "unavailable model " .. name end
    local base = exports.vcs_model:getVcsModelBase(id, "vehicle")
    if not base then return false, "unavailable model " .. name end
    local vehicle = exports.vcs_vehicle:createVcsVehicle(id, x, y, z + SPAWN_LIFT, 0, 0, angle)
    if not vehicle then return false, "creation failed for " .. name end
    local space = {interior = row.interior or 0, dimension = row.dimension or 0}
    parkedSpaces[vehicle] = space
    -- vcs_vehicle retains ownership for cleanup; parent under this resource so
    -- its respawn events reach the placement handlers as well.
    setElementParent(vehicle, resourceRoot)
    restoreSpace(vehicle, space)
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
        if row[8] > 0 then
            local ok, reason = spawnParked(row)
            if ok then created = created + 1 else missing[reason] = (missing[reason] or 0) + 1 end
        end
    end
    outputDebugString("[car_park] Spawned " .. created .. " initially enabled script generators.")
    for reason, count in pairs(missing) do
        outputDebugString("[car_park] " .. reason .. " (" .. count .. " locations)", 2)
    end
end)
