"""Run wanted-rule and MTA adapter smoke tests with Lupa's Lua 5.1 runtime."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


def main():
    traffic = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"
    wanted = traffic.parents[1] / "[module]/wanted"
    lua = LuaRuntime()
    lua.execute('''
        root, resourceRoot = {}, {}
        local trafficResource = {name="npchlc_traffic"}
        function getThisResource() return trafficResource end
        function getResourceName(res) return res.name end
        function getResourceState(res) return "running" end
        function call(resource, name, ...) return _G[name](...) end
        messages = {}
        function triggerClientEvent(...) table.insert(messages, {...}) end
        TrafficCustody = {
            isActive=function() return false end,
            begin=function(player) return exports.wanted:resetPlayerWanted(player, "arrest") end
        }
        local registered, handlers, timers = {}, {}, {}
        local now = 0
        player, other = {level = 0}, {level = 3}
        policePed = {kind = "ped", police = true, x = 1}
        events = {}

        function isElement(element) return type(element) == "table" end
        function getElementType(element) return element.kind or "player" end
        function getElementInterior(element) return element.interior or 0 end
        function getElementDimension(element) return element.dimension or 0 end
        function getElementPosition(element) return element.x or 0, 0, 0 end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
        function getElementModel() return 411 end
        function getElementData(element,key) return element[key] end
        function getDistanceBetweenPoints3D(x,_,_,tx) return math.abs(x-tx) end
        function isPedDead(element) return element.dead end
        function isPedInVehicle(element) return element.inVehicle end
        function setPedRotation() end
        function getPedWeapon(_,slot) return slot==2 and 22 or 0 end
        function getPedWeaponSlot(p) return p.slot or 0 end
        function getPedOccupiedVehicle(p) return p.car end
        function getVehicleOccupant(c) return c.driver end
        function isVehicleLocked(c) return c.locked end
        function getVehicleType(c) return c.type or "Automobile" end
        function getVehicleDoorState(c) return c.doorState or 0 end
        function getVehicleDoorOpenRatio(c) return c.open or 0 end
        function cancelEvent() eventCancelled=true end
        function wasEventCancelled() return vetoEnter end
        function getElementVelocity(c) return c.vx or 0,0,0 end
        function getElementSyncer() return player end
        TrafficGroundPolice = {target=function(p) return p.suspect end}
        function setPedWeaponSlot(p,slot) p.slot=slot end
        function setPedAnimation() end
        PedVoice = {emit=function() end}
        function getPlayerWantedLevel(element) return element.level end
        function setPlayerWantedLevel(element, level) element.level = level return true end
        function setElementData(element, key, value, mode, policy)
            assert(policy == "deny")
            element[key] = value
            return true
        end
        function removeElementData(element, key) element[key] = nil end
        function getElementsByType() return {player, other} end
        function getElementsWithinRange() return {policePed} end
        function getTickCount() return now end
        function addEvent(name, remote) registered[name] = remote end
        function addEventHandler(name, target, handler)
            handlers[name] = handlers[name] or {}
            table.insert(handlers[name], handler)
        end
        function triggerEvent(name, element, old, new, reason)
            assert(registered[name] == false)
            if name == "onTrafficPlayerArrest" then
                assert(element==player and old==policePed and new==player.level)
                lastArrest=reason
                return not cancelArrest
            end
            if name == "onPlayerPoliceResponseChange" then return true end
            assert(name == "onPlayerWanted")
            table.insert(events, {element, old, new, reason})
            if onWanted then onWanted(element, old, new, reason) end
        end
        function setTimer(handler, delay, repeats)
            if repeats==1 then return true end
            assert(delay == 50 and repeats == 0)
            table.insert(timers, handler)
        end
        function fire(name, element, ...)
            source = element
            for _, handler in ipairs(handlers[name]) do handler(...) end
            source = nil
        end
        function tick(ms)
            now = now + ms
            for _ = 1, 4 do for _, timer in ipairs(timers) do timer() end end
        end
        TrafficActors = {
            isPoliceNearby = function(_, radius) return policeDistance and policeDistance < radius or false end,
            isManagedPed = function(element) return element == policePed end,
            isPolicePed = function(element) return element.police end,
        }
    ''')
    lua.execute("authority = setmetatable({}, {__index = _G})")
    load_server = lua.eval("function(src, name) setfenv(assert(loadstring(src, name)), authority)() end")
    for script in ("rules.lua", "server.lua"):
        load_server((wanted / script).read_text(encoding="utf-8"), script)
    lua.execute("""
        exports = {wanted=setmetatable({}, {__index=function(_, name)
            return function(_, ...)
                authority.sourceResource=getThisResource()
                return authority[name](...)
            end
        end})}
    """)
    for script in ("ped_ai_rules.lua", "wanted.lua"):
        lua.execute((traffic / script).read_text(encoding="utf-8"))

    lua.execute('''
        fire("onResourceStart", resourceRoot, getThisResource())
        assert(#events == 0 and getPlayerWanted(other) == 3)
        fire("onPlayerResourceStart", player, getThisResource())
        assert(#messages == 1 and messages[1][1] == player and messages[1][2] == "wanted:snapshot")
        assert(messages[1][4] == 0 and messages[1][5] == 0 and messages[1][6] == "initial")

        local rules = authority.WantedRules
        for stars, points in ipairs({40, 180, 550, 1200, 2400, 4800}) do
            assert(rules.levelForPoints(points - 1) == stars - 1)
            assert(rules.levelForPoints(points) == stars)
            assert(rules.levelForPoints(rules.forLevel(stars)) == stars)
        end
        assert(rules.addCrime(0, 0, 16, true) == 166)
        assert(rules.addCrime(9599, 0, 16, false) == 9600)
        assert(rules.getPoliceResponse(0).policeHelicopters == 0)
        assert(rules.getPoliceResponse(3).undercover)
        assert(rules.getPoliceResponse(6).pursuitVehicleLimit == 4)
        assert(rules.getPoliceResponse(6).roadblockThreshold == 30)

        assert(setPlayerWanted(player, 2, "test"))
        assert(#messages == 2 and messages[2][1] == player and messages[2][2] == "wanted:change")
        assert(messages[2][4] == 0 and messages[2][5] == 2 and messages[2][6] == "test")
        assert(events[1][1] == player and events[1][2] == 0 and events[1][3] == 2 and events[1][4] == "test")
        assert(setPlayerWanted(player, 2) and #events == 1)
        assert(not setPlayerWanted(player, -1) and not setPlayerWanted(player, 2.5))
        assert(not setPlayerWanted(player, 1, {}) and not setPlayerWanted(player, "1"))
        setPlayerWantedLevel(player, 0)
        tick(200)
        assert(events[2][2] == 2 and events[2][3] == 0 and events[2][4] == "native")
        tick(200)
        assert(#events == 2)

        -- Two reported incidents through the timer path, with the second
        -- submission of the same incident sharing the original queue slot.
        policeDistance = 14
        assert(reportWantedCrime(player, 3, 100))
        assert(reportWantedCrime(player, 3, 100))
        tick(500)
        assert(getPlayerWanted(player) == 0)
        tick(200)
        assert(getPlayerWanted(player) == 1 and events[3][4] == "crime")
        policeDistance = 13.9
        assert(reportWantedCrime(player, 12, 200))
        assert(getPlayerWanted(player) == 2)
        tick(200)
        tick(1001)
        assert(getPlayerWanted(player) == 3)

        -- Queued or immediate zero-point reports restore saved parole score.
        assert(suspendPlayerWanted(player))
        assert(player["nspray:paroleStars"] == 3 and getPlayerWanted(player) == 0)
        fire("onPlayerWeaponFire", player)
        assert(getPlayerWanted(player) == 3 and player["nspray:paroleStars"] == nil)
        tick(20001)
        assert(player["nspray:paroleStars"] == nil)

        assert(setPlayerWanted(player, 1))
        policeDistance = 17.9
        for _ = 1, 22 do tick(1001) end
        assert(getPlayerWanted(player) == 1)

        policeDistance = 18
        for _ = 1, 21 do tick(1001) end
        assert(getPlayerWanted(player) == 0 and events[#events][4] == "decay")

        assert(setPlayerWanted(player, 1))
        assert(suspendPlayerWanted(player))
        tick(20001)
        assert(player["nspray:paroleStars"] == nil)
        assert(reportWantedCrime(player, 1, 301, true))
        assert(getPlayerWanted(player) == 0)

        -- Re-entrant listeners see transitions in order, and an unchanged
        -- native observation must not send the same event again.
        onWanted = function(element, old, new)
            if new == 1 then assert(setPlayerWanted(element, 2, "listener")) end
        end
        local before = #events
        assert(setPlayerWanted(player, 1))
        assert(#events == before + 2 and events[before + 1][3] == 1 and events[before + 2][3] == 2)
        assert(messages[#messages-1][5] == 1 and messages[#messages][5] == 2)
        tick(200)
        assert(#events == before + 2)
        onWanted = nil

        fire("onPlayerWasted", player)
        fire("onPlayerSpawn", player)
        assert(getPlayerWanted(player) == 0 and events[#events][4] == "respawn")

        policeDistance = nil
        policePed.dimension = 1
        fire("onPedWasted", policePed, 0, player, 22)
        assert(getPlayerWanted(player) == 0)
        policePed.dimension = 0
        fire("onPedWasted", policePed, 0, player, 22)
        assert(getPlayerWanted(player) == 2)
        setPlayerWanted(player, 1)

        local car={kind="vehicle"}
        assert(not TrafficWanted.tryArrest(policePed,player,getTickCount()))
        fire("onVehicleStartEnter",car,player,0)
        policePed.x=1.3
        assert(not TrafficWanted.tryArrest(policePed,player,getTickCount()))
        policePed.x=1.29
        cancelArrest=true
        assert(not TrafficWanted.tryArrest(policePed,player,getTickCount()) and player.level==1)
        cancelArrest=false
        fire("onVehicleStartEnter",car,player,0)
        assert(TrafficWanted.tryArrest(policePed,player,getTickCount()) and player.level==0 and policePed.slot==2)
        assert(setPlayerWanted(player,1))
        assert(setTrafficPlayerRestrained(player,true))
        policePed.x=5
        assert(not TrafficWanted.tryArrest(policePed,player,getTickCount()))
        policePed.x=4.99
        assert(TrafficWanted.tryArrest(policePed,player,getTickCount()) and player.level==0)
        player.dead=true
        assert(setPlayerWanted(player,2))
        fire("onPlayerWasted",player)
        assert(lastArrest=="wasted" and player.level==2)
        player.dead=false
        fire("onPlayerSpawn",player)
        assert(player.level==0)

        assert(setPlayerWanted(player,1))
        policePed.suspect, policePed.slot, policePed.x = player, 2, 2
        policePed["npchlc_traffic:originalModel"]=8
        player.inVehicle, player.car, car.driver = true, car, player
        local cleared=0
        exports.npc_hlc={clearNPCTasks=function(_,officer) assert(officer==policePed); cleared=cleared+1 end}
        exports.server_coldata={getModelBoundingBox=function() return -1,-2,-.5,1,2,1 end}
        local work={follow=true}
        assert(TrafficWanted.driverArrestCar(policePed,player)==car)
        car.locked=true
        assert(not TrafficWanted.driverArrestCar(policePed,player))
        car.locked,car.vx=false,.05
        assert(not TrafficWanted.driverArrestCar(policePed,player))
        car.vx=0
        policePed["npchlc_traffic:originalModel"]=9
        assert(setPlayerWanted(player,4))
        assert(TrafficWanted.driverArrestCar(policePed,player)==car)
        local specialist={x=3}
        local function fireDue(now) return TrafficWanted.vehicleFireDue(specialist,player,car,25,now) end
        assert(not fireDue(0))
        specialist.x=25; assert(not fireDue(0))
        specialist.x=3.01; assert(fireDue(0) and fireDue(200))
        specialist.x=2; assert(not fireDue(300))
        specialist.x=9; assert(not fireDue(2000)) -- approach retains the officer's cooldown
        assert(fireDue(7000))
        assert(setPlayerWanted(player,1))
        policePed["npchlc_traffic:originalModel"]=8
        assert(not TrafficWanted.tryArrest(policePed,player,getTickCount(),work) and work.follow)
        policePed.x=-2
        local arrested, entering=TrafficWanted.tryArrest(policePed,player,getTickCount(),work)
        assert(not arrested and entering and cleared==1 and not work.follow)
        assert(not car.open and player.level==1)
        local second={kind="ped",police=true,x=-2,suspect=player,slot=1}
        assert(select(2,TrafficWanted.tryArrest(second,player,getTickCount())))
        local function enter()
            fire("onVehicleStartEnter",car,policePed,0,player,0)
        end
        local function report(id)
            fire("npchlc_traffic:observedDriverDoor",resourceRoot,car,id,true)
        end
        for _,reason in ipairs({"passenger","locked","moving","veto","wrongDoor","unconfirmed","early"}) do
            local id=messages[#messages][7]
            vetoEnter=reason=="veto"
            eventCancelled=false
            if reason=="wrongDoor" then fire("onVehicleStartEnter",car,policePed,0,player,3) elseif reason~="unconfirmed" then enter() end
            assert(eventCancelled==(reason=="veto" or reason=="wrongDoor"))
            client=other;report(id);client=player;report(id+99)
            if reason=="passenger" then car.driver=other elseif reason=="locked" then car.locked=true elseif reason=="moving" then car.vx=.1 end
            if reason~="early" then tick(60) end
            car.open=.85;report(id)
            assert(player.level==1)
            car.driver,car.locked,car.vx,car.open,vetoEnter=player,false,0,0,false
            tick(2400)
            assert(select(2,TrafficWanted.tryArrest(policePed,player,getTickCount(),work)))
        end
        enter()
        tick(60)
        car.open=.82
        report(messages[#messages][7])
        assert(player.level==0 and car.driver==player and not policePed.inVehicle and policePed.slot==2)
        for _,case in ipairs({"open","missing","bike"}) do
            assert(setPlayerWanted(player,1))
            car.open,car.doorState,car.type=case=="open" and 1 or 0,case=="missing" and 4 or 0,case=="bike" and "Bike" or "Automobile"
            car.locked=true
            assert(not TrafficWanted.tryArrest(policePed,player,getTickCount()))
            car.locked=false
            assert(TrafficWanted.tryArrest(policePed,player,getTickCount()) and car.driver==player)
        end
        player.inVehicle,player.car=nil,nil
    ''')
    lua.execute("""
        local api=exports.wanted
        assert(api:setPlayerWantedCap(player,3) and api:setPlayerWanted(player,6))
        assert(getPlayerWanted(player)==3 and getPlayerWanted(other)==3)
        assert(api:setPlayerPoliceOverride(player,"army",true))
        assert(api:getPlayerPoliceResponse(player).army and not api:getPlayerPoliceResponse(other).army)
        assert(api:setPlayerPoliceOverride(player,"suppressPolice",true))
        assert(api:getPlayerPoliceResponse(player).policeHelicopters==0)
        assert(api:resetPlayerWanted(player,"reset") and api:setPlayerWanted(player,6))
        assert(getPlayerWanted(player)==6 and api:getPlayerPoliceResponse(player).policeHelicopters==1)
        assert(api:setPlayerWanted(player,0))
        assert(api:reportWantedEvent(player,4,1000,true) and getPlayerWanted(player)==1)
        assert(api:reportWantedEvent(player,12,1001,false) and getPlayerWanted(player)==2)

        -- Cross every boundary through the production scorer, including a
        -- full queue, while another player keeps their original three stars.
        assert(api:resetPlayerWanted(player))
        local thresholds = {40,180,550,1200,2400,4800}
        for points = 5, 4800, 5 do
            assert(api:reportWantedCrime(player, 2, points, true))
            local expected = 0
            for stars, minimum in ipairs(thresholds) do
                if points >= minimum then expected = stars end
            end
            assert(getPlayerWanted(player)==expected and getPlayerWanted(other)==3)
        end

        -- A direct setter clears the wanted queue, while the PS2 world
        -- event still absorbs repeat hits on the same victim and extends expiry.
        assert(api:resetPlayerWanted(player))
        assert(api:reportWantedEvent(player, 12, policePed, true))
        assert(api:setPlayerWanted(player, 0))
        tick(9900)
        assert(api:reportWantedEvent(player, 12, policePed, true) and player.level==0)
        tick(9900)
        assert(api:reportWantedEvent(player, 12, policePed, true) and player.level==0)
        tick(10001)
        assert(api:reportWantedEvent(player, 12, policePed, true) and player.level==2)

        assert(api:resetPlayerWanted(player))
        PedAIRules.reportPlayerStrike(player,policePed,true,4,false)
        assert(player.level==2)
        assert(api:resetPlayerWanted(player))
        PedAIRules.reportPlayerStrike(player,policePed,true,3,false)
        assert(player.level==1)
        assert(api:setPlayerWanted(player,5) and api:suspendPlayerWanted(player))
        assert(api:raisePlayerWanted(player,1,"vehicleAttack") and player.level==5)
        assert(api:resetPlayerWanted(player) and api:setPlayerWanted(player,2) and api:suspendPlayerWanted(player))
        local count = #events
        assert(api:raisePlayerWanted(player,4,"mission"))
        assert(#events==count+2 and events[count+1][3]==2 and events[count+2][3]==4)

        local names = {"suppressPolice", "suppressGarage", "swat", "fbi", "army"}
        local cops, cars, barriers = {0,2,3,4,6,8,10}, {0,1,2,3,3,4,4}, {0,0,0,12,18,24,30}
        for stars = 0, 6 do
            assert(api:setPlayerWanted(player,stars))
            for mask = 0, 31 do
                local flags = {}
                for bit, name in ipairs(names) do
                    flags[name] = math.floor(mask / 2^(bit-1)) % 2 == 1
                    assert(api:setPlayerPoliceOverride(player,name,flags[name]))
                end
                local row = api:getPlayerPoliceResponse(player)
                assert(row.pursuitPedLimit == cops[stars+1] and row.pursuitVehicleLimit == cars[stars+1])
                assert(row.roadblockThreshold == barriers[stars+1] and row.undercover == (stars >= 3))
                assert(row.swat == (flags.swat or stars==4) and row.fbi == (flags.fbi or stars==5))
                assert(row.army == (flags.army or stars==6))
                assert(row.policeHelicopters == ((stars>=3 and not flags.suppressPolice and not flags.suppressGarage) and 1 or 0))
            end
        end
    """)
    # Exercise the syncer's native-task gate independently of server authorization.
    client = LuaRuntime()
    client.execute("""
        root,resourceRoot,officer,car,driver={},{},{},{},{}
        handlers={}
        function addEvent() end
        function addEventHandler(name,_,f) handlers[name]=f end
        function removeEventHandler(name) handlers[name]=nil end
        function isElement(e) return e~=nil end
        function isElementSyncer() return true end
        function isElementStreamedIn() return true end
        function isVehicleLocked() return locked end
        function getVehicleOccupant() return driver end
        function getElementVelocity() return 0,0,0 end
        function isPedDead() return false end
        function getTickCount() return 100 end
        function getPedSimplestTask() return task end
        function getVehicleDoorOpenRatio() return hinge end
        function setPedEnterVehicle() return not veto end
        function setPedAnimation(_,_,name) pose=name end
        function setPedControlState(p,control,value) assert(p==officer and control=="fire" and not value) end
        function triggerServerEvent(_,_,_,id,opened) assert(id==73); observed=opened end
    """)
    client.execute((traffic / "traffic_passengers_c.lua").read_text(encoding="utf-8"))
    client.execute("""
        local start=handlers["npchlc_traffic:openPoliceDriverDoor"]
        local function enter() observed=nil;start(officer,car,driver,73) end
        locked=true;enter();assert(observed==false and not handlers.onClientPreRender)
        locked=false;veto=true;enter();assert(observed==false and not handlers.onClientPreRender)
        veto=false;enter()
        hinge=0;task="TASK_SIMPLE_CAR_ALIGN";handlers.onClientPreRender()
        task="TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE";hinge=.45;handlers.onClientPreRender();assert(observed==nil)
        locked=true;handlers.onClientPreRender()
        assert(observed==false and pose=="IDLE_stance" and not handlers.onClientPreRender)
        locked=false;enter();hinge=.7;handlers.onClientPreRender()
        task="TASK_SIMPLE_PLAYER_ON_FOOT";handlers.onClientPreRender();assert(observed==false)
        enter();hinge=.84;task="TASK_SIMPLE_CAR_OPEN_DOOR_FROM_OUTSIDE";handlers.onClientPreRender()
        assert(observed==true and pose=="ARRESTgun" and not handlers.onClientPreRender)
    """)
    hlc = traffic.parent / "npc_hlc"
    client.execute((hlc / "tasks_c.lua").read_text(encoding="utf-8"))
    client.execute((hlc / "valid_tasks_s.lua").read_text(encoding="utf-8"))
    client.execute("""
        function getElementType(e) return e==driver and "player" or "ped" end
        function getPedOccupiedVehicle() return car end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
        function getElementBoundingBox() return -1,-2,-.5,1,2,1 end
        function getElementPosition(e) return e.x or 0,0,e.z or 0 end
        function isLineOfSightClear() return not obstructed end
        function stopNPCWalkingActions() end
        function walkNPCTrafficFormation() end
        function setPedRotation() end
        function stopNPCWeaponActions() firing=false end
        function makeNPCShootAtPos() firing=true end
        local function check(x,z,permit,expected)
            officer.x,officer.z=x,z
            local task=normalizeNPCTask({"attackOccupiedVehicle",driver,25,8,1,permit})
            assert(task and task[6]==permit)
            performTask.attackOccupiedVehicle(officer,task,0,{})
            assert(firing==expected)
        end
        check(3,0,1,false)
        check(3,.1,1,true)
        check(24.99,0,1,true)
        check(25,0,1,false)
        check(10,0,0,false)
        obstructed=true
        check(10,0,1,false)
        assert(not normalizeNPCTask({"attackOccupiedVehicle",driver,25,8,0,1}))
    """)
    print("VCS wanted rules and MTA adapter passed")


if __name__ == "__main__":
    main()
