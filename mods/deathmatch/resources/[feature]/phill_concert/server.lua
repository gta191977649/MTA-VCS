local price = 6000
local x, y, z = -1056.27, 1330.77, 12.58
exports.marker:createMarker(x, y, z - 1, "cylinder", 1.6, 245, 88, 145, 150)
local entrance = createColSphere(x, y, z, 1.6)
local sessions = {}
local leaveFirst = {}
local serial = 0
local viewers = 0
local previousWarp

local function suspendUnderworldWarp()
    if viewers == 0 then
        previousWarp = isWorldSpecialPropertyEnabled("underworldwarp")
        setWorldSpecialPropertyEnabled("underworldwarp", false)
    end
    viewers = viewers + 1
end

local function releaseUnderworldWarp()
    viewers = viewers - 1
    if viewers == 0 then
        local enex = getResourceFromName("enex")
        if not enex or getResourceState(enex) ~= "running" then
            setWorldSpecialPropertyEnabled("underworldwarp", previousWarp)
        end
        previousWarp = nil
    end
end

local function tell(player, message)
    outputChatBox(message, player, 255, 205, 225)
end

local function eligible(player)
    return not isPedDead(player) and not isPedInVehicle(player)
end

local function atEntrance(player)
    return getElementInterior(player) == 0 and getElementDimension(player) == 0
        and isElementWithinColShape(player, entrance)
end

local function exit(player, reason)
    local session = sessions[player]
    if not session then return end
    sessions[player] = nil
    if isTimer(session.timeout) then killTimer(session.timeout) end
    if reason == "quit" then
        if session.entered then releaseUnderworldWarp() end
        return
    end
    if session.paid and reason == "failure" then
        givePlayerMoney(player, price)
        tell(player, "Concert unavailable. Your $6000 ticket was refunded.")
    end
    if session.entered then
        local s = session.saved
        setElementAlpha(player, s.alpha)
        setElementCollisionsEnabled(player, s.collisions)
        setElementFrozen(player, s.frozen)
        setElementDimension(player, s.dimension)
        if isPedDead(player) then
            setElementInterior(player, s.interior)
        else
            setElementInterior(player, s.interior, s.x, s.y, s.z)
            setElementPosition(player, s.x, s.y, s.z)
            setPedRotation(player, s.heading)
        end
        releaseUnderworldWarp()
    end
    if reason ~= "stop" then
        triggerClientEvent(player, "phillConcert:exit", resourceRoot, session.id)
    end
end

local function begin(player, debugStart)
    if sessions[player] or not eligible(player) then return end
    if debugStart == nil then
        if leaveFirst[player] or not atEntrance(player) then return end
        if getPlayerMoney(player) < price then
            triggerClientEvent(player, "phillConcert:ticketDenied", resourceRoot, price)
            return
        end
    end
    serial = serial + 1
    local session = { id = serial, debugStart = debugStart }
    sessions[player] = session
    session.timeout = setTimer(exit, 20000, 1, player, "failure")
    triggerClientEvent(player, "phillConcert:prepare", resourceRoot, serial, debugStart)
end

addEventHandler("onColShapeHit", entrance, function(player, matchingDimension)
    if matchingDimension and getElementType(player) == "player" and not leaveFirst[player]
        and not sessions[player] and eligible(player) and atEntrance(player) then
        triggerClientEvent(player, "phillConcert:offer", resourceRoot, true, price)
    end
end)

addEventHandler("onColShapeLeave", entrance, function(player)
    if getElementType(player) ~= "player" then return end
    local session = sessions[player]
    if not session or not session.entered then
        leaveFirst[player] = nil
        triggerClientEvent(player, "phillConcert:offer", resourceRoot, false)
        if session and session.debugStart == nil then exit(player, "cancel") end
    end
end)

addEvent("phillConcert:buy", true)
addEventHandler("phillConcert:buy", resourceRoot, function()
    if source == resourceRoot and client then begin(client) end
end)

addEvent("phillConcert:ready", true)
addEventHandler("phillConcert:ready", resourceRoot, function(id)
    if source ~= resourceRoot or not client then return end
    local player = client
    local session = sessions[player]
    if not session or session.id ~= id or session.entered then return end
    if not eligible(player) or (session.debugStart == nil and not atEntrance(player)) then
        exit(player, "cancel")
        return
    end
    local px, py, pz = getElementPosition(player)
    session.saved = {
        x = px, y = py, z = pz, heading = getPedRotation(player),
        alpha = getElementAlpha(player), collisions = getElementCollisionsEnabled(player),
        frozen = isElementFrozen(player), interior = getElementInterior(player),
        dimension = getElementDimension(player)
    }
    suspendUnderworldWarp()
    session.entered = true
    setElementFrozen(player, true)
    setElementCollisionsEnabled(player, false)
    setElementAlpha(player, 0)
    setElementDimension(player, ConcertStadium.dimension)
    setElementInterior(player, ConcertStadium.interior, -1568.09, 1359.76, -231.2)
    setElementPosition(player, -1568.09, 1359.76, -231.2)
    setPedRotation(player, 170)
    triggerClientEvent(player, "phillConcert:inside", resourceRoot, id)
end)

addEvent("phillConcert:stageReady", true)
addEventHandler("phillConcert:stageReady", resourceRoot, function(id)
    if source ~= resourceRoot or not client then return end
    local player = client
    local session = sessions[player]
    if not session or session.id ~= id or not session.entered or session.playing then return end
    if session.debugStart == nil then
        if getPlayerMoney(player) < price or not takePlayerMoney(player, price) then
            triggerClientEvent(player, "phillConcert:ticketDenied", resourceRoot, price)
            exit(player, "cancel")
            return
        end
        session.paid = true
        leaveFirst[player] = true
    end
    session.playing = true
    killTimer(session.timeout)
    session.timeout = setTimer(exit, 420000, 1, player, "failure")
    triggerClientEvent(player, "phillConcert:play", resourceRoot, id)
end)

addEvent("phillConcert:finish", true)
addEventHandler("phillConcert:finish", resourceRoot, function(id)
    if source ~= resourceRoot or not client then return end
    local session = sessions[client]
    if session and session.id == id then
        -- A client cannot issue itself a refund after the concert has started.
        exit(client, session.playing and "complete" or "cancel")
    end
end)

addCommandHandler("phillconcert", function(player, _, startAt)
    if not isElement(player) then return end
    local ip = getPlayerIP(player)
    if ip ~= "127.0.0.1" and ip ~= "::1"
        and not hasObjectPermissionTo(player, "command.start", false) then return end
    if not eligible(player) then
        tell(player, "Exit your vehicle and stay on foot to test the concert.")
        return
    end
    local seconds = startAt and tonumber(startAt) or 0
    if not seconds or seconds ~= seconds or seconds < 0 or seconds >= 377 then
        tell(player, "Usage: /phillconcert [seconds from 0 to 376]")
        return
    end
    begin(player, seconds)
end)

addEventHandler("onPlayerWasted", root, function()
    exit(source, "death")
    leaveFirst[source] = nil
end)

addEventHandler("onPlayerQuit", root, function()
    exit(source, "quit")
    leaveFirst[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(sessions) do exit(player, "stop") end
end)
