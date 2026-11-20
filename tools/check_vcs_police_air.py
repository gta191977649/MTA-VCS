"""Exercise pursuit timing, paired guns, LOS and volley ownership in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"

def main():
    lua = LuaRuntime()
    for name in ("police.lua", "police_flight.lua", "police_response_s.lua", "police_control_c.lua"):
        lua.execute("assert(loadstring(...))", (RESOURCE/name).read_text())
    lua.execute("""
        handlers, events, resourceRoot = {}, {}, {}
        function addEvent() end
        function addEventHandler(name, root, fn) handlers[name] = fn end
        function getElementPosition(e) return e.x or 0, e.y or 0, e.z or 0 end
        function getElementVelocity(e) return 0,0,0 end
        function getElementMatrix(e)
            return {{1,0,0},{0,1,0},{0,0,1},{getElementPosition(e)}}
        end
        function getElementsWithinRange() return {player} end
        function triggerClientEvent(to,event,root,...) events[event] = {...} end
        function isElement(e) return type(e) == "table" end
        function getElementInterior(e) return 0 end
        function getElementDimension(e) return e.world or 0 end
        function isPedDead(e) return false end
        function getVehicleOccupant(e,seat) return pilot end
        function isVehicleDamageProof(e) return e.protected end
        function getVehicleType(e) return e.kind end
        function getPlayerWantedLevel(e) return e.level end
        function getPedOccupiedVehicle(e) return e.vehicle end
        function getElementHealth(e) return e.hp end
        function setElementHealth(e,hp) e.hp=hp end
        function getPedArmor(e) return e.armor end
        function setPedArmor(e,val) e.armor=val end
        function getTickCount() return now end
        player = {level=6, armor=10, hp=100}
        TrafficCustody = {isActive=function(p) return p.held==true end}
        TrafficWanted = {getPoliceResponse=function(level)
            return {policeHelicopters=level>=3 and 1 or 0,swat=false}
        end}
        heli, pilot, boat = {z=20}, {}, {}
        air = {player=player,heli=heli,pilot=pilot,remaining=4,dimension=0}
        marine = {player=player,boat=boat,pilot=pilot,burst=20}
        TrafficPolice = {assignment=function(client,gun)
            if client==player then return gun==heli and air or gun==boat and marine end
        end}
    """)
    lua.execute((RESOURCE/"police_flight.lua").read_text())
    lua.execute((RESOURCE/"police_response_s.lua").read_text())
    lua.execute("""
        for i,v in ipairs({10000,5000,3500,2000}) do
            assert(TrafficPoliceFlight.acquisitionDelay(i+2,false)==v)
            assert(TrafficPoliceFlight.acquisitionDelay(i+2,true)==5000)
        end
        local function update(t)
            now=t
            TrafficPoliceResponse.air(air,t)
            if air.surveyId then
                client=player
                handlers["traffic:policeSurveyResult"](heli,air.surveyId,true,false)
            end
        end
        for t=0,2000,100 do update(t) end
        assert(not events["traffic:policeVolley"])
        update(2100)
        local shots=assert(events["traffic:policeVolley"])
        assert(shots[1]==heli and #shots[4]==1)
        client={}
        handlers["traffic:policeImpacts"](heli,shots[3],1)
        assert(player.hp==100)
        client=player
        handlers["traffic:policeImpacts"](heli,shots[3],1)
        assert(player.hp==90 and player.armor==0)
        handlers["traffic:policeImpacts"](heli,shots[3],1)
        assert(player.hp==90)
        update(2600)
        shots=events["traffic:policeVolley"]
        player.held=true
        handlers["traffic:policeImpacts"](heli,shots[3],1)
        assert(player.hp==90 and player.level==6)
        update(2700)
        assert(not air.acquired and not air.shots and events["traffic:policeVolley"]==shots)
        player.held=false
        local _,_,signed=TrafficPoliceFlight.boatIntent(2,0,0,0,1,0,0,0,0,math.pi,0)
        assert(signed)
        player.vehicle={kind="Boat",y=25,hp=1000}
        now=3000
        TrafficPoliceResponse.boat(marine,now)
        shots=events["traffic:policeVolley"]
        assert(shots[1]==boat and #shots[4]==2 and marine.burst==19)
        handlers["traffic:policeImpacts"](boat,shots[3],2)
        assert(player.vehicle.hp==970)
        player.held=true
        TrafficPoliceResponse.boat(marine,3450)
        assert(marine.burst==19 and not marine.shots and events["traffic:policeVolley"]==shots)
        player.held=false
        TrafficPoliceResponse.boat(marine,3400)
        assert(marine.burst==19)
        for i=1,19 do TrafficPoliceResponse.boat(marine,3000+i*401) end
        assert(marine.burst==20 and marine.delay==1800)
        local last=marine.lastShot
        TrafficPoliceResponse.boat(marine,last+1800)
        assert(marine.burst==20)
        TrafficPoliceResponse.boat(marine,last+1801)
        assert(marine.burst==19)
        player.vehicle=nil
        TrafficPoliceResponse.boat(marine,last+2402)
        assert(marine.burst==19)
        player.vehicle={kind="Boat",y=25,hp=970}
        TrafficPoliceResponse.boat(marine,last+3402)
        assert(marine.burst==19)
        TrafficPoliceResponse.boat(marine,last+3403)
        assert(marine.burst==18)
        player.vehicle.kind="Helicopter"
        update(last+2000)
        assert(not air.track and not air.lockAt)
        player.vehicle=nil
        player.level=0
        update(last+2100)
        assert(not air.shots)
        player.level=4
        local landed,peds={},{}
        local count=0
        TrafficAmbient={getPedestrianModel=function(id) assert(id==9); return 285 end,
            adoptDriver=function() return true end}
        exports={npc_hlc={enableHLCForNPC=function() return true end}}
        PedAI={attach=function(ped) assert(not ped.equipped); ped.equipped=true end}
        TrafficGroundPolice={enroll=function(ped,target)
            assert(target==player); landed[ped]=true
        end}
        TrafficModelBindings={tag=function() end}
        TrafficVisibility={track=function() end}
        TrafficWanted.getPoliceResponse=function() return {policeHelicopters=1,swat=true} end
        function setElementDimension() end
        function setElementFrozen(ped,on) ped.frozen=on end
        function setElementCollisionsEnabled(ped,on) ped.collisions=on end
        function setTrafficPolicePed() end
        function setPedAnimation() end
        function setElementData() end
        function removeElementData() end
        function setElementVelocity(p,x,y,z) assert(x==0 and y==0 and z==0); p.stopped=true end
        function createPed(id,x,y,z)
            count=count+1; peds[count]={x=x,y=y,z=z}
            return peds[count]
        end
        function setElementPosition(ped,x,y,z) ped.x,ped.y,ped.z=x,y,z end
        math.random=function(lo,hi) return hi and lo or 1 end
        for i=1,5 do
            now=last+3000+i*100
            air.floor,air.visible,air.surveyAt=0,true,now
            TrafficPoliceResponse.air(air,now)
        end
        assert(air.remaining==0 and count==4)
        for i=1,70 do TrafficPoliceResponse.descend(now+i*100) end
        local n=0
        for ped in pairs(landed) do
            assert(ped.z==1 and ped.stopped and ped.collisions and not ped.frozen and ped.equipped)
            n=n+1
        end
        assert(n==4)
        heli.x,heli.z,air.remaining=0,21,1
        now=now+8000
        air.floor,air.surveyAt=0,now
        TrafficPoliceResponse.air(air,now)
        assert(air.remaining==0 and not air.floor and not air.surveyId)
        local moving=peds[5]
        local startX,startZ=moving.x,moving.z
        assert(moving.equipped and moving.frozen and not moving.collisions)
        heli.x=3
        TrafficPoliceResponse.descend(now+1000)
        assert(moving.x>startX+2 and moving.z>startZ-3 and moving.z<startZ-2.8)
        -- Repeated sync readback of an older pose cannot rewind time on the rope.
        moving.z=startZ
        TrafficPoliceResponse.descend(now+5000)
        assert(moving.z<startZ-14)
        -- Lose the aircraft link above ground while custody is active.
        function isElement(e) return type(e)=="table" and not e.gone end
        heli.gone,player.held=true,true
        local lastZ=moving.z
        TrafficPoliceResponse.descend(now+5100)
        assert(moving.z==lastZ and not moving.frozen and moving.collisions and moving.stopped and not landed[moving])
        heli.gone,player.held=false,false
        function destroyElement(e) e.gone=true end
        local function drop(target,craft)
            local a={heli=craft,pilot=pilot,player=target,dimension=0,remaining=1,floor=0,surveyAt=now}
            TrafficPoliceResponse.air(a,now)
            assert(a.remaining==0)
            return peds[count],a
        end
        local other={level=4}
        local first=drop(player,heli)
        local second,assignment=drop(other,{z=18})
        player.level=0
        TrafficPoliceResponse.clear(player)
        assert(first.gone and second.frozen and not second.gone)
        -- The aircraft can still exist after retirement, theft or pilot loss.
        local previousZ=second.z
        TrafficPoliceResponse.release(assignment)
        local enrolled
        TrafficGroundPolice.enroll=function(p,t) assert(t==other);enrolled=p end
        TrafficPoliceResponse.descend(now+100)
        assert(second.z==previousZ and second.stopped and second.collisions and not second.frozen and enrolled==second)
        player.level=4
        local unreported=drop(player,heli)
        player.level=0
        TrafficPoliceResponse.descend(now+200)
        assert(unreported.gone and enrolled==second)
    """)
    lua.execute("""
        root,localPlayer={},player
        function isElementStreamedIn(e) return true end
        function getElementType(e) return e==heli and "vehicle" or "ped" end
        function removeEventHandler(name,root,fn)
            assert(handlers[name]==fn)
            handlers[name]=nil
        end
        function getElementData(e) return {player,"air"} end
        function getElementsByType(k) return k=="vehicle" and {heli} or {} end
        function getElementRotation() return 359,359,0 end
        function setElementRotation(e,rx,ry,rz) nextPitch,nextRoll=rx,ry end
        function isElementSyncer() return true end
        function setVehicleRotorSpeed() end
        function setElementVelocity() end
        function processLineOfSight() return false end
        player.x,player.y,player.vehicle=0,100,nil
        heli.x,heli.y,heli.z=0,0,25
    """)
    lua.execute((RESOURCE/"police_control_c.lua").read_text())
    lua.execute("""
        assert(handlers["onClientPreRender"]==nil)
        handlers["onClientResourceStart"]()
        handlers["onClientPreRender"](20)
        assert(math.abs(nextPitch-359)<2 and math.abs(nextRoll-359)<2)
        source=heli
        handlers["onClientElementStreamOut"]()
        assert(handlers["onClientPreRender"]==nil)
        local creations=0
        function createSWATRope(x,y,z,duration)
            assert(x==4 and y==7 and z==21 and duration>6700 and duration<6800)
            creations=creations+1
            return true
        end
        source={z=16}
        function getElementData() return {heli,4,7,21} end
        handlers["onClientElementStreamIn"]()
        handlers["onClientElementDataChange"]("traffic:policeRope")
        handlers["onClientElementStreamOut"]()
        handlers["onClientElementStreamIn"]()
        assert(creations==1 and handlers["onClientPreRender"]==nil)
        source=heli
        local steeringCalls,elapsed=0,0
        function getElementData() return {player,"boat",3} end
        exports.vcs_vehicle={steerBoatTraffic=function(self,vehicle,dx,dy,tx,ty,fx,fy,look,speed,vz,ms)
            steeringCalls,elapsed=steeringCalls+1,elapsed+ms
        end}
        player.vehicle={kind="Boat",y=100}
        handlers["onClientElementStreamIn"]()
        for i=1,180 do handlers["onClientPreRender"](1000/60) end
        assert(steeringCalls==90 and math.abs(elapsed-3000)<1)
        handlers["onClientElementStreamOut"]()
        assert(handlers["onClientPreRender"]==nil)
    """)
    lua.execute("""
        players,scans,probes,now={},0,0,1000
        for i=1,1000 do players[i]={level=i<=15 and 3 or 0} end
        function getElementsByType(kind) assert(kind=="player");scans=scans+1;return players end
        function setTimer(fn) tick=fn;return true end
        function removeEventHandler() end
        function killTimer() end
        function getTickCount() return now end
        TrafficModelBindings.get=function() return 497 end
        TrafficAmbient.getPedestrianModel=function() return 280 end
        TrafficWorld={isReady=function(p) return true end}
        TrafficWanted.getPoliceResponse=function(l) return {policeHelicopters=l>=3 and 1 or 0} end
        function triggerClientEvent(p,name)
            assert(name=="traffic:policeTerrain")
            assert(not p.probed)
            p.probed=true
            probes=probes+1
        end
    """)
    lua.execute((RESOURCE/"police.lua").read_text())
    lua.execute("""
        TrafficPolice.start({policeFlight={minWantedLevel=3,originalArea=0,
            spawnAttemptMs=15000,spawnAngleStep=0.02453125,spawnRadius=250,
            spawnBounds={minX=-2400,maxX=1600,minY=-2000,maxY=2000}}})
        for i=1,100 do
            local before=probes
            now=now+100
            tick()
            assert(probes-before<=4)
        end
        assert(scans==1 and probes==15)
        TrafficPolice.stop()
    """)
    print("Police air acquisition, cooldown, damage ownership, four rappels and Predator bursts passed")

if __name__ == "__main__":
    main()
