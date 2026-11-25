-- US PS2 CGameLogic, 0x24A670 / 0x24C428 / 0x24CF50.
local restarts, freeHealthCare = {}, {}

function setPlayerFreeHealthCare(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" or type(enabled) ~= "boolean" then
        return false
    end
    freeHealthCare[player] = enabled or nil
    return true
end

local function finish(player, interrupted)
    local state = restarts[player]
    if not state then return end
    restarts[player] = nil
    if state.timer and isTimer(state.timer) then killTimer(state.timer) end
    if interrupted and isElement(player) then
        if state.faded then fadeCamera(player, true, 0.5) end
        triggerClientEvent(player, "wasted:showMessage", resourceRoot, false)
    end
end

local function resurrect(player, state)
    state.spawning = true
    local spawned = spawnPlayer(player, state.x, state.y, state.z, state.heading, getElementModel(player),
        0, state.dimension, getPlayerTeam(player) or nil)
    state.spawning = false
    if not spawned then return false end

    setCameraTarget(player, player)
    setPedArmor(player, 0)
    setElementHealth(player, math.max(1, 100 + (getPedStat(player, 24) - 569) / 4.31))
    return true
end

local function restart(player, state)
    if not resurrect(player, state) then return false end
    -- wanted resets the player's record in its onPlayerSpawn handler.
    if freeHealthCare[player] then
        freeHealthCare[player] = nil
    else
        local fee = math.min(100, getPlayerMoney(player))
        if fee > 0 then takePlayerMoney(player, fee) end
    end
    RestorePedsWeapons(player, state.weapons)
    return true
end

local function update(player)
    local state = restarts[player]
    if not state then return end
    local elapsed = (getTickCount() - state.started) % 4294967296
    if elapsed >= 2048 and not state.faded then
        fadeCamera(player, false, 2, 200, 200, 200)
        state.faded = true
    end
    if elapsed >= 4096 and not state.spawned then
        state.spawned = restart(player, state)
        if not state.spawned then return end
    end
    if elapsed >= 4608 and state.spawned then
        fadeCamera(player, true, 3)
        finish(player, false)
    end
end

addEventHandler("onPlayerWasted", root, function()
    local player = source
    finish(player, true)
    local x, y, z, heading = FindClosestHospitalRestartPoint(getElementPosition(player))
    local state = {x = x, y = y, z = z, heading = heading, dimension = getElementDimension(player),
        weapons = StorePedsWeapons(player), started = getTickCount()}
    restarts[player] = state
    triggerClientEvent(player, "wasted:showMessage", resourceRoot, true)
    state.timer = setTimer(update, 50, 0, player)
end, true, "high")

addEventHandler("onPlayerSpawn", root, function()
    local state = restarts[source]
    if state and not state.spawning then finish(source, true) end
end)

addEventHandler("onPlayerQuit", root, function()
    finish(source, false)
    freeHealthCare[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, state in pairs(restarts) do
        if isPedDead(player) and resurrect(player, state) then
            RestorePedsWeapons(player, state.weapons)
        end
        finish(player, true)
    end
end, false)
