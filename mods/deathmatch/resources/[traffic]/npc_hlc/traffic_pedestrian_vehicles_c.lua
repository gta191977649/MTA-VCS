local motion = setmetatable({}, {__mode = "k"})

local function vehicleMoves(vehicle, x, y, now)
    local vx, vy = getElementVelocity(vehicle)
    if not isElementFrozen(vehicle) then return vx * vx + vy * vy > 0.03 ^ 2 end
    if not getElementData(vehicle, "npchlc_traffic:rail", false) then return false end
    local sample = motion[vehicle]
    if not sample then
        motion[vehicle] = {x = x, y = y, time = now, moving = true}
        return true
    end
    local elapsed = (now - sample.time) % 4294967296
    if elapsed >= 150 then
        local moved = (x - sample.x) ^ 2 + (y - sample.y) ^ 2
        sample.moving = moved > (elapsed * 0.0015) ^ 2
        sample.x, sample.y, sample.time = x, y, now
    end
    return sample.moving
end

local function bounds(vehicle, z)
    local matrix = getElementMatrix(vehicle)
    local x1, y1, z1, x2, y2, z2 = getElementBoundingBox(vehicle)
    if not matrix or not x1 then return end
    local x, y, height = unpack(matrix[4])
    if z < height + z1 - 0.3 or z > height + z2 + 0.45 then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.1 then return end
    return {x = x, y = y, fx = fx / length, fy = fy / length,
        minX = x1 - 0.35, minY = y1 - 0.35, maxX = x2 + 0.35, maxY = y2 + 0.35}
end

local function pointInVehicleSpace(box, x, y)
    x, y = x - box.x, y - box.y
    return {x * box.fy - y * box.fx, x * box.fx + y * box.fy}
end

local function interval(position, delta, low, high)
    if math.abs(delta) < 0.0001 then
        if low <= position and position <= high then return -math.huge, math.huge end
        return
    end
    local a, b = (low - position) / delta, (high - position) / delta
    return math.min(a, b), math.max(a, b)
end

local function hits(box, a, b)
    local sx, ex = interval(a[1], b[1] - a[1], box.minX, box.maxX)
    local sy, ey = interval(a[2], b[2] - a[2], box.minY, box.maxY)
    if sx and sy then
        local first = math.max(0, sx, sy)
        if first <= math.min(1, ex, ey) then return first end
    end
end

function findNPCTrafficVehicleInPath(npc, x, y, z, dx, dy, distance, target)
    local lookahead = math.min(distance, 3.6)
    local nearby = getElementsWithinRange(x, y, z, 9, "vehicle", getElementInterior(npc), getElementDimension(npc)) or {}
    local nearest, closest, nearestBox
    for _, vehicle in ipairs(nearby) do
        if vehicle ~= target and isElementStreamedIn(vehicle) then
            local box = bounds(vehicle, z)
            if box then
                local start = pointInVehicleSpace(box, x, y)
                local target = pointInVehicleSpace(box, x + dx * lookahead, y + dy * lookahead)
                local entry = hits(box, start, target)
                -- A just-exited driver can already stand in the clearance
                -- margin. A step away from that face does not enter the car.
                local outward = entry==0 and (
                    start[1]<=box.minX+.35 and target[1]<start[1] or
                    start[1]>=box.maxX-.35 and target[1]>start[1] or
                    start[2]<=box.minY+.35 and target[2]<start[2] or
                    start[2]>=box.maxY-.35 and target[2]>start[2])
                if entry and not outward and (not closest or entry < closest) then
                    nearest, closest, nearestBox = vehicle, entry, box
                end
            end
        end
    end
    return nearest, nearestBox
end

local function distance(a, b)
    return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
end

function planNPCTrafficWalkRoundCar(vehicle, box, x, y, dx, dy, remaining, now, canWalk)
    if vehicleMoves(vehicle, box.x, box.y, now) then return nil, true end
    local start = pointInVehicleSpace(box, x, y)
    local supportX = math.abs(dx * box.fy - dy * box.fx) * math.max(-box.minX, box.maxX)
    local supportY = math.abs(dx * box.fx + dy * box.fy) * math.max(-box.minY, box.maxY)
    local ahead = (box.x - x) * dx + (box.y - y) * dy
    local exitDistance = math.min(remaining, math.max(1, ahead + supportX + supportY + 0.8))
    local goal = pointInVehicleSpace(box, x + dx * exitDistance, y + dy * exitDistance)
    local corners = {{box.minX - 0.25, box.minY - 0.25}, {box.maxX + 0.25, box.minY - 0.25},
        {box.maxX + 0.25, box.maxY + 0.25}, {box.minX - 0.25, box.maxY + 0.25}}
    local options = {}
    for first, corner in ipairs(corners) do
        if not hits(box, start, corner) then
            for sign = -1, 1, 2 do
                local index = first
                local path, cost = {}, distance(start, corner)
                for _ = 1, 3 do
                    path[#path + 1] = corners[index]
                    if not hits(box, corners[index], goal) then
                        options[#options + 1] = {path = path, cost = cost + distance(corners[index], goal)}
                        break
                    end
                    local nextIndex = (index + sign - 1) % 4 + 1
                    cost = cost + distance(corners[index], corners[nextIndex])
                    index = nextIndex
                end
            end
        end
    end
    table.sort(options, function(a, b) return a.cost < b.cost end)
    for _, option in ipairs(options) do
        local points, px, py = {}, x, y
        for index = 1, #option.path + 1 do
            local corner = option.path[index] or goal
            local tx = box.x + corner[1] * box.fy + corner[2] * box.fx
            local ty = box.y - corner[1] * box.fx + corner[2] * box.fy
            if not canWalk(px, py, tx, ty) then break end
            points[index], px, py = {tx, ty}, tx, ty
        end
        if #points == #option.path + 1 then
            return {vehicle = vehicle, box = box, points = points, index = 1, checked = now}
        end
    end
end

function isNPCTrafficCarDetourValid(detour, z, now)
    local vehicle, original = detour.vehicle, detour.box
    if not isElement(vehicle) or not isElementStreamedIn(vehicle) then return false end
    local box = bounds(vehicle, z)
    return box and (box.x - original.x) ^ 2 + (box.y - original.y) ^ 2 < 0.4 ^ 2
        and box.fx * original.fx + box.fy * original.fy > 0.98
        and not vehicleMoves(vehicle, box.x, box.y, now)
end
