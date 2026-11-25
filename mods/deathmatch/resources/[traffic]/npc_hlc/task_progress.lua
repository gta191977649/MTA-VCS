local completion = {}

function getNPCFormationSlot(task)
    local matrix = getElementMatrix(task[2])
    if not matrix then return end
    local right,forward,pos = matrix[1],matrix[2],matrix[4]
    return pos[1]+right[1]*task[4]+forward[1]*task[5],
        pos[2]+right[2]*task[4]+forward[2]*task[5], pos[3], forward[1],forward[2]
end

function isNPCTrafficWalkTask(name)
    return name == "walkTrafficToPoint" or name == "walkTrafficCrossing"
end

-- The crossing task carries its entry point so a new syncer can distinguish
-- an NPC waiting at the curb from one already committed to crossing.
function getNPCTrafficCrossingPace(npc, task)
    if task[1] ~= "walkTrafficCrossing" then return end
    local signal = getTrafficLightState()
    if signal == 2 or signal == 6 or signal == 9 then return end
    local x, y = getElementPosition(npc)
    local dx, dy = task[2] - task[6], task[3] - task[7]
    local length = math.sqrt(dx * dx + dy * dy)
    local into = (x - task[6]) * dx + (y - task[7]) * dy
    if into >= length * math.min(0.8, length * 0.25) then return "run" end
    return "wait"
end

function getNPCControlElement(npc, task)
    local vehicle = getPedOccupiedVehicle(npc)
    local name = task[1]
    if name == "driveRaceToPoint" or name == "driveToPos" or name == "driveTrafficToPoint" or name == "driveTrafficRail" or name == "driveTrafficPhysics"
        or name == "driveAlongLine" or name == "driveAroundBend" or name == "driveAtPed" or name == "drivePoliceBlock" or name == "stopVehicle" then
        return vehicle and getVehicleOccupant(vehicle, 0) == npc and vehicle or false
    end
    if name == "waitForGreenLight" and vehicle then
        return getVehicleOccupant(vehicle, 0) == npc and vehicle or false
    end
    return npc
end

local function closeToPoint(actor, task, useZ)
    local x, y, z = getElementPosition(actor)
    local dx, dy = task[2] - x, task[3] - y
    local dz = useZ and task[4] - z or 0
    return dx * dx + dy * dy + dz * dz <= task[5] * task[5]
end

local function nearLineEnd(actor, task)
    local x, y = getElementPosition(actor)
    local x1, y1, z1, x2, y2, z2 = unpack(task, 2, 7)
    local length = getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
    return getPercentageInLine(x, y, x1, y1, x2, y2) >= 1 - task[9] / length
end

local function nearBendEnd(actor, task)
    local x, y = getElementPosition(actor)
    local x0, y0, x1, y1, _, x2, y2 = unpack(task, 2, 8)
    local length = getDistanceBetweenPoints2D(x1, y1, x2, y2) * math.pi * 0.5
    return getAngleInBend(x, y, x0, y0, x1, y1, x2, y2) + task[11] / length >= math.pi * 0.5
end

function completion.walkToPos(npc, actor, task)
    return isPedInVehicle(npc) or closeToPoint(actor, task, false)
end

function completion.fleeFromPoint(npc) return isPedInVehicle(npc) end

completion.walkTrafficToPoint = completion.walkToPos
completion.walkTrafficCrossing = completion.walkToPos

function completion.walkAlongLine(npc, actor, task)
    return isPedInVehicle(npc) or nearLineEnd(actor, task)
end

function completion.walkAroundBend(npc, actor, task)
    return isPedInVehicle(npc) or nearBendEnd(actor, task)
end

function completion.walkFollowElement(npc, _, task)
    return isPedInVehicle(npc) or not isElement(task[2])
end

completion.walkFormation = completion.walkFollowElement

function completion.shootElement(_, _, task)
    return not isElement(task[2])
end

function completion.killPed(npc, _, task)
    return isPedInVehicle(npc) or not isElement(task[2]) or getElementHealth(task[2]) < 1
end

function completion.attackOccupiedVehicle(npc, actor, task)
    return completion.killPed(npc, actor, task) or not getPedOccupiedVehicle(task[2])
end
completion.approachDriverDoor = completion.attackOccupiedVehicle

function completion.driveToPos(_, actor, task)
    return actor and closeToPoint(actor, task, true)
end

function completion.stopVehicle(_,_,task,authoritative)
    return authoritative and task.started and (getTickCount()-task.started)%4294967296>=task[2]
end

function completion.driveAtPed(_, _, task)
    return not isElement(task[2]) or isPedDead(task[2])
end
completion.drivePoliceBlock = completion.driveAtPed

function completion.driveTrafficToPoint(_, actor, task)
    if not actor then return false end
    if not task[9] then return closeToPoint(actor, task, false) end
    -- SLUS_215.90 0x00438A80 also advances after passing the lane centre.
    local x, y = getElementPosition(actor)
    local dx, dy = x - task[2], y - task[3]
    local distanceSquared = dx * dx + dy * dy
    if distanceSquared < 25 then return true end
    local nx, ny = task[9] - task[2], task[10] - task[3]
    local ahead = dx * nx + dy * ny
    return ahead > 0 and (distanceSquared < 64
        or ahead * ahead > 0.49 * distanceSquared * (nx * nx + ny * ny))
end

function completion.driveTrafficRail(_, actor, task, authoritative)
    return actor and hasCompletedNPCTrafficRail(actor, task, authoritative)
end

function completion.driveTrafficPhysics(_, actor, task, authoritative)
    if not actor or not authoritative then return false end
    if task.race and not getElementSyncer(actor) then
        local x,y,z=getElementPosition(actor)
        local point=task[5][1]
        if (x-point[3])^2+(y-point[4])^2<5^2 and math.abs(z-point[5])<7 then return true end
    end
    return getNPCTrafficPhysicsIndex(task, 1, getNPCTrafficPhysicsMotion(actor)) > 1
end

function completion.driveAlongLine(_, actor, task)
    return actor and nearLineEnd(actor, task)
end

function completion.driveAroundBend(_, actor, task)
    return actor and nearBendEnd(actor, task)
end

function completion.waitForGreenLight(_, actor, task)
    if not actor then return false end
    local state = getTrafficLightState()
    return state == 6 or state == 9
        or task[2] == "NS" and (state == 0 or state == 5 or state == 8)
        or task[2] == "WE" and (state == 3 or state == 5 or state == 7)
        or task[2] == "ped" and state == 2
end

function isNPCTaskComplete(npc, actor, task, authoritative)
    local check = completion[task[1]]
    return check and check(npc, actor, task, authoritative) or false
end
