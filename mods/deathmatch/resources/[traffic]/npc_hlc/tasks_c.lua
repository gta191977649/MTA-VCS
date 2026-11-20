performTask = {}

function performTask.walkToPos(npc, task, _, progress)
    walkNPCTrafficAroundPeds(npc, task, progress)
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

function performTask.walkFollowElement(npc, task, _, progress)
    local x, y = getElementPosition(npc)
    local fx, fy = getElementPosition(task[2])
    local dx, dy = fx - x, fy - y
    if dx * dx + dy * dy > task[3] * task[3] then
        walkNPCTrafficFormation(npc, fx, fy, progress, task[2])
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

function performTask.killPed(npc, task, _, progress)
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
        walkNPCTrafficFormation(npc, tx, ty, progress, task[2])
    else
        stopNPCWalkingActions(npc)
    end
end

local doorBySeat = {[0]="door_lf_dummy", "door_rf_dummy", "door_lr_dummy", "door_rr_dummy"}

function performTask.approachDriverDoor(npc,task,_,progress)
    stopNPCWeaponActions(npc)
    local car=getPedOccupiedVehicle(task[2])
    if not car or getVehicleOccupant(car,0)~=task[2] then stopNPCWalkingActions(npc) return end
    local m=getElementMatrix(car)
    local left,rear,_,right,front=getElementBoundingBox(car)
    if not m or not left then return end
    local x,y=getElementPosition(npc)
    local cx,cy=unpack(m[4])
    local dx,dy=x-cx,y-cy
    local side,along=dx*m[1][1]+dy*m[1][2],dx*m[2][1]+dy*m[2][2]
    local lateral,longitudinal=task[3] or left-.55,task[4] or front*.2
    if side>left+.2 and along>rear-.5 and along<front+.5 then
        -- Reach a bumper before crossing the body from its passenger side.
        if not progress.bumper then progress.bumper=along>(front+rear)*.5 and front+.9 or rear-.9 end
        if side>0 then lateral=math.max(side,right+.65) end
        longitudinal=progress.bumper
    elseif side>left+.2 then
        longitudinal=along
    end
    local tx,ty=cx+lateral*m[1][1]+longitudinal*m[2][1],cy+lateral*m[1][2]+longitudinal*m[2][2]
    if (x-tx)^2+(y-ty)^2>.28^2 then
        walkNPCTrafficFormation(npc,tx,ty,progress,car)
    else
        stopNPCWalkingActions(npc)
        setPedRotation(npc,-math.deg(math.atan2(cx-x,cy-y)))
        -- MTA sends position deltas unreliably. Report a missed arrival
        -- only at the final handle after allowing time for native entry.
        if task[5] and side<left+.2 then
            local now=getTickCount()
            progress.doorWait=progress.doorWait or now
            if (now-progress.doorWait)%4294967296>=1500 and (progress.arrivals or 0)<4 then
                progress.arrivals=(progress.arrivals or 0)+1
                progress.doorWait=now
                triggerServerEvent("npc_hlc:driverDoorArrival",npc,car,task[5])
            end
        end
    end
end

function performTask.attackOccupiedVehicle(npc, task, _, progress)
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
    if task[6]~=nil then
        -- A police pursuit uses the server's firing deadline. The syncer
        -- verifies the streamed target and cover before applying weapon input.
        local _,_,z=getElementPosition(npc)
        local px,py,pz=getElementPosition(task[2])
        local distance=(x-px)^2+(y-py)^2+(z-pz)^2
        if task[6]==1 and distance>9 and distance<task[3]^2
            and isLineOfSightClear(x,y,z+.45,tx,ty,cz+.45,true,false,false,true,false) then
            stopNPCWalkingActions(npc)
            setPedRotation(npc,-math.deg(math.atan2(cx-x,cy-y)))
            makeNPCShootAtPos(npc,tx,ty,cz)
        else
            stopNPCWeaponActions(npc)
            if (x-tx)^2+(y-ty)^2>.5^2 then
                walkNPCTrafficFormation(npc,tx,ty,progress,vehicle)
            else
                stopNPCWalkingActions(npc)
            end
        end
        return
    end
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
    if distance > task[4]^2 then walkNPCTrafficFormation(npc, tx, ty, progress, vehicle) else stopNPCWalkingActions(npc) end
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

local function drivePolicePoint(npc, vehicle, target, seed, progress)
    local frame = getElementMatrix(vehicle)
    if not frame or frame[3][3] < 0.35 then
        progress.ramTurnAt = nil
        setNPCVehicleInputs(npc, 0, 0, false)
        return
    end
    local now = getTickCount()
    if progress.ramTurnAt then
        -- 004380E0 executes temporary action 6/7 before mission steering.
        -- MTA's positive steering input turns right.
        setNPCVehicleInputs(npc, seed < 2 and 1 or -1, 1, false)
        recordNPCDebugDriving(seed < 2 and "Ram turn right" or "Ram turn left", true)
        if (now - progress.ramTurnAt) % 4294967296 > 250 then progress.ramTurnAt = nil end
        return
    end

    local x, y, z = getElementPosition(target)
    local vx, vy, vz = getElementVelocity(vehicle)
    local forward = frame[2]
    local ramVehicle = seed ~= nil and getElementType(target) == "vehicle" and target
    if seed == nil then
        local tx, ty = getElementVelocity(target)
        local planar = math.sqrt(tx*tx + ty*ty)
        local lead = planar > 0.13 and 60*0.13/planar or 60
        x, y = x + lead*tx, y + lead*ty
    elseif ramVehicle then
        local targetFrame = getElementMatrix(target)
        if not targetFrame then setNPCVehicleInputs(npc, 0, 0, false) return end
        local targetForward = targetFrame[2]
        local aligned = forward[1]*targetForward[1] + forward[2]*targetForward[2] + forward[3]*targetForward[3] > 0.5
        local offset = 26843546 -- Literal 0x4BCCCCCD at 004386DC.
        local flank = seed % 2 == 1 and aligned
        if flank then
            local _, _, _, targetWidth = getElementBoundingBox(target)
            local _, _, _, patrolWidth = getElementBoundingBox(vehicle)
            offset = ((targetWidth or 1) + (patrolWidth or 1) - 0.2) * (seed < 2 and -1 or 1)
        end
        x, y = x + targetFrame[1][1]*offset, y + targetFrame[1][2]*offset
        if flank then
            local tx, ty, tz = getElementVelocity(target)
            local reach = 2 + 12 * math.sqrt((tx-vx)^2 + (ty-vy)^2 + (tz-vz)^2)
            if (x-frame[4][1])^2 + (y-frame[4][2])^2 < reach^2 then progress.ramTurnAt = now end
        end
    end

    local dx, dy = x-frame[4][1], y-frame[4][2]
    local scale = math.min(1, 100/math.max(1, math.abs(dx), math.abs(dy)))
    recordNPCDebugTarget(npc, frame[4][1] + dx*scale, frame[4][2] + dy*scale, z)
    local angle = math.atan2(dx*forward[2] - dy*forward[1], dx*forward[1] + dy*forward[2])
    local avoid = getNPCPoliceAvoidance(vehicle, ramVehicle, dx, dy, progress)
    local steeringAngle = math.atan2(math.sin(angle+avoid), math.cos(angle+avoid))
    if not progress.steeringLock then
        local handling = getVehicleHandling(vehicle)
        progress.steeringLock = math.max(0.01, math.rad(handling.steeringLock))
        progress.steeringLimit = getElementData(vehicle, "npchlc_traffic:originalModel", false) == 234 and 0.7 or 0.5
    end
    -- 00439580 feeds speed in native velocity * 60 and the current
    -- cruise command through the angle multiplier from 00438060.
    local steer = math.max(-progress.steeringLimit, math.min(progress.steeringLimit, steeringAngle)) / progress.steeringLock
    local factor = 1 - 0.6 * math.max(0, math.min(1, (math.abs(angle)-0.4)/0.8))
    local speed = 60 * math.sqrt(vx^2 + vy^2 + vz^2)
    local error = getNPCDriveSpeed(npc) * 50 * factor - speed
    local pedal = error > 0 and (speed >= 25 and 1 or math.min(1, error*0.1)) or math.max(-0.5, error*0.05)
    setNPCVehicleInputs(npc, steer, pedal, false)
    if speed > 18 and math.abs(steeringAngle) > 0.7 then setPedControlState(npc, "handbrake", true) end
end

function performTask.drivePoliceBlock(npc, task, _, progress)
    drivePolicePoint(npc, getPedOccupiedVehicle(npc), getPedOccupiedVehicle(task[2]) or task[2], nil, progress)
end

function performTask.driveAtPed(npc, task, _, progress)
    local vehicle = getPedOccupiedVehicle(npc)
    local target = getPedOccupiedVehicle(task[2]) or task[2]
    if task[3] ~= nil then
        drivePolicePoint(npc, vehicle, target, task[3], progress)
        return
    end
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
    local scale=math.min(1,100/math.max(1,math.abs(dx),math.abs(dy)))
    recordNPCDebugTarget(npc, motion.x + dx*scale, motion.y + dy*scale, motion.z)
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

function getNPCTrafficFootprint(vehicle, now)
    local box = getNPCTrafficModelFootprint(vehicle, getElementBoundingBox(vehicle))
    if box then
        local x, y = getElementPosition(vehicle)
        box.vx, box.vy = nearbyMotion(vehicle, now, x, y)
        box.parked = box.vx^2+box.vy^2 < 0.3^2 and not getVehicleOccupant(vehicle,0)
    end
    return box
end

local reportedBlockers = setmetatable({}, {__mode="k"})
addEvent("npc_hlc:onHeadOnBlocker", false)
addEvent("npc_hlc:onAbandonedBlocker", false)

function reportNPCTrafficBlocker(vehicle, blocker, limit, cruise, now)
    if not blocker or limit >= cruise * 0.5 then return end
    local previous = reportedBlockers[vehicle]
    if previous and (now-previous)%4294967296 < 1000 then return end
    local order = getElementData(vehicle, "npchlc_traffic:roadOrder", false)
    if type(order) ~= "number" then return end
    if not getVehicleOccupant(blocker, 0) then
        reportedBlockers[vehicle] = now
        triggerEvent("npc_hlc:onAbandonedBlocker", vehicle, blocker)
        return
    end
    local otherOrder = getElementData(blocker, "npchlc_traffic:roadOrder", false)
    if type(otherOrder) ~= "number" or order >= otherOrder then return end
    local a, b = getElementMatrix(vehicle), getElementMatrix(blocker)
    if a and b and a[2][1]*b[2][1] + a[2][2]*b[2][2] < -0.5 then
        reportedBlockers[vehicle] = now
        triggerEvent("npc_hlc:onHeadOnBlocker", vehicle, blocker)
    end
end

local function roadRailLimit(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now, horizon, nearby)
    local own = getNPCTrafficFootprint(vehicle, now)
    if not own then return math.huge, false end
    local obstacles = {}
    for _, element in ipairs(nearby) do
        if element ~= vehicle and isElementStreamedIn(element) then
            local other = getNPCTrafficFootprint(element, now)
            if other and math.abs(other.z-z) < 4 then obstacles[#obstacles+1] = other end
        end
    end
    if #obstacles == 0 then return math.huge, false end
    local limit, blocker = math.huge, nil
    local travelled, arrival = 0, 0
    local previewSpeed = math.max(4, speed)
    for finish = 4, horizon+4, 4 do
        local distance = math.min(finish, horizon)
        local px, py, pz = getNPCTrafficRailPreview(task, segment, t, lengths, distance)
        local sx, sy = px-x, py-y
        local span = math.sqrt(sx*sx + sy*sy)
        if span < 0.001 then break end
        local duration = span / previewSpeed
        local fx, fy = sx/span, sy/span
        local cx, cy = x + fy*own.offsetX + fx*own.offsetY, y - fx*own.offsetX + fy*own.offsetY
        for _, other in ipairs(obstacles) do
            if math.abs(other.z - pz) < 2.8 then
                local rx, ry = other.x + other.vx*arrival - cx, other.y + other.vy*arrival - cy
                local contact = getNPCTrafficFootprintContact(rx, ry, other.vx-fx*previewSpeed,
                    other.vy-fy*previewSpeed, fx, fy, own.width, own.length, other, duration)
                -- A touching follower behind must be able to fall away as
                -- this car moves forward. Later crossings still constrain it.
                local leaving = contact == 0 and (other.x-own.x)*own.fx + (other.y-own.y)*own.fy < 0
                    and rx*fx + ry*fy < 0
                    and other.vx*fx + other.vy*fy <= previewSpeed
                if contact and not leaving then
                    local headingDot = other.fx*fx + other.fy*fy
                    local sameLane = headingDot > 0.9
                        and math.abs((other.x-own.x)*dy - (other.y-own.y)*dx) < own.width + other.width
                    local lead = sameLane and math.max(0, other.vx*fx + other.vy*fy) or 0
                    -- Leave the winner enough distance to steer around a genuine
                    -- oncoming conflict after the original 15-second hold.
                    local clearance = (headingDot < -0.5 or other.parked) and 6 or 2
                    local gap = math.max(0, travelled + contact*previewSpeed - clearance - speed*0.1)
                    local cap = math.sqrt(lead*lead + 20*gap)
                    if cap < limit then limit, blocker = cap, other.vehicle end
                end
            end
        end
        if limit == 0 or distance == horizon then break end
        travelled, arrival, x, y = travelled + span, arrival + duration, px, py
    end
    return limit, limit == 0, blocker
end

-- The original CarCtrl tests predicted vehicle rectangles. Sample the
-- actual rail curve in MTA and reserve braking room before the first overlap.
function limitNPCTrafficRailMerge(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now)
    local horizon = math.min(52, math.max(14, speed ^ 2 / 20 + speed * 0.15 + 8))
    local width, length = halfExtents(vehicle)
    local nearby = getElementsWithinRange(x, y, z, horizon + length + 8, "vehicle",
        getElementInterior(vehicle), getElementDimension(vehicle)) or {}
    if getVehicleType(vehicle) ~= "Boat" then
        return roadRailLimit(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now, horizon, nearby)
    end
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

local function railSpeedLimit(vehicle, x, y, z, ax, ay, az, dx, dy, centreHeight, task, segment, t, lengths, speed, cruise)
    local action = getElementData(vehicle, "npchlc_traffic:sirenYield", false)
    if type(action) == "table" and action[2] == "wait" then
        return 0, false
    end
    local now = getTickCount()
    local previous = roadSurface[vehicle]
    local elapsed = previous and (now - previous.tick) % 4294967296 or 0
    if previous and previous.task == task and previous.style == task.style and elapsed < 100 then
        return previous.speed, previous.emergency, previous.bearing
    end
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
    local style = not boat and task.style
    local scanTraffic = limit > 0 and style ~= 3
    local pedestrian = false
    if scanTraffic then
        local _, _, _, _, front = getElementBoundingBox(vehicle)
        front = front or 2
        local distance = front + 6
        local hit, hx, hy, _, obstacle = processLineOfSight(x, y, z, x + dx * distance, y + dy * distance, z,
            false, boat, true, false, false, false, false, false, vehicle)
        if hit then
            local lead = 0
            local kind = isElement(obstacle) and getElementType(obstacle)
            pedestrian = kind == "ped" or kind == "player"
            if kind == "vehicle" then
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
    if scanTraffic and limit > 0 then
        local mergeLimit, imminent, blocker = limitNPCTrafficRailMerge(vehicle, task, segment, t, lengths, speed, x, y, z, dx, dy, now)
        if not boat and mergeLimit < limit then reportNPCTrafficBlocker(vehicle, blocker, mergeLimit, task[14], now) end
        limit, emergency = math.min(limit, mergeLimit), emergency or imminent
    end
    local bearing
    if scanTraffic and style == 1 and limit < cruise then
        limit, emergency = (cruise + limit) * 0.5, false
    elseif scanTraffic and doesNPCTrafficAvoidCars(style) and not (style == 6 and pedestrian) then
        local cap
        bearing, cap = getNPCPoliceAvoidance(vehicle, nil, dx*24, dy*24, {}, style == 6)
        if bearing ~= 0 and cap then
            limit, emergency = cap, cap == 0
        elseif style == 6 and cap and cap < limit then
            limit, emergency = cap, cap == 0
        end
    end
    roadSurface[vehicle] = {tick = now, task = task, style = task.style, speed = limit,
        leader = leaderSample, emergency = emergency, bearing = bearing}
    return limit, emergency, bearing
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
