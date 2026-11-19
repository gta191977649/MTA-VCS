local UPDATE_INTERVAL = 50
local MAX_UPDATES = 128
local TIME_BUDGET_MS = 2
local FALLBACK_INTERVAL = 200
local MAX_FALLBACK_ELAPSED = 250
local WATCH_RANGE_SQUARED = 400 * 400
local MAX_WATCH_CHANGES = 64
local active, actorStates = {}, {}
local watchTimes = {}
local cursor, revision = 1, 0
local timings = {}
local timingIndex, budgetExhaustions = 1, 0
local clientDrivenTraffic = {driveTrafficToPoint = true, driveTrafficRail = true, driveTrafficPhysics = true}

local function elapsedMs(now, before)
    return (now - before) % 4294967296
end

local function sendTask(player, state, task)
    triggerClientEvent(player, "npc_hlc:control", resourceRoot,
        state.npc, state.revision, task or false, task and state.actor or false, task and state.preview or false)
end

local function updateAssignment(state, actor, owner, task, preview)
    if owner == state.owner and actor == state.actor and task == state.assignedTask and preview == state.preview then return end
    local previousOwner = state.owner
    if previousOwner ~= owner or state.actor ~= actor then state.lastMovement = getTickCount() end
    if state.actor and actorStates[state.actor] == state then actorStates[state.actor] = nil end
    if actor then actorStates[actor] = state end

    revision = revision + 1
    state.revision = revision
    state.actor, state.owner, state.assignedTask, state.preview = actor, owner, task, preview
    if previousOwner and previousOwner ~= owner and isElement(previousOwner) then
        sendTask(previousOwner, state, false)
    end
    if owner then
        addElementDataSubscriber(state.npc, "npc_hlc:profile", owner)
        sendTask(owner, state, task)
    end
end

local function setActive(state, enabled)
    if enabled and not state.index then
        state.index = #active + 1
        state.lastMovement = getTickCount()
        active[state.index] = state
    elseif not enabled and state.index then
        local index, last = state.index, active[#active]
        active[index] = last
        last.index = index
        active[#active] = nil
        state.index = nil
        if cursor > index then cursor = index end
    end
end

function refreshNPCControl(state)
    local task = state.tasks[state.head]
    local actor = task and getNPCControlElement(state.npc, task) or false
    local enabled = task and not isPedDead(state.npc)
    local owner = actor and enabled and getElementSyncer(actor) or false
    if owner and (getElementDimension(owner) ~= getElementDimension(actor)
        or getElementInterior(owner) ~= getElementInterior(actor)) then owner = false end
    local preview = enabled and isNPCTrafficWalkTask(task[1]) and state.tasks[state.head + 1]
    if not preview or not isNPCTrafficWalkTask(preview[1]) then preview = nil end
    updateAssignment(state, enabled and actor or false, owner, enabled and task or false, preview)
    setActive(state, enabled)
end

function removeNPCControl(state)
    updateAssignment(state, false, false, false)
    setActive(state, false)
end

local function completeTask(state, task)
    state.tasks[state.head] = nil
    state.head = state.head + 1
    if state.head > state.tail then state.head, state.tail = 1, 0 end
    triggerEvent("npc_hlc:onNPCTaskDone", state.npc, task)
    if all_npcs[state.npc] == state then refreshNPCControl(state) end
end

local function cycleNPCs()
    local now = getTickCount()
    local gameSpeed = getGameSpeed()
    for index = 1, math.min(MAX_UPDATES, #active) do
        if index % 4 == 0 and elapsedMs(getTickCount(), now) >= TIME_BUDGET_MS then
            budgetExhaustions = budgetExhaustions + 1
            break
        end
        if cursor > #active then cursor = 1 end
        local state = active[cursor]
        if not state or state.visitedAt == now then break end
        cursor = cursor + 1
        state.visitedAt = now
        refreshNPCControl(state)
        local task, actor = state.assignedTask, state.actor
        local elapsed = math.min(MAX_FALLBACK_ELAPSED, elapsedMs(getTickCount(), state.lastMovement))
        if task then
            if isNPCTaskComplete(state.npc, actor, task, true) then
                completeTask(state, task)
            elseif not clientDrivenTraffic[task[1]] and actor and not state.owner and not getElementSyncer(actor)
                and getElementHealth(actor) >= 1 and elapsed >= FALLBACK_INTERVAL then
                state.lastMovement = getTickCount()
                performTask[task[1]](state.npc, task, elapsed * gameSpeed)
                if isNPCTaskComplete(state.npc, actor, task, true) then completeTask(state, task) end
            end
        end
    end
    timings[timingIndex] = elapsedMs(getTickCount(), now)
    timingIndex = timingIndex % 1200 + 1
end

function getNPCSchedulerStats()
    local samples = {unpack(timings)}
    table.sort(samples)
    return {
        activeTasks = #active, samples = #samples, budgetExhaustions = budgetExhaustions,
        p95Ms = samples[math.ceil(#samples * 0.95)],
        p99Ms = samples[math.ceil(#samples * 0.99)],
    }
end

local function refreshActor()
    local state = actorStates[source] or all_npcs[source]
    if state and state.index then refreshNPCControl(state) end
end

local function watchProfiles(changes)
    if source ~= resourceRoot or not client or type(changes) ~= "table" then return end
    local now = getTickCount()
    if watchTimes[client] and elapsedMs(now, watchTimes[client]) < 100 then return end
    watchTimes[client] = now

    local px, py, pz = getElementPosition(client)
    local interior, dimension = getElementInterior(client), getElementDimension(client)
    for index = 1, math.min(MAX_WATCH_CHANGES, #changes) do
        local change = changes[index]
        local npc = type(change) == "table" and change[1]
        local state = npc and all_npcs[npc]
        if state then
            if change[2] == false and client ~= state.owner then
                removeElementDataSubscriber(npc, "npc_hlc:profile", client)
            elseif change[2] == true and interior == getElementInterior(npc)
                and dimension == getElementDimension(npc) then
                local x, y, z = getElementPosition(npc)
                local dx, dy, dz = x - px, y - py, z - pz
                if dx * dx + dy * dy + dz * dz <= WATCH_RANGE_SQUARED then
                    addElementDataSubscriber(npc, "npc_hlc:profile", client)
                    if client == state.owner then sendTask(client, state, state.assignedTask) end
                end
            end
        end
    end
end

function initNPCControl()
    addEvent("npc_hlc:onNPCTaskDone", false)
    addEvent("npc_hlc:watchProfiles", true)
    addEventHandler("npc_hlc:watchProfiles", resourceRoot, watchProfiles, false)
    addEventHandler("onPlayerQuit", root, function() watchTimes[source] = nil end)
    addEventHandler("onElementStartSync", root, refreshActor)
    addEventHandler("onElementStopSync", root, refreshActor)
    addEventHandler("onPedVehicleEnter", root, refreshActor)
    addEventHandler("onPedVehicleExit", root, refreshActor)
    addEventHandler("onPedWasted", root, refreshActor)
    addEventHandler("onElementDestroy", root, function()
        local state = all_npcs[source]
        if state then
            removeNPCControl(state)
            all_npcs[source] = nil
        end
    end)
    setTimer(cycleNPCs, UPDATE_INTERVAL, 0)
end
