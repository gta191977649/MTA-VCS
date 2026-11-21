local shot
local enterTime, exitTime = 650, 550

local function viewAngles(x, y, z, lookX, lookY, lookZ)
    local dx, dy, dz = lookX - x, lookY - y, lookZ - z
    return math.atan2(dy, dx), math.atan2(dz, math.sqrt(dx * dx + dy * dy))
end

local function angleDelta(from, to)
    return (to - from + math.pi) % (2 * math.pi) - math.pi
end

local function chooseCamera(shop, vehicle, cameraX, cameraY)
    local x, y, z = getElementPosition(vehicle)
    local doorX, doorY = unpack(shop.doorPosition)
    local dx, dy = doorX - shop.centerX, doorY - shop.centerY
    local length = math.sqrt(dx * dx + dy * dy)
    local nx, ny = dx / length, dy / length
    local ground = getGroundPosition(x, y, z + 0.5)
    if not ground or ground < shop.floor - 1.5 or ground > z then ground = shop.floor end

    -- SLUS-21590 garage camera, type 5 branch at 0x373090: use an outside
    -- view about 13 units from the entrance and 3.6 units above the ground.
    local cameraZ = ground + 3.6
    local tx, ty = doorX + nx, doorY + ny
    local side = (cameraX - tx) * -ny + (cameraY - ty) * nx
    local offset = side < 0 and -3 or 3
    for _, distance in ipairs({13, 9, 6}) do
        for _, shift in ipairs({offset, -offset, 0}) do
            local sx, sy = doorX + nx * distance - ny * shift, doorY + ny * distance + nx * shift
            if isLineOfSightClear(sx, sy, cameraZ, tx, ty, ground + 1.6, true, false, false, true, false) then
                return sx, sy, cameraZ
            end
        end
    end
end

local function captureView()
    local x, y, z, lx, ly, lz, roll, fov = getCameraMatrix()
    if not x then return end
    local yaw, pitch = viewAngles(x, y, z, lx, ly, lz)
    return {x = x, y = y, z = z, lx = lx, ly = ly, lz = lz, yaw = yaw, pitch = pitch,
        roll = roll or 0, fov = fov or 70, tick = getTickCount()}
end

local function ownsCamera()
    if getCameraTarget() then return false end
    local x, y, z = getCameraMatrix()
    return x and getDistanceBetweenPoints3D(x, y, z, shot.lastX, shot.lastY, shot.lastZ) < 0.15
end

local function restoreCamera()
    if not shot then return end
    local owns = ownsCamera()
    shot = nil
    if owns then setCameraTarget(localPlayer) end
end

local function available(config, vehicle)
    return config.door and getElementData(resourceRoot, garageTypeKey(config.kind), false) == true
        and garageInWorld(config, localPlayer) and garageInWorld(config, vehicle)
end

local function inBay(config, x, y, z, leaving)
    local padding = leaving and 0.25 or 0
    return z >= config.floor - padding and z <= config.ceiling + padding
        and garageContainsXY(config, x, y, leaving and 0.04 or 0)
end

local function beginShot(config, vehicle, x, y, z)
    local target = getCameraTarget()
    if target ~= localPlayer and target ~= vehicle then return end
    local view = captureView()
    if not view then return end
    local sx, sy, sz = chooseCamera(config, vehicle, view.x, view.y)
    if not sx then return end
    local _, _, heading = getElementRotation(vehicle)
    if not setCameraMatrix(view.x, view.y, view.z, view.lx, view.ly, view.lz, view.roll, view.fov) then return end
    shot = {config = config, vehicle = vehicle, start = view, duration = enterTime,
        x = sx, y = sy, z = sz, lastX = view.x, lastY = view.y, lastZ = view.z,
        followX = view.x - x, followY = view.y - y, followZ = view.z - z,
        followLookZ = view.lz - z, heading = heading}
end

local function animate(x, y, z, lx, ly, lz, roll)
    local start = shot.start
    local progress = math.min(1, (getTickCount() - start.tick) / shot.duration)
    local weight = progress * progress * (3 - 2 * progress)
    local cx = start.x + (x - start.x) * weight
    local cy = start.y + (y - start.y) * weight
    local cz = start.z + (z - start.z) * weight
    if progress < 1 then
        local yaw, pitch = viewAngles(x, y, z, lx, ly, lz)
        yaw = start.yaw + angleDelta(start.yaw, yaw) * weight
        pitch = start.pitch + (pitch - start.pitch) * weight
        local horizontal = math.cos(pitch)
        lx = cx + math.cos(yaw) * horizontal * 10
        ly = cy + math.sin(yaw) * horizontal * 10
        lz = cz + math.sin(pitch) * 10
    end
    setCameraMatrix(cx, cy, cz, lx, ly, lz, start.roll + (roll - start.roll) * weight, start.fov)
    shot.lastX, shot.lastY, shot.lastZ = cx, cy, cz
    return progress >= 1
end

local function returnToFollow(x, y, z)
    local _, _, heading = getElementRotation(shot.vehicle)
    local delta = math.rad(heading - shot.heading)
    local dx = shot.followX * math.cos(delta) - shot.followY * math.sin(delta)
    local dy = shot.followX * math.sin(delta) + shot.followY * math.cos(delta)
    local lx, ly, lz = x, y, z + shot.followLookZ
    local cx, cy, cz = x + dx, y + dy, z + shot.followZ
    local hit, hx, hy, hz = processLineOfSight(lx, ly, lz, cx, cy, cz,
        true, false, false, true, false, false, true, false, shot.vehicle)
    if hit then
        cx, cy, cz = lx + 0.85 * (hx - lx), ly + 0.85 * (hy - ly), lz + 0.85 * (hz - lz)
    end
    if animate(cx, cy, cz, lx, ly, lz, 0) then restoreCamera() end
end

addEventHandler("onClientPreRender", root, function()
    local mapResource = getResourceFromName("vcs")
    if not mapResource or getResourceState(mapResource) ~= "running" then
        restoreCamera()
        return
    end
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if not isElement(vehicle) then
        restoreCamera()
        return
    end
    local x, y, z = getElementPosition(vehicle)
    if shot then
        if not ownsCamera() then
            shot = nil
        elseif shot.vehicle ~= vehicle or not available(shot.config, vehicle) then
            restoreCamera()
        elseif inBay(shot.config, x, y, z, true) then
            if shot.leaving then
                shot.start, shot.duration, shot.leaving = captureView(), enterTime, nil
            end
            animate(shot.x, shot.y, shot.z, x, y, z, 0)
        else
            if not shot.leaving then
                shot.start, shot.duration, shot.leaving = captureView(), exitTime, true
            end
            returnToFollow(x, y, z)
        end
        return
    end
    for _, config in ipairs(VCS_GARAGES) do
        if available(config, vehicle) and inBay(config, x, y, z, false) then
            beginShot(config, vehicle, x, y, z)
            break
        end
    end
end)

addEventHandler("onClientPlayerWasted", localPlayer, restoreCamera)
addEventHandler("onClientPlayerVehicleExit", localPlayer, restoreCamera)
addEventHandler("onClientResourceStop", root, function(stopped)
    if stopped == getThisResource() or getResourceName(stopped) == "vcs" then restoreCamera() end
end)

