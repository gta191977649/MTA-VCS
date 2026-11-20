performTask = {}

function performTask.walkToPos(npc, task, elapsed)
    stepNPCToPoint(npc, task[2], task[3], task[4], elapsed)
end

performTask.walkTrafficToPoint = performTask.walkToPos

function performTask.walkTrafficCrossing(npc, task, elapsed)
    local pace = getNPCTrafficCrossingPace(npc, task)
    if pace ~= "wait" then stepNPCToPoint(npc, task[2], task[3], task[4], elapsed, nil, pace) end
end

function performTask.driveToPos(npc, task, elapsed)
    stepNPCToPoint(getPedOccupiedVehicle(npc), task[2], task[3], task[4], elapsed, getNPCDriveSpeed(npc))
end

function performTask.walkAlongLine(npc, task, elapsed)
    stepNPCAlongLine(npc, task, elapsed)
end

function performTask.driveAlongLine(npc, task, elapsed)
    stepNPCAlongLine(getPedOccupiedVehicle(npc), task, elapsed, getNPCDriveSpeed(npc))
end

function performTask.walkAroundBend(npc, task, elapsed)
    stepNPCAroundBend(npc, task, elapsed)
end

function performTask.driveAroundBend(npc, task, elapsed)
    stepNPCAroundBend(getPedOccupiedVehicle(npc), task, elapsed, getNPCDriveSpeed(npc))
end

function performTask.walkFollowElement() end
function performTask.walkFormation(npc,task,elapsed)
    local x,y,z,fx,fy = getNPCFormationSlot(task)
    if not x then return end
    local px,py = getElementPosition(npc)
    if (px-x)^2+(py-y)^2 > task[3]^2 then
        stepNPCToPoint(npc,x,y,z,elapsed)
    elseif task[4]>0 and task[5]==0 then
        local heading = math.deg(math.atan2(-fx,fy))
        local _,_,current = getElementRotation(npc)
        if math.abs((heading-current+180)%360-180)>0.5 then setPedRotation(npc,heading) end
    end
end
function performTask.shootPoint() end
function performTask.shootElement() end
function performTask.killPed() end
function performTask.attackOccupiedVehicle() end
function performTask.approachDriverDoor() end
-- These tasks act on the native vehicle through its syncer.
function performTask.stopVehicle() end
function performTask.driveAtPed() end
function performTask.drivePoliceBlock() end
function performTask.waitForGreenLight() end
