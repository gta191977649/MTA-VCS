"""Exercise vehicle mission entry, ownership, rewards, and persistence with Lua 5.1 and SQLite."""
from pathlib import Path
import sqlite3
from xml.etree import ElementTree

from lupa.lua51 import LuaRuntime

RESOURCES = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources"
MISSION = RESOURCES / "[mission]/mission"


def check():
    lua = LuaRuntime(unpack_returned_tuples=True)
    db = sqlite3.connect(":memory:")
    db.row_factory = sqlite3.Row
    db.executescript("""CREATE TABLE progress(owner TEXT PRIMARY KEY,taxiFares INTEGER,taxiEarnings INTEGER,
        vigilante INTEGER,paramedic INTEGER,airrescue INTEGER);
        INSERT INTO progress VALUES ('guest/legacy',9,400,10,5,0);""")

    def query(_, sql, *values):
        rows = db.execute(sql, values)
        db.commit()
        return lua.table_from([lua.table_from(dict(row)) for row in rows])

    lua.globals().dbQuery = query
    lua.execute("""
        resourceRoot, root = {}, {}
        local handlers, timers={},{}
        function addEvent() end
        function cancelEvent() cancelled=true end
        function addEventHandler(name, element, fn)
            handlers[name]=handlers[name] or {}
            table.insert(handlers[name],fn)
        end
        function fire(name,element,...)
            local prev=source
            source=element
            for _,fn in ipairs(handlers[name] or {}) do fn(...) end
            source=prev
        end
        function setTimer(fn,ms) timers[ms]=fn end
        now=0
        function pulse(ms) now=now+ms timers[ms]() end
        function getTickCount() return now end
        function dbConnect() return true end
        function getResourceFromName(name) return name end
        function getResourceName(name) return name end
        function getResourceState() return "running" end
        dbExec=dbQuery
        function dbPoll(result) return result end
        function addCommandHandler(_,fn) command=fn end
        function bindKey(player,key,_,fn) player[key]=fn end
        function isControlEnabled() return true end
        function isElement(e) return type(e)=="table" and e.kind ~= nil and not e.deadElement end
        function getElementType(e) return e.kind end
        function attachElements(m,e) m.target=e return true end
        function getElementAttachedTo(m) return m.target end
        function getElementData(e,k) return e[k] or false end
        function setElementData(e,k,v) e[k]=v end
        function hasElementData(e,k) return e[k]~=nil end
        function removeElementData(e,k) e[k]=nil end
        function getElementInterior(e) return e.interior or 0 end
        function getElementDimension(e) return e.dimension or 0 end
        function setElementInterior(e,i) e.interior=i end
        function setElementDimension(e,d) e.dimension=d end
        function getPedOccupiedVehicle(p) return p.car end
        function getVehicleOccupant(v,seat) return v[seat] end
        function isVehicleBlown() return false end
        function isVehicleOnGround() return true end
        function getElementVelocity() return 0,0,0 end
        function setElementVelocity(v,x,y,z) v.jump=z end
        function isPedDead() return false end
        function getPlayerAccount(p) return p.account end
        function getPlayerSerial(p) return p.serial end
        function getAccountName(a) return a end
        function isGuestAccount() return false end
        function getPedStat(p) return p.stat or 569 end
        function setPedStat(p,_,v) p.stat=v end
        function getPedArmor(p) return p.armor or 0 end
        function setPedArmor(p,v) p.armor=v return true end
        function getElementHealth(p) return p.health or 100 end
        function setElementHealth(p,v) p.health=v end
        function givePlayerMoney(p,amount) p.cash=p.cash+amount end
        function triggerClientEvent(p,event,_,...)
            p.last=event
            if event=="mission:end" and select(2,...) then p.passes=(p.passes or 0)+1 end
            if event=="mission:payout" then p.banners=p.banners+1 end
        end
        function outputDebugString(reason) error(reason) end
        function destroyElement(e) fire("onElementDestroy",e) e.deadElement=true end
        exports={marker={createMarker=function(_,x,y,z,style,size,r,g,b,a,viewer)
                return {kind="marker",viewer=viewer}
            end,setMarkerBlipVisible=function(_,m,v) m.blip=v end},
            wanted={setPlayerWanted=function(_,p,n) p.wanted=n end},
            frontend={showTextBox=function()end,
            showPayoutGameText=function(_,p) p.banners=p.banners+1 end},
            npchlc_traffic={releaseTrafficPed=function(_,ped) ped.released=true end}}
        function player(serial)
            local p={kind="player",serial=serial,cash=0,banners=0}
            fire("onPlayerJoin",p)
            return p
        end
        function drive(p,id)
            p.car={kind="vehicle",[0]=p,["vcs_vehicle:originalModel"]=id}
            now=now+500
            p.sub_mission(p)
        end
    """)
    lua.execute((MISSION / "course_gates.lua").read_text())
    lua.execute("""
        local car={x=-9,y=0,z=0}
        local run={vehicle=car}
        function getElementPosition(e) return e.x,e.y,e.z end
        local gate={0,0,0}
        assert(not CourseGates.crossed(run,0,gate,2))
        car.x=9
        assert(CourseGates.crossed(run,200,gate,2))
        car.x=-100
        assert(not CourseGates.crossed(run,400,gate,2))
        car.x=100
        assert(not CourseGates.crossed(run,600,gate,2))
        run.vehicle={x=0,y=7,z=0}
        assert(not CourseGates.crossed(run,650,gate,2))
        run.vehicle.x,run.vehicle.y=-9,0
        assert(not CourseGates.crossed(run,700,gate,2))
        run.vehicle.x=9
        assert(not CourseGates.crossed(run,3000,gate,2))
    """)
    lua.execute((MISSION / "race_collision_c.lua").read_text())
    lua.execute("""
        function isElementStreamedIn() return true end
        function isElementCollidableWith(a,b) return not (a.disabled and a.disabled[b]) end
        function setElementCollidableWith(a,b,value)
            a.disabled=a.disabled or {}; a.disabled[b]=not value
            return true
        end
        local a,b,c={kind="vehicle"},{kind="vehicle"},{kind="vehicle"}
        a["mission:raceOwner"]=1
        b["mission:raceOwner"]=2
        c["mission:raceOwner"]=1
        setElementCollidableWith(b,c,false)
        for _,v in ipairs({a,b,c}) do fire("onClientElementStreamIn",v) end
        assert(isElementCollidableWith(a,c) and not isElementCollidableWith(a,b))
        assert(not isElementCollidableWith(b,a) and not isElementCollidableWith(c,b))
        b["mission:raceOwner"]=nil
        fire("onClientElementDataChange",b,"mission:raceOwner")
        assert(isElementCollidableWith(a,b) and isElementCollidableWith(c,b))
        assert(not isElementCollidableWith(b,c))
    """)
    startup = (RESOURCES / "[vcs]/leeds_engine/resources.lua").read_text()
    assert startup.index('{ "mission" }') > startup.index('{ "npchlc_traffic" }')
    compile_lua = lua.eval("function(s) local f,e=loadstring(s); assert(f,e) end")
    for node in ElementTree.parse(MISSION / "meta.xml").getroot().findall("script"):
        compile_lua((MISSION / node.attrib["src"]).read_text(encoding="utf-8-sig"))
    for name in ("main.lua", "profile.lua"):
        lua.execute((MISSION / name).read_text(encoding="utf-8-sig"))
    lua.execute("""
        local function capture(r) r.player.run=r end
        models={taxi=226,paramedic=227,airrescue=189,vigilante=207,beachpatrol=255,
            firefighter=194,firecopter=188,vicesights=213}
        for id,model in pairs(models) do
            Mission.register(id,{models={model},title=id,start=capture,tick=function()end,
                startLevel=(id=="firecopter" or id=="vicesights") and function() return 1 end or nil})
        end
        local function launchCourse(r)
            capture(r)
            Mission.selectCourse(r,{"Short","Long"},function(run,index) run.chosen=index end)
        end
        Mission.register("skyTest",{title="Sky",models={207},canStart=function(p) return p.atPad end,
            start=launchCourse,tick=function()end})
        local a,b=player("course-a"),player("course-b")
        a.atPad,b.atPad=true,true
        drive(a,207)
        drive(b,207)
        local ar,br=a.run,b.run
        assert(ar.id=="skyTest" and br.id==ar.id)
        client=b
        fire("mission:courseChoice",resourceRoot,ar.token,ar.id,2,ar.menuSerial)
        assert(not ar.chosen and not br.chosen)
        client=a
        fire("mission:courseChoice",resourceRoot,ar.token,ar.id,2,ar.menuSerial+1)
        assert(not ar.chosen)
        fire("mission:courseChoice",resourceRoot,ar.token,ar.id,2,ar.menuSerial)
        fire("mission:courseChoice",resourceRoot,ar.token,ar.id,1,ar.menuSerial)
        assert(ar.chosen==2 and not br.chosen)
        assert(Mission.finishCourse(ar,2,{time=37001,lap=18200,position=2,score=50},300,true))
        assert(not Mission.finishCourse(ar,2,{time=10},300,true))
        assert(a.cash==300 and Mission.courseRecord(br,2).wins==0)
        drive(a,207)
        Mission.finishCourse(a.run,2,{time=38200,lap=17500,position=1,score=40},50,true)
        local row=Mission.courseRecord(a.run,2)
        assert(row.time==37001 and row.lap==17500 and row.position==1 and row.score==50 and row.wins==2)
        assert(Mission.courseRecord(a.run,1).wins==0)
        a.account="new"
        fire("onPlayerLogin",a)
        drive(a,207)
        assert(Mission.courseRecord(a.run,2).wins==0)
        Mission.endRun(a)
        Mission.endRun(b)
        client=nil
        local switcher,other=player("switcher"),player("other")
        drive(switcher,189)
        drive(other,188)
        local old,parallel=switcher.run,other.run
        local hook=Mission.track(old,{kind="object"})
        local patient=Mission.lease(old,{kind="ped"})
        local waypoint=Mission.marker(old,1,2,3,"arrow2",1,nil,true)
        local otherBucket=Mission.track(parallel,{kind="object"})
        assert(Mission.claimSite(old,"sling"))
        drive(switcher,188)
        assert(switcher.run.id=="firecopter" and not Mission.active(old))
        assert(hook.deadElement and waypoint.deadElement and patient.released)
        assert(Mission.vehicleAvailable(nil,old.vehicle) and Mission.siteAvailable(parallel,"sling"))
        Mission.pay(old,100)
        assert(switcher.cash==0 and Mission.active(parallel) and not otherBucket.deadElement)
        Mission.endRun(switcher)
        Mission.endRun(other)
        local p=player("qa")
        drive(p,99)
        assert(not p.run)
        drive(p,226)
        local t=p.run
        assert(Mission.active(t))
        p.car[0]={}
        -- A second toggle addresses the existing run, never creates a second one.
        now=now+501
        command(p)
        assert(p.run==t and p.last=="mission:message")
        p.car[0]=p
        local item=Mission.track(t,{kind="object"})
        local ped=Mission.lease(t,{kind="ped"})
        Mission.taxiFare(t,5000)
        Mission.taxiFare(t,5000)
        assert(p.cash==5000 and t.profile.taxiFares==1 and p.banners==1)
        p.horn(p)
        assert(p.car.jump>0)
        Mission.endRun(p)
        assert(ped.released and item.deadElement)
        Mission.taxiFare(t,50)
        assert(p.cash==5000)
        p.account="account-a"
        fire("onPlayerLogin",p)
        assert(Mission.profile(p).taxiEarnings==0)
        drive(p,226)
        for i=1,50 do pulse(200) Mission.taxiFare(p.run,5) end
        assert(p.banners==2 and p.run.profile.taxiFares==50)
        p.account=false
        fire("onPlayerLogout",p)
        assert(Mission.profile(p).taxiEarnings==5000)
        for _,mission in ipairs({{"paramedic",227},{"vigilante",207},{"airrescue",189}}) do
            local id,model=unpack(mission)
            drive(p,model)
            local r=p.run
            for level=1,15 do
                pulse(200)
                assert(r.level==level)
                Mission.finishLevel(r,100)
                Mission.finishLevel(r,100)
                if level%5==0 then assert(r.profile[id]==level) end
            end
            assert(r.level==16 and r.profile[id]==15)
            fire("onPlayerWasted",p)
            fire("onPlayerSpawn",p)
            drive(p,model)
            assert(p.run.level==16)
            Mission.endRun(p)
        end
        assert(p["mission:unlimitedSprint"] and p["mission:maxArmour"]==150)
        assert(p.health>=150 and p.health<151)
        p.armor=70
        pulse(100)
        assert(p.armor==100 and p["mission:extraArmour"]==20)
        assert(p.cash==5000+250+45*100+500)
        fire("onPlayerQuit",p)
        local fresh=player("qa")
        assert(Mission.profile(fresh).airrescue==15 and fresh["mission:taxiJump"])
        fresh.account="account-a"
        fire("onPlayerLogin",fresh)
        assert(Mission.profile(fresh).taxiFares==50 and fresh["mission:maxArmour"]==100)
        local legacy=Mission.profile(player("legacy"))
        assert(legacy.taxiFares==9 and legacy.vigilante==10 and legacy.beachpatrol==0)
        for id,model in pairs(models) do
            local a,b=player("a-"..id),player("b-"..id)
            drive(a,model)
            b.car=a.car
            b.car[0]=b
            now=now+500
            command(b)
            assert(not b.run)
            a.car[0]=a
            drive(b,model)
            local ra,rb=a.run,b.run
            assert(ra~=rb and ra.token~=rb.token and Mission.participants(ra)[1]==a)
            cancelled=false
            fire("onVehicleStartEnter",ra.vehicle,b,0)
            assert(cancelled)
            cancelled=false
            fire("onVehicleStartEnter",ra.vehicle,a,0)
            assert(not cancelled)
            assert(not Mission.forParticipant(a,rb.token,id) and Mission.forParticipant(b,rb.token,id)==rb)
            assert(not Mission.switchVehicle(ra,rb.vehicle))
            local ambient=Mission.lease(ra,{kind="ped"})
            assert(not Mission.lease(rb,ambient) and not Mission.release(rb,ambient))
            assert(Mission.claimSite(ra,"shared-position") and not Mission.claimSite(rb,"shared-position"))
            Mission.releaseSite(rb,"shared-position")
            assert(not Mission.siteAvailable(rb,"shared-position"))
            local ma=Mission.marker(ra,1,2,3,"arrow2",1,nil,true)
            local mb=Mission.marker(rb,1,2,3,"arrow2",1,nil,true)
            assert(ma.viewer==a and mb.viewer==b and ma.blip and mb.blip)
            ra.vehicle.x,ra.vehicle.y,ra.vehicle.z=1,2,3
            Mission.showReturnVehicle(ra,ra.vehicle)
            local arrow=ra.returnMarker
            assert(arrow.target==ra.vehicle and arrow.viewer==a and arrow.blip)
            Mission.showReturnVehicle(ra,ra.vehicle)
            assert(ra.returnMarker==arrow)
            Mission.clearReturnVehicle(ra)
            assert(arrow.deadElement and not ra.returnMarker)
            Mission.endRun(a)
            assert(ma.deadElement and not mb.deadElement and Mission.active(rb) and ambient.released)
            assert(Mission.claimSite(rb,"shared-position"))
            drive(a,model)
            assert(not Mission.forParticipant(a,ra.token,id))
            fire("onPlayerQuit",a)
            if id=="firecopter" or id=="vicesights" then
                for pass=1,2 do
                    for level=1,5 do
                        pulse(200)
                        assert(rb.level==level)
                        Mission.finishLevel(rb,100)
                        Mission.finishLevel(rb,100)
                    end
                    assert(not Mission.active(rb) and b.cash==pass*500+500 and b.passes==pass and b.banners==0)
                    drive(b,model)
                    rb=b.run
                end
            elseif id=="beachpatrol" or id=="firefighter" then
                for level=1,20 do pulse(200) Mission.finishLevel(rb,0) end
                assert(b["mission:"..(id=="beachpatrol" and "unlimitedSwim" or "fireproof")])
                assert(b.cash==(id=="beachpatrol" and 1500 or 0))
                assert(rb.profile[id]==(id=="beachpatrol" and 20 or 15))
            end
            Mission.endRun(b)
        end
        for _,pair in ipairs({{"firefighter","firecopter"},{"paramedic","beachpatrol"}}) do
            local a,b=player("cross-a"),player("cross-b")
            drive(a,models[pair[1]])
            drive(b,models[pair[2]])
            local x,y=a.run,b.run
            assert(not Mission.forParticipant(a,y.token,y.id))
            assert(not Mission.forParticipant(a,x.token,y.id))
            assert(Mission.claimSite(x,"incident") and not Mission.claimSite(y,"incident"))
            local medic=Mission.lease(x,{kind="ped"})
            assert(not Mission.lease(y,medic))
            fire("onPlayerQuit",a)
            assert(Mission.active(y) and Mission.claimSite(y,"incident"))
            Mission.finishLevel(y,100)
            assert(b.cash==100 and a.cash==0)
            Mission.endRun(b)
        end
        local a,b=player("restart-a"),player("restart-b")
        drive(a,194)
        drive(b,227)
        local marker=Mission.marker(a.run,0,0,0,"arrow2",1,nil,true)
        fire("onResourceStop",{},"npchlc_traffic")
        assert(not Mission.active(a.run) and not Mission.active(b.run) and marker.deadElement)
        assert(Mission.vehicleAvailable(nil,a.car) and Mission.vehicleAvailable(nil,b.car))
    """)
    db.close()


def check_boarding():
    lua = LuaRuntime()
    lua.execute("""
        local function noop() end
        events={}
        function addEventHandler(name,_,fn) events[name]=fn end
        function setTimer(fn) advance=fn end
        sourceResource="mission"
        function isElement(e) return type(e)=="table" and e.kind~=nil end
        function getElementType(e) return e.kind end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function isPedDead() return false end
        function isVehicleBlown() return false end
        function getPedOccupiedVehicle(p) return p.car end
        function isPedInVehicle(p) return p.car~=nil end
        function getPedOccupiedVehicleSeat(p) return p.seat end
        function getVehicleMaxPassengers() return 3 end
        function getVehicleOccupant(v,n) return v[n] end
        clock=900
        function getTickCount() return clock end
        function getElementVelocity() return 0,0,0 end
        function isVehicleLocked() return false end
        function getElementData() return false end
        function getElementHealth() return 100 end
        function getElementPosition() return 1.4,0.7,0 end
        function getDistanceBetweenPoints3D() return carDistance or 0 end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
        function getElementSyncer() return "client" end
        function triggerClientEvent(_,name,_,ped,car,seat) report={name,ped,car,seat} end
        function cancelEvent() blocked=true end
        function warpPedIntoVehicle(p,c,s)
            if p.seat then c[p.seat]=nil end
            c[s],p.car,p.seat=p,c,s
            source=c
            events.onVehicleEnter(p,s)
            return true
        end
        setElementHealth=noop
        exports={npc_hlc={clearNPCTasks=noop,setNPCWalkSpeed=noop,setNPCTask=function() walks=(walks or 0)+1 end}}
        TrafficVisibility,TrafficAmbient,TrafficRoad={},{suspend=noop},{}
        TrafficActors={endMissionPath=noop}
        PedVehicleEvasion,PedCarjack={cancel=noop},{cancelExtraction=noop}
        PedSpecial={interrupt=noop,update=function() return false end}
        PedAI={brain=function(p) return p.brain end}
        function ped()
            local p={kind="ped"}
            p.brain={ped=p,tasks={clear=noop},objectives=PedObjectives.new(),profile={pedType=4}}
            return p
        end
    """)
    traffic = RESOURCES / "[traffic]/npchlc_traffic"
    for script in ("ped_objectives.lua", "ped_script_control.lua"):
        lua.execute((traffic / script).read_text())
    lua.execute("""
        local a,b,car=ped(),ped(),{kind="vehicle"}
        assert(acquireTrafficPed(a) and acquireTrafficPed(b))
        sourceResource="another-resource"
        assert(not acquireTrafficPed(a))
        sourceResource="mission"
        assert(assignTrafficPedObjective(a,"enterVehicle",car,1))
        assert(assignTrafficPedObjective(a,"enterVehicle",car,1))
        assert(not assignTrafficPedObjective(b,"enterVehicle",car,1))
        source=car
        events.onVehicleStartEnter(b,1)
        assert(blocked)
        carDistance=12
        advance();advance()
        assert(walks==1 and not report)
        carDistance=8
        advance()
        assert(report[1]=="npchlc_traffic:missionEntry" and report[4]==1)
        assert(assignTrafficPedObjective(a,"clear"))
        assert(report[1]=="npchlc_traffic:cancelMissionEntry")
        assert(assignTrafficPedObjective(b,"enterVehicle",car,1))
        b.car,b.seat,car[2]=car,2,b
        assert(not isMissionPedSeated(b,car))
        assert(assignTrafficPedObjective(b,"enterVehicle",car,1))
        events.onVehicleEnter(b,2)
        advance()
        assert(isMissionPedSeated(b,car,1))
        assert(car[1]==b and car[2]==nil and not b.brain.objectives.current)
        assert(assignTrafficPedObjective(a,"enterVehicle",car,0))
        assert(releaseTrafficPed(a))
        assert(not assignTrafficPedObjective(a,"enterVehicle",car,0))
        local c=ped()
        assert(acquireTrafficPed(c) and assignTrafficPedObjective(c,"enterVehicle",car,3))
        advance()
        assert(report[1]=="npchlc_traffic:missionEntry" and not isMissionPedSeated(c,car,3))
        carDistance=1.5;clock=clock+4600
        advance()
        assert(isMissionPedSeated(c,car,3) and car[1]==b)
    """)


def check_client():
    lua = LuaRuntime()
    lua.execute("""
        localPlayer,root,resourceRoot={},{},{}
        events,calls={},{}
        function addEvent() end
        function addEventHandler(name,_,fn) events[name]=fn end
        function getBoundKeys() return keys end
        function getResourceFromName() return "frontend" end
        function getResourceState() return "running" end
        function getElementData(p,k) return p[k] end
        function isPedDead() return false end
        function isPedInVehicle() return false end
        function isElementInWater() return inWater end
        function setElementData(e,key,value) e[key]=value end
        function getElementVelocity() return .2,0,0 end
        function getPedControlState() return true end
        function getPedMoveState() return move end
        function isControlEnabled() return not locked end
        function toggleControl(_,enabled) locked=not enabled end
        exports={frontend=setmetatable({}, {__index=function(_,name)
            return function(self,...) calls[name]={...} end
        end})}
    """)
    lua.execute((MISSION / "main_c.lua").read_text())
    lua.execute("""
        keys={num_add="down",["2"]="down"}
        local car={}
        source=car
        function triggerServerEvent(name,_,v) assert(name=="mission:driverEntered" and v==car) end
        function getPedOccupiedVehicle() return car end
        function getPedOccupiedVehicleSeat() return 0 end
        events["mission:prompt"]("Taxi Driver",car)
        assert(not calls.showTextBox,"prompt appeared before driver entry finished")
        events.onClientVehicleEnter(localPlayer,1)
        events["mission:prompt"]("Taxi Driver",car)
        assert(not calls.showTextBox,"passenger received driver prompt")
        events.onClientVehicleEnter(localPlayer,0)
        events["mission:prompt"]("Taxi Driver",car)
        assert(calls.showTextBox[1]=="Press 2 to start Taxi Driver")
        keys={k="down"}
        events["mission:prompt"]("Vigilante",car)
        assert(calls.showTextBox[1]=="Press K to start Vigilante")
        events["mission:start"]("Taxi Driver",17)
        events["mission:hud"]("taxi",1,75,"Fares",3,"Tip",80,17)
        local row = calls.showVehicleMissionHud
        assert(row[1]==75 and not row[2] and row[3]=="Fares" and row[4]==3)
        assert(row[5]=="Tip" and row[6]==80)
        events["mission:start"]("Vigilante",18)
        events["mission:hud"]("vigilante",5,299,"Kills",12,false,0,18)
        row = calls.showVehicleMissionHud
        assert(row[1]==299 and row[2]==5 and row[3]=="Kills" and row[4]==12 and not row[5])
        events["mission:message"]("Take the patient to the hospital.",18)
        assert(calls.showCaptionForPlayer[1]=="Take the patient to the hospital.")
        events["mission:end"]("Time is up!",false,18)
        assert(calls.showVehicleMissionResult[1]==false and calls.showVehicleMissionResult[2]=="Time is up!")
        assert(calls.hideVehicleMissionHud and calls.hideCaptionForPlayer[1] and not MissionRunToken)
        calls.showVehicleMissionHud,calls.showPayoutGameText,calls.showCaptionForPlayer=nil,nil,nil
        events["mission:hud"]("vigilante",5,299,"Kills",12,false,0,18)
        events["mission:payout"](18,500)
        events["mission:message"]("expired",18)
        assert(not calls.showVehicleMissionHud and not calls.showPayoutGameText and not calls.showCaptionForPlayer)
        move="sprint"
        for _=1,600 do events.onClientPreRender(20) end
        assert(locked)
        localPlayer["mission:unlimitedSprint"]=true
        for _=1,1000 do events.onClientPreRender(20) end
        assert(not locked)
        inWater=true
        for _=1,1000 do events.onClientPreRender(20) end
        assert(locked and localPlayer["mission:swimEnergy"]==0)
        localPlayer["mission:unlimitedSwim"]=true
        events.onClientPreRender(20)
        assert(not locked and localPlayer["mission:swimEnergy"]==100)
        localPlayer["mission:fireproof"]=true
        function isPedOnFire() return true end
        function setPedOnFire(_,burning) extinguished=not burning end
        function cancelEvent() cancelled=true end
        events.onClientPlayerDamage(nil,37)
        assert(cancelled and extinguished)
        cancelled=false
        events.onClientPlayerDamage(nil,51)
        assert(not cancelled)
    """)


if __name__ == "__main__":
    check()
    check_boarding()
    check_client()
    print("Mission bindings, profile separation, duplicate rewards, perks and reconnect checks passed.")

