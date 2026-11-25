-- Busted, US PS2 0024A770 / 0024C428 / 0024CF50.
local fees = {100, 200, 400, 600, 900, 1500}
local active, freeBail = {}, {}
local arresting = {}
local timer
local controls = {
    "forwards", "backwards", "left", "right", "sprint", "jump", "crouch",
    "fire", "aim_weapon", "enter_exit", "accelerate", "brake_reverse", "vehicle_fire",
    "action", "walk", "next_weapon", "previous_weapon", "zoom_in", "zoom_out", "change_camera",
    "look_behind", "conversation_yes", "conversation_no", "group_control_forwards", "group_control_back",
    "vehicle_secondary_fire", "vehicle_left", "vehicle_right", "steer_forward", "steer_back",
    "radio_next", "radio_previous", "radio_user_track_skip", "horn", "sub_mission", "handbrake",
    "vehicle_look_left", "vehicle_look_right", "vehicle_look_behind", "vehicle_mouse_look",
    "special_control_left", "special_control_right", "special_control_down", "special_control_up", "enter_passenger",
}

function TrafficCustody.isActive(player)
    return active[player] ~= nil
end

function isTrafficPlayerInCustody(player)
    return TrafficCustody.isActive(player)
end

function TrafficCustody.isArresting(officer)
    return arresting[officer] ~= nil
end

local function endPose(player, state)
    if state.frozeCar and isElement(state.frozeCar) then
        setElementFrozen(state.frozeCar,false)
        state.frozeCar=nil
    end
    local officer = state.officer
    if officer and arresting[officer] == player then
        arresting[officer] = nil
        if isElement(officer) then
            if getElementData(officer,"npchlc_traffic:seatedArrestAim",false)==player then
                removeElementData(officer,"npchlc_traffic:seatedArrestAim")
            end
            if not isPedDead(officer) then setPedAnimation(officer) end
        end
    end
    if state.pose and isElement(player) and not isPedDead(player) then
        setPedAnimation(player)
        state.pose = nil
    end
end

function setTrafficPlayerFreeBail(player, enabled)
    if not isElement(player) or getElementType(player) ~= "player" or type(enabled) ~= "boolean" then
        return false
    end
    freeBail[player] = enabled or nil
    return true
end

local function release(player, interrupted)
    local state = active[player]
    if not state then return end
    endPose(player, state)
    active[player] = nil
    if not next(active) and timer and isTimer(timer) then
        killTimer(timer)
        timer = nil
    end
    if not isElement(player) then return end
    for _, control in ipairs(state.disabled) do toggleControl(player, control, true) end
    if state.froze then setElementFrozen(player, false) end
    if interrupted and state.faded then fadeCamera(player, true, 0.5) end
    if interrupted then triggerClientEvent(player, "traffic:bustedText", resourceRoot, false) end
end

local function restart(player, state)
    local x, y, z, heading = TrafficCustody.restartPoint(getElementPosition(player))
    state.restarting = true
    endPose(player, state)
    if getPedOccupiedVehicle(player) then removePedFromVehicle(player) end
    -- Preserve the player's multiplayer dimension. VCS returns to the outdoor world.
    setElementInterior(player, 0)
    state.interior = 0
    setElementPosition(player, x, y, z)
    setElementRotation(player, 0, 0, heading, "default", true)
    setElementVelocity(player, 0, 0, 0)
    triggerClientEvent(player, "traffic:bustedCameraEnd", resourceRoot)
    setPedAnimation(player)
    setPedArmor(player, 0)
    local maxHealth = math.max(1, 100 + (getPedStat(player, 24) - 569) / 4.31)
    setElementHealth(player, maxHealth)
    if freeBail[player] then
        freeBail[player] = nil
        -- 0x24C428 clears current weapons after release even on free bail.
        -- The previous confiscation is still available at the police pickups.
        takeAllWeapons(player)
        exports.wasted:ActivateWeaponBuyback(player, "busted")
    else
        local fine = math.min(math.max(0, getPlayerMoney(player)), fees[state.level])
        if fine > 0 then takePlayerMoney(player, fine) end
        exports.wasted:ConfiscatePlayerWeapons(player, "busted")
    end
    exports.wanted:resetPlayerWanted(player, "arrest")
    state.restarting = false
end

local function update()
    local now = getTickCount()
    for player, state in pairs(active) do
        if not isElement(player) or isPedDead(player) or getElementDimension(player) ~= state.dimension
            or getElementInterior(player) ~= state.interior then
            release(player, true)
        else
            local elapsed = (now - state.started) % 4294967296
            if elapsed > 2048 and not state.faded then
                state.faded = now
                fadeCamera(player, false, 2, 0, 0, 0)
            end
            if elapsed >= 4096 and not state.restarted and (now-state.faded)%4294967296 >= 2000 then
                state.restarted = now
                restart(player, state)
            end
            if state.restarted and (now-state.restarted)%4294967296 >= 512 and not state.fadingIn then
                state.fadingIn = now
                fadeCamera(player, true, 3)
            end
            if state.fadingIn and (now-state.fadingIn)%4294967296 >= 3000 then release(player, false) end
        end
    end
end

addEvent("traffic:onPlayerBusted",false)
function TrafficCustody.begin(player, level, officer)
    if active[player] or (officer and arresting[officer]) or not fees[level] or not isElement(player)
        or getElementType(player) ~= "player" or isPedDead(player) then return false end
    local state = {level = level, started = getTickCount(), disabled = {},
        dimension = getElementDimension(player), interior = getElementInterior(player), officer = officer}
    active[player] = state
    triggerEvent("traffic:onPlayerBusted",player)
    -- Cancelling an organizer or cutscene can release its freeze during this event.
    state.froze = not isElementFrozen(player)
    for _, control in ipairs(controls) do
        if isControlEnabled(player, control) then
            toggleControl(player, control, false)
            state.disabled[#state.disabled + 1] = control
        end
    end
    if state.froze then setElementFrozen(player, true) end
    if officer then arresting[officer] = player end
    local car=getPedOccupiedVehicle(player)
    if car and getVehicleOccupant(car,0)==player and not isElementFrozen(car) then
        if setElementFrozen(car,true) then state.frozeCar=car end
    elseif not car then
        state.pose = setPedAnimation(player, "PED", "handsup", -1, false, false, false, true)
    end
    triggerClientEvent(player, "traffic:bustedText", resourceRoot, true, officer)
    if not timer then timer = setTimer(update, 50, 0) end
    return true
end

local function interrupted()
    local state = active[source]
    if state and not state.restarting then release(source, true) end
end

addEventHandler("onPlayerWasted", root, interrupted)
addEventHandler("onPlayerSpawn", root, interrupted)
addEventHandler("onPlayerQuit", root, function()
    freeBail[source] = nil
    release(source, true)
end)
addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(active) do release(player, true) end
end, false)
