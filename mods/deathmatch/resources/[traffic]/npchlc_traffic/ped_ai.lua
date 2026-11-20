PedAI = {}
local brains = {}
local Intelligence = {}
Intelligence.__index = Intelligence
local rules = PedAIRules
local playerProfile = rules.profile(0)
local priorities = {serviceDuty = 1, gunpoint = 1,approach = 0, gunshot = 0, nearMiss = 1, witness = 1, ally = 1, passenger = 1, carjack = 2,
    vehicleThreat = 2, roadRage = 2, returnCar = 0, damage = 3}
local witnessSerial, poolSerial = 0, 0

local function elapsed(now, thenTick)
    return (now - thenTick) % 4294967296
end

local function leavingVehicle(kind)
    return kind == "carjack" or kind == "passenger" or kind == "vehicleThreat" or kind == "roadRage"
end

local function sameWorld(a, b)
    return isElement(a) and isElement(b) and getElementDimension(a) == getElementDimension(b)
        and getElementInterior(a) == getElementInterior(b)
end

local function distance(a, b)
    local x, y, z = getElementPosition(a)
    local tx, ty, tz = getElementPosition(b)
    return getDistanceBetweenPoints3D(x, y, z, tx, ty, tz)
end

function PedAI.attach(ped, model)
    if not brains[ped] then
        poolSerial = poolSerial + 1
        brains[ped] = setmetatable({ped = ped, poolSlot = poolSerial, profile = rules.profile(model), tasks = PedTaskManager.new(ped),
            objectives = PedObjectives.new(), losses = {}, reports = {}, receipts = {},
            health = getElementHealth(ped), sampled = getTickCount(), reactionDelay = math.random(250, 999)}, Intelligence)
        if PedServices and brains[ped].profile.pedType==6 then PedServices.initializeOfficer(ped,model) end
    end
    return brains[ped]
end

function PedAI.brain(ped) return brains[ped] end

function PedAI.isScriptControlled(ped)
    return brains[ped] and brains[ped].scriptOwner ~= nil or false
end

function PedAI.profile(ped)
    return brains[ped] and brains[ped].profile
end

function PedAI.setLeader(ped, leader)
    if not brains[ped] or ped == leader or not (brains[leader] or isElement(leader) and getElementType(leader) == "player") then return false end
    brains[ped].leader = leader
    return true
end

-- 00307550 mutates the responder's threat mask and the masks of nearby
-- members of its own group. Selecting an attack remains a separate decision.
function PedAI.rememberHostility(ped,attacker)
    local brain = brains[ped]
    if not brain or brain.scriptOwner or brain.leader == attacker then return end
    local group = brain.profile.pedType
    if group < 7 or group > 17 then return end
    local other = PedAI.profile(attacker) or playerProfile
    if other.pedType == 0 and (group == 13 or group == 15) or other.pedType ~= 0
        and (other.pedType < 7 or other.pedType > 15) then return end
    local bit = PedAITypes[other.pedType].identity
    if bit == 0 then return end
    local function remember(member)
        local mask = member.profile.threats or PedAITypes[group].threats
        if math.floor(mask / bit) % 2 == 0 then member.profile.threats = mask + bit end
    end
    remember(brain)
    local x,y,z = getElementPosition(ped)
    for _,neighbor in ipairs(getElementsWithinRange(x,y,z,22,"ped",getElementInterior(ped),getElementDimension(ped)) or {}) do
        local member = brains[neighbor]
        if member and not member.scriptOwner and member.profile.pedType == group and not isPedDead(neighbor) then remember(member) end
    end
end

addEventHandler("onPlayerDamage",root,function(attacker,weapon)
    if not isElement(attacker) or getElementType(attacker) ~= "ped" or not sameWorld(source,attacker) then return end
    local acting = brains[attacker]
    if acting and acting.event and acting.event.intent == "fight" and acting.event.target == source then
        acting.event.struck = getTickCount()
    end
    local profile = PedAI.profile(attacker)
    if not profile or profile.pedType == 6 then return end
    local x,y,z = getElementPosition(source)
    for _,ped in ipairs(getElementsWithinRange(x,y,z,30,"ped",getElementInterior(source),getElementDimension(source)) or {}) do
        local brain = brains[ped]
        if brain and brain.leader == source and brain.profile.temper > brain.profile.fear then
            brain:react("ally",attacker,weapon or 0,"fight","run",30000)
        end
    end
end)

function PedAI.detach(ped)
    if PedVehicleEvasion then PedVehicleEvasion.cancel(ped) end
    if PedSpecial then PedSpecial.cancel(ped) end
    brains[ped] = nil
end

function PedAI.busy(ped)
    if PedSpecial and PedSpecial.active(ped) then return true end
    if PedVehicleEvasion and PedVehicleEvasion.active(ped) then return true end
    return brains[ped] and brains[ped].event ~= nil or false
end

function Intelligence:react(kind, attacker, weapon, intent, pace, duration)
    if kind == "damage" and self.leader and (self.leader == attacker or isElement(self.leader) and getElementType(self.leader) == "player") then return false end
    if self.scriptOwner or self.burning or isPedDead(self.ped) or isPedInVehicle(self.ped) and not leavingVehicle(kind) or not sameWorld(self.ped, attacker)
        or self.ped == attacker or isPedDead(attacker) then return false end
    local now = getTickCount()
    local old = self.event
    if old and priorities[kind] < priorities[old.kind] then return false end
    intent = intent or rules.intent(kind, self.profile, PedAI.profile(attacker) or playerProfile,
        rules.ranged(weapon), self.tasks:hasRangedWeapon())
    if not intent then return false end
    if old and old.intent == intent and old.target == attacker and old.kind == kind then
        if kind ~= "gunshot" and kind ~= "nearMiss" then old.lastSeen = now end
        return true
    end
    local event = {kind = kind, target = attacker, intent = intent, pace = pace, duration = duration,
        started = now, lastSeen = now, originalRoad = old and old.originalRoad}
    if intent == "evade" then event.animation = rules.evadeAnimation(self.profile) end
    event.id = intent == "fight" and 8 or intent == "flee" and 10 or nil
    if event.id and not self.objectives:request(event) then
        local current = self.objectives.current
        if not current or current.id ~= event.id or current.target ~= attacker then return false end
        -- Same objective and target, but a stronger stimulus may carry a car
        -- or a different deadline. Keep just this actor's latest parameters.
        self.objectives.current = event
        self.objectives.revision = self.objectives.revision + 1
    end
    if event.id and self.objectives.current ~= event then return false end
    self.event = event
    if kind ~= "gunshot" then self.tasks:clear() end
    if TrafficAmbient and TrafficAmbient.scheduleReaction then
        TrafficAmbient.scheduleReaction(self.ped,event)
    end
    return true
end

-- The 22 m interest radius and validation window are multiplayer sampling budgets.
-- The server owns the candidate, target, event class and lifetime.
local function notifyWitnesses(brain, attacker, weapon)
    local victim = brain.ped
    local x, y, z = getElementPosition(victim)
    local now = getTickCount()
    if brain.witnessAt and elapsed(now, brain.witnessAt) < 1200 then return end
    brain.witnessAt = now
    witnessSerial = witnessSerial + 1
    local bySyncer = {}
    for _, ped in ipairs(getElementsWithinRange(x, y, z, 22, "ped", getElementInterior(victim), getElementDimension(victim)) or {}) do
        local witness = brains[ped]
        if witness and ped ~= victim and ped ~= attacker and not isPedDead(ped) and not isPedInVehicle(ped) then
            local owner = getElementSyncer(ped)
            if isElement(owner) then
                witness.sight = {id = witnessSerial, owner = owner, at = now, attacker = attacker,
                    victim = victim, weapon = weapon}
                bySyncer[owner] = bySyncer[owner] or {}
                table.insert(bySyncer[owner], ped)
            end
        end
    end
    for owner, observers in pairs(bySyncer) do
        triggerClientEvent(owner, "npchlc_traffic:pedObserve", resourceRoot, witnessSerial, victim, observers)
    end
end

addEvent("npchlc_traffic:pedSight", true)
addEventHandler("npchlc_traffic:pedSight", resourceRoot, function(id, observers)
    if source ~= resourceRoot or type(observers) ~= "table" then return end
    for i = 1, math.min(#observers, 64) do
        local ped = observers[i]
        local brain = brains[ped]
        local pending = brain and brain.sight
        if pending and pending.id == id and pending.owner == client and getElementSyncer(ped) == client then
            brain.sight = nil
            if elapsed(getTickCount(), pending.at) < 1200 and sameWorld(ped, pending.victim)
                and distance(ped, pending.victim) < 25 then
                brain:react(brain.leader == pending.victim and "ally" or "witness",
                    pending.attacker, pending.weapon)
            end
        end
    end
end)

function PedAI.carjacked(ped, player, vehicle, roadState)
    local brain = brains[ped]
    if not brain or not sameWorld(ped, player) then return end
    local current = brain.event
    if roadState and current and current.kind == "carjack" and current.road == roadState then return end
    local accepted = brain:react("carjack", player, getPedWeapon(player))
    if accepted and roadState and roadState.driver == ped and roadState.vehicle == vehicle then
        local event = brain.event
        event.road = roadState
        PedCarjack.capture(event, vehicle, player)
        if not event.resolved then
            event.attackTarget = current and current.intent == "fight" and current.target or event.attackTarget
        end
    end
    if PedVoice and (not current or current.kind ~= "carjack" or current.target ~= player) then
        PedVoice.emit(ped, "carjack")
    end
    notifyWitnesses(brain, player, getPedWeapon(player))
end

function PedAI.passengerThreat(ped, jacker)
    local brain = brains[ped]
    if not brain or not sameWorld(ped, jacker) then return end
    brain:react("passenger", jacker, getPedWeapon(jacker))
end

function PedAI.confirmDriverSeat(ped)
    local brain = brains[ped]
    if brain and PedCarjack.seated(brain) then return true end
    local car=getPedOccupiedVehicle(ped)
    return car and TrafficRoad.isDriving(ped,car) or false
end

function PedAI.expectsDriverSeat(ped, vehicle)
    local brain = brains[ped]
    local event = brain and brain.event
    return event and event.road and event.entryVehicle == vehicle and event.task == "enter"
end

function PedAI.vehicleThreat(ped, attacker, road)
    local brain = brains[ped]
    if brain and sameWorld(ped, attacker) and brain:react("vehicleThreat", attacker, getPedWeapon(attacker), "fight") and road then
        brain.event.originalRoad, brain.event.attackOccupied = road, true
    end
end

function PedAI.roadRage(ped, attacker, road)
    local brain = brains[ped]
    if not brain or not brain:react("roadRage", attacker, 0, "fight", "run", 20000) then return end
    brain.event.originalRoad = road
    -- CTaskComplexRoadRage::CreateFirstSubTask equips the offended driver.
    if getPedWeapon(ped) == 0 then
        if brain.profile.pedType >= 7 and brain.profile.pedType <= 15 then
            giveWeapon(ped, 22, 2000, true)
        elseif math.random(0, 1) == 1 then
            local melee = {5, 2, 6}
            giveWeapon(ped, melee[math.random(#melee)], 1, true)
        end
    end
end

local function prune(queue, now)
    for i = #queue, 1, -1 do
        if elapsed(now, queue[i].at) > 900 then table.remove(queue, i) end
    end
end

local function remember(queue, item)
    if #queue == 8 then table.remove(queue, 1) end
    queue[#queue + 1] = item
end

local function confirmReaction(brain, report)
    if report.acted or not sameWorld(report.attacker, brain.ped) or isPedDead(brain.ped) then return end
    report.acted = true
    if PedSpecial then PedSpecial.interrupt(brain.ped) end
    if PedVehicleEvasion then PedVehicleEvasion.cancel(brain.ped) end
    if report.weapon == 37 and PedSpecial then PedSpecial.observeFire(brain,false,report.attacker) end
    if brain.profile.pedType==16 and getElementType(report.attacker)=="player" then
        local flee=getPedWeapon(report.attacker)>=16
        brain:react("damage",report.attacker,report.weapon,flee and "flee" or "fight","run",flee and 6000 or 20000)
        if flee then PedVoice.emit(brain.ped,"fear") end
    else
        PedAI.rememberHostility(brain.ped,report.attacker)
        brain:react("damage", report.attacker, report.weapon)
    end
    if getElementType(report.attacker)=="player" and brain.event and brain.event.kind=="damage"
        and TrafficAmbient and TrafficAmbient.wakeReaction then
        TrafficAmbient.wakeReaction(brain.ped,brain.event)
    end
    notifyWitnesses(brain, report.attacker, report.weapon)
end

local function confirmLoss(brain, report, observation)
    observation.used, report.scored = true, true
    confirmReaction(brain, report)
    local acting = brains[report.attacker]
    if acting and acting.event and acting.event.intent == "fight" and acting.event.target == brain.ped then
        acting.event.struck = getTickCount()
    end
    local attacker, weapon, ped = report.attacker, report.weapon, brain.ped
    if PedVoice and not isPedDead(ped) then
        PedVoice.emit(ped, rules.ranged(weapon) and "pain" or "impact")
    end
    if sameWorld(attacker, ped) and not isPedDead(ped) and getElementType(attacker) == "player" then
        local police = brain.profile.pedType == 6 or TrafficActors.isPolicePed(ped)
        rules.reportPlayerStrike(attacker, ped, police, weapon)
        if weapon == 37 and PedSpecial then PedSpecial.reportIgnition(brain, attacker) end
    end
end

local function similar(a, b)
    return math.abs(a - b) <= math.max(1, math.min(a, b) * 0.1)
end

local function recordLoss(brain, loss, channel, now)
    if PedVehicleEvasion then PedVehicleEvasion.cancel(brain.ped) end
    prune(brain.losses, now)
    -- One injury can appear in both the native server event and the next HP sync.
    for _, seen in ipairs(brain.losses) do
        if not seen[channel] and similar(seen.loss, loss) then
            seen[channel] = true
            return
        end
    end
    local observation = {loss = loss, at = now, [channel] = true}
    remember(brain.losses, observation)
    prune(brain.reports, now)
    for _, report in ipairs(brain.reports) do
        if not report.scored and similar(report.loss, loss) then
            confirmLoss(brain, report, observation)
            return
        end
    end
end

function PedAI.sampleHealth(ped)
    local brain = brains[ped]
    if not brain then return end
    local now, hp = getTickCount(), getElementHealth(ped)
    if not hp then return end
    if PedSpecial then PedSpecial.observeFire(brain) end
    local loss = brain.health - hp
    if hp > 0 and loss > 0 and elapsed(now, brain.sampled) < 1500 then
        recordLoss(brain, loss, "sample", now)
    end
    brain.health, brain.sampled = hp, now
end

function PedAI.damaged(ped, loss)
    local brain = brains[ped]
    if not brain or not (type(loss) == "number" and loss > 0 and loss < math.huge) then return end
    recordLoss(brain, loss, "native", getTickCount())
end

local function validHit(ped, attacker, weapon, loss)
    if source ~= resourceRoot or not brains[ped] or ped == attacker or not isElement(client) then return false end
    if not sameWorld(ped, attacker) or not sameWorld(ped, client) or isPedDead(ped) then return false end
    local kind = getElementType(attacker)
    if kind ~= "player" and kind ~= "ped" then return false end
    if type(weapon) ~= "number" or weapon % 1 ~= 0 or getPedWeapon(attacker) ~= weapon
        or not (type(loss) == "number" and loss > 0 and loss < math.huge) then return false end
    return distance(ped, attacker) <= (rules.ranged(weapon) and 160 or 6)
end

local function sameHit(report, attacker, weapon, loss)
    return report.attacker == attacker and report.weapon == weapon and similar(report.loss, loss)
end

addEvent("npchlc_traffic:pedHit", true)
addEventHandler("npchlc_traffic:pedHit", resourceRoot, function(ped, attacker, weapon, loss)
    if not validHit(ped, attacker, weapon, loss) then return end
    if attacker ~= client and (not brains[attacker] or getElementSyncer(attacker) ~= client) then return end
    local brain, now = brains[ped], getTickCount()
    local report = {at = now, attacker = attacker, weapon = weapon, loss = loss}
    prune(brain.reports, now)
    remember(brain.reports, report)
    prune(brain.losses, now)
    for _, observation in ipairs(brain.losses) do
        if not observation.used and similar(observation.loss, loss) then
            confirmLoss(brain, report, observation)
            return
        end
    end
    -- The victim's syncer observes the native hit even on servers that never emit
    -- onPedDamage for it. A client may initiate an attack only as itself or its NPC.
    if client == getElementSyncer(ped) then
        confirmReaction(brain, report)
    else
        prune(brain.receipts, now)
        for i, receipt in ipairs(brain.receipts) do
            if sameHit(receipt, attacker, weapon, loss) then
                table.remove(brain.receipts, i)
                confirmReaction(brain, report)
                break
            end
        end
    end
end)

addEvent("npchlc_traffic:pedHitSeen", true)
addEventHandler("npchlc_traffic:pedHitSeen", resourceRoot, function(ped, attacker, weapon, loss)
    if not validHit(ped, attacker, weapon, loss) or getElementSyncer(ped) ~= client then return end
    local brain, now = brains[ped], getTickCount()
    prune(brain.reports, now)
    for _, report in ipairs(brain.reports) do
        if not report.acted and sameHit(report, attacker, weapon, loss) then
            confirmReaction(brain, report)
            return
        end
    end
    prune(brain.receipts, now)
    remember(brain.receipts, {at = now, attacker = attacker, weapon = weapon, loss = loss})
end)

local function finish(brain)
    if brain.event == brain.objectives.current then brain.objectives:complete() end
    brain.event = brain.objectives.current
    brain.objectives.body = 1
    if brain.event then brain.event.task = nil end
    brain.tasks:clear(true)
    return brain.event ~= nil
end

local function returnToCar(brain, now, road)
    road = road or brain.event and brain.event.originalRoad
    if not road or not sameWorld(brain.ped, road.vehicle) or isVehicleBlown(road.vehicle)
        or isPedDead(brain.ped) or getVehicleOccupant(road.vehicle, 0) then return finish(brain) end
    brain.tasks:clear()
    brain.objectives:clear()
    brain.event = {id = 0x12, kind = "returnCar", intent = "reclaim", resolved = true, road = road,
        target = brain.ped, started = now, lastSeen = now, duration = 20000}
    brain.objectives:request(brain.event)
    return true
end

function PedAI.returnServiceDriver(ped, road)
    local brain=brains[ped]
    if not brain or brain.scriptOwner or brain.event or not road or not sameWorld(ped,road.vehicle)
        or isVehicleBlown(road.vehicle) or getVehicleOccupant(road.vehicle,0) then return false end
    return returnToCar(brain,getTickCount(),road)
end

function PedAI.afterRoadFall(ped,attacker,road)
    local brain=brains[ped]
    if not brain or brain.scriptOwner or brain.event and brain.event.kind=="carjack" then return end
    if isElement(attacker) and sameWorld(ped,attacker) and not isPedDead(attacker) then
        if brain:react("damage",attacker,0) then brain.event.originalRoad=road return end
    end
    if not brain.event and road and sameWorld(ped,road.vehicle) and not isVehicleBlown(road.vehicle)
        and not getVehicleOccupant(road.vehicle,0) then
        returnToCar(brain,getTickCount(),road)
    end
end

function PedAI.update(ped, graph)
    if PedAI.isScriptControlled(ped) then return true end
    if PedSpecial and PedSpecial.update(ped,graph) then return true end
    if PedVehicleEvasion and PedVehicleEvasion.active(ped) then return true end
    local brain = brains[ped]
    local event = brain and brain.event
    if not event then return false end
    local now = getTickCount()
    if brain.profile.pedType==6 and event.intent=="fight" and TrafficCustody and TrafficCustody.isActive(event.target) then
        return returnToCar(brain,now)
    end
    if event.road and PedCarjack.seated(brain) then return true end
    if event.kind == "returnCar" and (not sameWorld(ped, event.road.vehicle) or isVehicleBlown(event.road.vehicle)
        or getVehicleOccupant(event.road.vehicle, 0)) then return finish(brain) end
    local pointFlight = event.intent == "flee" and event.origin and (not event.road or event.resolved)
    if isPedDead(ped) or not pointFlight and (not sameWorld(ped, event.target) or isPedDead(event.target)) then return returnToCar(brain, now) end
    if isPedInVehicle(ped) then
        if leavingVehicle(event.kind) and elapsed(now, event.started) < 2500 then return true end
        return finish(brain)
    end
    local separation = not pointFlight and distance(ped, event.target) or 0
    local duration = event.duration or (event.kind == "witness" and 10000 or event.kind == "ally" and 30000 or 20000)
    local fromGunfire = event.kind == "gunshot" or event.kind == "nearMiss"
    local delay = event.kind == "gunshot" and not event.consumed and brain.reactionDelay or 0
    if event.intent == "flee" then
        local x, y = getElementPosition(ped)
        local tx, ty = x, y
        if not pointFlight then tx, ty = getElementPosition(event.target) end
        if PedObjectives.flightExpired(event, now, duration == 0 and 0 or duration + delay, (tx-x)^2 + (ty-y)^2) then
            return returnToCar(brain, now)
        end
    elseif duration > 0 and elapsed(now, event.lastSeen) > duration + delay then
        if event.intent == "fight" and event.struck and elapsed(now,event.struck)<2000
            and not brain.tasks:hasRangedWeapon() then
            event.duration,event.lastSeen,event.struck=2000,now,nil
        else
            return returnToCar(brain, now)
        end
    elseif (event.intent ~= "fight" or event.originalRoad) and not fromGunfire and separation > 65 then
        return returnToCar(brain, now)
    end
    if delay > 0 and elapsed(now, event.started) < delay then return true end
    if delay > 0 then
        brain.tasks:clear()
        event.consumed, event.lastSeen = true, now
    end
    if leavingVehicle(event.kind) and not isPedOnGround(ped) and elapsed(now, event.started) < 2500 then return true end
    if event.road and PedCarjack.update(brain, now) then return true end
    brain.objectives.body = event.intent == "flee" and (event.origin and 8 or 9)
        or event.intent == "fight" and (brain.tasks:hasRangedWeapon() and 0x10 or 0x11) or 2
    if event.kind == "damage" and not isPedOnGround(ped) and elapsed(now, event.started) < 2500 then return true end
    if fromGunfire and not event.voiced and (event.intent == "flee" or event.intent == "evade") then
        event.voiced = true
        if PedVoice then PedVoice.emit(ped, "fear") end
    end
    brain.tasks:execute(graph, event, now)
    return true
end

local lastGunfire = {}

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

local function scanBulletPath(shooter, weapon, sx, sy, sz, ex, ey, ez, interior, dimension)
    if not (finite(ex) and finite(ey) and finite(ez)) then return end
    local dx, dy, dz = ex - sx, ey - sy, ez - sz
    local length2 = dx * dx + dy * dy + dz * dz
    if length2 < 0.01 or length2 > 400 * 400 then return end
    local radius = math.sqrt(length2) * 0.5 + 2
    for _, ped in ipairs(getElementsWithinRange((sx+ex)/2, (sy+ey)/2, (sz+ez)/2, radius, "ped", interior, dimension) or {}) do
        local brain = brains[ped]
        if brain and ped ~= shooter and not isPedInVehicle(ped) and not isPedDead(ped) then
            local x, y, z = getElementPosition(ped)
            local t = math.max(0, math.min(1, ((x-sx)*dx + (y-sy)*dy + (z-sz)*dz) / length2))
            if (x-sx-t*dx)^2 + (y-sy-t*dy)^2 + (z-sz-t*dz)^2 < 4 and math.random(0, 31) == 0 then
                brain:react("nearMiss", shooter, weapon, "evade", nil, 1000)
            end
        end
    end
end

function PedAI.gunfire(shooter, weapon, ex, ey, ez, sx, sy, sz)
    if not isElement(shooter) or type(weapon) ~= "number" or not (weapon >= 22 and weapon <= 34 or weapon == 38) then return end
    local kind = getElementType(shooter)
    if kind ~= "ped" and kind ~= "player" or isPedDead(shooter) then return end
    local x, y, z = getElementPosition(shooter)
    -- Single-handed fire while looking backwards can produce map-centre trace
    -- coordinates in MTA. The audible source is still the verified shooter.
    local validOrigin = finite(sx) and finite(sy) and finite(sz) and (sx-x)^2+(sy-y)^2+(sz-z)^2 <= 64
    if not (finite(ex) and finite(ey) and finite(ez)) or (ex-x)^2 + (ey-y)^2 + (ez-z)^2 > 400^2 then
        ex, ey, ez = nil, nil, nil
    end
    if kind == "player" and not validOrigin then ex, ey, ez = nil, nil, nil end
    if TrafficRoad and TrafficRoad.noteGunfire then
        if not validOrigin then sx, sy, sz = x, y, z end
        TrafficRoad.noteGunfire(shooter, weapon, ex, ey, ez, sx, sy, sz)
    end
    local interior, dimension = getElementInterior(shooter), getElementDimension(shooter)
    local now, last = getTickCount(), lastGunfire[shooter]
    if not last or elapsed(now, last) >= 1000 then
        lastGunfire[shooter] = now
        local shooterProfile = PedAI.profile(shooter) or playerProfile
        local wanted = getElementType(shooter) == "player" and getPlayerWantedLevel(shooter) > 0
        for _, ped in ipairs(getElementsWithinRange(x, y, z, 60, "ped", interior, dimension) or {}) do
            local brain = brains[ped]
            if brain and ped ~= shooter and not isPedDead(ped) and not isPedInVehicle(ped) then
                local px, py, pz = getElementPosition(ped)
                local h2 = (px-x)^2 + (py-y)^2
                local d2 = h2 + (pz-z)^2
                local event = brain.event
                if d2 < 3600 and not (event and event.kind == "gunshot" and not event.consumed) and (not event or event.kind ~= "gunshot" or event.target == shooter
                    or not sameWorld(ped, event.target) or d2 < distance(ped, event.target)^2) then
                    local intent, pace, duration = rules.gunshot(brain.profile, shooterProfile,
                        math.sqrt(h2), brain.tasks:hasRangedWeapon(), wanted)
                    if intent and brain:react("gunshot", shooter, weapon, intent, pace, duration)
                        and intent == "flee" and h2 >= 900 and brain.profile.pedType ~= 6
                        and brain.profile.fear <= brain.profile.law and brain.profile.temper <= brain.profile.fear then
                        brain.event.origin = brain.event.origin or {x,y,z}
                    end
                end
            end
        end
    end
    -- The PS2 samples the local player's bullet bounds on frame phase zero.
    if kind == "player" and ex and math.random(0, 3) == 0 then
        scanBulletPath(shooter, weapon, sx, sy, sz, ex, ey, ez, interior, dimension)
    end
end

addEventHandler("onPlayerWeaponFire", root, function(weapon, ex, ey, ez, _, sx, sy, sz)
    PedAI.gunfire(source, weapon, ex, ey, ez, sx, sy, sz)
end)

addEvent("npchlc_traffic:minigun", true)
local minigunReports = {}
addEventHandler("npchlc_traffic:minigun", resourceRoot, function(ex, ey, ez, sx, sy, sz)
    if source ~= resourceRoot or not isElement(client) or getPedWeapon(client) ~= 38 then return end
    local now = getTickCount()
    if minigunReports[client] and elapsed(now, minigunReports[client]) < 100 then return end
    minigunReports[client] = now
    PedAI.gunfire(client, 38, ex, ey, ez, sx, sy, sz)
end)

addEvent("npchlc_traffic:pedGunfire", true)
addEventHandler("npchlc_traffic:pedGunfire", resourceRoot, function(ped, weapon, ex, ey, ez)
    if source ~= resourceRoot or not brains[ped] or not sameWorld(ped, client)
        or getElementSyncer(ped) ~= client or getPedWeapon(ped) ~= weapon then return end
    PedAI.gunfire(ped, weapon, ex, ey, ez)
end)

addEventHandler("onPlayerQuit", root, function() lastGunfire[source], minigunReports[source] = nil, nil end)
addEventHandler("onElementDestroy", root, function()
    lastGunfire[source] = nil
    PedAI.detach(source)
end)
