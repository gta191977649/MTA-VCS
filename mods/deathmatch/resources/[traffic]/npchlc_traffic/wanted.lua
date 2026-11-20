local rules = TrafficWantedRules
local states = {}
local pendingEvents = {}
local publishing = false
local paroleKey = "nspray:paroleStars"
local clockPeriod = 4294967296

TrafficWanted = {getPoliceResponse = rules.getPoliceResponse}

local function elapsed(now, thenTick)
    return (now - thenTick) % clockPeriod
end

local function isPlayer(player)
    return isElement(player) and getElementType(player) == "player"
end

local function publish(player, state, level, reason)
    local oldLevel = state.level
    state.level = level
    if oldLevel == level then return end

    pendingEvents[#pendingEvents + 1] = {player, oldLevel, level, reason}
    if publishing then return end
    publishing = true
    local index = 1
    while index <= #pendingEvents do
        local change = pendingEvents[index]
        if isPlayer(change[1]) then
            triggerEvent("onPlayerWanted", change[1], change[2], change[3], change[4])
        end
        index = index + 1
    end
    pendingEvents = {}
    publishing = false
end

local function observe(player, now)
    local level = getPlayerWantedLevel(player)
    local state = states[player]
    if not state then
        state = {level = level, points = rules.forLevel(level), lastUpdate = now, crimes = {}}
        states[player] = state
    elseif level ~= state.level then
        state.points = rules.forLevel(level)
        state.crimes = {}
        publish(player, state, level, "native")
    end
    return state
end

local function writePoints(player, state, points, reason)
    local level = rules.levelForPoints(points)
    if level ~= state.level and not setPlayerWantedLevel(player, level) then return false end
    state.points = points
    publish(player, state, level, reason)
    return true
end

local function clearParole(player, state)
    if not state.parole then return end
    if state.parole.visible then removeElementData(player, paroleKey) end
    state.parole = nil
end

function getPlayerWanted(player)
    if not isPlayer(player) then return false end
    return getPlayerWantedLevel(player)
end

function setPlayerWanted(player, level, reason)
    if not isPlayer(player) or type(level) ~= "number" then return false end
    local points = rules.forLevel(level)
    if not points or (reason ~= nil and type(reason) ~= "string") then return false end

    local state = observe(player, getTickCount())
    state.crimes = {}
    return writePoints(player, state, points, reason or "script")
end

function suspendPlayerWanted(player)
    if not isPlayer(player) then return false end

    local now = getTickCount()
    local state = observe(player, now)
    if state.level == 0 then return false end
    local previousParole = state.parole
    state.parole = {points = state.points, started = now, visible = true}
    setElementData(player, paroleKey, state.level, "broadcast", "deny")
    if writePoints(player, state, 0, "respray") then return true end

    state.parole = previousParole
    if previousParole and previousParole.visible then
        setElementData(player, paroleKey, rules.levelForPoints(previousParole.points), "broadcast", "deny")
    else
        removeElementData(player, paroleKey)
    end
    return false
end

local function policeNearby(player, range)
    return TrafficActors and TrafficActors.isPoliceNearby and TrafficActors.isPoliceNearby(player, range)
end

local function applyCrime(player, state, crimeType, reduced)
    local parole = state.parole
    local points = rules.addCrime(state.points, parole and parole.points or 0, crimeType, reduced)
    if parole and parole.visible then
        parole.visible = false
        removeElementData(player, paroleKey)
    end
    return writePoints(player, state, points, "crime")
end

-- 0x003AB2A8 scans 16 records by crime ID and incident identity. An
-- immediate report in 0x003AAB08 still adds an unreported queue record.
local function queueCrime(state, crimeType, incident, reduced, now)
    local vacancy
    for index = 1, 16 do
        local record = state.crimes[index]
        if record then
            if record.type == crimeType and record.incident == incident then return not record.reported end
        elseif not vacancy then
            vacancy = index
        end
    end

    if vacancy then
        state.crimes[vacancy] = {type = crimeType, incident = incident, reduced = reduced, started = now}
    end
    return true
end

-- Server scripts report a classified VCS incident. A nil immediate value
-- uses the 14 m police-presence branch at 0x00279768.
function reportWantedCrime(player, crimeType, incident, immediate, reduced)
    if not isPlayer(player) or not rules.isCrimeType(crimeType) then return false end
    if incident ~= nil and not isElement(incident) and type(incident) ~= "number" then return false end
    if immediate ~= nil and type(immediate) ~= "boolean" then return false end
    if reduced ~= nil and type(reduced) ~= "boolean" then return false end

    local now = getTickCount()
    local state = observe(player, now)
    if state.parole and elapsed(now, state.parole.started) > 20000 then clearParole(player, state) end
    if immediate == nil then immediate = policeNearby(player, 14) end
    if queueCrime(state, crimeType, incident or player, reduced, now) and immediate then
        return applyCrime(player, state, crimeType, reduced)
    end
    return true
end

local function updatePlayer(player, now)
    local state = observe(player, now)
    if state.parole and elapsed(now, state.parole.started) > 20000 then clearParole(player, state) end
    if elapsed(now, state.lastUpdate) <= 1000 then return end
    if state.points == 0 and next(state.crimes) == nil then
        state.lastUpdate = now
        return
    end
    if state.level >= 2 then
        state.lastUpdate = now
    elseif not policeNearby(player, 18) then
        state.lastUpdate = now
        if state.points > 0 then
            writePoints(player, state, state.points - 1, "decay")
        end
    end

    for index = 1, 16 do
        local record = state.crimes[index]
        if record then
            local age = elapsed(now, record.started)
            if age > 500 and not record.reported then
                record.reported = true
                applyCrime(player, state, record.type, record.reduced)
            end
            if age > 10000 and state.crimes[index] == record then state.crimes[index] = nil end
        end
    end
end

addEvent("onPlayerWanted", false)

addEventHandler("onPlayerJoin", root, function() observe(source, getTickCount()) end)
addEventHandler("onPlayerQuit", root, function() states[source] = nil end)
addEventHandler("onPlayerWasted", root, function()
    local state = observe(source, getTickCount())
    state.respawn = true
    clearParole(source, state)
end)
addEventHandler("onPlayerSpawn", root, function()
    local state = states[source]
    if state and state.respawn then
        state.respawn = nil
        setPlayerWanted(source, 0, "respawn")
    end
end)

-- VCS reports event 4 -> crime 1 when firing a bullet (0x002C3E48).
-- Native MTA supplies the shooter without a client-script report.
addEventHandler("onPlayerWeaponFire", root, function()
    local now = getTickCount()
    local state = observe(source, now)
    local last = state.lastShot
    state.lastShot = now
    if last and elapsed(now, last) <= 1000 then return end
    reportWantedCrime(source, 1, source)
end)

-- 0x002C6460 and 0x002C7C28 submit an additional firearm hit report after
-- the general damage report in 0x001D7940. MTA only exposes full attribution
-- for a ped on the server when the damage was fatal.
addEventHandler("onPedWasted", root, function(_, killer, weapon)
    local victim = source
    if type(weapon) ~= "number" or weapon < 22 or weapon > 34 or not isPlayer(killer)
        or not TrafficActors.isManagedPed(victim)
        or getElementInterior(killer) ~= getElementInterior(victim)
        or getElementDimension(killer) ~= getElementDimension(victim) then
        return
    end

    local police = TrafficActors.isPolicePed(victim)
    local immediate = policeNearby(killer, 14) == true
    if police and not immediate then
        local x, y, z = getElementPosition(killer)
        local vx, vy, vz = getElementPosition(victim)
        local dx, dy, dz = x - vx, y - vy, z - vz
        immediate = dx * dx + dy * dy + dz * dz < 14 * 14
    end
    reportWantedCrime(killer, police and 3 or 2, victim, immediate)
    reportWantedCrime(killer, police and 5 or 4, victim, immediate)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local now = getTickCount()
    for _, player in ipairs(getElementsByType("player")) do observe(player, now) end
    setTimer(function()
        local tick = getTickCount()
        for player in pairs(states) do updatePlayer(player, tick) end
    end, 200, 0)
end, false)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, state in pairs(states) do clearParole(player, state) end
end, false)
-- A wanted arrest is committed by the same authority that owns wanted points.
local entering, arrests, restrained = {}, {}, {}
addEvent("onTrafficPlayerArrest",false)
addEventHandler("onVehicleStartEnter",root,function(p,seat)
    if getElementType(p)=="player" and seat==0 then entering[p]={vehicle=source,at=getTickCount()} end
end)
addEventHandler("onVehicleEnter",root,function(p) entering[p]=nil end)
addEventHandler("onPlayerQuit",root,function() entering[source]=nil; arrests[source]=nil; restrained[source]=nil end)

-- The game mode owns the player control state. It can report its native
-- equivalent of 0x41 while retaining authority over jail or release.
function setTrafficPlayerRestrained(player,active)
    if not isPlayer(player) or type(active)~="boolean" then return false end
    restrained[player]=active or nil
    return true
end
addEventHandler("onPlayerSpawn",root,function() restrained[source],entering[source]=nil,nil end)
local function eligibleOfficer(officer,player,allowWasted)
    if not isElement(player) or getElementType(player)~="player" or (isPedDead(player) and not allowWasted)
        or not isElement(officer) or not TrafficActors.isPolicePed(officer) or isPedDead(officer)
        or getPlayerWantedLevel(player)==0 or getElementInterior(officer)~=getElementInterior(player)
        or getElementDimension(officer)~=getElementDimension(player) then return false end
    local x,y,z=getElementPosition(officer)
    return getDistanceBetweenPoints3D(x,y,z,getElementPosition(player))<=65
end
function TrafficWanted.officerCanPursue(officer,player)
    return eligibleOfficer(officer,player,false)
end
local function arrest(officer,player,now,wasted)
    if not eligibleOfficer(officer,player,wasted) then return false end
    local entry=entering[player]
    local x,y,z=getElementPosition(player)
    local officerDistance=getDistanceBetweenPoints3D(x,y,z,getElementPosition(officer))
    local duringEntry=entry and isElement(entry.vehicle) and (now-entry.at)%4294967296<=1800
        and not isPedInVehicle(player) and getDistanceBetweenPoints3D(x,y,z,getElementPosition(entry.vehicle))<=4
    if not ((wasted or restrained[player]) and officerDistance<5 or duringEntry and officerDistance<1.3) then return false end
    if arrests[player] then return false end
    arrests[player]=officer
    local level=getPlayerWantedLevel(player)
    -- The game mode may cancel this event and process the arrest itself.
    local accepted=triggerEvent("onTrafficPlayerArrest",player,officer,level,wasted and "wasted" or "alive")
    arrests[player],entering[player]=nil,nil
    if not accepted or not isElement(player) or not isElement(officer) then return false end
    restrained[player]=nil
    if not wasted then setPlayerWanted(player,0,"arrest") end
    local ox,oy=getElementPosition(officer)
    setPedRotation(officer,-math.deg(math.atan2(x-ox,y-oy)))
    if getPedWeapon(officer,2)==22 then setPedWeaponSlot(officer,2) end
    setPedAnimation(officer,"PED","ARRESTgun",1200,false,false,true,false)
    PedVoice.emit(officer,"arrest")
    PedVoice.emit(player,"arrested")
    return true
end

function TrafficWanted.tryArrest(officer,player,now)
    return arrest(officer,player,now,false)
end
-- The PS2 corpse branch leaves the player in its dying/wasted state.
-- Emit the ownership notification while preserving MTA's respawn lifecycle.
addEventHandler("onPlayerWasted",root,function()
    local player=source
    if not isPedDead(player) or getPlayerWantedLevel(player)==0 then return end
    local x,y,z=getElementPosition(player)
    local best,distance=nil,5
    for _,officer in ipairs(getElementsWithinRange(x,y,z,5,"ped",getElementInterior(player),getElementDimension(player)) or {}) do
        if eligibleOfficer(officer,player,true) then
            local d=getDistanceBetweenPoints3D(x,y,z,getElementPosition(officer))
            if d<distance then best,distance=officer,d end
        end
    end
    if best then arrest(best,player,getTickCount(),true) end
end)
