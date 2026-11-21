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
local clientDrivenTraffic = {fleeFromPoint=true, driveTrafficToPoint = true, driveTrafficRail = true, driveTrafficPhysics = true}

local function elapsedMs(now, before)
    return (now - before) % 4294967296
end

addEvent("npc_hlc:debugAssignmentChanged", false)

addEvent("npc_hlc:driverDoorArrival",true)
addEvent("npc_hlc:onDriverDoorArrival",false)
addEventHandler("npc_hlc:driverDoorArrival",root,function(car,order)
    local state=all_npcs[source]
    local task=state and state.assignedTask
    if not client or not task or state.owner~=client or state.actor~=source
        or task[1]~="approachDriverDoor" or type(order)~="number" or task[5]~=order
        or getElementSyncer(source)~=client or getPedOccupiedVehicle(task[2])~=car then return end
    triggerEvent("npc_hlc:onDriverDoorArrival",source,car,order)
end)

local function taskDrivingStyle(task)
    if task and task[1] == "driveTrafficPhysics" then return task[6] or 0 end
    if task and task[1] == "driveTrafficRail" then return task.style or 0 end
end

function getNPCDebugAssignment(npc)
    local state = all_npcs[npc]
    if not state then return false end
    state.debugReadAt = getTickCount()
    local task = state.tasks[state.head]
    return task and task[1] or false, state.revision or 0, state.owner or false, state.debugFallback or false, taskDrivingStyle(task)
end

function recordNPCDebugFallback(actor, x, y, z)
    local state = actorStates[actor]
    if state and state.debugReadAt and elapsedMs(getTickCount(),state.debugReadAt)<1000 and state.assignedTask then
        state.debugFallback = {state.assignedTask[1], false, x, y, z, false, false, false}
    end
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
    state.debugFallback = nil
    state.revision = revision
    state.actor, state.owner, state.assignedTask, state.preview = actor, owner, task, preview
    if previousOwner and previousOwner ~= owner and isElement(previousOwner) then
        sendTask(previousOwner, state, false)
    end
    if state.debugReadAt and elapsedMs(getTickCount(),state.debugReadAt)<1000 then
        triggerEvent("npc_hlc:debugAssignmentChanged",state.npc,revision,task and task[1] or false,owner or false,taskDrivingStyle(task))
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
        -- The swapped-in state gets its turn after wraparound. Rewinding here
        -- lets churn near the head starve states beyond the per-tick budget.
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

local function completeHead(state, task)
    state.tasks[state.head] = nil
    state.head = state.head + 1
    if state.head > state.tail then state.head, state.tail = 1, 0 end
    triggerEvent("npc_hlc:onNPCTaskDone", state.npc, task)
    if all_npcs[state.npc] == state then refreshNPCControl(state) end
end

-- Consume queued steps whose completion condition already holds at this position.
-- A completion handler may replace the queue, disable the ped or enqueue more work.
local function completeTask(state, task)
    for _ = 1, 8 do
        completeHead(state, task)
        if all_npcs[state.npc] ~= state then return end
        task = state.assignedTask
        if not task or not isNPCTaskComplete(state.npc, state.actor, task, true) then return end
    end
end

-- A walking owner can pass a waypoint between two position sync packets.
-- Accept only the current head and a nearby server position from that owner.
addEvent("npc_hlc:walkArrival", true)
addEventHandler("npc_hlc:walkArrival", root, function(order)
    local state = all_npcs[source]
    local task = state and state.assignedTask
    if not client or not task or not isNPCTrafficWalkTask(task[1]) or order ~= state.revision
        or state.owner ~= client or state.actor ~= source or getElementSyncer(source) ~= client
        or isPedDead(source) or isPedInVehicle(source) then return end
    local x,y=getElementPosition(source)
    if (x-task[2])^2+(y-task[3])^2 <= (task[5]+0.75)^2 then completeTask(state,task) end
end)

addEvent("npc_hlc:walkBlocked",true)
addEvent("npc_hlc:onWalkBlocked",false)
addEventHandler("npc_hlc:walkBlocked",root,function(order)
    local state=all_npcs[source]
    local task=state and state.assignedTask
    if not client or not task or task[1]~="walkTrafficToPoint" or state.revision~=order
        or state.actor~=source or state.owner~=client or getElementSyncer(source)~=client
        or isPedInVehicle(source) or isPedDead(source) then return end
    local now=getTickCount()
    if state.blockedAt and elapsedMs(now,state.blockedAt)<750 then return end
    state.blockedAt=now
    triggerEvent("npc_hlc:onWalkBlocked",source,task)
end)

local function cycleNPCs()
    local now = getTickCount()
    local gameSpeed = getGameSpeed()
    for _ = 1, math.min(MAX_UPDATES, #active) do
        local visit = getTickCount()
        if elapsedMs(visit, now) >= TIME_BUDGET_MS then
            budgetExhaustions = budgetExhaustions + 1
            break
        end
        if cursor > #active then cursor = 1 end
        local state = active[cursor]
        if not state or state.visitedAt == now then break end
        cursor = cursor + 1
        state.visitedAt = now
        local previousMovement = state.lastMovement
        refreshNPCControl(state)
        local task, actor = state.assignedTask, state.actor
        if task then
            local passed=false
            if actor and (state.preview or task.flee) and task[1]=="walkTrafficToPoint" then
                local x,y,z=getElementPosition(actor)
                if state.sampledWalk==task and state.walkOwner==state.owner then
                    local dx,dy=x-state.walkX,y-state.walkY
                    local length=dx*dx+dy*dy
                    if length>0 and length<=36 then
                        local t=math.max(0,math.min(1,((task[2]-x)*dx+(task[3]-y)*dy)/length+1))
                        passed=(state.walkX+t*dx-task[2])^2+(state.walkY+t*dy-task[3])^2<=task[5]^2
                    end
                end
                state.sampledWalk,state.walkOwner,state.walkX,state.walkY,state.walkZ=task,state.owner,x,y,z
            else
                state.sampledWalk=nil
            end
            if passed or isNPCTaskComplete(state.npc, actor, task, true) then
                completeTask(state, task)
            elseif not clientDrivenTraffic[task[1]] and actor and not state.owner and state.lastMovement == previousMovement
                and elapsedMs(visit, previousMovement) >= FALLBACK_INTERVAL
                and not getElementSyncer(actor) and getElementHealth(actor) >= 1 then
                local elapsed = math.min(MAX_FALLBACK_ELAPSED, elapsedMs(visit, state.lastMovement))
                state.debugFallback = nil
                state.lastMovement = visit
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
