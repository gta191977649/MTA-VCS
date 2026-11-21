local assignments, watching, pending, controlled = {}, {}, {}, {}
local watchBatchSize = 64
local renderBudget = 64
local renderCursor = 1
local active = {}
local activeIndex = {}
local trafficHits = setmetatable({}, {__mode = "k"})

-- Only keep executor samples while a debug viewer is asking for this ped.
local samples = setmetatable({}, {__mode = "k"})
local recording

function recordNPCDebugTarget(npc, x, y, z)
    if recording and (recording.npc == npc or recording.actor == npc) then
        recording.x, recording.y, recording.z = x, y, z
    end
end

function recordNPCDebugDriving(reason, moving)
    if recording then
        recording.action = reason
        if not moving then recording.x, recording.y, recording.z = nil, nil, nil end
    end
end

function getNPCDebugExecution(npc, revision)
    local state = assignments[npc]
    if not state or not state.task or state.revision ~= revision or not isElement(state.actor)
        or not isElementStreamedIn(npc) or not isElementSyncer(state.actor) then return false end
    local sample = samples[npc]
    if not sample or sample.revision ~= revision then
        sample = {npc = npc, actor = state.actor, revision = revision}
        samples[npc] = sample
    end
    sample.requested = getTickCount()
    if not sample.task then return false end
    return {sample.task, sample.action or false, sample.x or false, sample.y or false,
        sample.z or false, sample.gx or false, sample.gy or false, sample.gz or false,
        sample.waitingForServer or false}
end

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
        -- Continue the round robin when earlier actors leave the active list.
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

local socialStops = {}
local socialFacing = "npchlc_traffic:socialFacing"
local activityMotion = "npchlc_traffic:activityMotion"

local function refreshSocialStop(npc)
    local motion = getElementData(npc, activityMotion, false)
    local chatting = type(motion) == "table" and motion[6] == "PED"
        and (motion[1] == "idle_chat" or motion[1] == "xpressscratch")
    socialStops[npc] = getElementData(npc, socialFacing, false) or chatting or nil
    if socialStops[npc] then stopControl(npc, true) end
end

local function onStreamIn()
    if getElementType(source) == "ped" and isHLCEnabled(source) then
        refreshSocialStop(source)
        watch(source, true)
        local state = assignments[source]
        setActive(source, state and state.task)
    end
end

local function onStreamOut()
    socialStops[source] = nil
    watch(source, false)
    stopControl(source, true)
    samples[source] = nil
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
    local keepDrive=continuous
    if continuous and task[1]=="driveTrafficPhysics" then
        local first=current.task[2]
        keepDrive=task[2]>=first and task[2]<first+#current.task[5]
    end
    assignments[npc] = {revision = revision, task = task, actor = actor, preview = preview,
        driveProgress = keepDrive and current.driveProgress or {},
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
        local sample = samples[npc]
        if sample and (sample.revision ~= state.revision or (getTickCount()-sample.requested)%4294967296 > 1200) then
            samples[npc], sample = nil, nil
        end
        recording = sample
        if sample then
            sample.task, sample.action, sample.x, sample.y, sample.z = nil, nil, nil, nil, nil
            sample.gx, sample.gy, sample.gz = nil, nil, nil
            sample.waitingForServer = nil
        end
        local hitAt = trafficHits[npc]
        if hitAt and (getTickCount() - hitAt) % 4294967296 >= 350 then
            trafficHits[npc], hitAt = nil, nil
        end
        if (socialStops[npc] and actor == npc) or (hitAt and isNPCTrafficWalkTask(task[1])) then
            if sample then sample.task = task[1] end
            stopControl(npc, true)
        elseif isElement(actor) and isElementStreamedIn(actor) and isElementSyncer(actor)
            and getNPCControlElement(npc, task) == actor and getElementHealth(actor) >= 1
            and not isPedDead(npc) and getNPCWalkSpeed(npc) then
            if state.usePreview and state.preview then task = state.preview end
            local complete = isNPCTaskComplete(npc, actor, task)
            if complete and not state.usePreview and not state.arrivalSent and isNPCTrafficWalkTask(task[1])
                and not isPedInVehicle(npc) then
                state.arrivalSent=true
                triggerServerEvent("npc_hlc:walkArrival",npc,state.revision)
            end
            if complete and state.preview and not state.usePreview then
                state.usePreview, task = true, state.preview
                complete = isNPCTaskComplete(npc, actor, task)
            end
            if sample then sample.task = task[1] end
            if complete then
                if task[1] == "driveTrafficToPoint" and task[9] and task[12] == 0 then
                    performTask.driveTrafficToPoint(npc, task, elapsed, true)
                    controlled[npc] = true
                else
                    if sample then sample.waitingForServer = true end
                    if sample and isNPCTrafficWalkTask(task[1]) then sample.action="Awaiting route" end
                    stopControl(npc, task[1] == "driveTrafficToPoint" or task[1] == "driveTrafficRail"
                        or task[1] == "driveTrafficPhysics")
                end
            else
                if task[1] == "driveTrafficPhysics" or task[1] == "driveAtPed" or task[1] == "drivePoliceBlock" then
                    performTask[task[1]](npc, task, elapsed, state.driveProgress)
                elseif isNPCTrafficWalkTask(task[1]) or task[1] == "walkFormation" or task[1] == "walkToPos"
                    or task[1] == "walkFollowElement" or task[1] == "killPed" or task[1] == "attackOccupiedVehicle"
                    or task[1] == "approachDriverDoor" then
                    local walk = state.walkProgress
                    walk.action=nil
                    performTask[task[1]](npc, task, elapsed, walk)
                    -- A completed, unsuccessful detour search is actionable.
                    -- Never replace a route solely because a crossing or moving car needs time.
                    if task[1]=="walkTrafficToPoint" and not state.usePreview
                        and (walk.action=="Waiting for clear path" or walk.action=="Waiting for pedestrian clearance") then
                        local now=getTickCount()
                        state.blockedSince=state.blockedSince or now
                        if (now-state.blockedSince)%4294967296>=750 then
                            triggerServerEvent("npc_hlc:walkBlocked",npc,state.revision)
                            state.blockedSince=now
                        end
                    else
                        state.blockedSince=nil
                    end
                    if sample then
                        sample.action = (sample.x or walk.waiting or walk.action == "TASK_SIMPLE_STAND_STILL") and walk.action or nil
                        if state.usePreview then sample.action="Route preview" end
                        if sample.x and (walk.detour or walk.carDetour or walk.localRoute) then
                            sample.gx, sample.gy, sample.gz = walk.goalX, walk.goalY, walk.goalZ
                        end
                    end
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
        recording = nil
    end
end

function initNPCControl()
    addEvent("npc_hlc:control", true)
    addEventHandler("npc_hlc:control", resourceRoot, updateTask, false)
    addEventHandler("onClientPreRender", root, cycleNPCs)
    addEventHandler("onClientPedDamage", root, function(attacker, weapon, _, loss)
        local state = assignments[source]
        if loss == 0 or not state or not state.task or not isNPCTrafficWalkTask(state.task[1])
            or not isElementSyncer(source) then return end
        -- Keep native contact recovery for falls and vehicles. Grounded
        -- weapon victims can take their new movement input on the next frame.
        if isElement(attacker) and (getElementType(attacker)=="player" or getElementType(attacker)=="ped")
            and weapon and weapon<=46 and isPedOnGround(source) then return end
        trafficHits[source] = getTickCount()
        state.walkProgress = {}
        stopControl(source, true)
    end)
    addEventHandler("onClientElementStreamIn", root, onStreamIn)
    addEventHandler("onClientElementStreamOut", root, onStreamOut)
    addEventHandler("onClientElementDestroy", root, function()
        samples[source], socialStops[source] = nil, nil
        watching[source], pending[source], controlled[source], assignments[source] = nil, nil, nil, nil
        setActive(source, false)
    end)
    addEventHandler("onClientElementDataChange", root, function(key)
        if key == socialFacing or key == activityMotion then
            if isElementStreamedIn(source) and isHLCEnabled(source) then refreshSocialStop(source) end
            return
        end
        if key ~= "npc_hlc" or not isElementStreamedIn(source) then return end
        if isHLCEnabled(source) then onStreamIn() else onStreamOut() end
    end)
    addEventHandler("onClientResourceStop", resourceRoot, function()
        for npc in pairs(controlled) do stopControl(npc, true) end
    end, false)
    for _, npc in ipairs(getElementsByType("ped", root, true)) do
        if isHLCEnabled(npc) then
            refreshSocialStop(npc)
            watch(npc, true)
        end
    end
    setTimer(flushProfiles, 150, 0)
end
