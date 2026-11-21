local corridor = 14
local verticalTolerance = 7
local laneTolerance = 2.5
local headingTolerance = 0.35

function getNPCTrafficPhysicsMotion(actor)
    local matrix = getElementMatrix(actor)
    if not matrix then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.1 then return end
    fx, fy = fx / length, fy / length
    local vx, vy = getElementVelocity(actor)
    vx, vy = vx * 50, vy * 50
    local forward, lateral = vx * fx + vy * fy, vx * fy - vy * fx
    return {x = matrix[4][1], y = matrix[4][2], z = matrix[4][3], fx = fx, fy = fy,
        grade = matrix[2][3] / length, vx = vx, vy = vy, forward = forward, lateral = lateral,
        unstable = matrix[3][3] < 0.35 or forward < -0.8 or math.abs(lateral) > math.max(1.5, forward * 0.45)}
end

-- Traffic physics task: first sequence, base speed, previous lane centre,
-- then up to eight records with link, lane, centre, unit heading, class and signal.
function normalizeNPCTrafficPhysics(task)
    local first, speed, anchor, segments = task[2], task[3], task[4], task[5]
    local function finite(value)
        return type(value) == "number" and value > -math.huge and value < math.huge
    end
    if (#task ~= 5 and not (#task == 6 and isNPCTrafficDrivingStyle(task[6]))) or not finite(first) or first < 1 or first % 1 ~= 0
        or not finite(speed) or speed <= 0 or type(anchor) ~= "table" or #anchor ~= 3
        or type(segments) ~= "table" or #segments < 1 or #segments > 8 then return false end
    for i = 1, 3 do if not finite(anchor[i]) then return false end end
    local copy = {}
    for i = 1, #segments do
        local segment = segments[i]
        if type(segment) ~= "table" or #segment ~= 9 then return false end
        for j = 1, 9 do if not finite(segment[j]) then return false end end
        local link, lane, _, _, _, dx, dy, class, signal = unpack(segment)
        if link < 0 or link % 1 ~= 0 or lane < 0 or lane > 6 or lane % 1 ~= 0
            or math.abs(dx * dx + dy * dy - 1) > 0.01
            or class < 0 or class > 3 or class % 1 ~= 0
            or signal < 0 or signal > 2 or signal % 1 ~= 0 then return false end
        copy[i] = {unpack(segment)}
    end
    local normalized={task[1], first, speed, {unpack(anchor)}, copy, task[6]}
    if task.mission==true then normalized.mission=true end
    return normalized
end

local function distanceToSegment(x, y, z, ax, ay, az, segment)
    local dx, dy = segment[3] - ax, segment[4] - ay
    local squared = dx * dx + dy * dy
    local t = squared > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / squared)) or 0
    if math.abs(z - (az + (segment[5] - az) * t)) > verticalTolerance then return math.huge end
    return (x - ax - dx * t) ^ 2 + (y - ay - dy * t) ^ 2
end

-- 0x00438A80 advances near the lane centre or upon passing it towards the
-- next link. Bound the forward test to the route corridor after an MTA impact.
function getNPCTrafficPhysicsIndex(task, index, motion)
    if not motion or motion.unstable or motion.forward < -0.1 then return index end
    local x, y, z, fx, fy = motion.x, motion.y, motion.z, motion.fx, motion.fy
    local segments = task[5]
    while index <= #segments do
        local current, following = segments[index], segments[index + 1]
        local px, py = x - current[3], y - current[4]
        local squared = px * px + py * py
        local past = px * current[6] + py * current[7]
        if isNPCTrafficSignalClosed(current[9], task[6]) and past <= 0 then break end
        local aligned = fx * current[6] + fy * current[7] > headingTolerance
            and math.abs(px * current[7] - py * current[6]) <= laneTolerance
        local passed = squared < 25 and aligned
        if following then
            local dx, dy = following[3] - current[3], following[4] - current[4]
            local ahead = px * dx + py * dy
            local nextDistance = distanceToSegment(x, y, z, current[3], current[4], current[5], following)
            passed = passed or ahead > 0 and nextDistance <= laneTolerance ^ 2
                and (squared < 64 or ahead * ahead > 0.49 * squared * (dx * dx + dy * dy))
                and fx * following[6] + fy * following[7] > headingTolerance
        else
            passed = passed or past > 0 and squared < 64 and aligned
        end
        if not passed or math.abs(z - current[5]) > verticalTolerance then break end
        index = index + 1
    end
    return index
end

local function routeDistance(task, index, x, y, z)
    local previous = task[5][index - 1]
    local ax, ay, az
    if previous then ax, ay, az = previous[3], previous[4], previous[5]
    else ax, ay, az = unpack(task[4]) end
    return distanceToSegment(x, y, z, ax, ay, az, task[5][index])
end

function isNPCTrafficPhysicsOnRoute(task, index, x, y, z)
    return routeDistance(task, index, x, y, z) <= corridor ^ 2
end

function canNPCTrafficPhysicsAvoid(task, index, x, y, z, dx, dy, distance, halfWidth, passing)
    local margin = ((passing or doesNPCTrafficAvoidCars(task[6])) and 2 * laneTolerance or laneTolerance) - halfWidth
    if margin <= 0 then return false end
    return routeDistance(task, index, x, y, z) <= margin ^ 2
        and routeDistance(task, index, x + dx * distance, y + dy * distance, z) <= margin ^ 2
end

function getNPCTrafficWindowProgress(task,vehicle)
    local motion=getNPCTrafficPhysicsMotion(vehicle)
    if not motion or motion.unstable then return 1 end
    local index=getNPCTrafficPhysicsIndex(task,1,motion)
    if index==1 then
        local rejoin=findNPCTrafficPhysicsRejoin(task,1,motion.x,motion.y,motion.z,motion.fx,motion.fy)
        if rejoin then index=getNPCTrafficPhysicsIndex(task,rejoin,motion) end
    end
    return index
end

function findNPCTrafficPhysicsRejoin(task, index, x, y, z, fx, fy)
    local best, distance = nil, laneTolerance ^ 2
    for nextIndex = index + 1, #task[5] do
        local previous, candidate = task[5][nextIndex - 1], task[5][nextIndex]
        if isNPCTrafficSignalClosed(previous[9], task[6])
            and (x - previous[3]) * previous[6] + (y - previous[4]) * previous[7] <= 0 then break end
        if fx * candidate[6] + fy * candidate[7] > headingTolerance
            and (candidate[3] - x) * candidate[6] + (candidate[4] - y) * candidate[7] >= 0 then
            local error = routeDistance(task, nextIndex, x, y, z)
            if error < distance then best, distance = nextIndex, error end
        end
    end
    return best
end

function getNPCTrafficPhysicsRejoin(task, actor)
    local motion = getNPCTrafficPhysicsMotion(actor)
    if not motion or motion.unstable or motion.forward < -0.1
        or isNPCTrafficPhysicsOnRoute(task, 1, motion.x, motion.y, motion.z) then return false end
    local nextLane = findNPCTrafficPhysicsRejoin(task, 1, motion.x, motion.y, motion.z, motion.fx, motion.fy)
    return nextLane or false, not nextLane and motion.vx^2 + motion.vy^2 < 1
end

-- Bounds are relative to the model origin. Use their centre so long hoods
-- and rear overhangs have the same footprint on the client and server.
function getNPCTrafficModelFootprint(vehicle, left, rear, _, right, front)
    local matrix = getElementMatrix(vehicle)
    if not matrix then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local norm = math.sqrt(fx*fx + fy*fy)
    if norm < 0.01 then return end
    fx, fy = fx/norm, fy/norm
    if not (left and rear and right and front) then left, rear, right, front = -1, -2, 1, 2 end
    local x, y, z = matrix[4][1], matrix[4][2], matrix[4][3]
    local side, along = (left+right)/2, (rear+front)/2
    return {vehicle=vehicle, x=x+fy*side+fx*along, y=y-fx*side+fy*along, z=z, fx=fx, fy=fy,
        width=(right-left)/2, length=(front-rear)/2, offsetX=side, offsetY=along}
end

local function contactInterval(p, v, radius, first, last)
    if math.abs(v) < 0.00001 then
        if math.abs(p) <= radius then return first, last end
        return
    end
    local a, b = (-radius-p)/v, (radius-p)/v
    first, last = math.max(first, math.min(a,b)), math.min(last, math.max(a,b))
    if first <= last then return first, last end
end

-- Swept separating-axis test. Both rectangles must overlap along all four
-- axes at the same instant within the supplied interval.
function getNPCTrafficFootprintContact(rx, ry, vx, vy, fx, fy, width, length, other, horizon)
    local ox, oy = other.fx, other.fy
    local dot, cross = math.abs(fx*ox + fy*oy), math.abs(fx*oy - fy*ox)
    local first, last = contactInterval(rx*fy-ry*fx, vx*fy-vy*fx,
        width + dot*other.width + cross*other.length, 0, horizon)
    if not first then return end
    first, last = contactInterval(rx*fx+ry*fy, vx*fx+vy*fy,
        length + dot*other.length + cross*other.width, first, last)
    if not first then return end
    first, last = contactInterval(rx*oy-ry*ox, vx*oy-vy*ox,
        other.width + dot*width + cross*length, first, last)
    if not first then return end
    return contactInterval(rx*ox+ry*oy, vx*ox+vy*oy,
        other.length + dot*length + cross*width, first, last)
end

-- Validate a stopped sync owner's reported blocker against the server route.
-- The two stationary cars have no relative velocity until the first advances.
function isNPCTrafficHeadOnBlocked(task, vehicle, blocker, ownBounds, otherBounds)
    local own = getNPCTrafficModelFootprint(vehicle, unpack(ownBounds))
    local other = getNPCTrafficModelFootprint(blocker, unpack(otherBounds))
    if not own or not other then return false end
    local x, y, z = getElementPosition(vehicle)
    local rail = task[1] == "driveTrafficRail"
    local segment, t, steerX, steerY
    local lengths = {}
    if rail then
        segment, t = getNPCTrafficRailSegment(task, x, y)
    else
        local lane = task[5][getNPCTrafficWindowProgress(task, vehicle)]
        if not lane then return false end
        local dx, dy = lane[3]-x, lane[4]-y
        local remaining = math.sqrt(dx*dx+dy*dy)
        if remaining <= 40 then dx,dy = dx-0.4*remaining*lane[6],dy-0.4*remaining*lane[7] end
        local norm = math.sqrt(dx*dx+dy*dy)
        if norm < 0.01 then return false end
        steerX, steerY = dx/norm, dy/norm
    end
    local startX, startY = x, y
    for distance = 2, 14, 2 do
        local px, py, pz
        if rail then
            px, py, pz = getNPCTrafficRailPreview(task, segment, t, lengths, distance)
        else
            px, py, pz = x+steerX*distance, y+steerY*distance, z
        end
        local dx, dy = px-startX, py-startY
        local span = math.sqrt(dx*dx+dy*dy)
        if span < 0.001 then break end
        local fx, fy = dx/span, dy/span
        local cx = startX + fy*own.offsetX + fx*own.offsetY
        local cy = startY - fx*own.offsetX + fy*own.offsetY
        if math.abs(other.z-pz) < 2.8 and getNPCTrafficFootprintContact(other.x-cx, other.y-cy,
            -fx,-fy,fx,fy,own.width,own.length,other,span) then return true end
        startX, startY = px, py
    end
    return false
end
