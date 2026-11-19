local SCAN_MS = 200
local SCAN_RADIUS = 3.2
local PASS_DISTANCE = 0.65
local SIDE_STEP = 0.85
local WALK_SPEED = 1.25

local function ground(ped, x, y, z)
    local hit, _, _, height, _, _, _, normalZ = processLineOfSight(x, y, z + 0.2, x, y, z - 1.25,
        true, false, false, true, false, false, false, false, ped)
    if hit and (not normalZ or normalZ >= 0.7) then return height end
end

local function clearStep(ped, x, y, z, tx, ty, floor, checkVehicles)
    if not floor or not isLineOfSightClear(x, y, z + 0.15, tx, ty, z + 0.15,
        true, checkVehicles == true, false, true, false, false, false, ped) then return false end
    local destinationFloor = ground(ped, tx, ty, z)
    return destinationFloor and math.abs(destinationFloor - floor) <= 0.25
end

local function findBlocker(npc, x, y, z, dx, dy, distance)
    local interior, dimension = getElementInterior(npc), getElementDimension(npc)
    local closest, closestTime = nil, math.huge
    local vx, vy = getElementVelocity(npc)
    local speed = math.max(WALK_SPEED, (vx * dx + vy * dy) * 50)
    for _, kind in ipairs({"ped", "player"}) do
        local nearby = getElementsWithinRange(x, y, z, SCAN_RADIUS, kind, interior, dimension) or {}
        for _, other in ipairs(nearby) do
            if other ~= npc and isElementStreamedIn(other) and not isPedDead(other) and not isPedInVehicle(other) then
                local ox, oy, oz = getElementPosition(other)
                local px, py = ox - x, oy - y
                local ahead = px * dx + py * dy
                if ahead > -0.2 and ahead <= distance + 0.5 and math.abs(oz - z) <= 0.8 then
                    local oxv, oyv = getElementVelocity(other)
                    local rx, ry = oxv * 50 - dx * speed, oyv * 50 - dy * speed
                    local relativeSpeed = rx * rx + ry * ry
                    local time = relativeSpeed > 0.01 and math.max(0, math.min(1.1, -(px * rx + py * ry) / relativeSpeed)) or 0
                    local predicted = (px + rx * time) ^ 2 + (py + ry * time) ^ 2
                    if predicted < PASS_DISTANCE ^ 2 and time < closestTime then
                        closest, closestTime = other, time
                    end
                end
            end
        end
    end
    return closest
end

local function stillBlocking(npc, other, x, y, z, dx, dy, distance)
    if not isElement(other) or not isElementStreamedIn(other) or isPedDead(other) or isPedInVehicle(other)
        or getElementInterior(other) ~= getElementInterior(npc)
        or getElementDimension(other) ~= getElementDimension(npc) then return false end
    local ox, oy, oz = getElementPosition(other)
    local px, py = ox - x, oy - y
    local ahead = px * dx + py * dy
    if ahead < -0.2 or ahead > math.min(SCAN_RADIUS, distance + 0.5)
        or math.abs(px * dy - py * dx) >= PASS_DISTANCE or math.abs(oz - z) > 0.8 then return false end
    local vx, vy = getElementVelocity(other)
    return ahead <= 1 or (vx * dx + vy * dy) * 50 < WALK_SPEED
end

local function chooseSide(npc, blocker, x, y, z, dx, dy)
    local floor = ground(npc, x, y, z)
    if not floor then return false end
    local ox, oy, oz = getElementPosition(blocker)
    local matrix = getElementMatrix(blocker)
    local headOn = getElementType(blocker) == "ped" and matrix
        and matrix[2][1] * dx + matrix[2][2] * dy < -0.7
    local otherFloor = headOn and ground(blocker, ox, oy, oz)
    local available
    for side = 1, -1, -2 do
        local sx, sy = dy * SIDE_STEP * side, -dx * SIDE_STEP * side
        local tx, ty = x + sx + dx * 0.25, y + sy + dy * 0.25
        if clearStep(npc, x, y, z, tx, ty, floor)
            and clearStep(npc, tx, ty, z, tx + dx, ty + dy, floor) then
            if not headOn or clearStep(blocker, ox, oy, oz, ox - sx - dx * 0.25, oy - sy - dy * 0.25, otherFloor) then
                return tx, ty, sx, sy
            end
            if not available then available = {tx, ty, sx, sy} end
        end
    end
    -- If only one side has room for a single pedestrian, both owners make
    -- the same decision about which direction yields.
    if available and (dx > 0.01 or math.abs(dx) <= 0.01 and dy > 0
        or not otherFloor) then return unpack(available) end
    return false
end

local function followDetour(npc, state, x, y, z, now, pace)
    local detour, blocker = state.detour, state.blocker
    if not isElement(blocker) or not isElementStreamedIn(blocker) or isPedDead(blocker)
        or isPedInVehicle(blocker) or (now - detour.started) % 4294967296 >= 2200 then return false end
    local ox, oy, oz = getElementPosition(blocker)
    local ahead = (ox - x) * detour.dx + (oy - y) * detour.dy
    if ahead < -0.45 or math.abs(oz - z) > 0.8
        or (ox - x) ^ 2 + (oy - y) ^ 2 > SCAN_RADIUS ^ 2 then return false end
    if detour.step then
        if (x - detour.x) ^ 2 + (y - detour.y) ^ 2 > 0.18 ^ 2 then
            makeNPCWalkToPos(npc, detour.x, detour.y, pace)
            return true
        end
        detour.step = false
    end
    local progress = (x - detour.x) * detour.dx + (y - detour.y) * detour.dy
    local advance = progress + math.min(1.5, math.max(0.5, ahead + 0.55))
    local tx, ty = detour.x + detour.dx * advance, detour.y + detour.dy * advance
    if not detour.checked or (now - detour.checked) % 4294967296 >= SCAN_MS then
        detour.checked = now
        if not clearStep(npc, x, y, z, tx, ty, ground(npc, x, y, z)) then return false end
    end
    makeNPCWalkToPos(npc, tx, ty, pace)
    return true
end

local function followCarDetour(npc, detour, x, y, z, now, pace)
    local point = detour.points[detour.index]
    if (x - point[1]) ^ 2 + (y - point[2]) ^ 2 <= 0.2 ^ 2 then
        detour.index = detour.index + 1
        point = detour.points[detour.index]
        if not point then return false end
    end
    if (now - detour.checked) % 4294967296 >= SCAN_MS then
        detour.checked = now
        if not isNPCTrafficCarDetourValid(detour, z, now)
            or not clearStep(npc, x, y, z, point[1], point[2], ground(npc, x, y, z), true) then return false end
    end
    makeNPCWalkToPos(npc, point[1], point[2], pace)
    return true
end

function walkNPCTrafficAroundPeds(npc, task, state, pace)
    local x, y, z = getElementPosition(npc)
    local dx, dy = task[2] - x, task[3] - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.05 then stopNPCWalkingActions(npc) return end
    dx, dy = dx / distance, dy / distance
    local now = getTickCount()
    if state.goalX ~= task[2] or state.goalY ~= task[3] or state.goalZ ~= task[4] then
        state.goalX, state.goalY, state.goalZ = task[2], task[3], task[4]
        state.detour, state.blocker, state.checked, state.waiting = nil, nil, nil, nil
        state.carDetour = nil
    end
    if state.carDetour then
        if followCarDetour(npc, state.carDetour, x, y, z, now, pace) then return end
        state.carDetour, state.checked = nil, nil
    end
    if state.detour then
        if followDetour(npc, state, x, y, z, now, pace) then return end
        state.detour, state.blocker, state.checked = nil, nil, nil
    end
    if not state.checked or (now - state.checked) % 4294967296 >= SCAN_MS then
        state.checked = now
        local vehicle, box = findNPCTrafficVehicleInPath(npc, x, y, z, dx, dy, distance)
        if vehicle then
            local floor = ground(npc, x, y, z)
            state.carDetour = planNPCTrafficWalkRoundCar(vehicle, box, x, y, dx, dy, distance, now,
                function(px, py, tx, ty) return clearStep(npc, px, py, z, tx, ty, floor, true) end)
            state.waiting, state.blocker = not state.carDetour, nil
            if state.carDetour then
                state.action = "TASK_COMPLEX_WALK_ROUND_CAR"
                followCarDetour(npc, state.carDetour, x, y, z, now, pace)
            else
                state.action = "TASK_SIMPLE_STAND_STILL"
                stopNPCWalkingActions(npc)
            end
            return
        end
        local blocker = findBlocker(npc, x, y, z, dx, dy, distance)
        if not blocker and state.waiting and stillBlocking(npc, state.blocker, x, y, z, dx, dy, distance) then
            blocker = state.blocker
        end
        state.blocker = blocker
        state.waiting = blocker ~= nil
        if blocker then
            local tx, ty = chooseSide(npc, blocker, x, y, z, dx, dy)
            if tx then
                state.detour = {x = tx, y = ty, dx = dx, dy = dy, started = now, step = true}
                state.action = "TASK_COMPLEX_AVOID_OTHER_PED_WHILE_WANDERING"
                makeNPCWalkToPos(npc, tx, ty, pace)
                return
            end
        end
    end
    if state.waiting then
        state.action = "TASK_SIMPLE_STAND_STILL"
        stopNPCWalkingActions(npc)
    else
        state.action = "TASK_SIMPLE_GO_TO_POINT"
        makeNPCWalkToPos(npc, task[2], task[3], pace)
    end
end
