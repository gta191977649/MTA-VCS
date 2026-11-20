PedActivity = {}

local hlc = exports.npc_hlc
local actors, slots = {}, {}
local queues = {}
local capacities = {atm=5, seat=1, bus=5, shop=5, shelter=5, work=1, beach=1}
local cells, sequence = {}, 0
local motion = "npchlc_traffic:activityMotion"
local turn = "npchlc_traffic:activityHeading"
local function age(now, thenTick) return (now - thenTick) % 4294967296 end
local function cell(x, y) return math.floor(x / 32) .. "/" .. math.floor(y / 32) end
local function insertSite(site)
    local key = cell(site[6], site[7])
    cells[key] = cells[key] or {}
    table.insert(cells[key], site)
end
for _, site in ipairs(PedActivitySites) do insertSite(site) end

local function beachWeather()
    local hour = getTime()
    return hour >= 10 and hour <= 18 and (getRainLevel() or 0) == 0
end

local function beachSite(x,y,z,profile)
    if (profile.name ~= "STAT_BEACH_GUY" and profile.name ~= "STAT_BEACH_GIRL") or not beachWeather() then return end
    for _, bounds in ipairs(PedActivityBeaches) do
        if x >= bounds[1] and y >= bounds[2] and z >= bounds[3]
            and x <= bounds[4] and y <= bounds[5] and z <= bounds[6] then
            for site in pairs(slots) do
                if site[1] == "beach" and (site[6]-x)^2 + (site[7]-y)^2 < 9 then return end
            end
            return {"beach", false, x,y,z, x,y,z, math.random(0,359)}
        end
    end
end

local function nearest(ped, profile)
    local x,y,z = getElementPosition(ped)
    local best, bestDist
    for i = -1, 1 do
        for j = -1, 1 do
            for _, site in ipairs(cells[cell(x+i*32, y+j*32)] or {}) do
                local dx,dy,dz = site[6]-x, site[7]-y, site[8]-z
                local dist = dx*dx + dy*dy + dz*dz
                local limit = site[1] == "work" and 28 or 10
                local approach = not site[11] or site[1] == "work" or site[1] == "shelter"
                    or -(dx*site[11]+dy*site[12]+dz*site[13]) > math.sqrt(dist)*0.25
                if approach and (site[1] ~= "shelter" or (getRainLevel() or 0) >= 0.2)
                    and (not queues[site] or #queues[site] < capacities[site[1]]) and math.abs(dz) < 2.2 and dist < limit*limit
                    and (not bestDist or dist < bestDist) then
                    best, bestDist = site, dist
                end
            end
        end
    end
    return best or beachSite(x,y,z,profile)
end

local function clearWalk(ped, state)
    hlc:clearNPCTasks(ped)
    state.queued, state.crossing, state.nextCrossing = 0, nil, nil
    state.blockedSince, state.retryAt = nil, nil
end

local function queuePosition(base, index)
    if index == 1 then return base end
    local site = {unpack(base)}
    if base[1] == "shelter" then
        local angle = (index-2)*math.pi/2
        site[6],site[7] = site[6]+math.cos(angle),site[7]+math.sin(angle)
    else
        site[6],site[7] = site[6]+(index-1)*site[11],site[7]+(index-1)*site[12]
    end
    return site
end

local function release(ped)
    local actor = actors[ped]
    if not actor then return end
    slots[actor.site], actors[ped] = nil, nil
    local queue = queues[actor.base]
    for i,entry in ipairs(queue) do
        if entry == actor then
            table.remove(queue,i)
            if actor.base[1] ~= "shelter" then
                for j=i,#queue do queue[j].newPosition = j end
            end
            break
        end
    end
    if #queue == 0 then queues[actor.base] = nil end
    actor.walk.activityChecked = getTickCount()
    if isElement(ped) and actor.ownsWalk then
        clearWalk(ped, actor.walk)
        actor.walk.anchor, actor.walk.blockedSince = nil, getTickCount()
        if actor.clip then removeElementData(ped, motion) end
        if actor.phase == "turn" then removeElementData(ped, turn) end
    end
end

PedActivity.cancel = release
function PedActivity.debugTask(ped)
    local actor = actors[ped]
    if actor then return actor.site[1], actor.phase end
end

function PedActivity.active(ped) return actors[ped] ~= nil end

local function requestProbe(ped, actor, now)
    local peer = getElementSyncer(ped) or actor.walk.owner
    if not isElement(peer) or getElementDimension(peer) ~= 0 or getElementInterior(peer) ~= 0 then return false end
    sequence = sequence + 1
    actor.peer, actor.token, actor.sent = peer, sequence, now
    return triggerClientEvent(peer, "npchlc_traffic:activityProbe", resourceRoot, ped, sequence, actor.site,
        actor.phase == "probe")
end

addEvent("npchlc_traffic:activityReply", true)
addEventHandler("npchlc_traffic:activityReply", resourceRoot, function(ped, token, result)
    local actor = actors[ped]
    if not actor or not actor.token or client ~= actor.peer or token ~= actor.token
        or getElementDimension(client) ~= 0 or getElementInterior(client) ~= 0
        or age(getTickCount(), actor.sent) > 2400 then return end
    actor.token = nil
    if result == "streaming" then
        actor.waitingSince = actor.waitingSince or getTickCount()
        return
    end
    local x,y,z = getElementPosition(ped)
    local px,py,pz = getElementPosition(client)
    if type(result) ~= "number" or not (math.abs(result - actor.site[8]) <= 2)
        or getDistanceBetweenPoints3D(x,y,z,px,py,pz) > 220 then
        release(ped)
        return
    end
    actor.ground, actor.waitingSince = result, nil
end, false)

local function tryActivity(ped, state, now)
    if getElementInterior(ped) ~= 0 or getElementDimension(ped) ~= 0 or isPedInVehicle(ped) then return false end
    local profile = PedAI.profile(ped)
    if not profile or (profile.pedType ~= 4 and profile.pedType ~= 5) then return false end
    local site = nearest(ped,profile)
    if not site then return false end
    local base = site
    local queue = queues[base] or {}
    local position = #queue+1
    if base[1] == "shelter" then
        for i=1,capacities.shelter do
            local used = false
            for _,entry in ipairs(queue) do if entry.position == i then used = true end end
            if not used then position=i break end
        end
    end
    site = queuePosition(base,position)
    local actor = {base=base, site=site, position=position, walk=state,phase="probe",started=now}
    queue[#queue+1], queues[base] = actor,queue
    slots[site], actors[ped] = ped, actor
    if requestProbe(ped, actor, now) then return true end
    release(ped)
    return false
end

function PedActivity.onSpawn(ped, state)
    local now = getTickCount()
    state.activityChecked = now
    return tryActivity(ped, state, now)
end

local function play(ped, actor, phase, clip, now, duration, loop)
    actor.phase, actor.clip, actor.started, actor.duration = phase, clip, now, duration
    sequence = sequence + 1
    actor.revision = sequence
    setElementData(ped, motion, {clip, loop == true, sequence, PedActivityClips[clip]}, "broadcast", "deny")
end

-- A newly streamed observer can enter the original four-second clip mid-phase.
addEvent("npchlc_traffic:activityClock", true)
addEventHandler("npchlc_traffic:activityClock", resourceRoot, function(ped, revision)
    local actor = actors[ped]
    if not isElement(client) or not isElement(ped) then return end
    local started = actor and actor.clip and actor.revision == revision and actor.started
    if not started then
        local data = getElementData(ped,motion,false)
        started = type(data) == "table" and data[3] == revision and data[5]
    end
    if type(started) ~= "number" then return end
    local x,y,z = getElementPosition(ped)
    local px,py,pz = getElementPosition(client)
    if getElementDimension(ped) == getElementDimension(client) and getElementInterior(ped) == getElementInterior(client)
        and getDistanceBetweenPoints3D(x,y,z,px,py,pz) <= 220 then
        triggerClientEvent(client, "npchlc_traffic:activityElapsed", resourceRoot, ped, revision, age(getTickCount(),started))
    end
end, false)

local function requestTurn(ped,actor,now)
    local _,_,facing = getElementRotation(ped)
    local arc = math.abs((actor.site[9] - facing + 180) % 360 - 180)
    sequence = sequence + 1
    actor.turnRevision, actor.aligned, actor.started = sequence, false, now
    actor.turnTime = math.max(0, arc - 5) / 0.16
    setElementData(ped, turn, {actor.site[9],sequence}, "broadcast", "deny")
    triggerClientEvent(actor.peer, "npchlc_traffic:activityObserveTurn",resourceRoot,ped,sequence)
end

local function beginTurn(ped, actor, now)
    clearWalk(ped, actor.walk)
    actor.phase = "turn"
    requestTurn(ped,actor,now)
end

addEvent("npchlc_traffic:activityTurned",true)
addEventHandler("npchlc_traffic:activityTurned",resourceRoot,function(ped,revision,heading)
    local actor = actors[ped]
    if not actor or actor.phase ~= "turn" or actor.turnRevision ~= revision or actor.peer ~= client
        or (getElementSyncer(ped) or actor.walk.owner) ~= client or type(heading) ~= "number"
        or not (math.abs((actor.site[9] - heading + 180) % 360 - 180) <= 2)
        or age(getTickCount(),actor.started) > 5000 then return end
    local x,y,z = getElementPosition(ped)
    local px,py,pz = getElementPosition(client)
    if getElementDimension(client) == 0 and getElementInterior(client) == 0
        and getDistanceBetweenPoints3D(x,y,z,px,py,pz) <= 220
        and (x-actor.site[6])^2+(y-actor.site[7])^2 <= 0.6^2
        and math.abs(z-actor.ground-0.85) <= 1.15 then actor.aligned = true end
end,false)

local function atSite(ped, actor, now)
    local s = actor.site
    -- The syncer's smooth turn is complete. Persist its result for later
    -- observers because GTA ped position sync does not transmit scripted yaw.
    setElementRotation(ped,0,0,s[9],"default",true)
    removeElementData(ped, turn)
    if actor.position > 1 and s[1] ~= "shelter" then
        actor.phase, actor.started, actor.duration = "waiting", now, math.huge
    elseif s[1] == "seat" then
        play(ped, actor, "enter", "seat_down", now, PedActivityClips.seat_down)
    elseif s[1] == "work" then
        play(ped, actor, "enter", "emp_bar_idle", now, PedActivityClips.emp_bar_idle)
    elseif s[1] == "atm" then
        play(ped, actor, "transaction", "atm", now, PedActivityClips.atm)
    elseif s[1] == "shelter" or s[1] == "shop" or s[1] == "bus" then
        actor.phase, actor.started = "waiting", now
        actor.duration = s[1] == "shop" and 2000 or math.huge
    else
        play(ped, actor, "lower", "beach_lower", now, PedActivityClips.beach_lower)
    end
end

local function nextPhase(ped, actor, now)
    local kind = actor.site[1]
    if actor.phase == "transaction" then
        actor.walk.cash = ((actor.walk.cash or 0) + 20*math.random(1,50)) % 65536
        release(ped)
    elseif actor.phase == "waiting" and kind == "shop" then
        actor.walk.cash = math.max(0,(actor.walk.cash or 0)-10)
        release(ped)
    elseif actor.phase == "enter" then
        local clip = kind == "seat" and "seat_idle" or "emp_bar_clean"
        play(ped, actor, "idle", clip, now, kind == "seat" and math.random(25000, 30000) or math.random(10000, 25000), true)
    elseif actor.phase == "lower" then
        play(ped, actor, "recline", "beach_recline", now, PedActivityClips.beach_recline)
    elseif actor.phase == "recline" then
        play(ped, actor, "idle", "sunbathe", now, math.random(50000, 100000), true)
    elseif actor.phase == "idle" then
        local clip = kind == "seat" and "seat_up" or kind == "work" and "emp_bar_look" or "sunbathe_to_sit"
        play(ped, actor, kind == "beach" and "sitting" or "leave", clip, now, PedActivityClips[clip])
    elseif actor.phase == "sitting" then
        play(ped, actor, "leave", "sunbathe_stand", now, PedActivityClips.sunbathe_stand)
    else
        release(ped)
    end
end

-- Wait 0x18 continues through 0x17 before the stored threat takes control.
function PedActivity.leaveForThreat(ped, state, now)
    local actor = actors[ped]
    if not actor or (actor.site[1] ~= "seat" and actor.site[1] ~= "beach") then return false end
    if actor.phase == "idle" then nextPhase(ped, actor, now) end
    if actor.phase ~= "leave" and actor.phase ~= "sitting" then return false end
    return PedActivity.update(ped, state, now)
end

function PedActivity.update(ped, state, now)
    local actor = actors[ped]
    if not actor then
        if state.crossing then return false end
        state.activityTicks = (state.activityTicks or 0)+1
        if state.activityTicks <= 11 then return false end
        state.activityTicks = 0
        state.activityChecked = now
        return tryActivity(ped, state, now)
    end
    if actor.newPosition then
        slots[actor.site] = nil
        actor.position, actor.newPosition = actor.newPosition,nil
        actor.site = queuePosition(actor.base,actor.position)
        slots[actor.site] = ped
        if actor.phase == "turn" then removeElementData(ped,turn) end
        clearWalk(ped,state)
        actor.phase,actor.started,actor.ground = "probe",now,nil
        if not requestProbe(ped,actor,now) then release(ped) return false end
    end
    if actor.site[1] == "shelter" and (getRainLevel() or 0) < 0.2 then
        release(ped)
        return false
    end
    if isPedInVehicle(ped) or getElementDimension(ped) ~= 0 or getElementInterior(ped) ~= 0 or isPedDead(ped) then
        release(ped)
        return false
    end
    local peer = getElementSyncer(ped) or state.owner
    if peer ~= actor.peer then
        actor.waitingSince = now
        if not requestProbe(ped,actor,now) then release(ped) return false end
        if actor.phase == "turn" then requestTurn(ped,actor,now) end
    end
    if actor.token and age(now,actor.sent) > 2400 or actor.waitingSince and age(now,actor.waitingSince) > 2400 then
        release(ped)
        return false
    end
    if actor.waitingSince and not actor.token and age(now,actor.sent) >= 250 then
        if not requestProbe(ped,actor,now) then release(ped) return false end
    end
    if actor.phase == "probe" then
        if actor.token or actor.waitingSince then return true end
        actor.ownsWalk = true
        local site = actor.site
        clearWalk(ped, state)
        if site[1] == "beach" then
            beginTurn(ped, actor, now)
        else
            local angle = math.rad(site[9])
            local ahead = site[1] == "seat" and 0.85 or 0
            actor.x, actor.y = site[6] - ahead*math.sin(angle), site[7] + ahead*math.cos(angle)
            if not hlc:addNPCTask(ped, {"walkToPos", actor.x, actor.y, actor.ground + 0.85, 0.2}) then
                release(ped)
                return false
            end
            actor.phase, actor.started = ahead > 0 and "approach" or "entry", now
        end
    elseif actor.phase == "approach" or actor.phase == "entry" then
        local x,y,z = getElementPosition(ped)
        if (x-actor.x)^2 + (y-actor.y)^2 <= 0.29^2 and math.abs(z - actor.ground - 0.85) < 1.15 then
            if actor.phase == "approach" then
                clearWalk(ped,state)
                actor.phase, actor.x, actor.y = "entry", actor.site[6], actor.site[7]
                if not hlc:addNPCTask(ped, {"walkToPos",actor.x,actor.y,actor.ground+0.85,0.16}) then
                    release(ped)
                    return false
                end
            else
                beginTurn(ped,actor,now)
            end
        elseif age(now,actor.started) > 25000 then
            release(ped)
            return false
        end
    elseif actor.phase == "turn" then
        local x,y = getElementPosition(ped)
        if age(now,actor.started) > 5000 or (x-actor.site[6])^2 + (y-actor.site[7])^2 > 0.6^2 then
            release(ped)
            return false
        elseif actor.aligned and age(now,actor.started) >= actor.turnTime then
            atSite(ped,actor,now)
        end
    elseif age(now,actor.started) >= actor.duration
        or actor.site[1] == "beach" and actor.phase == "idle" and not beachWeather() then
        nextPhase(ped, actor, now)
    end
    if actors[ped] and not actor.token and age(now,actor.sent) >= 2500 and not requestProbe(ped,actor,now) then
        release(ped)
    end
    return actors[ped] ~= nil
end

function PedActivity.stats()
    local stats = {seat = 0, work = 0, beach = 0, atm = 0, shelter = 0, shop = 0, bus = 0}
    for site in pairs(slots) do stats[site[1]] = stats[site[1]] + 1 end
    return stats
end

function PedActivity.stop()
    for ped in pairs(actors) do release(ped) end
end

addEventHandler("onElementDestroy", root, function() release(source) end)
