"""Exercise USA VIG dispatch, progression and shared traffic route completion with Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

RESOURCES = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources"
MISSION = RESOURCES / "[mission]/mission"
TRAFFIC = RESOURCES / "[traffic]/npchlc_traffic"


def load(lua, path):
    lua.execute(path.read_text(encoding="utf-8-sig"), name=str(path))


def verify_encounters():
    lua = LuaRuntime()
    lua.execute("""
        local events={}
        resourceRoot,root={},{}
        function addEvent() end
        function addEventHandler(name,target,fn) events[name]=fn end
        function emit(name,target,...)
            source=target
            return events[name](...)
        end
        function entity(x,y,z) return {x=x or 0,y=y or 0,z=z or 0,valid=true,hp=100} end
        function isElement(e) return type(e)=="table" and e.valid end
        function destroyElement(e) assert(isElement(e)); e.valid=false end
        function getElementHealth(e) return e.hp end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getElementPosition(e) return e.x,e.y,e.z end
        function getElementVelocity() return 0,0,0 end
        function setElementDimension() end
        function setElementInterior() end
        function setElementData() end
        function setElementFrozen(e,b) e.frozen=b end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        function setElementVelocity() end
        function setElementSyncer() end
        function removeElementData() end
        function setVehicleEngineState() end
        function getVehicleSirensOn() return false end
        function setPedRotation() end
        function isPedDead(e) return e.hp<=0 end
        function giveWeapon(p,w,a) assert(a==50); p.weapon=w end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function getTickCount() return time end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1}} end
        function getVehicleOccupant(car,seat) return car[seat or 0] end
        function getPedOccupiedVehicle(p) return p.car end
        function getPedOccupiedVehicleSeat(p) return p.seat end
        function warpPedIntoVehicle(p,v,s)
            assert(v[s]==nil); assert(s<=((v.model==232 or v.model==252) and 1 or 3))
            p.seat,p.car,v[s]=s,v,p
            return true
        end
        function createBlipAttachedTo(e,icon,size,r,g,blue,alpha,order,distance,player)
            local b=entity()
            b.attached,b.r,b.g,b.blue,b.viewer=e,r,g,blue,player
            return b
        end
        function getElementAttachedTo(b) return b.attached end
        local traffic={}
        function traffic:isMissionPedSeated(p,v,seat) return p.confirmed and p.car==v and p.seat==seat end
        function traffic:getTrafficIslandAt() return 2 end
        function traffic:getMissionTrafficRoad(x,y,z) return x,y,z,0 end
        function traffic:createTrafficScriptPed(id,x,y,z) assert(id==55 or id==58); return entity(x,y,z) end
        function traffic:cruiseMissionTraffic(p,speed) p.speed=speed; return true end
        function traffic:assignTrafficPedObjective(p,order) p.order=order; return true end
        local wanted={multiplier=1}
        function wanted:getPlayerCrimeMultiplier() return self.multiplier end
        function wanted:setPlayerCrimeMultiplier(p,val) self.multiplier=val end
        function wanted:setPlayerWanted(p,val) p.wanted=val end
        local vehicles={}
        function vehicles:createVcsVehicle(id,x,y,z) local v=entity(x,y,z); v.model,v.hp=id,1000; return v end
        exports={npchlc_traffic=traffic,vcs_vehicle=vehicles,npc_hlc={setNPCDriveSpeed=function()end,setNPCTask=function()end},wanted=wanted}
        Mission={}
        function getResourceFromName(name) return name end
        function getResourceState() return "running" end
        function Mission.releaseSites() end
        function Mission.siteAvailable() return true end
        function Mission.claimSite() return true end
        function Mission.vehicleAvailable() return true end
        function Mission.claimVehicle() return true end
        function Mission.releaseVehicle() end
        function Mission.switchVehicle(r,v) r.vehicle=v return true end
        function Mission.forParticipant(p,token) return token==17 and p and p.run end
        function Mission.driverOf(v) return getVehicleOccupant(v,0) end
        function Mission.register(id,definition) assert(id=="vigilante"); vig=definition end
        function Mission.track(r,e) r.elements[e]=true; return e end
        function Mission.pay(r,m) r.money=r.money+m end
        function Mission.finishLevel(r,amount) assert(amount==0); r.level=r.level+1 end
        function Mission.message(r,m) r.message=m end
        function Mission.hud(r,label,n) assert(label=="Kills"); r.hud=n end
        function Mission.fail(r,m) r.failed=m end
        function Mission.model(v) return v.model end
        function start(level,variant)
            time=1000
            local p=entity(-800,760,10)
            p.seat,p.car,p.wanted=0,entity(),3
            p.car.model=207
            p.car[0]=p
            local r={profile={vigilante=0},player=p,level=level,money=0,elements={}}
            p.run=r
            math.randomseed(399112)
            local random=math.random
            math.random=function(...) math.random=random; return variant end
            vig.start(r)
            assert(not r.failed,r.failed)
            assert(r.deadline==301000 and wanted.multiplier==0.5)
            return r
        end
    """)
    load(lua, MISSION / "vigilante_data.lua")
    load(lua, MISSION / "vigilante.lua")
    lua.execute("""
        assert(#vig.models==8 and #VigilanteSites.mainland==40 and #VigilanteSites.beach==40)
        for _,level in ipairs({1,5,10,15,16}) do
            for _,pattern in ipairs({1,3,4}) do
                local r=start(level,pattern)
                local tier=level<5 and 1 or level<10 and 2 or 3
                local reward=tier*20-10
                local cars=pattern==4 and 0 or pattern==3 and tier+1 or tier
                local count=pattern==4 and 2+tier*2 or cars*(pattern==3 and 2 or tier+1)
                assert(#r.cars==cars and #r.suspects==count)
                assert(r.message:find("~r~Suspects~w~",1,true))
                local b=r.suspects[1].blip
                assert(b.viewer==r.player and b.g==0)
                if pattern==4 then
                    assert(b.attached==r.suspects[1].ped and b.r==174 and b.blue==0)
                else
                    assert(r.message:find("~b~",1,true))
                    assert(b.attached==r.cars[1] and b.r==0 and b.blue==255)
                end
                local previous=r.suspects
                for _,s in ipairs(previous) do
                    assert(s.ped.weapon and (pattern==4 or s.car[s.seat]==s.ped))
                    s.ped.hp=0
                end
                vig.tick(r,2000)
                assert(r.level==level+1 and r.nextWave==5000)
                assert(r.money==count*reward and r.hud==count and r.kills==count)
                assert(r.player.wanted==(level==15 and 0 or 3))
                vig.tick(r,4900)
                assert(r.money==count*reward)
                vig.tick(r,5000)
                for _,s in ipairs(previous) do assert(not isElement(s.ped)) end
                assert(not r.nextWave and not r.failed)
                vig.stop(r)
                assert(exports.wanted.multiplier==1)
                for e in pairs(r.elements) do assert(not isElement(e)) end
            end
        end
        local officerA,officerB=start(2,4),start(2,4)
        for _,s in ipairs(officerA.suspects) do s.ped.hp=0 end
        vig.tick(officerA,2000)
        assert(officerA.level==3 and officerA.money>0 and officerB.money==0 and officerB.level==2)
        vig.stop(officerA)
        for _,s in ipairs(officerB.suspects) do assert(isElement(s.ped) and not isPedDead(s.ped)) end
        vig.stop(officerB)
        local r=start(1,4)
        local car=r.player.car
        r.player.car=nil
        vig.tick(r,1001);assert(r.returnBy==31001)
        r.player.car=car;vig.tick(r,30000);assert(not r.returnBy)
        r.player.car=nil;vig.tick(r,31000);vig.tick(r,61001)
        assert(r.failed=="You failed to return to a police vehicle in time.")
        vig.stop(r)
        local r=start(5,1)
        local driver=r.suspects[1]
        local car=driver.car
        assert(car.frozen)
        client=r.player
        emit("mission:vigilanteRoadReady",resourceRoot,car,car.z,17);assert(car.frozen)
        r.player.x,r.player.y,r.player.z=car.x,car.y,car.z
        emit("mission:vigilanteRoadReady",resourceRoot,car,car.z+50,17);assert(car.frozen)
        emit("mission:vigilanteRoadReady",resourceRoot,car,car.z-0.8,16);assert(car.frozen)
        emit("mission:vigilanteRoadReady",resourceRoot,car,car.z-0.8,17);assert(not car.frozen)
        driver.car.hp=640;vig.tick(r,2000)
        assert(driver.state=="leaving" and driver.ped.order=="exitVehicle")
        driver.ped.car=nil;vig.tick(r,2500)
        assert(driver.ped.order=="flee" and driver.state=="flee")
        driver.state,driver.enterAt="entering",2500
        driver.ped.car,driver.ped.seat=driver.car,0
        vig.tick(r,2700);assert(driver.state=="entering")
        driver.ped.confirmed=true
        vig.tick(r,2800);assert(driver.state=="riding")
        vig.stop(r)
    """)


def verify_road_path():
    lua = LuaRuntime()
    lua.execute("""
        local events={}
        resourceRoot,root={},{}
        function addEvent() end
        function addEventHandler(name,element,fn)
            events[name]=events[name] or {}
            table.insert(events[name],fn)
        end
        function triggerEvent(name,ped,done) finished=done; completions=completions+1 end
        function complete(ped)
            source=ped
            local task=ped.task
            for _,listener in ipairs(events["npc_hlc:onNPCTaskDone"]) do listener(task) end
        end
        function getPedOccupiedVehicle(ped) return ped.car end
        function getVehicleOccupant(car) return car.driver end
        function getVehicleType() return "Automobile" end
        function getElementInterior() return 0 end
        function getElementPosition() return 5,-2,2 end
        testTime=0
        function getTickCount() return testTime end
        function getElementSyncer(e) return e.driver end
        function setTimer(fn) tickProgress=fn;return {} end
        function setElementData() end
        function removeElementData() end
        local hlc={}
        function hlc:setNPCDriveSpeed(p,s) p.speed=s; return true end
        function hlc:setNPCTask(p,t) p.task=t;return true end
        function hlc:clearNPCTasks(p) p.task=nil end
        exports={npc_hlc=hlc};completions=0
    """)
    load(lua, TRAFFIC / "traffic_actors.lua")
    lua.execute("""
        TrafficActors.start()
        local p={car={}}
        p.car.driver=p
        assert(not TrafficActors.driveMissionPath(p,{},25))
        local a,b={0,0,4,5,6,1,0,0,0},{1,0,7,8,9,0,1,0,0}
        assert(TrafficActors.driveMissionPath(p,{a,b},25))
        assert(p.task[3]==25 and p.task[1]=="driveTrafficPhysics" and #p.task[5]==2)
        complete(p); assert(p.task[5][1]==b and completions==0)
        complete(p); assert(finished and completions==1)
        assert(TrafficActors.driveMissionPath(p,{a},5))
        TrafficActors.endMissionPath(p);assert(not p.task and completions==1)
        assert(TrafficActors.driveMissionPath(p,{a,b},20))
        p.car.driver=nil;complete(p);assert(finished==false and completions==2)
    """)
    lua.execute("""
        function getServerConfigSetting() return "100" end
        function setElementData() end
        function setTimer() return {} end
        function isElement(e) return type(e)=="table" end
        function getElementMatrix() return {{0,-1,0},{1,0,0},{0,0,1},{5,-2,2}} end
        TrafficVisibility={roadRange=150}
        TrafficRoadPopulation={resolveMode=function() return "pc" end}
        PedAI={brain=function(ped) return ped.brain end}
    """)
    load(lua, TRAFFIC / "traffic_graph.lua")
    load(lua, TRAFFIC / "traffic_road.lua")
    lua.execute("""
        local road={nodes={},links={},population={},roadTurnClosures={}}
        for i=0,4 do
            local node={id=i,x=math.min(i,2)*40,y=math.max(0,i-2)*40,z=1,scene="outdoor",kind="vehicle",flags=0,rawWidth=0,
                        firstLink=#road.links,linkCount=0}
            road.nodes[i+1]=node
            for _,to in ipairs({i-1,i+1}) do
                if to>=0 and to<=4 then
                    road.links[#road.links+1]={id=#road.links,from=i,to=to,lanes=1,leftLanes=1,rightLanes=1}
                    node.linkCount=node.linkCount+1
                end
            end
        end
        TrafficRoad.start(road,function() return 1 end)
        local x,y,z=getMissionTrafficRoad(6,0,1)
        assert(x==6 and math.abs(y)==2.5 and z==1)
        assert(not getMissionTrafficRoad(500,200,1))
        sourceResource={}
        local p={car={},brain={scriptOwner=sourceResource}}
        p.car.driver=p
        assert(driveMissionTrafficTo(p,82.5,78,1,23))
        local sawCorner=false
        for i,segment in ipairs(p.task[5]) do
            local after=p.task[5][i+1]
            if after and segment[6]==1 and after[7]==1 then
                assert(math.abs(segment[3]-80)<5 and math.abs(segment[4])<5)
                sawCorner=true
            end
        end
        assert(sawCorner)
        local count=0
        repeat
            count=count+1; assert(count<=6 and p.task[3]==23)
            complete(p)
        until completions==3
        assert(count>=3 and finished)
        assert(cruiseMissionTraffic(p,20) and p.task[3]==20)
        for i=1,24 do if completions<4 then complete(p) end end
        assert(finished and completions==4)
        assert(driveMissionTrafficTo(p,100,0,1,23) and p.task.mission)
        tickProgress();testTime=46000;tickProgress()
        assert(not finished and completions==5 and not p.task)
        p.brain.scriptOwner={}
        assert(not driveMissionTrafficTo(p,50,0,1,23) and not cruiseMissionTraffic(p,25))
    """)


if __name__ == "__main__":
    verify_encounters()
    verify_road_path()
    print("Vigilante dispatch, payouts, progression, cleanup and mission road routing passed.")
