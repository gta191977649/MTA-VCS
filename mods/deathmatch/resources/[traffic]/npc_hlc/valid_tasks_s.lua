local signatures = {
    fleeFromPoint = "nn",
    walkToPos = "nnnd",
    walkTrafficToPoint = "nnnd",
    walkTrafficCrossing = "nnndnn",
    walkAlongLine = "nnnnnndd",
    walkAroundBend = "nnnnnnnndd",
    walkFollowElement = "ed",
    walkFormation = "ednn",
    shootPoint = "nnn",
    shootElement = "e",
    killPed = "pdd",
    attackOccupiedVehicle = "pdd",
    approachDriverDoor = "p",
    stopVehicle = "",
    driveAtPed = "p",
    drivePoliceBlock = "p",
    driveToPos = "nnnd",
    driveTrafficToPoint = "nnnd",
    driveTrafficRail = "nnnnnnnnnnnnddd",
    driveAlongLine = "nnnnnndd",
    driveAroundBend = "nnnnnnnndd",
    waitForGreenLight = "l",
}

function normalizeNPCTask(task)
    if type(task) ~= "table" then return false end
    if task[1] == "driveTrafficPhysics" then return normalizeNPCTrafficPhysics(task) end
    local signature = signatures[task[1]]
    if not signature then return false end
    local speedClasses = 0
    local driving = task[1] == "driveTrafficToPoint"
    if task[1] == "driveTrafficRail" then
        if task.style ~= nil and not isNPCTrafficDrivingStyle(task.style) then return false end
        if #task == 17 or #task == 22 or #task == 27 then
            speedClasses = (#task - 12) / 5
        elseif #task ~= 16 and #task ~= 20 and #task ~= 24 then
            return false
        end
        signature = signature .. string.rep("dnnn", (#task - 16 - speedClasses) / 4)
    elseif task[1]=="approachDriverDoor" and #task>2 then
        if #task~=4 and #task~=5 then return false end
        signature=#task==5 and "pnnd" or "pnn"
    elseif task[1]=="driveAtPed" and #task==3 then
        if type(task[3])~="number" or task[3]%1~=0 or task[3]<0 or task[3]>3 then return false end
        signature=signature.."d"
    elseif task[1]=="attackOccupiedVehicle" and #task==6 then
        if task[5]~=1 or (task[6]~=0 and task[6]~=1) then return false end
        signature=signature.."dd"
    elseif (task[1] == "killPed" or task[1] == "attackOccupiedVehicle") and #task == 5 then
        if task[5] ~= 0 and task[5] ~= 1 then return false end
        signature = signature .. "d"
    elseif driving and (#task == 6 or #task == 8 or #task == 14) then
        speedClasses = 1
    end

    local normalized = {task[1]}
    if task[1]=="walkTrafficToPoint" and task.flee==true then normalized.flee=true end
    if task[1] == "driveTrafficRail" then normalized.style = task.style end
    for index = 1, #signature do
        local rule = signature:sub(index, index)
        local arg = task[index + 1]
        if rule == "n" or rule == "d" then
            arg = tonumber(arg)
            if not arg or not (arg > -math.huge and arg < math.huge)
                or rule == "d" and arg < 0 then return false end
        elseif rule == "e" then
            if not isElement(arg) or not getElementPosition(arg) then return false end
        elseif rule == "p" then
            if not isElement(arg) then return false end
            local kind = getElementType(arg)
            if kind ~= "ped" and kind ~= "player" then return false end
        elseif arg ~= "NS" and arg ~= "WE" and arg ~= "ped" then
            return false
        end
        normalized[index + 1] = arg
    end
    for index = #signature + 2, #signature + 1 + speedClasses do
        local class = tonumber(task[index])
        if not class or class < 0 or class > 3 or class % 1 ~= 0 then return false end
        normalized[index] = class
    end
    if driving and (#task == 8 or #task == 14) then
        for index = 7, #task do
            local value = tonumber(task[index])
            if not value or not (value > -math.huge and value < math.huge) then return false end
            normalized[index] = value
        end
        if normalized[7] == 0 and normalized[8] == 0 then return false end
        if normalized[12] and (normalized[12] < 0 or normalized[12] > 2 or normalized[12] % 1 ~= 0
            or normalized[13] == 0 and normalized[14] == 0) then return false end
    end

    local name = normalized[1]
    if name == "walkTrafficCrossing" then
        if normalized[2] == normalized[6] and normalized[3] == normalized[7] then return false end
    elseif name == "walkAlongLine" or name == "driveAlongLine" then
        if normalized[2] == normalized[5] and normalized[3] == normalized[6] then return false end
    elseif name == "walkAroundBend" or name == "driveAroundBend" then
        local ax, ay = normalized[4] - normalized[2], normalized[5] - normalized[3]
        local bx, by = normalized[7] - normalized[2], normalized[8] - normalized[3]
        if ax * by == ay * bx then return false end
    end
    return normalized
end
