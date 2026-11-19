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
function performTask.shootPoint() end
function performTask.shootElement() end
function performTask.killPed() end
function performTask.waitForGreenLight() end
