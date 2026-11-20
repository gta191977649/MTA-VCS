local progressByVehicle = setmetatable({}, {__mode = "k"})
local windowByVehicle = setmetatable({}, {__mode = "k"})
local multiplierByVehicle = setmetatable({}, {__mode = "k"})
local points = {2, 5, 8, 11, 18, 22}
local signals = {15, 17, 21}
local geometrySize = {16, 20, 24}
local speedMultipliers = {[0] = 1, 1.5, 2, 1}

local function segmentCount(task)
    return #task >= 24 and 3 or #task >= 20 and 2 or 1
end

-- 0x0042A818 reads the class for ordinary cruise and interpolates its multiplier.
function getNPCTrafficDriveMultiplier(vehicle, class, elapsed)
    local current = multiplierByVehicle[vehicle] or 1
    local target = speedMultipliers[class] or 1
    local step = elapsed * 0.0005
    local multiplier = current < target and math.min(target, current + step) or math.max(target, current - step)
    multiplierByVehicle[vehicle] = multiplier
    return multiplier
end

local function axis(a, b, c, d, t)
    local tangent = c - a
    local quadratic = 2 * a - 5 * b + 4 * c - d
    local cubic = 3 * b - a - 3 * c + d
    return b + t * (tangent + t * (quadratic + t * cubic)) * 0.5,
        (tangent + t * (2 * quadratic + t * 3 * cubic)) * 0.5
end

-- PS2 SLUS_215.90 0x00318870 advances between the middle two lane centres.
function sampleNPCTrafficRail(task, t, segment)
    segment = segment or 1
    local a, b, c, d = points[segment], points[segment + 1], points[segment + 2], points[segment + 3]
    local x, dx = axis(task[a], task[b], task[c], task[d], t)
    local y, dy = axis(task[a + 1], task[b + 1], task[c + 1], task[d + 1], t)
    local z, dz = axis(task[a + 2], task[b + 2], task[c + 2], task[d + 2], t)
    return x, y, z, dx, dy, dz
end

local function distanceToRail(task, t, x, y, segment)
    local px, py = sampleNPCTrafficRail(task, t, segment)
    return (px - x) ^ 2 + (py - y) ^ 2
end

local function project(task, x, y, segment)
    local best, distance = 0, distanceToRail(task, 0, x, y, segment)
    -- 0x003181D0 samples every 0.05. Refine around the closest sample
    -- to keep the vehicle in place when the MTA sync owner changes.
    for step = 1, 20 do
        local t = step * 0.05
        local candidate = distanceToRail(task, t, x, y, segment)
        if candidate < distance then best, distance = t, candidate end
    end
    local low, high = math.max(0, best - 0.05), math.min(1, best + 0.05)
    for _ = 1, 9 do
        local left, right = (2 * low + high) / 3, (low + 2 * high) / 3
        if distanceToRail(task, left, x, y, segment) < distanceToRail(task, right, x, y, segment) then high = right
        else low = left end
    end
    local t = (low + high) * 0.5
    local refined = distanceToRail(task, t, x, y, segment)
    if refined < distance then return t, refined end
    return best, distance
end

function projectNPCTrafficRailStart(task, x, y)
    local t = project(task, x, y, 1)
    return sampleNPCTrafficRail(task, t, 1)
end

function getNPCTrafficRailDebugPoints(task)
    local samples = {}
    for segment = 1, math.min(2, segmentCount(task)) do
        for step = 0, 8 do
            local x, y, z = sampleNPCTrafficRail(task, step / 8, segment)
            samples[#samples + 1] = {x, y, z}
        end
    end
    return samples
end

-- 0x00318528 measures the horizontal spline at 0.05 intervals. 0x002D1230
-- and 0x0047FCC8 use that length to time the entire segment.
local function railLength(task, segment, lengths)
    if lengths[segment] then return lengths[segment] end
    local x, y = sampleNPCTrafficRail(task, 0, segment)
    local length = 0
    for step = 1, 20 do
        local nx, ny = sampleNPCTrafficRail(task, step * 0.05, segment)
        length = length + math.sqrt((nx - x) ^ 2 + (ny - y) ^ 2)
        x, y = nx, ny
    end
    lengths[segment] = math.max(0.01, length)
    return lengths[segment]
end

local function advanceAlongRail(task, segment, t, lengths, distance)
    local length = railLength(task, segment, lengths)
    local count = segmentCount(task)
    while segment < count and distance > (1 - t) * length do
        distance = distance - (1 - t) * length
        segment, t = segment + 1, 0
        length = railLength(task, segment, lengths)
    end
    return segment, math.min(1, t + distance / length)
end

function getNPCTrafficRailPreview(task, segment, t, lengths, distance)
    segment, t = advanceAlongRail(task, segment, t, lengths, distance)
    return sampleNPCTrafficRail(task, t, segment)
end

-- Refresh the window after the first segment. The current sync owner can
-- keep moving on the two segments already received while the update is sent.
function hasCompletedNPCTrafficRail(vehicle, task, authoritative)
    local x, y = getElementPosition(vehicle)
    local count = segmentCount(task)
    local goal = points[count + 2]
    if not authoritative or count == 1 then
        local progress = progressByVehicle[vehicle]
        if progress and progress.task == task and progress.segment < count then return false end
        return (task[goal] - x) ^ 2 + (task[goal + 1] - y) ^ 2 <= 0.25 ^ 2
    end

    local progress = progressByVehicle[vehicle]
    if progress and progress.task == task and (progress.x - x) ^ 2 + (progress.y - y) ^ 2 < 0.04 then
        return progress.segment > 1
    end
    local cached = windowByVehicle[vehicle]
    if cached and cached.task == task and cached.x == x and cached.y == y then return false end
    windowByVehicle[vehicle] = {task = task, x = x, y = y}
    local _, firstDistance = project(task, x, y, 1)
    if firstDistance < 0.04 then return false end
    for segment = 2, count do
        local t, distance = project(task, x, y, segment)
        if t > 0 and distance < 2.25 and distance < firstDistance then return true end
    end
    return false
end

local function restoreProgress(task, x, y, previous)
    local count = segmentCount(task)
    if previous then
        local start, goal = points[previous.segment + 1], points[previous.segment + 2]
        local old = previous.task
        for segment = 1, count do
            local a, b = points[segment + 1], points[segment + 2]
            if task[a] == old[start] and task[a + 1] == old[start + 1]
                and task[b] == old[goal] and task[b + 1] == old[goal + 1] then
                return segment, project(task, x, y, segment)
            end
        end
    end
    local closest, t, distance = 1, project(task, x, y, 1)
    for segment = 2, count do
        local candidate, errorSquared = project(task, x, y, segment)
        if errorSquared < distance then closest, t, distance = segment, candidate, errorSquared end
    end
    return closest, t
end

function getNPCTrafficRailSegment(task, x, y, z, fx, fy)
    if not z then return restoreProgress(task, x, y) end
    local closest, score = 1, math.huge
    for segment = 1, segmentCount(task) do
        local t, distance = project(task, x, y, segment)
        local _, _, height, dx, dy = sampleNPCTrafficRail(task, t, segment)
        local length = math.sqrt(dx * dx + dy * dy)
        local agreement = length > 0 and (dx * fx + dy * fy) / length or 0
        local candidate = distance + (z - height) ^ 2 + 4 * (1 - agreement)
        if candidate < score then closest, score = segment, candidate end
    end
    return closest
end

function isNPCTrafficSignalClosed(group)
    if group == 0 then return false end
    local state = getTrafficLightState()
    if state == 5 or state == 6 or state == 9 then return false end
    if group == 1 then return state ~= 0 and state ~= 8 end
    return state ~= 3 and state ~= 7
end

local function railSignalBlocked(task, segment, x, y)
    local goal = points[segment + 2]
    return isNPCTrafficSignalClosed(task[signals[segment]])
        and (task[goal] - x) ^ 2 + (task[goal + 1] - y) ^ 2 < 64
end

function isNPCTrafficRailWaitingForSignal(task, x, y, z, fx, fy)
    return railSignalBlocked(task, getNPCTrafficRailSegment(task, x, y, z, fx, fy), x, y)
end

function advanceNPCTrafficRail(vehicle, task, elapsed, limitSpeed, boat)
    local x, y, z = getElementPosition(vehicle)
    local progress = progressByVehicle[vehicle]
    if not progress or progress.task ~= task or (x - progress.x) ^ 2 + (y - progress.y) ^ 2 > 1 then
        local segment, t = restoreProgress(task, x, y, progress)
        progress = {task = task, segment = segment, t = t, lengths = {}, x = x, y = y,
            speed = progress and progress.speed or task[14]}
        progressByVehicle[vehicle] = progress
    end
    local segment, t = progress.segment, progress.t
    local count = segmentCount(task)
    -- Project actual displacement locally. A blocked car cannot advance its
    -- task just because another render frame elapsed.
    local px, py, _, dx, dy = sampleNPCTrafficRail(task, t, segment)
    local tangentSquared = dx * dx + dy * dy
    if tangentSquared > 0.0001 then
        t = math.max(0, math.min(1, t + ((x - px) * dx + (y - py) * dy) / tangentSquared))
    end
    if t >= 0.9999 and segment < count then
        segment = segment + 1
        t = project(task, x, y, segment)
    end
    progress.segment, progress.t, progress.x, progress.y = segment, t, x, y
    px, py, _, dx, dy = sampleNPCTrafficRail(task, t, segment)
    local tangent = math.max(0.1, math.sqrt(dx * dx + dy * dy))
    local speed = task[14] * getNPCTrafficDriveMultiplier(vehicle, task[geometrySize[count] + segment], elapsed)
    if railSignalBlocked(task, segment, x, y) then speed = 0 end
    if limitSpeed then
        local ax, ay, az = sampleNPCTrafficRail(task, math.min(1, t + 5 / tangent), segment)
        local limit, emergency = limitSpeed(vehicle, x, y, z, ax, ay, az, dx / tangent, dy / tangent,
            task[16], task, segment, t, progress.lengths, progress.speed)
        speed = math.min(speed, limit)
        if emergency then progress.speed = math.min(progress.speed, speed) end
    end
    -- 0x00434178 uses 0.05 acceleration and 0.7 deceleration per game time step.
    local step = elapsed * 0.05
    progress.speed = speed >= progress.speed and math.min(speed, progress.speed + step * 0.05)
        or math.max(speed, progress.speed - step * 0.7)
    local _, _, vz = getElementVelocity(vehicle)
    local look = boat and math.max(2.5, progress.speed * 0.45) or math.max(0.5, progress.speed * 0.16)
    local nx, ny, nz, nextDX, nextDY = getNPCTrafficRailPreview(task, segment, t, progress.lengths, look)
    local tx, ty = nx - x, ny - y
    local distance = math.sqrt(tx * tx + ty * ty)
    if distance < 0.001 or progress.speed <= 0 then
        setElementVelocity(vehicle, 0, 0, vz)
        return
    end
    if localPlayer and recordNPCDebugTarget then recordNPCDebugTarget(vehicle, nx, ny, nz) end
    local speedMS = progress.speed
    if segment == count then
        local goal = points[count + 2]
        local remaining = math.sqrt((task[goal] - x)^2 + (task[goal+1] - y)^2)
        speedMS = math.min(speedMS, remaining * 1000 / math.max(1, elapsed))
    end
    if boat then
        exports.vcs_vehicle:steerBoatTraffic(vehicle, tx / distance, ty / distance, dx, dy, nextDX, nextDY, look, speedMS, vz, elapsed)
        return
    end
    setElementVelocity(vehicle, tx / distance * speedMS / 50, ty / distance * speedMS / 50, vz)
    local _, _, heading = getElementRotation(vehicle)
    local error = (-math.atan2(tx, ty) - math.rad(heading) + math.pi) % (2 * math.pi) - math.pi
    local wx, wy = getElementAngularVelocity(vehicle)
    setElementAngularVelocity(vehicle, wx, wy, math.max(-0.08, math.min(0.08, error * 0.16)))
end
