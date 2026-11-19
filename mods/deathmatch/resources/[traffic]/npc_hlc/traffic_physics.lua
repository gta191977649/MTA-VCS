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
        unstable = forward < -0.8 or math.abs(lateral) > math.max(1.5, forward * 0.45)}
end

-- Traffic physics task: first sequence, base speed, previous lane centre,
-- then up to three records with link, lane, centre, unit heading, class and signal.
function normalizeNPCTrafficPhysics(task)
    local first, speed, anchor, segments = task[2], task[3], task[4], task[5]
    local function finite(value)
        return type(value) == "number" and value > -math.huge and value < math.huge
    end
    if #task ~= 5 or not finite(first) or first < 1 or first % 1 ~= 0
        or not finite(speed) or speed <= 0 or type(anchor) ~= "table" or #anchor ~= 3
        or type(segments) ~= "table" or #segments < 1 or #segments > 3 then return false end
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
    return {task[1], first, speed, {unpack(anchor)}, copy}
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
        if isNPCTrafficSignalClosed(current[9]) and past <= 0 then break end
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

function canNPCTrafficPhysicsAvoid(task, index, x, y, z, dx, dy, distance, halfWidth)
    local margin = laneTolerance - halfWidth
    if margin <= 0 then return false end
    return routeDistance(task, index, x, y, z) <= margin ^ 2
        and routeDistance(task, index, x + dx * distance, y + dy * distance, z) <= margin ^ 2
end

function findNPCTrafficPhysicsRejoin(task, index, x, y, z, fx, fy)
    local best, distance = nil, laneTolerance ^ 2
    for nextIndex = index + 1, #task[5] do
        local previous, candidate = task[5][nextIndex - 1], task[5][nextIndex]
        if isNPCTrafficSignalClosed(previous[9])
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
    return findNPCTrafficPhysicsRejoin(task, 1, motion.x, motion.y, motion.z, motion.fx, motion.fy)
end
