local assignments, watching, pending, controlled = {}, {}, {}, {}
local watchBatchSize = 64
local renderBudget = 64
local renderCursor = 1
local active = {}
local activeIndex = {}
local trafficHits = setmetatable({}, {__mode = "k"})

local function setActive(npc, enabled)
    local index = activeIndex[npc]
    if enabled and not index then
        active[#active + 1] = npc
        activeIndex[npc] = #active
    elseif not enabled and index then
        local last = active[#active]
        active[index] = last
        activeIndex[last] = index
        active[#active] = nil
        activeIndex[npc] = nil
        if renderCursor > index then renderCursor = index end
    end
end

local function stopControl(npc, release)
    if controlled[npc] and isElement(npc) then
        local assignment = assignments[npc]
        if assignment and assignment.actor and assignment.task and assignment.task[1] == "driveTrafficRail" then
            resetNPCTrafficRailGround(assignment.actor)
        elseif assignment and isElement(assignment.actor) and assignment.task and assignment.task[1] == "driveTrafficPhysics" then
            resetNPCTrafficPhysicsSensor(assignment.actor)
        end
        if release then
            releaseNPCActions(npc)
        else
            stopAllNPCActions(npc)
        end
    end
    controlled[npc] = nil
end

local function watch(npc, enabled)
    if enabled == (watching[npc] == true) then return end
    watching[npc] = enabled or nil
    pending[npc] = enabled
end

local function onStreamIn()
    if getElementType(source) == "ped" and isHLCEnabled(source) then
        watch(source, true)
        local state = assignments[source]
        setActive(source, state and state.task)
    end
end

local function onStreamOut()
    watch(source, false)
    stopControl(source, true)
    local state = assignments[source]
    if state then state.driveProgress, state.walkProgress = {}, {} end
    setActive(source, false)
end

local function flushProfiles()
    if not next(pending) then return end
    local changes = {}
    for npc, enabled in pairs(pending) do
        pending[npc] = nil
        if isElement(npc) then
            changes[#changes + 1] = {npc, enabled}
            if #changes == watchBatchSize then break end
        end
    end
    if #changes > 0 then triggerServerEvent("npc_hlc:watchProfiles", resourceRoot, changes) end
end

local function updateTask(npc, revision, task, actor, preview)
    if not isElement(npc) then return end
    local current = assignments[npc]
    if current and revision <= current.revision then return end
    local continuous = task and (isNPCTrafficWalkTask(task[1]) or task[1] == "driveTrafficToPoint"
        or task[1] == "driveTrafficRail" or task[1] == "driveTrafficPhysics")
        and current and current.task and (current.task[1] == task[1]
            or isNPCTrafficWalkTask(current.task[1]) and isNPCTrafficWalkTask(task[1])) and actor == current.actor
    if not continuous then stopControl(npc, true) end
    assignments[npc] = {revision = revision, task = task, actor = actor, preview = preview,
        driveProgress = continuous and current.driveProgress or {},
        walkProgress = continuous and current.walkProgress or {}}
    setActive(npc, task and isElementStreamedIn(npc))
end

local function cycleNPCs(elapsed)
    beginNPCTrafficPhysicsFrame()
    for _ = 1, math.min(renderBudget, #active) do
        if renderCursor > #active then renderCursor = 1 end
        local npc = active[renderCursor]
        renderCursor = renderCursor + 1
        local state = assignments[npc]
        local actor, task = state.actor, state.task
        local hitAt = trafficHits[npc]
        if hitAt and (getTickCount() - hitAt) % 4294967296 >= 350 then
            trafficHits[npc], hitAt = nil, nil
        end
        if hitAt and isNPCTrafficWalkTask(task[1]) then
            stopControl(npc, true)
        elseif isElement(actor) and isElementStreamedIn(actor) and isElementSyncer(actor)
            and getNPCControlElement(npc, task) == actor and getElementHealth(actor) >= 1
            and not isPedDead(npc) and getNPCWalkSpeed(npc) then
            if state.preview and (state.usePreview or isNPCTaskComplete(npc, actor, task)) then
                state.usePreview, task = true, state.preview
            end
            if isNPCTaskComplete(npc, actor, task) then
                if task[1] == "driveTrafficToPoint" and task[9] and task[12] == 0 then
                    performTask.driveTrafficToPoint(npc, task, elapsed, true)
                    controlled[npc] = true
                else
                    stopControl(npc, task[1] == "driveTrafficToPoint" or task[1] == "driveTrafficRail"
                        or task[1] == "driveTrafficPhysics")
                end
            else
                if task[1] == "driveTrafficPhysics" then
                    performTask.driveTrafficPhysics(npc, task, elapsed, state.driveProgress)
                elseif isNPCTrafficWalkTask(task[1]) then
                    performTask[task[1]](npc, task, elapsed, state.walkProgress)
                else
                    performTask[task[1]](npc, task, elapsed)
                end
                controlled[npc] = true
            end
        else
            stopControl(npc, true)
            if next(state.driveProgress) then state.driveProgress = {} end
            if next(state.walkProgress) then state.walkProgress = {} end
        end
    end
end

function initNPCControl()
    addEvent("npc_hlc:control", true)
    addEventHandler("npc_hlc:control", resourceRoot, updateTask, false)
    addEventHandler("onClientPreRender", root, cycleNPCs)
    addEventHandler("onClientPedDamage", root, function(_, _, _, loss)
        local state = assignments[source]
        if loss == 0 or not state or not state.task or not isNPCTrafficWalkTask(state.task[1])
            or not isElementSyncer(source) then return end
        trafficHits[source] = getTickCount()
        state.walkProgress = {}
        stopControl(source, true)
    end)
    addEventHandler("onClientElementStreamIn", root, onStreamIn)
    addEventHandler("onClientElementStreamOut", root, onStreamOut)
    addEventHandler("onClientElementDestroy", root, function()
        watching[source], pending[source], controlled[source], assignments[source] = nil, nil, nil, nil
        setActive(source, false)
    end)
    addEventHandler("onClientElementDataChange", root, function(key)
        if key ~= "npc_hlc" or not isElementStreamedIn(source) then return end
        if isHLCEnabled(source) then onStreamIn() else onStreamOut() end
    end)
    addEventHandler("onClientResourceStop", resourceRoot, function()
        for npc in pairs(controlled) do stopControl(npc, true) end
    end, false)
    for _, npc in ipairs(getElementsByType("ped", root, true)) do
        if isHLCEnabled(npc) then watch(npc, true) end
    end
    setTimer(flushProfiles, 150, 0)
end
