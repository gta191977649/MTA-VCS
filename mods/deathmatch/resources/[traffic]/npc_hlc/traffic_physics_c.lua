local samples = setmetatable({}, {__mode = "k"})
local diagnostics = setmetatable({}, {__mode = "k"})
local debugging = false
local sensorBudget = 12
local deferred = setmetatable({}, {__mode="k"})
local frame, reserved, missed = 0,0,0
local SAMPLE_MS = 75
local BRAKING = 3 -- Conservative MTA braking envelope, in world units/s².
local STALL_MS = 1000
local REVERSE_MS = 700 -- VCS PC 0x0041FC57, ordinary cruise traffic.
local AVOID_DISTANCE = 4
local AVOID_ANGLE = math.rad(15)
local RECOVERY_SPEED = 2.5
addEvent("npc_hlc:onCruiseStuck", false)
addEvent("npc_hlc:onRouteLow",false)

function beginNPCTrafficPhysicsFrame()
    sensorBudget = 12
    frame,reserved,missed=frame+1,math.min(6,missed),0
end

function resetNPCTrafficPhysicsSensor(vehicle)
    samples[vehicle], diagnostics[vehicle] = nil, nil
end

addEventHandler("onClientVehicleCollision", root, function()
    if samples[source] then resetNPCTrafficPhysicsSensor(source) end
end)

local function stopSpeed(gap, leader, speed)
    local available = math.max(0, gap - 2 - math.max(0, speed - leader) * 0.15)
    return math.sqrt(leader * leader + 2 * BRAKING * available)
end

local function vehicleExtents(vehicle)
    local a, b, _, c, d = getElementBoundingBox(vehicle)
    return a and c and math.max(-a, c) or 1, b and d and math.max(-b, d) or 2
end

local function scanStrip(vehicle, x0, y0, z, dx, dy, halfWidth, sweep, grade, travelled, speed)
    local limit, nearest, cause = math.huge, math.huge, "clear"
    for offset = -1, 1 do
        local side = offset * halfWidth * 0.85
        local x = x0 + dy * side
        local y = y0 - dx * side
        local hit, hx, hy, _, element = processLineOfSight(x, y, z, x + dx * sweep, y + dy * sweep, z + grade * sweep,
            true, true, true, true, false, false, false, false, vehicle)
        if hit then
            local leader = 0
            local kind = isElement(element) and getElementType(element)
            if kind == "vehicle" and not isElementFrozen(element) then
                local vx, vy = getElementVelocity(element)
                leader = math.max(0, (vx * dx + vy * dy) * 50)
            end
            local gap = math.max(0, travelled + (hx - x) * dx + (hy - y) * dy)
            local candidate = stopSpeed(gap, leader, speed)
            local hitCause = kind == "vehicle" and "following"
                or (kind == "ped" or kind == "player") and "pedestrian" or "obstacle"
            nearest = math.min(nearest, gap)
            if candidate < limit or candidate == limit and cause == "obstacle" and hitCause ~= "obstacle" then
                limit, cause = candidate, hitCause
            end
        end
    end
    return limit, cause, nearest
end

local function scanBumper(vehicle, motion, dx, dy, width, length, range, speed)
    local sign = dx * motion.fx + dy * motion.fy < 0 and -1 or 1
    local offset = sign * (length - 0.35)
    local grade = math.max(-0.3, math.min(0.3, motion.grade))
    return scanStrip(vehicle, motion.x + motion.fx * offset, motion.y + motion.fy * offset,
        motion.z + grade * offset, dx, dy, width, range + 0.35, grade * sign, -0.35, speed)
end

-- Near a turn the steering target can already point across the junction while
-- the bumper is still facing into it. Sweep from the actual bumper, rounding
-- toward the steering target before extending the braking sightline.
local function scanRoute(vehicle, motion, dx, dy, width, length, range, speed, lane, nextLane)
    local dot = dx * motion.fx + dy * motion.fy
    local radius = math.max(3, length * 1.5)
    local straight = 0
    if dot > 0.985 then
        local nextDot = nextLane and dx*nextLane[6]+dy*nextLane[7]
        if not nextDot or nextDot > 0.985 then return scanBumper(vehicle,motion,dx,dy,width,length,range,speed) end
        local bendAngle = math.acos(math.max(-1, math.min(1, nextDot)))
        local remaining = (lane[3]-motion.x)*dx + (lane[4]-motion.y)*dy - length
        straight = math.max(0, remaining - radius * math.tan(math.min(bendAngle, math.pi/2)/2))
        if straight >= range then return scanBumper(vehicle,motion,dx,dy,width,length,range,speed) end
        dx,dy = nextLane[6],nextLane[7]
        dot = dx * motion.fx + dy * motion.fy
    end
    local angle = math.atan2(motion.fx * dy - motion.fy * dx, dot)
    local bend = math.min(radius * math.abs(angle), range-straight)
    local steps = math.max(1, math.ceil(bend / radius / math.rad(25)))
    local heading = math.atan2(motion.fy, motion.fx)
    local grade = math.max(-0.3, math.min(0.3, motion.grade))
    local x,y = motion.x + motion.fx*(length-0.35), motion.y + motion.fy*(length-0.35)
    local z = motion.z + grade*(length-0.35)
    local limit,cause,gap = math.huge,"clear",math.huge
    local travelled = -0.35
    if straight > 0 then
        limit,cause,gap = scanStrip(vehicle,x,y,z,motion.fx,motion.fy,width,straight,grade,travelled,speed)
        x,y,z=x+motion.fx*straight,y+motion.fy*straight,z+grade*straight
        travelled=travelled+straight
    end
    for i=1,steps+1 do
        local turn = math.min(i-0.5,steps) * bend / (steps*radius)
        local yaw = heading + (angle<0 and -turn or turn)
        local ux,uy = math.cos(yaw),math.sin(yaw)
        local distance = i<=steps and 2*radius*math.sin(bend/(2*radius*steps)) or range-straight-bend+0.35
        local slope = grade*(motion.fx*ux+motion.fy*uy)
        local cap,reason,clearance = scanStrip(vehicle,x,y,z,ux,uy,width,distance,slope,travelled,speed)
        if cap<limit then limit,cause=cap,reason end
        gap=math.min(gap,clearance)
        x,y,z=x+ux*distance,y+uy*distance,z+slope*distance
        travelled=travelled+distance
    end
    return limit,cause,gap
end

-- Calculate the time interval in which one axis of two moving bounds overlaps.
local function overlap(position, velocity, extent)
    if math.abs(velocity) < 0.01 then
        if math.abs(position) <= extent then return -math.huge, math.huge end
        return
    end
    local enter, leave = (-extent - position) / velocity, (extent - position) / velocity
    return math.min(enter, leave), math.max(enter, leave)
end

local function crossingLimit(vehicle, motion, dx, dy, width, length, range, speed)
    if speed < 0.5 then return math.huge end
    local limit, tested = math.huge, 0
    local x, y, z = motion.x, motion.y, motion.z
    local vehicles = getElementsWithinRange(x, y, z, range + length, "vehicle",
        getElementInterior(vehicle), getElementDimension(vehicle)) or {}
    for _, other in ipairs(vehicles) do
        if other ~= vehicle and isElementStreamedIn(other) and not isElementFrozen(other) then
            local ox, oy, oz = getElementPosition(other)
            local vx, vy = getElementVelocity(other)
            vx, vy = vx * 50, vy * 50
            if math.abs(oz - z) <= 3 and math.abs(vx * dy - vy * dx) > 0.8 then
                local a, b, _, c, d = getElementBoundingBox(other)
                local heading = getElementMatrix(other)
                if a and b and c and d and heading then
                    tested = tested + 1
                    local otherWidth, otherLength = (c - a) * 0.5, (d - b) * 0.5
                    local h = heading[2]
                    local forward, side = math.abs(h[1] * dx + h[2] * dy), math.abs(h[1] * dy - h[2] * dx)
                    local long = length + forward * otherLength + side * otherWidth
                    local wide = width + side * otherLength + forward * otherWidth
                    local px, py = ox - x, oy - y
                    local enter, leave = overlap(px * dx + py * dy, vx * dx + vy * dy - speed, long)
                    local sideEnter, sideLeave = overlap(px * dy - py * dx, vx * dy - vy * dx, wide)
                    if enter and sideEnter then
                        local t = math.max(0, enter, sideEnter)
                        if t <= math.min(leave, sideLeave, 3) then
                            limit = math.min(limit, stopSpeed(t * speed, 0, speed))
                        end
                    end
                    if tested == 12 then break end
                end
            end
        end
    end
    return limit
end

-- The VCS PC follow-path routine (0x00434900) calls the traffic speed
-- routine (0x00434400). Measure clearance with streamed MTA collision data.
local function trafficLimit(vehicle, motion, routeX, routeY, task, index, allowAvoid)
    local speed = math.sqrt(motion.vx ^ 2 + motion.vy ^ 2)
    local dx, dy = routeX, routeY
    if speed > 0.5 then dx, dy = motion.vx / speed, motion.vy / speed end
    local sequence = task[2] + index - 1
    local previous, now = samples[vehicle], getTickCount()
    if previous and previous.sequence == sequence and (now - previous.tick) % 4294967296 < SAMPLE_MS
        and previous.dx * dx + previous.dy * dy > 0.94
        and previous.fx * motion.fx + previous.fy * motion.fy > 0.94
        and previous.routeX * routeX + previous.routeY * routeY > 0.94
        and previous.allowAvoid == allowAvoid and math.abs(previous.speed - speed) < 2
        and (motion.x - previous.x) ^ 2 + (motion.y - previous.y) ^ 2 < 1 then
        return previous.limit, previous.cause, previous.avoidAngle
    end
    local priority=deferred[vehicle]==frame-1
    if sensorBudget==0 or not priority and sensorBudget<=reserved then
        if deferred[vehicle]~=frame then missed=missed+1 end
        deferred[vehicle]=frame
        if previous and previous.sequence==sequence and previous.cause=="clear"
            and (now-previous.tick)%4294967296<=150 and previous.dx*dx+previous.dy*dy>0.995
            and previous.routeX*routeX+previous.routeY*routeY>0.995 and previous.fx*motion.fx+previous.fy*motion.fy>0.995
            and previous.nextLink==(task[5][index+1] and task[5][index+1][1]) and math.abs(motion.z-previous.z)<0.5 then
            local shift=math.sqrt((motion.x-previous.x)^2+(motion.y-previous.y)^2)
            if shift<=2 and previous.range-shift>=speed^2/(2*BRAKING)+speed*0.15+2 then
                return math.huge,"clear",0
            end
        end
        return 0,"Sensor budget",0
    end
    if priority then reserved=math.max(0,reserved-1) end
    deferred[vehicle]=nil
    sensorBudget = sensorBudget - 1
    local width, length = vehicleExtents(vehicle)
    local range = math.min(120, math.max(8, speed ^ 2 / (2 * BRAKING) + speed * 0.15 + 4))
    local limit, cause, gap = scanRoute(vehicle, motion, routeX, routeY, width, length, range, speed,
        task[5][index],task[5][index+1])
    local avoidAngle = 0
    if task[6] == 2 and allowAvoid and cause == "following" and limit < task[3] then
        local angle = math.atan2(routeY,routeX)
        local reach = math.min(range,math.max(7,speed*1.4))
        for side = -1, 1, 2 do
            local offset = side * math.min(math.rad(25),math.atan2(3.25,reach))
            local ax, ay = math.cos(angle+offset), math.sin(angle+offset)
            local sideLimit = scanBumper(vehicle,motion,ax,ay,width,length,reach,speed)
            if sideLimit > limit and canNPCTrafficPhysicsAvoid(task,index,motion.x,motion.y,motion.z,ax,ay,reach,width) then
                limit, cause, avoidAngle = math.min(sideLimit,task[3]), "avoiding", offset
                break
            end
        end
    end
    if allowAvoid and cause == "obstacle" and gap <= AVOID_DISTANCE and speed <= RECOVERY_SPEED then
        local angle = math.atan2(routeY, routeX)
        for side = -1, 1, 2 do
            local offset = side * AVOID_ANGLE
            local ax, ay = math.cos(angle + offset), math.sin(angle + offset)
            if ax * motion.fx + ay * motion.fy > 0
                and canNPCTrafficPhysicsAvoid(task, index, motion.x, motion.y, motion.z, ax, ay, AVOID_DISTANCE, width) then
                local _, _, clearance = scanBumper(vehicle, motion, ax, ay, width, length, AVOID_DISTANCE, speed)
                if clearance == math.huge then
                    limit, cause, avoidAngle = RECOVERY_SPEED, "avoiding", offset
                    break
                end
            end
        end
    end
    if speed > 0.6 and dx * routeX + dy * routeY < 0.999 then
        -- The tangent checks immediate drift during steering. Longer range
        -- braking is already covered along the turning path above.
        local emergencyRange = math.max(2, speed * 0.35)
        local emergency, hazard = scanBumper(vehicle, motion, dx, dy, width, length, math.min(range, emergencyRange), speed)
        if emergency < limit then limit, cause = emergency, hazard end
    end
    local crossing = crossingLimit(vehicle, motion, dx, dy, width, length, range, speed)
    if dx * routeX + dy * routeY < 0.94 then
        crossing = math.min(crossing, crossingLimit(vehicle, motion, routeX, routeY, width, length, range, speed))
    end
    if crossing < limit then limit, cause = crossing, "crossing" end
    samples[vehicle] = {tick = now, sequence = sequence, dx = dx, dy = dy, fx = motion.fx, fy = motion.fy,
        routeX = routeX, routeY = routeY, limit = limit, speed = speed, cause = cause, avoidAngle = avoidAngle,
        allowAvoid = allowAvoid, x = motion.x, y = motion.y,z=motion.z,range=range,
        nextLink=task[5][index+1] and task[5][index+1][1]}
    return limit, cause, avoidAngle
end

local function applyInputs(npc, vehicle, motion, progress, steer, speed, reason, avoidAngle, rear, elapsed)
    local reversing = reason == "reverse"
    local error = speed - motion.forward
    local gain = motion.forward < 2 and 0.25 or 0.125
    local throttle = speed > 0 and math.max(0, math.min(1, error * gain)) or 0
    if reason == "cruise" and elapsed then
        -- Keep enough throttle to hold the rail target against drag or grade.
        -- Limit the integral so a stationary or slow vehicle cannot wind it up.
        local trim = progress.cruiseThrottle or 0
        if throttle + trim < 1 or error < 0 then
            trim = math.max(0, math.min(1, trim + error * elapsed * 0.00022))
        end
        progress.cruiseThrottle = trim
        throttle = error >= -0.25 and math.max(0, math.min(1, error * gain + trim)) or 0
    else
        progress.cruiseThrottle = nil
    end
    local moving = motion.forward > 0.5
    local urgent = reason == "obstacle" or reason == "following" or reason == "crossing"
        or reason == "pedestrian" or reason == "signal" or reason == "Sensor budget"
    local brake = moving and (speed == 0 and 1
        or math.max(0, math.min(urgent and 1 or 0.5, -error * (urgent and 0.25 or 0.05)))) or 0
    if throttle > 0 then brake = 0 end
    if reversing then brake = math.max(0, math.min(1, (1.5 + motion.forward) * 0.6)) end
    local handbrake = speed == 0 and not moving and not reversing and reason ~= "sliding"
    setNPCVehicleInputs(npc, steer, throttle - brake, handbrake)
    recordNPCDebugDriving(reason=="cruise" and progress.usingPreview and "Route preview" or reason, speed > 0)
    if debugging then
        local action = reversing and "reverse" or progress.reverseAt and "rear check"
            or progress.rejoinAt and "rejoin" or "follow"
        diagnostics[vehicle] = {progress.sequence, motion.lateral, progress.cruiseSpeed or 0, motion.forward,
            speed, reason, brake, action,
            math.deg(avoidAngle or 0), rear or "-"}
    end
end

local function elapsedSince(now, started)
    return (now - started) % 4294967296
end

local function runReverse(npc, vehicle, motion, progress, now, signalClosed)
    local reason, rear
    if signalClosed then
        reason = "signal"
    elseif elapsedSince(now, progress.reverseAt) >= (progress.reverseDuration or REVERSE_MS) then
        reason = "reverse complete"
    elseif sensorBudget == 0 then
        reason = "Sensor budget"
    else
        sensorBudget = sensorBudget - 1
        local width, length = vehicleExtents(vehicle)
        local speed = math.max(0, -motion.forward)
        local clearance = 2.5 + speed ^ 2 / (2 * BRAKING)
        local _, _, gap = scanBumper(vehicle, motion, -motion.fx, -motion.fy, width, length, clearance, speed)
        rear = gap == math.huge and "clear" or ("%.2f"):format(gap)
        reason = gap == math.huge and "reverse" or "rear blocked"
    end
    applyInputs(npc, vehicle, motion, progress, 0, 0, reason, 0, rear)
    if reason ~= "reverse" then
        progress.reverseAt, progress.stalledAt = nil, nil
        progress.rejoinAt = now
        samples[vehicle] = nil
    end
end

local function speedForAngle(angle, start, finish)
    angle = math.abs(math.atan2(math.sin(angle), math.cos(angle)))
    local fraction = math.max(0, math.min(1, (angle - start) / (finish - start)))
    return 1 - 0.6 * fraction
end

function performTask.driveTrafficPhysics(npc, task, elapsed, progress)
    local vehicle = getPedOccupiedVehicle(npc)
    if isElementFrozen(vehicle) then setNPCVehicleInputs(npc, 0, 0, false) return end
    local motion = getNPCTrafficPhysicsMotion(vehicle)
    if not motion then stopAllNPCActions(npc) return end
    local now = getTickCount()
    local x, y, z, fx, fy = motion.x, motion.y, motion.z, motion.fx, motion.fy
    local start = math.max(1, (progress.sequence or task[2]) - task[2] + 1)
    if progress.reverseAt then
        local lane = task[5][start]
        local signalClosed = lane and isNPCTrafficSignalClosed(lane[9])
            and (lane[3] - x) * lane[6] + (lane[4] - y) * lane[7] >= 0
        runReverse(npc, vehicle, motion, progress, now, signalClosed)
        return
    end
    if progress.rejoinAt and motion.forward < -0.1 then
        applyInputs(npc, vehicle, motion, progress, 0, 0, "settling")
        return
    end
    local index = getNPCTrafficPhysicsIndex(task, start, motion)
    local lane = task[5][index]
    local onRoute = lane and isNPCTrafficPhysicsOnRoute(task, index, x, y, z)
    if lane and not motion.unstable and not onRoute then
        local rejoin = findNPCTrafficPhysicsRejoin(task, index, x, y, z, fx, fy)
        if rejoin then index, lane, onRoute = rejoin, task[5][rejoin], true end
    end
    local sequence = task[2] + index - 1
    if progress.sequence ~= sequence then progress.stalledAt = nil end
    progress.sequence = sequence
    progress.usingPreview = index>1 and lane~=nil
    if motion.unstable or not onRoute then
        progress.stalledAt = nil
        applyInputs(npc, vehicle, motion, progress, 0, 0, motion.unstable and "sliding" or not lane and "Awaiting route" or "route")
        return
    end

    local dx, dy = lane[3] - x, lane[4] - y
    local distance = math.sqrt(dx * dx + dy * dy)
    local remainingPath=distance
    for i=index+1,#task[5] do
        local a,b=task[5][i-1],task[5][i]
        remainingPath=remainingPath+math.sqrt((a[3]-b[3])^2+(a[4]-b[4])^2)
    end
    local last=task[2]+#task[5]-1
    if remainingPath<math.max(task[3],motion.forward) and (progress.hintedFirst~=task[2] or progress.hintedLast~=last) then
        progress.hintedFirst,progress.hintedLast=task[2],last
        triggerEvent("npc_hlc:onRouteLow",vehicle,task[2],last)
    end
    local forward = math.atan2(fy, fx)
    local direct = distance > 0.01 and math.atan2(dy, dx) - forward or 0
    if distance <= 40 then dx, dy = dx - 0.4 * distance * lane[6], dy - 0.4 * distance * lane[7] end
    recordNPCDebugTarget(npc, x + dx, y + dy, lane[5])
    local length = math.sqrt(dx * dx + dy * dy)
    local routeX, routeY = lane[6], lane[7]
    if length > 0.01 then routeX, routeY = dx / length, dy / length end
    local limit = getElementData(vehicle, "npchlc_traffic:steeringLimit", false)
    if type(limit) ~= "number" or not (limit > 0 and limit <= 1) then limit = 0.5 end
    if motion.vx ^ 2 + motion.vy ^ 2 > (0.45 * 50) ^ 2 then limit = 0.2 end
    if not progress.steeringLock then
        local handling = getVehicleHandling(vehicle)
        progress.steeringLock = handling and handling.steeringLock and math.rad(handling.steeringLock) or 0.5
    end
    local step = math.min(elapsed or 16, 100) * getGameSpeed()
    local multiplier = getNPCTrafficDriveMultiplier(vehicle, lane[8], step)
    progress.cruiseSpeed = task[3] * multiplier
    local speed, reason = progress.cruiseSpeed * speedForAngle(direct, 0.4, 1.2), "cruise"
    local nextLane = task[5][index + 1]
    if nextLane and distance <= 40 then
        local bend = math.atan2(nextLane[7], nextLane[6]) - math.atan2(lane[7], lane[6])
        local bendSpeed = progress.cruiseSpeed * speedForAngle(bend, 0.1, 1.2)
        local approachSpeed = math.sqrt(bendSpeed ^ 2 + 2 * BRAKING * math.max(0, distance - 5))
        if approachSpeed < speed then speed, reason = approachSpeed, "bend" end
    end
    local remaining = (lane[3] - x) * lane[6] + (lane[4] - y) * lane[7]
    local signalClosed = remaining >= 0 and isNPCTrafficSignalClosed(lane[9])
    if signalClosed then
        local signalSpeed = stopSpeed(remaining - 6, 0, motion.forward)
        if signalSpeed < speed then speed, reason = signalSpeed, "signal" end
    end
    local obstacle, cause, avoidAngle = trafficLimit(vehicle, motion, routeX, routeY, task, index,
        not signalClosed and remaining > AVOID_DISTANCE)
    if obstacle < speed then speed, reason = obstacle, cause end
    if not nextLane then
        local terminalSpeed=math.sqrt(2*BRAKING*remainingPath)
        if terminalSpeed<speed then speed,reason=terminalSpeed,"Awaiting route" end
    end
    -- Random-created VCS cruise cars are excluded from the short reverse
    -- used by other missions. 0x0042A364 permits a 400 ms reverse after a
    -- thirty-second stall for one fixed seed class. Keep queued cars at red.
    local ambientReverse = getElementData(vehicle, "npchlc_traffic:stuckReverse", false)
    local ps2Cruise = type(ambientReverse) == "number"
    local waiting = reason == "obstacle" or ps2Cruise and reason == "following"
    if not signalClosed and waiting and speed == 0 and ambientReverse ~= 0
        and motion.vx ^ 2 + motion.vy ^ 2 < (ps2Cruise and 0.9^2 or 0.6^2) then
        if not progress.stalledAt or (x - progress.stalledX) ^ 2 + (y - progress.stalledY) ^ 2 > 0.5 ^ 2 then
            progress.stalledAt, progress.stalledX, progress.stalledY = now, x, y
        elseif elapsedSince(now, progress.stalledAt) >= (ps2Cruise and 30000 or STALL_MS) then
            progress.reverseDuration = ps2Cruise and ambientReverse or REVERSE_MS
            progress.reverseAt = now
            if ps2Cruise then triggerEvent("npc_hlc:onCruiseStuck", vehicle) end
            runReverse(npc, vehicle, motion, progress, now, false)
            return
        end
    else
        progress.stalledAt = nil
    end
    if progress.rejoinAt then
        if elapsedSince(now, progress.rejoinAt) < 2000 then
            if speed > RECOVERY_SPEED then speed, reason = RECOVERY_SPEED, "rejoin" end
        else
            progress.rejoinAt = nil
        end
    end
    local angle = forward - math.atan2(routeY, routeX) - avoidAngle
    angle = math.atan2(math.sin(angle), math.cos(angle))
    local steer = math.max(-1, math.min(1, math.max(-limit, math.min(limit, angle)) / math.max(0.01, progress.steeringLock)))
    applyInputs(npc, vehicle, motion, progress, steer, speed, reason, avoidAngle, nil, step)
end

addCommandHandler("trafficphysicsdebug", function()
    debugging = not debugging
    if not debugging then diagnostics = setmetatable({}, {__mode = "k"}) end
    outputChatBox("Traffic physics debug " .. (debugging and "on" or "off"))
end)

setTimer(function()
    if not debugging then return end
    local x, y, z = getElementPosition(localPlayer)
    local closest, distance
    for vehicle, sample in pairs(diagnostics) do
        if isElement(vehicle) and isElementSyncer(vehicle) then
            local px, py, pz = getElementPosition(vehicle)
            local squared = (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2
            if squared < (distance or 30 ^ 2) then closest, distance = sample, squared end
        end
    end
    if closest then
        outputDebugString(("Traffic physics owner=%s segment=%d lateral=%.2f cruise=%.2f actual=%.2f target=%.2f reason=%s brake=%.2f action=%s avoid=%.0f rear=%s")
            :format(getPlayerName(localPlayer), unpack(closest)))
    end
end, 500, 0)
