"""Run the street ped decision and server/client attribution regression cases."""

from pathlib import Path

from lupa.lua51 import LuaRuntime

RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        root, resourceRoot, exports, handlers, nearby, crimes, messages = {}, {}, {}, {}, {}, {}, {}
        now = 12300
        local hlc = {}
        exports.npc_hlc = hlc
        function hlc:clearNPCTasks(p) p.task = nil; p.clears = (p.clears or 0) + 1 end
        function hlc:setNPCTask(p, t) p.task = t; p.tasks = (p.tasks or 0) + 1; return true end
        function hlc:setNPCWalkSpeed(p, speed) p.speed = speed end
        function hlc:addNPCTask(p, task) p.preview=task; return true end
        function addEvent() end
        function addEventHandler(n, _, fn) handlers[n] = fn end
        function getTickCount() return now end
        function getElementType(e) return e.kind end
        function isElement(e) return type(e) == "table" and e.kind ~= nil and not e.gone end
        function isPedDead(e) return e.dead end
        function getElementHealth(e) return e.hp or 100 end
        function getPedOccupiedVehicle(e) return e.vehicle end
        function isPedInVehicle(e) return e.vehicle ~= nil end
        function isPedOnGround(e) return true end
        function getElementDimension(e) return e.dim or 0 end
        function getElementInterior(e) return 0 end
        function getPedWeapon(e) return e.weapon or 0 end
        function getPedTotalAmmo(e) return e.ammo or 0 end
        function setPedWeaponSlot(e, slot) if slot == 0 then e.weapon = 0 end end
        function getPedRotation() return 0 end
        function setPedRotation(e, value) e.heading = value end
        function setPedAnimation(e, block, anim) e.anim = anim end
        function getPlayerWantedLevel(e) return e.wanted or 0 end
        function getElementPosition(e) return e.x, e.y, e.z or 0 end
        function getElementSyncer(e) return e.owner end
        function getDistanceBetweenPoints2D(x, y, a, b) return math.sqrt((x-a)^2 + (y-b)^2) end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function getElementsWithinRange() return nearby end
        function triggerClientEvent(...) table.insert(messages, {...}) end
        function reportWantedCrime(...) table.insert(crimes, {...}) end
        voices = {}
        PedVoice = {emit = function(ped, kind) table.insert(voices, {ped, kind}) end}
        TrafficActors = {isPolicePed = function() return false end}
        TrafficGraph = {pedestrianAnchor = function() return 0 end}
        TrafficWorld = {reachable = function(owner, ped, node, candidates)
            local ids = {}
            for _, candidate in ipairs(candidates) do ids[#ids+1] = candidate.id end
            return ids
        end}
        graph = {nodes={{x=0,y=0,z=0,linkCount=2,firstLink=0}, {id=1,x=6,y=0,z=0,flags=0,linkCount=0},
            {id=2,x=-6,y=0,z=0,flags=0,linkCount=0}}, links={{to=1},{to=2}}}
        function person(kind, x) return {kind=kind, x=x or 0, y=0} end
    """)
    for filename in ("ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_objectives.lua", "ped_ai_tasks.lua", "ped_carjack.lua", "ped_ai.lua"):
        lua.execute((RESOURCE / filename).read_text(encoding="utf-8-sig"))
    lua.execute("""
        function modelFor(stat)
            for model, row in pairs(PedAIModels) do if row[2] == stat then return model end end
        end
        local tough, timid = modelFor(18), modelFor(16)
        local player = person("player", -1)
        local cop = person("ped", 2)
        cop.owner = player
        local first = PedAI.attach(cop, 8)
        assert(PedAI.attach(cop, tough) == first and first.profile.name == "STAT_COP")
        local function victim(model)
            local p = person("ped")
            p.owner = player
            PedAI.attach(p, model)
            return p
        end
        local driver = victim(tough)
        nearby = {driver, cop}
        PedAI.carjacked(driver, player, {})
        assert(PedAI.busy(driver) and PedAI.update(driver, graph) and not driver.task)
        assert(not PedAI.busy(cop) and #messages == 1)
        now = now + 1000
        assert(PedAI.update(driver, graph) and driver.task[1] == "killPed" and driver.task[2] == player)
        driver.weapon, driver.ammo = 24, 6
        assert(PedAI.update(driver, graph) and driver.task[3] == 30)
        driver.ammo = 0
        assert(PedAI.update(driver, graph) and driver.task[3] < 2 and driver.weapon == 0)
        local previous = driver.tasks
        assert(PedAI.update(driver, graph) and driver.tasks == previous)
        source, client = resourceRoot, person("player")
        local msg = messages[1]
        handlers["npchlc_traffic:pedSight"](msg[4], {cop})
        assert(not PedAI.busy(cop))
        client = player
        handlers["npchlc_traffic:pedSight"](msg[4], {cop})
        assert(PedAI.busy(cop))
        -- An out-of-dimension target clears the chase and restores the previous pace.
        player.dim = 1
        assert(not PedAI.update(driver, graph) and driver.speed == "walk")
        player.dim = 0
        nearby = {}
        local scared = victim(timid)
        local remote = person("player")
        scared.owner = remote
        local hit = handlers["npchlc_traffic:pedHit"]
        hit(scared, player, 0, 8)
        assert(not PedAI.busy(scared) and #crimes == 0)
        PedAI.damaged(scared, 8)
        now = now + 450
        assert(PedAI.update(scared, graph) and scared.task[1] == "walkTrafficToPoint")
        assert(scared.task[2] == 6 and #crimes == 1)
        local count = #crimes
        hit(scared, player, 0, 8)
        assert(#crimes == count)
        -- Reverse arrival order; expire old unmatched reports first.
        now = now + 1100
        driver.owner = remote
        PedAI.damaged(driver, 7)
        client = person("player")
        hit(driver, player, 0, 7)
        assert(not PedAI.busy(driver))
        client = player
        hit(driver, player, 0, 20)
        assert(not PedAI.busy(driver))
        hit(driver, player, 0, 7)
        assert(PedAI.busy(driver) and #crimes == count + 1)
        local sampled = victim(timid)
        hit(sampled, player, 0, 1.32)
        assert(PedAI.busy(sampled) and #crimes == count + 1)
        sampled.hp = 99
        PedAI.sampleHealth(sampled)
        assert(#crimes == count + 2)
        -- A native server event can arrive for the same health update.
        PedAI.damaged(sampled, 1.32)
        assert(#crimes == count + 2)
        local split = victim(tough)
        split.owner = remote
        client = remote
        handlers["npchlc_traffic:pedHitSeen"](split, player, 0, 1.32)
        assert(not PedAI.busy(split))
        client = player
        hit(split, player, 0, 1.32)
        assert(PedAI.busy(split) and #crimes == count + 2)
        local passenger = victim(timid)
        passenger.vehicle = {}
        PedAI.passengerThreat(passenger, player)
        assert(PedAI.update(passenger, graph) and not passenger.task)
        passenger.vehicle = nil
        now = now + 1000
        assert(PedAI.update(passenger, graph) and passenger.task[1] == "walkTrafficToPoint")
        now = now + 21000
        assert(not PedAI.update(driver, graph))
        -- Fear == 100 - aggressor temper stays out of the high-fear branch.
        local tie = {pedType=4, statId=16, fear=50,temper=0}
        assert(PedAIRules.intent("damage",tie,PedAIRules.profile(0),false,false) == "fight")
        assert(PedAIRules.intent("damage",tie,tie,false,false) == nil)
        local gang = {pedType=7,statId=4,fear=30,temper=65}
        assert(PedAIRules.intent("ally",gang,PedAIRules.profile(0),false,false) == "fight")
        assert(PedAIRules.intent("witness",gang,PedAIRules.profile(0),false,false) == nil)
        assert(PedAI.setLeader(cop, driver) and not PedAI.setLeader(driver, driver))
        local fatal = victim(tough)
        PedAI.damaged(fatal, 25)
        fatal.dead = true
        hit(fatal, player, 0, 25)
        assert(not PedAI.busy(fatal) and #crimes == count + 2)
        PedAI.detach(fatal)
        assert(not PedAI.profile(fatal))

        local listener = victim(modelFor(27)) -- tourist, fear 100 > law 70
        local outer, offWorld, boundary = victim(tough), victim(timid), victim(timid)
        local shooter = person("player", 0)
        shooter.weapon = 22
        listener.x, outer.x, offWorld.dim, boundary.z = 10, 45, 1, 60
        local onDuty = victim(8)
        local gangPed, medic = victim(modelFor(4)), victim(modelFor(2))
        nearby = {listener, outer, boundary, offWorld, onDuty, gangPed, medic}
        local beforeCrime, beforeVoices = #crimes, #voices
        source = shooter
        handlers.onPlayerWeaponFire(22)
        assert(not PedAI.busy(boundary) and not PedAI.busy(offWorld))
        assert(not PedAI.busy(gangPed) and not PedAI.busy(medic))
        assert(PedAI.busy(listener) and PedAI.busy(outer) and PedAI.busy(onDuty))
        assert(PedAI.update(listener, graph) and listener.speed == nil)
        now = now + 1100
        assert(PedAI.update(listener, graph) and listener.speed == "sprint")
        assert(PedAI.update(outer, graph) and outer.speed == "walk")
        -- Only the two actual frightened pedestrians should vocalize.
        assert(#voices == beforeVoices + 2 and #crimes == beforeCrime)
        assert(PedAI.update(listener, graph) and #voices == beforeVoices + 2)
        -- Neutral police orient; independently wanted shooter triggers intervention.
        assert(PedAI.update(onDuty, graph) and onDuty.heading ~= nil and not onDuty.task)
        now = now + 1
        shooter.wanted = 1
        handlers.onPlayerWeaponFire(22)
        now = now + 1100
        assert(PedAI.update(onDuty, graph) and onDuty.task[1] == "killPed")
        local profile, playerStats = PedAIRules.profile(modelFor(27)), PedAIRules.profile(0)
        local intent, pace, duration = PedAIRules.gunshot(profile, playerStats, 30, false, false)
        assert(intent == "flee" and pace == "run" and duration == 5000)
        assert(PedAIRules.gunshot(PedAIRules.profile(modelFor(18)), playerStats, 1, true, false) == "fight")
        -- A near miss at 80 m can evade without hearing the shooter. A parallel
        -- bystander a little more than 2 m away stays out of the trace branch.
        local near, missed = victim(timid), victim(timid)
        near.x, missed.x, missed.y = 80, 80, 2.1
        nearby = {near, missed}
        local originalRandom = math.random
        math.random = function(low, high) return 0 end
        handlers.onPlayerWeaponFire(22, 90, 0, 0, nil, 0, 0, 0)
        math.random = originalRandom
        assert(PedAI.update(near, graph) and near.anim and not PedAI.busy(missed))
        assert(#voices == beforeVoices + 3 and #crimes == beforeCrime)
        -- Pain is emitted once even if same-personality rules choose no fight/flee.
        local passive = victim(0)
        local sameStat = person("player")
        client, source, passive.owner = sameStat, resourceRoot, sameStat
        local n = #voices
        hit(passive, sameStat, 0, 1)
        PedAI.damaged(passive, 1)
        assert(not PedAI.busy(passive) and #voices == n+1 and voices[#voices][2] == "impact")
        client.weapon = 24
        now = now + 1000
        PedAI.damaged(passive, 7)
        hit(passive, sameStat, 24, 7)
        assert(#voices == n+2 and voices[#voices][2] == "pain")
        local checkpoint = #voices
        local recent = victim(tough)
        nearby = {}
        PedAI.carjacked(recent, player)
        PedAI.carjacked(recent, player)
        assert(#voices == checkpoint+1 and voices[#voices][2] == "carjack")
        local vehicleAttacker = person("vehicle")
        local bystander = victim(timid)
        nearby = {bystander}
        PedAI.gunfire(vehicleAttacker, 22)
        PedAI.gunfire(player, 36)
        assert(not PedAI.busy(bystander))
        local previousCrimes = #crimes
        client, source = player, resourceRoot
        client.weapon = 22
        handlers["npchlc_traffic:minigun"](0,0,0,0,0,0)
        assert(not PedAI.busy(bystander))
        client.weapon = 38
        handlers["npchlc_traffic:minigun"](0,0,0,0,0,0)
        assert(PedAI.busy(bystander) and #crimes == previousCrimes)
        nearby = {}
        function getPedOccupiedVehicle(p) return p.vehicle end
        function getVehicleOccupant(v) return v.driver end
        function isVehicleBlown(v) return v.blown end
        local resumed
        TrafficRoad = {isDriving=function(p,c) return resumed and resumed.driver==p and resumed.vehicle==c end,resumeDriver=function(road) resumed=road return true end}
        local function theft(model, door, quick, occupied)
            local ped, car = victim(model), person("vehicle")
            local road = {driver=ped, vehicle=car, jackDoor=door, quickDrag=quick}
            player.vehicle, car.driver = occupied and car or nil, occupied and player or nil
            PedAI.carjacked(ped,player,car,road)
            return ped, car, road, PedAI.attach(ped,model)
        end
        local cautious,car,_,brain = theft(timid,0,true,true)
        now=now+1000
        assert(PedAI.update(cautious,graph) and brain.event.intent=="flee" and brain.event.duration==10000)
        local early,v,_,runner = theft(tough,0,true,false)
        v.driver,player.vehicle=player,v
        now=now+1000
        assert(PedAI.update(early,graph) and runner.event.intent=="flee")
        local fighter,targetCar,_,avenger = theft(tough,1,false,false)
        now=now+1000
        PedAI.update(fighter,graph)
        assert(avenger.event.intent=="fight" and fighter.task[1]=="killPed")
        targetCar.driver,player.vehicle=player,targetCar
        PedAI.update(fighter,graph)
        assert(not fighter.task and messages[#messages][2]=="npchlc_traffic:reclaimDriverSeat")
        targetCar.driver,player.vehicle=nil,nil
        PedAI.update(fighter,graph)
        assert(fighter.task[1]=="killPed" and fighter.task[2]==player)
        local exits=0
        TrafficPassengers={requestExit=function(p,v,s)
            assert(p==fighter and v==targetCar and s==0)
            exits=exits+1
        end}
        fighter.vehicle,targetCar.driver=targetCar,fighter
        assert(PedAI.confirmDriverSeat(fighter) and exits==1)
        now=now+3000
        assert(PedAI.update(fighter,graph) and exits==2)
        fighter.vehicle,targetCar.driver=nil,nil
        assert(PedAI.update(fighter,graph) and fighter.task[1]=="killPed")
        local owner,stolen,road,reclaimer = theft(tough,0,false,true)
        stolen.x,now=13,now+1000
        PedAI.update(owner,graph)
        assert(reclaimer.event.intent=="reclaim" and owner.task[1]=="walkFollowElement")
        stolen.x=1
        PedAI.update(owner,graph)
        local req=messages[#messages]
        assert(req[1]==owner.owner and req[4]==owner and req[5]==stolen and req[6]==player)
        assert(not PedAI.confirmDriverSeat(owner) and not resumed)
        owner.owner=person("player")
        PedAI.update(owner,graph)
        assert(messages[#messages][1]==owner.owner)
        stolen.driver,owner.vehicle=owner,stolen
        assert(PedAI.confirmDriverSeat(owner) and resumed==road and not PedAI.busy(owner))
        assert(PedAI.confirmDriverSeat(owner))
        local strong, fearful = {temper=70,fear=30}, {temper=30,fear=30}
        local function decide(profile,door,quick,occupant,playerCar,lockedTarget)
            return PedCarjack.decide(profile,door,quick,occupant,player,playerCar,lockedTarget)
        end
        local action,ms = decide(fearful,1,false,player,false,nil)
        assert(action=="flee" and ms==4000)
        action,ms = decide(fearful,2,true,player,false,nil)
        assert(action=="flee" and ms==14000)
        action,ms = decide(strong,0,true,nil,true,nil)
        assert(action=="flee" and ms==10000)
        assert(decide(strong,0,false,nil,true,nil)=="reclaim")
        assert(decide(strong,0,true,player,false,nil)=="reclaim")
        assert(decide(strong,1,false,nil,false,player)=="fight")

        function giveWeapon(p, weapon, ammo) p.weapon, p.ammo = weapon, ammo end
        local enraged, ownCar, targetCar = victim(tough), person("vehicle",1), person("vehicle",2)
        local previousRoad = {vehicle=ownCar,driver=enraged}
        player.vehicle, targetCar.driver = targetCar, player
        PedAI.roadRage(enraged,player,previousRoad)
        now = now + 1000
        assert(PedAI.update(enraged,graph) and enraged.anim == "fucku" and not enraged.task)
        now = now + 1333
        PedAI.update(enraged,graph)
        assert(enraged.task[1] == "attackOccupiedVehicle" and enraged.task[2] == player)
        player.vehicle = nil
        PedAI.update(enraged,graph)
        assert(enraged.task[1] == "killPed" and enraged.task[2] == player)
        player.x = 90
        PedAI.update(enraged,graph)
        PedAI.update(enraged,graph)
        assert(messages[#messages][2] == "npchlc_traffic:reclaimDriverSeat" and messages[#messages][5] == ownCar)
        ownCar.driver, enraged.vehicle = enraged, ownCar
        assert(PedAI.confirmDriverSeat(enraged) and resumed == previousRoad)
    """)
    lua.execute((RESOURCE / "ped_ai_c.lua").read_text(encoding="utf-8-sig"))
    print("Street AI profiles, damage, witnesses, gunshot hearing, near misses, speech and recovery passed")


if __name__ == "__main__":
    main()
