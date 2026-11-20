local function publishProfile(npc, state)
    setElementData(npc, "npc_hlc:profile", state.profile, "subscribe", "deny")
end

local function finiteNumber(value)
    value = tonumber(value)
    if value and value > -math.huge and value < math.huge then return value end
end

function enableHLCForNPC(npc, walkSpeed, accuracy, driveSpeed)
    if not isElement(npc) or getElementType(npc) ~= "ped" or all_npcs[npc] then return false end

    walkSpeed = walkSpeed or "run"
    accuracy = finiteNumber(accuracy or 1)
    driveSpeed = finiteNumber(driveSpeed or 40 / 180)
    if not NPC_SPEED_ONFOOT[walkSpeed] or not accuracy or accuracy < 0 or accuracy > 1
        or not driveSpeed or driveSpeed < 0 then return false end

    local state = {npc = npc, profile = {walkSpeed, accuracy, driveSpeed}, tasks = {}, head = 1, tail = 0}
    all_npcs[npc] = state
    publishProfile(npc, state)
    setElementData(npc, "npc_hlc", true, "broadcast", "deny")
    return true
end

function disableHLCForNPC(npc)
    local state = all_npcs[npc]
    if not state then return false end
    removeNPCControl(state)
    all_npcs[npc] = nil
    removeElementData(npc, "npc_hlc")
    removeElementData(npc, "npc_hlc:profile")
    return true
end

local function setProfileValue(npc, state, index, value)
    if state.profile[index] ~= value then
        state.profile[index] = value
        publishProfile(npc, state)
    end
    return true
end

function setNPCWalkSpeed(npc, speed)
    local state = all_npcs[npc]
    if not state or not NPC_SPEED_ONFOOT[speed] then return false end
    return setProfileValue(npc, state, 1, speed)
end

function setNPCWeaponAccuracy(npc, accuracy)
    local state = all_npcs[npc]
    accuracy = finiteNumber(accuracy)
    if not state or not accuracy or accuracy < 0 or accuracy > 1 then return false end
    return setProfileValue(npc, state, 2, accuracy)
end

function setNPCDriveSpeed(npc, speed)
    local state = all_npcs[npc]
    speed = finiteNumber(speed)
    if not state or not speed or speed < 0 then return false end
    return setProfileValue(npc, state, 3, speed)
end

local function queueTask(state, task)
    state.tail = state.tail + 1
    state.tasks[state.tail] = task
    if state.head == state.tail or state.tail == state.head + 1 and isNPCTrafficWalkTask(task[1]) then
        refreshNPCControl(state)
    end
end

function getNPCTaskCount(npc)
    local state=all_npcs[npc]
    return state and state.tail-state.head+1 or 0
end

function addNPCTask(npc, task)
    local state = all_npcs[npc]
    task = normalizeNPCTask(task)
    if not state or not task then return false end
    queueTask(state, task)
    return true
end

function clearNPCTasks(npc)
    local state = all_npcs[npc]
    if not state then return false end
    state.tasks, state.head, state.tail = {}, 1, 0
    refreshNPCControl(state)
    return true
end

function setNPCTask(npc, task)
    local state = all_npcs[npc]
    task = normalizeNPCTask(task)
    if not state or not task then return false end
    state.tasks, state.head, state.tail = {}, 1, 0
    queueTask(state, task)
    return true
end
