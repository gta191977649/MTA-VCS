local rules = WantedRules
local states = {}
local pendingEvents = {}
local publishing = false
local paroleKey = "nspray:paroleStars"
local clockPeriod = 4294967296

local provider
local ceilings = {[0]=0, 110, 365, 875, 1800, 3600, 7200}
local buckets = {{}, {}, {}, {}}
local nextBucket = 1
local function sendSnapshot(player, state, reason)
    if not state.clientReady then return end
    triggerClientEvent(player, "wanted:snapshot", resourceRoot, state.level,
        state.parole and state.parole.visible and rules.levelForPoints(state.parole.points) or 0, reason)
end

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
            if states[change[1]] and states[change[1]].clientReady then
                triggerClientEvent(change[1], "wanted:change", resourceRoot, change[2], change[3], change[4])
            end
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
        state.bucket = nextBucket
        buckets[nextBucket][player] = true
        nextBucket = nextBucket % #buckets + 1
    elseif level ~= state.level then
        level = math.min(level, state.cap or 6)
        if getPlayerWantedLevel(player) ~= level then setPlayerWantedLevel(player, level) end
        state.points = rules.forLevel(level)
        state.crimes = {}
        publish(player, state, level, "native")
    end
    return state
end

local function writePoints(player, state, points, reason)
    points = math.min(state.ceiling or 9600, points)
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
    sendSnapshot(player, state, "parole")
end

function getPlayerWanted(player)
    if not isPlayer(player) then return false end
    return observe(player, getTickCount()).level
end

function setPlayerWanted(player, level, reason)
    if not isPlayer(player) or type(level) ~= "number" then return false end
    local points = rules.forLevel(level)
    if not points or (reason ~= nil and type(reason) ~= "string") then return false end

    local state = observe(player, getTickCount())
    state.crimes = {}
    return writePoints(player, state, rules.forLevel(math.min(level, state.cap or 6)), reason or "script")
end

function suspendPlayerWanted(player)
    if not isPlayer(player) then return false end

    local now = getTickCount()
    local state = observe(player, now)
    if state.level == 0 then return false end
    local previousParole = state.parole
    state.parole = {points = state.points, started = now, visible = true}
    setElementData(player, paroleKey, state.level, "broadcast", "deny")
    if writePoints(player, state, 0, "respray") then
        sendSnapshot(player, state, "parole")
        return true
    end

    state.parole = previousParole
    if previousParole and previousParole.visible then
        setElementData(player, paroleKey, rules.levelForPoints(previousParole.points), "broadcast", "deny")
    else
        removeElementData(player, paroleKey)
    end
    return false
end

local function policeNearby(player, range)
    return provider and getResourceState(provider) == "running" and call(provider, "isWantedPoliceNearby", player, range) == true
end

local function applyCrime(player, state, crimeType, reduced)
    local parole = state.parole
    local points = rules.addCrime(state.points, parole and parole.points or 0, crimeType, reduced, state.multiplier)
    if parole and parole.visible then
        parole.visible = false
        removeElementData(player, paroleKey)
        sendSnapshot(player, state, "parole")
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

-- World events add a minimum level after the original immediate/deferred
-- crime path. Direct classified reports retain their independent semantics.
local eventCrime = {2, 7, 3, 1, [8]=6, [9]=10, [10]=11, [11]=4, [12]=5,
    [13]=17, [14]=13, [15]=14, [16]=15, [17]=18, [18]=19}
local eventLifetime = {[1]=2000, [3]=2000, [4]=1000, [8]=1500, [9]=1000, [10]=1000,
    [11]=10000, [12]=10000, [13]=1000, [14]=10000, [15]=10000, [16]=10000, [17]=2000, [18]=2000}

-- The world-event list (002792C0) survives direct star setters that empty
-- the separate 16-entry crime queue. Keep one bounded list per offender.
local function repeatWorldEvent(state, event, incident, now, lifetime)
    local list = state.worldEvents
    if not list then
        list = {}
        state.worldEvents = list
    end
    local free
    for i, entry in ipairs(list) do
        if elapsed(now, entry.at) > entry.lifetime then
            free = free or i
        elseif entry.event == event and entry.incident == incident then
            entry.at = now
            return true
        end
    end
    if free or #list < 64 then
        list[free or #list + 1] = {event=event, incident=incident, at=now, lifetime=lifetime}
    end
    return false
end

function reportWantedEvent(player, event, incident, immediate)
    if not isPlayer(player) or not eventCrime[event] then return false end
    if incident ~= nil and not isElement(incident) and type(incident) ~= "number" then return false end
    if immediate ~= nil and type(immediate) ~= "boolean" then return false end
    local now = getTickCount()
    if eventLifetime[event] and repeatWorldEvent(observe(player, now), event, incident or player, now, eventLifetime[event]) then
        return true
    end
    if immediate == nil then immediate = policeNearby(player, 14) == true end
    if not reportWantedCrime(player, eventCrime[event], incident, immediate) then return false end
    if (immediate or event == 3) and not raisePlayerWanted(player, 1, "crime") then return false end
    return (event ~= 12 and event ~= 18) or raisePlayerWanted(player, 2, "crime")
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
addEvent("onPlayerPoliceResponseChange", false)

addEventHandler("onPlayerJoin", root, function() observe(source, getTickCount()) end)
addEventHandler("onPlayerQuit", root, function()
    local state = states[source]
    if state then buckets[state.bucket][source] = nil end
    states[source] = nil
end)
addEventHandler("onPlayerWasted", root, function()
    local state = observe(source, getTickCount())
    state.respawn = true
    clearParole(source, state)
end)
addEventHandler("onPlayerSpawn", root, function()
    local state = states[source]
    if state and state.respawn then
        state.respawn = nil
        resetPlayerWanted(source, "respawn")
    end
end)

-- VCS reports event 4 -> crime 1 when firing a bullet (0x002C3E48).
-- Native MTA supplies the shooter without a client-script report.
addEventHandler("onPlayerWeaponFire", root, function()
    reportWantedEvent(source, 4, source)
end)

addEventHandler("onResourceStart", resourceRoot, function()
    local now = getTickCount()
    for _, player in ipairs(getElementsByType("player")) do observe(player, now) end
    local bucket = 1
    setTimer(function()
        local tick = getTickCount()
        for player in pairs(buckets[bucket]) do updatePlayer(player, tick) end
        bucket = bucket % #buckets + 1
    end, 50, 0)
end, false)

addEventHandler("onResourceStop", resourceRoot, function()
    for player, state in pairs(states) do clearParole(player, state) end
end, false)

function raisePlayerWanted(player, level, reason)
    if not isPlayer(player) or not rules.forLevel(level) or (reason ~= nil and type(reason) ~= "string") then return false end
    local now = getTickCount()
    local state = observe(player, now)
    if state.parole and elapsed(now, state.parole.started) > 20000 then clearParole(player, state) end
    local saved = state.parole and rules.levelForPoints(state.parole.points) or 0
    if state.level < saved and not setPlayerWanted(player, saved, reason) then return false end
    return state.level >= math.min(level, state.cap or 6) or setPlayerWanted(player, level, reason)
end

function resetPlayerWanted(player, reason)
    if not isPlayer(player) or (reason ~= nil and type(reason) ~= "string") then return false end
    local state = observe(player, getTickCount())
    local previousOverrides = state.overrides
    state.cap, state.ceiling, state.overrides, state.multiplier = nil, nil, nil, nil
    if previousOverrides then triggerEvent("onPlayerPoliceResponseChange", player) end
    state.crimes, state.worldEvents, state.lastUpdate = {}, nil, getTickCount()
    clearParole(player, state)
    return writePoints(player, state, 0, reason or "reset")
end

function setPlayerWantedCap(player, maximum)
    if not isPlayer(player) or not ceilings[maximum] then return false end
    local state = observe(player, getTickCount())
    state.cap, state.ceiling = maximum, ceilings[maximum]
    return writePoints(player, state, state.points, "cap")
end

function setPlayerCrimeMultiplier(player, multiplier)
    if not isPlayer(player) or type(multiplier) ~= "number" or multiplier < 0
        or multiplier ~= multiplier or multiplier == math.huge then return false end
    observe(player, getTickCount()).multiplier = multiplier
    return true
end

local overrideNames = {swat=true, fbi=true, army=true, suppressPolice=true, suppressGarage=true}
function setPlayerPoliceOverride(player, name, active)
    if not isPlayer(player) or not overrideNames[name] or type(active) ~= "boolean" then return false end
    local state = observe(player, getTickCount())
    state.overrides = state.overrides or {}
    if (state.overrides[name] == true) == active then return true end
    state.overrides[name] = active or nil
    triggerEvent("onPlayerPoliceResponseChange", player)
    return true
end

function getPlayerPoliceResponse(player)
    if not isPlayer(player) then return false end
    local state = observe(player, getTickCount())
    local result = rules.getPoliceResponse(state.level)
    for name in pairs(state.overrides or {}) do result[name] = true end
    if result.suppressPolice or result.suppressGarage then result.policeHelicopters = 0 end
    return result
end

function getWantedResponseForLevel(level)
    return rules.getPoliceResponse(level)
end

function registerPolicePresenceProvider()
    if not sourceResource or getResourceName(sourceResource) ~= "npchlc_traffic" then return false end
    provider = sourceResource
    return true
end
addEventHandler("onResourceStop", root, function(resource)
    if provider == resource then provider = nil end
end)
addEventHandler("onPlayerResourceStart", root, function(resource)
    if resource == getThisResource() then
        local state = observe(source, getTickCount())
        state.clientReady = true
        sendSnapshot(source, state, "initial")
    end
end)
