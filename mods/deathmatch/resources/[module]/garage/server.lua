local providers, bays, catalog = {}, {}, {}
local doorViewers = {}
local parkingSpeedSquared = 0.015 ^ 2
local serviceTime = 2000
for _, definition in ipairs(VCS_GARAGES) do catalog[definition.id] = definition end

local longVehicles = {
    [403] = true, [408] = true, [414] = true, [431] = true, [433] = true,
    [443] = true, [455] = true, [456] = true, [486] = true, [498] = true,
    [499] = true, [514] = true, [515] = true, [524] = true, [573] = true,
    [578] = true, [588] = true,
}

local function makeBay(config)
    local ax, ay, bx, by, cx, cy = unpack(config.bay)
    local ux, uy, vx, vy = bx - ax, by - ay, cx - ax, cy - ay
    local dx, dy, dz = unpack(config.doorPosition)
    local bay = {config = config, attempted = {}, nearby = createColSphere(dx, dy, dz, 22),
        doorFrom = 1, doorTo = 1, doorStart = 0, doorDuration = 0}

    -- Locate the entrance edge by the placement of the original door.
    local edges = {
        {ax, ay, ux, uy}, {cx, cy, ux, uy}, {ax, ay, vx, vy}, {bx, by, vx, vy},
    }
    local bestDistance = math.huge
    for _, edge in ipairs(edges) do
        local x, y, ex, ey = unpack(edge)
        local length = math.sqrt(ex * ex + ey * ey)
        local tx, ty = ex / length, ey / length
        local along = (dx - x) * tx + (dy - y) * ty
        local nearest = math.max(0, math.min(length, along))
        local offsetX, offsetY = dx - (x + nearest * tx), dy - (y + nearest * ty)
        local distance = offsetX * offsetX + offsetY * offsetY
        if distance < bestDistance then
            bestDistance = distance
            bay.entrance = {x = x, y = y, tx = tx, ty = ty, length = length}
        end
    end
    return bay
end

local function inBayHeight(bay, z)
    return z >= bay.config.floor and z <= bay.config.ceiling
end

local function footprint(vehicle)
    -- Server-side bounds for checking clearance around the closed door.
    local model, kind = getElementModel(vehicle), getVehicleType(vehicle)
    local width, length = 1.15, 2.75
    if longVehicles[model] or kind == "Trailer" then
        width, length = 1.45, 4.75
    elseif kind == "Bike" or kind == "BMX" or kind == "Quad" then
        width, length = 0.65, 1.3
    end
    local _, _, rotation = getElementRotation(vehicle)
    local heading = math.rad(rotation)
    local sin, cos = math.sin(heading), math.cos(heading)
    return width * cos, width * sin, -length * sin, length * cos
end

local function vehicleFits(bay, vehicle, x, y)
    local rx, ry, fx, fy = footprint(vehicle)
    return garageContainsXY(bay.config, x + rx + fx, y + ry + fy)
        and garageContainsXY(bay.config, x - rx + fx, y - ry + fy)
        and garageContainsXY(bay.config, x + rx - fx, y + ry - fy)
        and garageContainsXY(bay.config, x - rx - fx, y - ry - fy)
end

local function blocksDoor(bay, element, vehicle)
    if not garageInWorld(bay.config, element) then return false end
    local x, y, z = getElementPosition(element)
    if z < bay.config.floor - 0.8 or z > bay.config.ceiling then return false end

    local edge = bay.entrance
    local dx, dy = x - edge.x, y - edge.y
    local along = dx * edge.tx + dy * edge.ty
    local across = math.abs(dx * edge.ty - dy * edge.tx)
    local side, depth = 0.4, 0.55
    if vehicle then
        local rx, ry, fx, fy = footprint(element)
        side = side + math.abs(rx * edge.tx + ry * edge.ty) + math.abs(fx * edge.tx + fy * edge.ty)
        depth = depth + math.abs(rx * edge.ty - ry * edge.tx) + math.abs(fx * edge.ty - fy * edge.tx)
    end
    return along >= -side and along <= edge.length + side and across <= depth
end

local function entranceBlocked(bay, serviceVehicle, vehicles)
    for _, vehicle in ipairs(vehicles) do
        if vehicle ~= serviceVehicle and blocksDoor(bay, vehicle, true) then return true end
    end
    for _, kind in ipairs({"player", "ped"}) do
        for _, ped in ipairs(getElementsWithinColShape(bay.nearby, kind)) do
            if not isPedInVehicle(ped) and not isPedDead(ped) and blocksDoor(bay, ped, false) then
                return true
            end
        end
    end
    return false
end

local function parkedInside(bay, vehicle, x, y, z)
    return inBayHeight(bay, z) and vehicleFits(bay, vehicle, x, y) and not blocksDoor(bay, vehicle, true)
end

local function validDriver(bay, player, vehicle)
    return isElement(player) and getElementType(player) == "player" and isElement(vehicle)
        and garageInWorld(bay.config, player) and garageInWorld(bay.config, vehicle)
        and getVehicleOccupant(vehicle, 0) == player and not isPedDead(player) and not isVehicleBlown(vehicle)
end

local function doorPosition(bay, now)
    if bay.doorDuration == 0 then return bay.doorTo end
    local progress = math.min(1, (now - bay.doorStart) / bay.doorDuration)
    return bay.doorFrom + (bay.doorTo - bay.doorFrom) * progress
end

local function broadcastDoor(...)
    for player in pairs(doorViewers) do
        triggerClientEvent(player, "garage:door", resourceRoot, ...)
    end
end

-- SLUS-21590 0x41ECD8/0x41FB14 and 0x41FDD8/0x4203A0. The original
-- timestep is in 1/50 s units, so straight doors close at 2 m/s and open at 1.75 m/s.
local function moveDoor(bay, destination, now)
    local from = doorPosition(bay, now)
    local speed = destination == 1 and 1.75 or 2.0
    local duration = math.ceil(math.abs(destination - from) * bay.config.lift * 1000 / speed)
    if now >= bay.doorStart + bay.doorDuration then bay.motorStart = now end
    bay.doorFrom, bay.doorTo, bay.doorStart, bay.doorDuration = from, destination, now, duration
    broadcastDoor(bay.config.id, from, destination, duration, now - bay.motorStart)
    return duration
end

local function release(bay)
    local session = bay.session
    if not session then return end
    bay.session = nil
    if isElement(session.vehicle) then setElementFrozen(session.vehicle, false) end
end

local function reset(bay)
    release(bay)
    bay.attempted = {}
    bay.doorFrom, bay.doorTo, bay.doorStart, bay.doorDuration = 1, 1, 0, 0
    broadcastDoor(bay.config.id, 1, 1, 0)
end

local function runService(bay, stage, player, vehicle)
    local provider = providers[bay.config.kind]
    if not provider or getResourceState(provider.resource) ~= "running" then return false end
    return call(provider.resource, provider.handler, stage, bay.config.id, player, vehicle) == true
end

local function openBay(bay, now)
    bay.session.opensAt = now + moveDoor(bay, 1, now)
end

local function updateService(bay, now, vehicles)
    local session = bay.session
    if session.opensAt then
        if now >= session.opensAt then release(bay) end
        return
    end

    local player, vehicle = session.player, session.vehicle
    if not validDriver(bay, player, vehicle) then
        openBay(bay, now)
        return
    end
    local x, y, z = getElementPosition(vehicle)
    if not parkedInside(bay, vehicle, x, y, z) or entranceBlocked(bay, vehicle, vehicles) then
        openBay(bay, now)
    elseif now >= session.completesAt then
        runService(bay, "commit", player, vehicle)
        openBay(bay, now)
    end
end

local function vehicleInBay(bay, vehicle)
    if not isElement(vehicle) or not garageInWorld(bay.config, vehicle) then return false end
    local x, y, z = getElementPosition(vehicle)
    return inBayHeight(bay, z) and garageContainsXY(bay.config, x, y)
end

local function updateBay(bay, now)
    for vehicle in pairs(bay.attempted) do
        if not vehicleInBay(bay, vehicle) then bay.attempted[vehicle] = nil end
    end
    local vehicles = getElementsWithinColShape(bay.nearby, "vehicle")
    if bay.session then
        updateService(bay, now, vehicles)
        return
    end
    for _, vehicle in ipairs(vehicles) do
        local player = getVehicleOccupant(vehicle, 0)
        if not bay.attempted[vehicle] and not isElementFrozen(vehicle) and validDriver(bay, player, vehicle) then
            local x, y, z = getElementPosition(vehicle)
            local vx, vy, vz = getElementVelocity(vehicle)
            if vx * vx + vy * vy + vz * vz < parkingSpeedSquared
                and inBayHeight(bay, z) and garageContainsXY(bay.config, x, y) then
                if not runService(bay, "quote", player, vehicle) then
                    bay.attempted[vehicle] = true
                elseif parkedInside(bay, vehicle, x, y, z) and not entranceBlocked(bay, vehicle, vehicles)
                    and setElementFrozen(vehicle, true) then
                    bay.attempted[vehicle] = true
                    bay.session = {player = player, vehicle = vehicle,
                        completesAt = now + moveDoor(bay, 0, now) + serviceTime}
                    return
                end
            end
        end
    end
end

function getGarage(id)
    local config = catalog[id]
    if not config then return false end
    return config, providers[config.kind] ~= nil
end

function registerGarageType(kind, handler)
    if not sourceResource or type(handler) ~= "string" or handler == "" then return false end
    if providers[kind] then
        local registered = providers[kind]
        return registered.resource == sourceResource and registered.handler == handler
    end

    local matched = false
    for _, config in ipairs(VCS_GARAGES) do
        if config.kind == kind and config.door and config.doorKind == "slide" then
            bays[config.id] = makeBay(config)
            matched = true
        end
    end
    if not matched then return false end
    providers[kind] = {resource = sourceResource, handler = handler}
    setElementData(resourceRoot, garageTypeKey(kind), true, "broadcast", "deny")
    return true
end

addEventHandler("onResourceStart", resourceRoot, function()
    setTimer(function()
        local mapResource = getResourceFromName("vcs")
        if not mapResource or getResourceState(mapResource) ~= "running" then return end
        local now = getTickCount()
        for _, bay in pairs(bays) do updateBay(bay, now) end
    end, 100, 0)
end)

addEvent("garage:doorsReady", true)
addEventHandler("garage:doorsReady", resourceRoot, function()
    if source ~= resourceRoot or not client or doorViewers[client] then return end
    doorViewers[client] = true
    local now = getTickCount()
    for id, bay in pairs(bays) do
        local remaining = math.max(0, bay.doorStart + bay.doorDuration - now)
        triggerClientEvent(client, "garage:door", resourceRoot, id,
            doorPosition(bay, now), bay.doorTo, remaining, remaining > 0 and now - bay.motorStart or nil)
    end
end, false)
addEventHandler("onPlayerQuit", root, function() doorViewers[source] = nil end)

addEventHandler("onResourceStop", root, function(stopped)
    if stopped == getThisResource() then
        -- The client stop handler resets the local door and audio.
        for _, bay in pairs(bays) do release(bay) end
        return
    end
    if getResourceName(stopped) == "vcs" then
        for _, bay in pairs(bays) do reset(bay) end
        return
    end
    for kind, provider in pairs(providers) do
        if provider.resource == stopped then
            providers[kind] = nil
            setElementData(resourceRoot, garageTypeKey(kind), false, "broadcast", "deny")
            for id, bay in pairs(bays) do
                if bay.config.kind == kind then
                    reset(bay)
                    destroyElement(bay.nearby)
                    bays[id] = nil
                end
            end
        end
    end
end)

