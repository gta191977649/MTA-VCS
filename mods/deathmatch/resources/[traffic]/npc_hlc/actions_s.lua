-- The server advances movement when no MTA client owns the physical simulation.
local collisionResource

function configureNPCFallbackCollision()
    local enabled = get("npc_hlc.server_colchecking")
    if enabled == true or enabled == "true" then
        collisionResource = getResourceFromName("server_coldata")
    end
end

local function stepToPoint(actor, tx, ty, tz, elapsed, driveSpeed, x, y, z, pace)
    recordNPCDebugFallback(actor, tx, ty, tz)
    local dx, dy, dz = tx - x, ty - y, tz - z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance == 0 then return end

    local speed = driveSpeed and driveSpeed * 50 or NPC_SPEED_ONFOOT[pace or getNPCWalkSpeed(actor)]
    if not speed or speed <= 0 then return end
    local fraction = math.min(1, speed * elapsed * 0.001 / distance)
    local nx, ny, nz = x + dx * fraction, y + dy * fraction, z + dz * fraction
    local heading = -math.deg(math.atan2(dx, dy))
    if collisionResource and getResourceState(collisionResource) == "running"
        and call(collisionResource, "hasNearbyModelCollision", actor, nx, ny, nz, heading) then
        return
    end
    setElementPosition(actor, nx, ny, nz, false)
    if driveSpeed then
        setElementRotation(actor, math.deg(math.asin(dz / distance)), 0, heading)
    else
        setPedRotation(actor, heading)
    end
end

function stepNPCToPoint(actor, tx, ty, tz, elapsed, driveSpeed, pace)
    local x, y, z = getElementPosition(actor)
    stepToPoint(actor, tx, ty, tz, elapsed, driveSpeed, x, y, z, pace)
end

function stepNPCAlongLine(actor, task, elapsed, driveSpeed)
    local x, y, z = getElementPosition(actor)
    local x1, y1, z1, x2, y2, z2, offset = unpack(task, 2, 8)
    local length = getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
    local progress = getPercentageInLine(x, y, x1, y1, x2, y2)
    local target = math.min(1, math.max(0, progress + math.max(offset, 0.01) / length))
    stepToPoint(actor, x1 + (x2 - x1) * target, y1 + (y2 - y1) * target, z1 + (z2 - z1) * target,
        elapsed, driveSpeed, x, y, z)
end

function stepNPCAroundBend(actor, task, elapsed, driveSpeed)
    local x, y, z = getElementPosition(actor)
    local cx, cy, x1, y1, z1, x2, y2, z2, offset = unpack(task, 2, 10)
    local length = getDistanceBetweenPoints2D(x1, y1, x2, y2)
    local angle = getAngleInBend(x, y, cx, cy, x1, y1, x2, y2)
    local target = math.min(math.pi * 0.5, math.max(0, angle + math.max(offset, 0.01) / length))
    local tx, ty = getPosFromBend(target, cx, cy, x1, y1, x2, y2)
    stepToPoint(actor, tx, ty, z1 + (z2 - z1) * target / (math.pi * 0.5), elapsed, driveSpeed, x, y, z)
end
