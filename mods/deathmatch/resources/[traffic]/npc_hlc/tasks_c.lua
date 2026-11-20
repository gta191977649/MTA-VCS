performTask = {}

function performTask.walkToPos(npc, task)
    makeNPCWalkToPos(npc, task[2], task[3])
end

function performTask.walkTrafficToPoint(npc, task, _, progress)
    progress.runningCrossing = nil
    walkNPCTrafficAroundPeds(npc, task, progress)
end

function performTask.walkTrafficCrossing(npc, task, _, progress)
    local pace = getNPCTrafficCrossingPace(npc, task)
    if progress.runningCrossing == task or pace == "run" then
        progress.runningCrossing = task
        pace = "run"
    end
    if pace == "wait" then
        progress.action = "TASK_SIMPLE_STAND_STILL"
        stopNPCWalkingActions(npc)
    else
        walkNPCTrafficAroundPeds(npc, task, progress, pace)
    end
end

function performTask.walkAlongLine(npc, task)
    makeNPCWalkAlongLine(npc, unpack(task, 2, 8))
end

function performTask.walkAroundBend(npc, task)
    makeNPCWalkAroundBend(npc, task[2], task[3], task[4], task[5], task[7], task[8], task[10])
end

function performTask.walkFollowElement(npc, task)
    local x, y = getElementPosition(npc)
    local fx, fy = getElementPosition(task[2])
    local dx, dy = fx - x, fy - y
    if dx * dx + dy * dy > task[3] * task[3] then
        makeNPCWalkToPos(npc, fx, fy)
    else
        stopNPCWalkingActions(npc)
    end
end

function performTask.walkFormation(npc,task,elapsed,progress)
    local x,y,_,fx,fy = getNPCFormationSlot(task)
    if not x then stopNPCWalkingActions(npc) return end
    local px,py = getElementPosition(npc)
    local gap = (px-x)^2+(py-y)^2
    -- Slot 7 is beside the leader. Aim along their path while abreast so a
    -- small sideways correction does not turn the follower across the couple.
    if task[4]>0 and task[5]==0 and gap<=task[3]^2 then
        local vx,vy = getElementVelocity(task[2])
        if vx*fx+vy*fy > 0.003 then
            walkNPCTrafficFormation(npc,x+fx,y+fy,progress)
        else
            stopNPCWalkingActions(npc)
            local _,_,heading = getElementRotation(npc)
            local target = math.deg(math.atan2(-fx,fy))
            local delta = (target-heading+180)%360-180
            local step = math.min(elapsed,100)*0.24
            if math.abs(delta)>0.5 then setPedRotation(npc,heading+math.max(-step,math.min(step,delta)),true) end
        end
    elseif gap > task[3]^2 then walkNPCTrafficFormation(npc,x,y,progress)
    else stopNPCWalkingActions(npc) end
end

function performTask.shootPoint(npc, task)
    makeNPCShootAtPos(npc, task[2], task[3], task[4])
end

function performTask.shootElement(npc, task)
    makeNPCShootAtElement(npc, task[2])
end

-- The optional fifth argument selects VCS objective 8. Existing HLC callers
-- retain their continuous attack. Timers belong to this task on this syncer.
local attackClocks = setmetatable({}, {__mode="k"})
local function canStrike(npc, task, distance, occupied)
    if task[5] == nil then return true end
    local state = getPedSimplestTask(task[2])
    if state == "TASK_SIMPLE_GET_UP" or state == "TASK_SIMPLE_CAR_GET_DRAGGED_OUT" then return false end
    local x,y,z = getElementPosition(npc)
    local tx,ty,tz = getElementPosition(task[2])
    if not isLineOfSightClear(x,y,z+0.45,tx,ty,tz+0.45,true,false,false,true,false) then return false end
    local ranged = task[5] == 1
    if occupied and ranged and distance <= 3 then return false end
    local now = getTickCount()
    local clock = attackClocks[npc]
    if clock and clock.task == task then
        local age = (now-clock.start)%4294967296
        if age <= clock.burst then return true end
        if age <= clock.nextAttack then return false end
    end
    -- 0010262C / 00101308: the second timer starts after the first.
    local burst = ranged and math.random(600,1499) or math.random(0,499)
    local delay = not ranged and math.random(100,1499)
        or distance <= task[4] and math.random(100,499) or math.random(1500,2999)
    attackClocks[npc] = {task=task,start=now,burst=burst,nextAttack=burst+delay}
    return true
end

function performTask.killPed(npc, task)
    local x, y, z = getElementPosition(npc)
    local tx, ty, tz = getElementPosition(task[2])
    local dx, dy = tx - x, ty - y
    local distanceSquared = dx * dx + dy * dy
    if task[5] ~= nil then distanceSquared = distanceSquared + (tz-z)^2 end
    if distanceSquared < task[3] * task[3] and canStrike(npc,task,math.sqrt(distanceSquared),false) then
        makeNPCShootAtElement(npc, task[2])
        setPedRotation(npc, -math.deg(math.atan2(dx, dy)))
    else
        stopNPCWeaponActions(npc)
    end
    if distanceSquared > task[4] * task[4] then
        makeNPCWalkToPos(npc, tx, ty)
    else
        stopNPCWalkingActions(npc)
    end
end

local doorBySeat = {[0]="door_lf_dummy", "door_rf_dummy", "door_lr_dummy", "door_rr_dummy"}

function performTask.attackOccupiedVehicle(npc, task)
    local vehicle = getPedOccupiedVehicle(task[2])
    if not vehicle then stopNPCWeaponActions(npc) stopNPCWalkingActions(npc) return end
    local m = getElementMatrix(vehicle)
    local xmin, ymin, _, xmax, ymax = getElementBoundingBox(vehicle)
    if not m or not xmin or not xmax then return end
    local x, y = getElementPosition(npc)
    local cx, cy, cz = unpack(m[4])
    local dx, dy = x - cx, y - cy
    local side = math.max(xmin, math.min(xmax, dx * m[1][1] + dy * m[1][2]))
    local along = math.max(ymin, math.min(ymax, dx * m[2][1] + dy * m[2][2]))
    local tx, ty = cx + side*m[1][1] + along*m[2][1], cy + side*m[1][2] + along*m[2][2]
    if task[5] == 0 then
        local component = doorBySeat[getPedOccupiedVehicleSeat(task[2])]
        local doorX,doorY
        if component then doorX,doorY = getVehicleComponentPosition(vehicle,component,"world") end
        if doorX then tx,ty = doorX,doorY end
    end
    local distance = (x - tx)^2 + (y - ty)^2
    if task[5] == 1 and distance <= 9 then
        stopNPCWeaponActions(npc)
        local length = math.sqrt(dx*dx+dy*dy)
        if length>0.01 then
            local retreatX,retreatY = x+dx/length*2,y+dy/length*2
            local _,_,z=getElementPosition(npc)
            if isLineOfSightClear(x,y,z,retreatX,retreatY,z,true,true,false,true,false,false,false,npc)
                and isLineOfSightClear(retreatX,retreatY,z,retreatX,retreatY,z-1.8,true,false,false,true,false)==false then
                makeNPCWalkToPos(npc,retreatX,retreatY)
                return
            end
        end
        stopNPCWalkingActions(npc)
        return
    end
    if distance <= task[3]^2 and canStrike(npc,task,math.sqrt(distance),true) then
        setPedRotation(npc, -math.deg(math.atan2(cx - x, cy - y)))
        makeNPCShootAtPos(npc, tx, ty, cz)
    else
        stopNPCWeaponActions(npc)
    end
    if distance > task[4]^2 then makeNPCWalkToPos(npc, tx, ty) else stopNPCWalkingActions(npc) end
end

function performTask.driveToPos(npc, task)
    makeNPCDriveToPos(npc, task[2], task[3], task[4])
end

function performTask.stopVehicle(npc)
    local vehicle = getPedOccupiedVehicle(npc)
    local motion = getNPCTrafficPhysicsMotion(vehicle)
    if motion and motion.forward > 0.5 then setNPCVehicleInputs(npc, 0, -1, false)
    else setNPCVehicleInputs(npc, 0, 0, true) end
end

function performTask.driveAtPed(npc, task)
    local vehicle = getPedOccupiedVehicle(npc)
    local target = getPedOccupiedVehicle(task[2]) or task[2]
    local motion = getNPCTrafficPhysicsMotion(vehicle)
    if not motion or motion.unstable then
        setNPCVehicleInputs(npc, 0, 0, false)
        return
    end
    local x, y = getElementPosition(target)
    local dx, dy = x - motion.x, y - motion.y
    local distance = math.sqrt(dx * dx + dy * dy)
    local vx, vy = getElementVelocity(target)
    local lead = math.min(0.6, distance / 40)
    dx, dy = dx + vx * 50 * lead, dy + vy * 50 * lead
    recordNPCDebugTarget(npc, motion.x + dx, motion.y + dy, motion.z)
    local angle = math.atan2(dx * motion.fy - dy * motion.fx, dx * motion.fx + dy * motion.fy)
    local steer = math.max(-1, math.min(1, angle * 2))
    local speed = 40 / (1 + math.abs(angle) * 2)
    if vx*vx + vy*vy <= 0.02^2 and distance < 20 then
        speed = math.min(speed, math.sqrt(8 * math.max(0, distance-1.5)))
        if distance < 10 and math.abs(angle) > math.pi * 0.55 then speed = 0 end
    end
    setNPCVehicleInputs(npc, steer, math.max(-0.5, math.min(1, (speed - motion.forward) * 0.16)), false)
end

function performTask.driveTrafficToPoint(npc, task, elapsed, useNextLane)
    local vehicle = getPedOccupiedVehicle(npc)
    local multiplier = getNPCTrafficDriveMultiplier(vehicle, task[6], math.min(elapsed or 16, 100) * getGameSpeed())
    local x, y, z, dx, dy = task[2], task[3], task[4], task[7], task[8]
    if useNextLane then x, y, z, dx, dy = task[9], task[10], task[11], task[13], task[14] end
    if dx then
        local px, py = getElementPosition(vehicle)
        local distance = math.sqrt((x - px) ^ 2 + (y - py) ^ 2)
        if distance <= 40 then
            -- 0x00438A80 approaches the lane centre along the link heading.
            x, y = x - 0.4 * distance * dx, y - 0.4 * distance * dy
        end
    end
    makeNPCDriveToPos(npc, x, y, z, true, getNPCDriveSpeed(npc) * multiplier)
end

local roadSurface = setmetatable({}, {__mode = "k"})
local railMotionSamples = setmetatable({}, {__mode = "k"})

local function nearbyMotion(vehicle, now, x, y)
    if not isElementFrozen(vehicle) then
        local vx, vy = getElementVelocity(vehicle)
        return vx * 50, vy * 50
    end
    local sample = railMotionSamples[vehicle]
    if not sample then
        railMotionSamples[vehicle] = {x = x, y = y, tick = now, vx = 0, vy = 0}
        return 0, 0
    end
    local elapsed = (now - sample.tick) % 4294967296
    if elapsed >= 50 then
        local dx, dy = x - sample.x, y - sample.y
        if elapsed >= 250 or dx * dx + dy * dy > 0.0004 then
            local scale = math.min(1000 / elapsed, 50 / math.max(0.01, math.sqrt(dx * dx + dy * dy)))
            sample.vx, sample.vy = elapsed < 400 and dx * scale or 0, elapsed < 400 and dy * scale or 0
            sample.x, sample.y, sample.tick = x, y, now
        end
    end
    return sample.vx, sample.vy
end

local function halfExtents(vehicle)
    local minX, minY, _, maxX, maxY = getElementBoundingBox(vehicle)
    return minX and maxX and math.max(-minX, maxX) or 1,
        minY and maxY and math.max(-minY, maxY) or 2
end

-- The original CarCtrl tests predicted vehicle rectangles. Sample the
-- actual rail curve in MTA and reserve braking room before the first overlap.
function limitNPCTrafficRailMerge(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now)
    local horizon = math.min(52, math.max(14, speed ^ 2 / 20 + speed * 0.15 + 8))
    local width, length = halfExtents(vehicle)
    local nearby = getElementsWithinRange(x, y, z, horizon + length + 8, "vehicle",
        getElementInterior(vehicle), getElementDimension(vehicle)) or {}
    local obstacles = {}
    for _, other in ipairs(nearby) do
        if other ~= vehicle and isElementStreamedIn(other) then
            local ox, oy, oz = getElementPosition(other)
            local matrix = getElementMatrix(other)
            if matrix and math.abs(oz - z) < 4 then
                local vx, vy = nearbyMotion(other, now, ox, oy)
                local ow, ol = halfExtents(other)
                local heading = matrix[2]
                obstacles[#obstacles + 1] = {x = ox, y = oy, z = oz, vx = vx, vy = vy,
                    fx = heading[1], fy = heading[2], width = ow, length = ol}
            end
            if #obstacles >= 16 then break end
        end
    end
    if #obstacles == 0 then return math.huge, false end

    local limit, emergency = math.huge, false
    local lastX, lastY
    for distance = 1, horizon, 4 do
        local px, py, pz, tx, ty = getNPCTrafficRailPreview(task, segment, t, lengths, distance)
        if px == lastX and py == lastY then break end
        lastX, lastY = px, py
        local tangent = math.sqrt(tx * tx + ty * ty)
        if tangent > 0.01 then tx, ty = tx / tangent, ty / tangent else tx, ty = dx, dy end
        local arrival = math.min(2.5, distance / math.max(4, speed))
        for _, other in ipairs(obstacles) do
            if math.abs(other.z - pz) < 2.8 then
                local angle = other.fx * tx + other.fy * ty
                local side = math.abs(other.fx * ty - other.fy * tx)
                local lateral = width + math.abs(angle) * other.width + side * other.length
                local longitudinal = length + math.abs(angle) * other.length + side * other.width
                local rx, ry = other.x + other.vx * arrival - px, other.y + other.vy * arrival - py
                local forward = rx * tx + ry * ty
                if math.abs(rx * ty - ry * tx) < lateral + 0.2 and math.abs(forward) < longitudinal + 0.4 then
                    local initialSide = math.abs((other.x - x) * dy - (other.y - y) * dx)
                    local sameLane = angle > 0.9 and initialSide < width + other.width
                    local leader = sameLane and math.max(0, other.vx * tx + other.vy * ty) or 0
                    local gap = math.max(0, distance + forward - longitudinal - 2 - speed * 0.1)
                    limit = math.min(limit, math.sqrt(leader * leader + 20 * gap))
                    emergency = emergency or distance == 1 and gap == 0
                end
            end
        end
    end
    return limit, emergency
end

local function observedRailLeader(previous, leader, now, dx, dy)
    local x, y = getElementPosition(leader)
    if not previous or previous.vehicle ~= leader then return {vehicle = leader, x = x, y = y, tick = now, speed = 0} end
    local elapsed = (now - previous.tick) % 4294967296
    local moved = (x - previous.x) * dx + (y - previous.y) * dy
    if moved > 0.02 and elapsed > 0 then
        local measured = math.min(25, moved * 1000 / elapsed)
        return {vehicle = leader, x = x, y = y, tick = now,
            speed = elapsed <= 500 and (previous.speed + measured) * 0.5 or measured}
    end
    if elapsed >= 300 then return {vehicle = leader, x = x, y = y, tick = now, speed = 0} end
    -- A frozen leader's position arrives in sync packets. Keep its estimate
    -- between packets instead of treating every unchanged sample as a stop.
    return previous
end

local function railSpeedLimit(vehicle, x, y, z, ax, ay, az, dx, dy, centreHeight, task, segment, t, lengths, speed)
    local now = getTickCount()
    local previous = roadSurface[vehicle]
    local elapsed = previous and (now - previous.tick) % 4294967296 or 0
    if previous and previous.task == task and elapsed < 100 then return previous.speed, previous.emergency end
    local limit = math.huge
    local leaderSample
    local emergency = false
    local boat = getVehicleType(vehicle) == "Boat"
    if boat then
        -- Leave vertical velocity and pitch/roll to native buoyancy. Refuse a dry next sample.
        local water = getWaterLevel(ax, ay, az, true)
        if type(water) ~= "number" or math.abs(water - az) > 7 then limit = 0 end
    elseif centreHeight then
        local expectedGround = az - centreHeight
        local water = getWaterLevel(ax, ay, expectedGround, true)
        if type(water) == "number" and water >= expectedGround - 3 then
            local hit, _, _, ground = processLineOfSight(ax, ay, expectedGround + 3, ax, ay, expectedGround - 3,
                true, false, false, true, false, false, false, false, vehicle)
            if not hit or ground <= water then limit = 0 end
        end
    end
    if limit > 0 then
        local _, _, _, _, front = getElementBoundingBox(vehicle)
        front = front or 2
        local distance = front + 6
        local hit, hx, hy, _, obstacle = processLineOfSight(x, y, z, x + dx * distance, y + dy * distance, z,
            false, true, true, false, false, false, false, false, vehicle)
        if hit then
            local lead = 0
            if isElement(obstacle) and getElementType(obstacle) == "vehicle" then
                if isElementFrozen(obstacle) then
                    leaderSample = observedRailLeader(previous and previous.leader, obstacle, now, dx, dy)
                    lead = leaderSample.speed
                else
                    local vx, vy = getElementVelocity(obstacle)
                    lead = math.max(0, (vx * dx + vy * dy) * 50)
                end
            end
            local gap = (hx - x) * dx + (hy - y) * dy - front
            limit = gap > 0 and math.max(0, lead + (gap - 2) * 2) or 0
            emergency = gap <= 1 and lead < speed
        end
    end
    if boat and limit > 0 and getElementData(vehicle, "npchlc_traffic:boatStyle") ~= 2 then
        limit = math.min(limit, exports.vcs_vehicle:getBoatTrafficSpeedLimit(vehicle, task[14]))
    end
    if limit > 0 then
        local mergeLimit, imminent = limitNPCTrafficRailMerge(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now)
        limit, emergency = math.min(limit, mergeLimit), emergency or imminent
    end
    roadSurface[vehicle] = {tick = now, task = task, speed = limit, leader = leaderSample, emergency = emergency}
    return limit, emergency
end

function performTask.driveTrafficRail(npc, task, elapsed)
    local vehicle = getPedOccupiedVehicle(npc)
    if getElementData(vehicle, "npchlc_traffic:rail", false) and not isElementFrozen(vehicle)
        and not getElementData(vehicle, "npchlc_traffic:impactPending", false) then
        advanceNPCTrafficRail(vehicle, task, math.min(elapsed or 16, 100) * getGameSpeed(), railSpeedLimit,
            getVehicleType(vehicle) == "Boat")
    end
end

function performTask.driveAlongLine(npc, task)
    makeNPCDriveAlongLine(npc, unpack(task, 2, 8))
end

function performTask.driveAroundBend(npc, task)
    makeNPCDriveAroundBend(npc, unpack(task, 2, 10))
end

function performTask.waitForGreenLight(npc)
    stopAllNPCActions(npc)
end
