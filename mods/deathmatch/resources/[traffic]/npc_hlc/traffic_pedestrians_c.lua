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

-- Search a small patch of streamed collision only when the walking corridor is blocked.
-- Coordinates are aligned with the original approach. The destination stays on the HLC task.
local CELL = 1.2
local neighbors4 = {{1,0}, {0,1}, {0,-1}, {-1,0}}

local function corridor(npc, x, y, z, tx, ty, tz, cars)
    local dx,dy = tx-x,ty-y
    local length = math.sqrt(dx*dx+dy*dy)
    if length < 0.01 then return true end
    local sx,sy = 0.30*dy/length,-0.30*dx/length
    for side = 0,2 do
        local offset = side == 2 and -1 or side
        if not isLineOfSightClear(x+offset*sx,y+offset*sy,z+0.05,tx+offset*sx,ty+offset*sy,tz+0.05,
            true,cars,false,true,false,false,false,npc) then return false end
    end
    return true
end

local function directLeg(npc,x,y,z,gx,gy,gz,cars)
    local dx,dy = gx-x,gy-y
    local length=math.sqrt(dx*dx+dy*dy)
    local t=math.min(1,3.6/math.max(0.01,length))
    return corridor(npc,x,y,z,x+dx*t,y+dy*t,z+((gz or z)-z)*t,cars)
end

local function startSearch(npc,x,y,z,dx,dy)
    local floor=ground(npc,x,y,z)
    if not floor then return end
    local origin={i=0,j=0,x=x,y=y,z=z,cost=0,score=0}
    return {x=x,y=y,dx=dx,dy=dy,height=z-floor,open={origin},seen={[0]=true},count=0}
end

local function expandSearch(npc,search,gx,gy,gz)
    for _=1,8 do
        local open=search.open
        if #open==0 or search.count>=160 then return false end
        local best=1
        for i=2,#open do if open[i].score<open[best].score then best=i end end
        local node=table.remove(open,best)
        search.count=search.count+1
        -- A short clear leg is sufficient to resume the ordinary obstacle scan.
        if node.parent and directLeg(npc,node.x,node.y,node.z,gx,gy,gz,true)
            and (node.x-gx)^2+(node.y-gy)^2 < (search.x-gx)^2+(search.y-gy)^2 then
            local points={}
            while node.parent do points[#points+1]=node;node=node.parent end
            return points
        end
        for _,step in ipairs(neighbors4) do
            local i,j=node.i+step[1],node.j+step[2]
            local key=i*64+j
            if math.abs(i)<=14 and math.abs(j)<=14 and not search.seen[key] then
                local x=search.x+CELL*(i*search.dx-j*search.dy)
                local y=search.y+CELL*(i*search.dy+j*search.dx)
                local floor=ground(npc,x,y,node.z)
                local mid=ground(npc,(node.x+x)/2,(node.y+y)/2,node.z)
                if floor and mid and math.abs(floor+search.height-node.z)<=0.45
                    and math.abs(mid+search.height-node.z)<=0.45
                    and corridor(npc,node.x,node.y,node.z,x,y,floor+search.height,true) then
                    local cost=node.cost+CELL
                    local distance=math.sqrt((gx-x)^2+(gy-y)^2)
                    open[#open+1]={i=i,j=j,x=x,y=y,z=floor+search.height,parent=node,cost=cost,score=cost+distance}
                    search.seen[key]=true
                end
            end
        end
    end
end

local function walkLocalRoute(npc,state,x,y,z,gx,gy,gz,now,pace)
    local points=state.localRoute
    local point=points and points[#points]
    if point and (point.x-x)^2+(point.y-y)^2<0.20^2 then
        points[#points]=nil
        point=points[#points]
    end
    if not point then state.localRoute,state.checked=nil,nil;return false end
    if not state.checked or (now-state.checked)%4294967296>=SCAN_MS then
        state.checked=now
        if directLeg(npc,x,y,z,gx,gy,gz,true) or not corridor(npc,x,y,z,point.x,point.y,point.z,true) then
            state.localRoute,state.checked=nil,nil
            return false
        end
    end
    state.action="Walk around obstacle"
    makeNPCWalkToPos(npc,point.x,point.y,pace)
    return true
end

local function findBlocker(npc, x, y, z, dx, dy, distance, passingReady, target)
    local interior, dimension = getElementInterior(npc), getElementDimension(npc)
    local traits = getElementData(npc,"npchlc_traffic:passing",false)
    local neighbors = {}
    local closest, closestTime = nil, math.huge
    local vx, vy = getElementVelocity(npc)
    local speed = math.max(WALK_SPEED, (vx * dx + vy * dy) * 50)
    for _, kind in ipairs({"ped", "player"}) do
        local nearby = getElementsWithinRange(x, y, z, SCAN_RADIUS, kind, interior, dimension) or {}
        for _, other in ipairs(nearby) do
            if other ~= npc and other ~= target and isElementStreamedIn(other) and not isPedDead(other) and not isPedInVehicle(other) then
                local ox, oy, oz = getElementPosition(other)
                local px, py = ox - x, oy - y
                if math.abs(oz-z) <= 0.8 then
                    neighbors[#neighbors+1] = {ped=other, x=ox, y=oy}
                end
                local ahead = px * dx + py * dy
                local eligible = true
                if traits then
                    local peer = getElementData(other,"npchlc_traffic:passing",false)
                    local identity = peer and peer[1] or (kind == "player" and 1 or 0)
                    eligible = passingReady and identity > 0 and math.floor(traits[2]/identity)%2 == 1
                        and (px-1.25*dx)^2+(py-1.25*dy)^2 <= 1
                end
                -- Physical contact still needs a free exit when anticipatory passing is masked out.
                local touching = px*px + py*py <= PASS_DISTANCE^2
                if (eligible or touching) and ahead > -0.2 and ahead <= distance + 0.5 and math.abs(oz - z) <= 0.8 then
                    local oxv, oyv = getElementVelocity(other)
                    local rx, ry = oxv * 50 - dx * speed, oyv * 50 - dy * speed
                    local relativeSpeed = rx * rx + ry * ry
                    local time = relativeSpeed > 0.01 and math.max(0, math.min(1.1, -(px * rx + py * ry) / relativeSpeed)) or 0
                    local predicted = (px + rx * time) ^ 2 + (py + ry * time) ^ 2
                    if (traits and eligible or predicted < PASS_DISTANCE ^ 2) and time < closestTime then
                        closest, closestTime = other, time
                    end
                end
            end
        end
    end
    return closest, neighbors
end

local function corridorFree(neighbors, blocker, x, y, tx, ty)
    local dx, dy = tx-x, ty-y
    for _, other in ipairs(neighbors) do
        if other.ped ~= blocker then
            local px, py = other.x-x, other.y-y
            local along = px*dx + py*dy
            -- A neighbor behind the step must not prevent walking out of an overlap.
            if along > 0 then
                local t = math.min(1, along/(dx*dx+dy*dy))
                if (px-t*dx)^2+(py-t*dy)^2 < PASS_DISTANCE^2 then return false end
            end
        end
    end
    return true
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

local function chooseSide(npc, blocker, neighbors, x, y, z, dx, dy)
    local floor = ground(npc, x, y, z)
    if not floor then return false end
    local ox, oy, oz = getElementPosition(blocker)
    local matrix = getElementMatrix(blocker)
    local headOn = getElementType(blocker) == "ped" and matrix
        and matrix[2][1] * dx + matrix[2][2] * dy < -0.7
    local otherFloor = headOn and ground(blocker, ox, oy, oz)
    local available
    local gap = (ox-x)*dx+(oy-y)*dy
    local forward = math.min(SIDE_STEP, math.max(0, gap-PASS_DISTANCE))
    local first = getElementData(npc,"npchlc_traffic:passing",false) and -1 or 1
    for side = first, -first, -2*first do
        local sx, sy = dy * SIDE_STEP * side, -dx * SIDE_STEP * side
        local tx, ty = x + sx + dx * forward, y + sy + dy * forward
        if corridorFree(neighbors, blocker, x, y, tx, ty)
            and corridorFree(neighbors, blocker, tx, ty, tx+dx, ty+dy)
            and clearStep(npc, x, y, z, tx, ty, floor)
            and clearStep(npc, tx, ty, z, tx + dx, ty + dy, floor) then
            if not headOn or clearStep(blocker, ox, oy, oz, ox - sx - dx * forward, oy - sy - dy * forward, otherFloor) then
                return tx, ty, sx, sy
            end
            if not available then available = {tx, ty, sx, sy} end
        end
    end
    -- If only one side has room for a single pedestrian, both owners make
    -- the same decision about which direction yields.
    local vx,vy = getElementVelocity(blocker)
    if available and (dx > 0.01 or math.abs(dx) <= 0.01 and dy > 0
        or not otherFloor or vx*vx+vy*vy < 0.000001) then return unpack(available) end
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

local function walkAroundPeds(npc, gx, gy, gz, state, pace, formation, target)
    local x, y, z = getElementPosition(npc)
    local dx, dy = gx - x, gy - y
    local distance = math.sqrt(dx * dx + dy * dy)
    if distance < 0.05 then stopNPCWalkingActions(npc) return end
    dx, dy = dx / distance, dy / distance
    local now = getTickCount()
    if not state.goalX or (formation and (gx-state.goalX)^2+(gy-state.goalY)^2 > 4)
        or (not formation and (state.goalX ~= gx or state.goalY ~= gy or state.goalZ ~= gz)) then
        state.goalX, state.goalY, state.goalZ = gx, gy, gz
        state.detour, state.blocker, state.checked, state.waiting = nil, nil, nil, nil
        state.carDetour,state.localRoute,state.search,state.retryAt = nil,nil,nil,nil
    end
    if state.localRoute and walkLocalRoute(npc,state,x,y,z,gx,gy,gz,now,pace) then return end
    if state.carDetour then
        if followCarDetour(npc, state.carDetour, x, y, z, now, pace) then return end
        state.carDetour, state.checked = nil, nil
    end
    if state.detour then
        if followDetour(npc, state, x, y, z, now, pace) then return end
        state.detour, state.blocker, state.checked = nil, nil, nil
    end
    local scanInterval = state.search and 50 or SCAN_MS
    if not state.checked or (now - state.checked) % 4294967296 >= scanInterval then
        state.checked = now
        local vehicle, box = findNPCTrafficVehicleInPath(npc, x, y, z, dx, dy, distance, target)
        local blockedCar = false
        if vehicle then
            local floor = ground(npc, x, y, z)
            local moving
            state.carDetour, moving = planNPCTrafficWalkRoundCar(vehicle, box, x, y, dx, dy, distance, now,
                function(px, py, tx, ty) return clearStep(npc, px, py, z, tx, ty, floor, true) end)
            state.waiting, state.blocker = not state.carDetour, nil
            if state.carDetour then
                state.action = "TASK_COMPLEX_WALK_ROUND_CAR"
                followCarDetour(npc, state.carDetour, x, y, z, now, pace)
                state.search=nil
                return
            elseif moving then
                state.action = "TASK_SIMPLE_STAND_STILL"
                stopNPCWalkingActions(npc)
                return
            end
            blockedCar=true
        end
        local passingReady = not state.passedAt or (now-state.passedAt)%4294967296 >= state.passDelay
        local blocker, neighbors = findBlocker(npc, x, y, z, dx, dy, distance, passingReady, target)
        if not blocker and state.waiting and stillBlocking(npc, state.blocker, x, y, z, dx, dy, distance) then
            blocker = state.blocker
        end
        state.blocker = blocker
        state.waiting = blocker ~= nil
        if blocker then
            local tx, ty = chooseSide(npc, blocker, neighbors, x, y, z, dx, dy)
            if tx then
                state.passedAt, state.passDelay = now, math.random(500,699)
                state.detour = {x = tx, y = ty, dx = dx, dy = dy, started = now, step = true}
                state.action = "TASK_COMPLEX_AVOID_OTHER_PED_WHILE_WANDERING"
                makeNPCWalkToPos(npc, tx, ty, pace)
                return
            end
        elseif blockedCar or not directLeg(npc,x,y,z,gx,gy,gz,false) then
            state.waiting=true
            if not state.retryAt or (now-state.retryAt)%4294967296>=1000 then
                state.search=state.search or startSearch(npc,x,y,z,dx,dy)
                local path=state.search and expandSearch(npc,state.search,gx,gy,gz)
                if path then
                    state.localRoute,state.search,state.retryAt=path,nil,nil
                    walkLocalRoute(npc,state,x,y,z,gx,gy,gz,now,pace)
                    return
                elseif path==false or not state.search then
                    state.search,state.retryAt=nil,now
                end
            end
        else
            state.search,state.retryAt=nil,nil
        end
    end
    if state.waiting then
        state.action = "TASK_SIMPLE_STAND_STILL"
        stopNPCWalkingActions(npc)
    else
        state.action = "TASK_SIMPLE_GO_TO_POINT"
        makeNPCWalkToPos(npc, gx, gy, pace)
    end
end

function walkNPCTrafficAroundPeds(npc, task, state, pace)
    walkAroundPeds(npc, task[2], task[3], task[4], state, pace)
end

function walkNPCTrafficFormation(npc, x, y, state, target)
    walkAroundPeds(npc, x, y, nil, state, nil, true, target)
end
