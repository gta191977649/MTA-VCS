"""Exercise the Paramedic and Air Rescue state machines with Lua 5.1."""

import json
from pathlib import Path

from lupa.lua51 import LuaRuntime


MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"


def check_client_rig():
    lua = LuaRuntime()
    lua.execute("""
        events, root, resourceRoot, allocations, frees = {}, {}, {}, 0, 0
        function getResourceFromName() return {} end
        function getResourceState() return "running" end
        function addEventHandler(event,root,fn) events[event]=fn end
        function fire(event,element,...) source=element events[event](...) end
        function isElement(e) return type(e)=="table" and not e.destroyed end
        function destroyElement(e) assert(isElement(e)) e.destroyed=true end
        function getElementType(e) return e.type end
        function isElementStreamedIn(e) return e.stream end
        function getElementData(e,key) return e[key] end
        function setElementData(e,key,value) e[key]=value end
        function engineRequestModel(kind,parent) allocations=allocations+1 return 25000 end
        function engineImportTXD() return true end
        function engineLoadTXD() return {} end
        function engineLoadDFF() return {} end
        function engineReplaceModel() return true end
        function engineSetModelLODDistance() end
        function engineRestoreModel() end
        function engineFreeModel(m) freed=m frees=frees+1 end
        function getElementPosition() return 0,0,0 end
        function createObject(model,x,y,z) assert(model==25000 and z==0) if failCreate then return false end return {} end
        function getElementInterior() return 1 end
        function getElementDimension() return 2 end
        function setElementInterior(e,i) assert(i==1) end
        function setElementDimension(e,d) assert(d==2) end
        function setElementCollisionsEnabled(e,b) assert(not b) end
        function setElementDoubleSided(e,b) assert(b) end
        function attachElements(e,p) if failAttach then return false end p.visual=e;e.parent=p;return true end
        function getElementAttachedTo(e) return e.parent end
        function detachElements(e) e.parent=nil end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        function setElementRotation(e,x,y,z) e.spin=z end
        function getTickCount() return now end
        exports={frontend={setRescueWinchVisible=function(_,hook,b) hook.cable=b end}}
    """)
    lua.execute((MISSION / "rescue_c.lua").read_text())
    lua.execute("""
        local key="mission:airRescueCable"
        local a,b={type="object",stream=true,[key]=true},{type="object",stream=false,[key]=true}
        fire("onClientElementStreamIn",a)
        local first=a.visual
        assert(a.cable and first["mission:rescueRigModel"]==7353)
        fire("onClientElementDataChange",a,key)
        assert(a.visual==first)
        fire("onClientElementDataChange",b,key)
        assert(not b.visual)
        b.stream=true
        fire("onClientElementStreamIn",b)
        assert(b.cable and allocations==1 and frees==0)
        fire("onClientElementStreamOut",a)
        assert(not a.cable and first.destroyed and isElement(b.visual))
        fire("onClientElementStreamIn",a)
        assert(a.visual~=first and allocations==1)
        fire("onClientElementDestroy",a)
        assert(a.visual.destroyed and not a.cable)
        local ring={type="object",stream=true,["mission:attachmentModel"]=7375}
        fire("onClientElementStreamIn",ring)
        assert(ring.visual["mission:rescueRigModel"]==7375 and not ring.cable)
        now=10000
        ring["mission:preserverFlight"]={x=2,y=3,z=8,vx=-15,vy=0,vz=1,gravity=20,waterAt=.5,age=0,side=-1}
        fire("onClientElementDataChange",ring,"mission:preserverFlight")
        for _,t in ipairs({0,16,33,49,81,113,250,500,600}) do
            now=10000+t
            fire("onClientPreRender",root)
            local dt=math.min(.5,t/1000)
            assert(not ring.visual.parent and math.abs(ring.visual.x-(2-15*dt))<.00001)
            assert(math.abs(ring.visual.z-(8+dt-10*dt*dt))<.00001 and ring.visual.spin==-300*dt)
        end
        local bucket={type="object",stream=true,[key]=7350}
        fire("onClientElementStreamIn",bucket)
        assert(bucket.cable and bucket.visual["mission:rescueRigModel"]==7350)
        fire("onClientElementStreamOut",ring)
        assert(ring.visual.destroyed and frees==1 and not b.visual.destroyed)
        ring["mission:attachmentModel"]=nil
        fire("onClientElementDataChange",ring,"mission:attachmentModel")
        assert(frees==1)
        fire("onClientElementDestroy",bucket)
        assert(bucket.visual.destroyed and frees==2)
        fire("onClientElementStreamOut",b)
        assert(frees==3 and not b.cable)
        failCreate=true
        fire("onClientElementStreamIn",a)
        failCreate=false
        assert(frees==4)
        failAttach=true
        fire("onClientElementStreamIn",a)
        failAttach=false
        assert(frees==5)
        fire("onClientElementStreamIn",b)
        fire("onClientResourceStop",resourceRoot)
        assert(allocations==6 and frees==allocations and not b.cable and b.visual.destroyed)
    """)


def check_sling():
    lua = LuaRuntime()
    lua.execute("""
        root,resourceRoot,localPlayer={},{},{}
        handlers={}
        function addEventHandler(name,element,fn) handlers[name]=fn end
        function addEvent() end
        local now=0
        function getTickCount() return now end
        function advance(dt) now=now+dt;handlers.onClientPreRender() end
        function isElement(e) return type(e)=="table" end
        function isElementStreamedIn() return true end
        function getElementType() return "object" end
        function getElementData(e,k) return e[k] end
        function getElementAttachedTo(h) return h.parent end
        function getElementPosition(v) return v.x,v.y,v.z end
        function getElementMatrix(v) return {{1,0,0},{0,1,0},{0,0,1},{v.x,v.y,v.z}} end
        function setElementAttachedOffsets(h,x,y,z) h.x,h.y,h.z=x,y,z end
        function getVehicleOccupant(v) return v.driver end
        reports=0
        function triggerServerEvent(_,_,token,hook,x,y,z)
            assert(x*x+y*y+z*z <= 6.313^2)
            assert(token=="live" and hook.parent.driver==localPlayer)
            reports=reports+1
        end
    """)
    lua.execute((MISSION / "sling_c.lua").read_text())
    lua.execute("""
        MissionRunToken="live"
        for _,dt in ipairs({10,16,35,80}) do
            local v={x=0,y=0,z=40,driver=localPlayer}
            local h={parent=v,["mission:slingOwner"]=localPlayer,["mission:airRescueCable"]=true}
            source=h;handlers.onClientElementStreamIn()
            for i=1,40 do advance(dt) end
            v.x=3
            advance(dt)
            assert(h.x < -1,"rig failed to lag a lateral move")
            local forward=false
            local before=reports
            for i=1,math.ceil(18000/dt) do
                advance(dt)
                if h.x>0.1 then forward=true end
            end
            assert(reports-before>80 and reports-before<=145)
            assert(forward and math.abs(h.x)<0.04 and math.abs(h.z+5.8125)<0.08)
            v.x=v.x+15
            advance(dt)
            assert(h.x*h.x+h.y*h.y+h.z*h.z <= 6.313^2)
            v.x,v.z=200,80
            advance(dt)
            assert(math.abs(h.x)<0.03 and h.z==-5.8125)
            v.driver={}
            before=reports
            handlers["mission:slingSnapshot"](h,2,0,-5)
            advance(16)
            assert(h.x>0 and h.x<2,"observer snapped or ignored correction")
            advance(200)
            assert(reports==before,"observer transmitted the pilot state")
            handlers.onClientElementStreamOut()
            local last=h.x
            advance(100)
            assert(h.x==last)
        end
    """)


def check_sling_sync():
    lua = LuaRuntime()
    lua.execute("""
        Mission={driverOf=function(v) return getVehicleOccupant(v,0) end}
        root,resourceRoot,owner,other,heli,hook={},{},{},{},{},{}
        now=100
        run={vehicle=heli,player=owner,dimension=11,interior=2}
        function getTickCount() return now end
        function isElement(e) return type(e)=="table" end
        function addEvent() end
        function addEventHandler(_,_,fn) receive=fn end
        function attachElements() return true end
        function setElementData(e,k,v) e[k]=v end
        function getElementData(e,k) return e[k] end
        function getElementPosition() return 10,20,30 end
        function getVehicleOccupant() return driver end
        function getElementsWithinRange(x,y,z,r,kind,interior,dimension)
            assert(interior==2 and dimension==11 and kind=="player")
            return {owner,other}
        end
        forwards=0
        function triggerClientEvent(players,kind,src,h,x,y,z)
            assert(#players==1 and players[1]==other and h==hook)
            forwards=forwards+1
        end
        function Mission.forParticipant(p,token,id)
            if p==owner and token=="current" and id=="airrescue" then return run end
        end
    """)
    lua.execute((MISSION / "sling.lua").read_text())
    lua.execute("""
        assert(Mission.attachSling(run,hook))
        source,client,driver=resourceRoot,owner,owner
        hook["mission:airRescueCable"]=true
        local m={{1,0,0},{0,1,0},{0,0,1},{10,20,30}}
        assert(not Mission.slingPosition(run,m))
        receive("expired",hook,0,0,-5)
        receive("current",{},0,0,-5)
        receive("current",hook,0/0,0,-5)
        receive("current",hook,6,6,-5)
        receive("current",hook,"0",0,-5)
        client=other;receive("current",hook,0,0,-5)
        client=owner;driver=other;receive("current",hook,0,0,-5)
        assert(forwards==0 and not run.sling.received)
        driver=owner;receive("current",hook,2,1,-5)
        assert(forwards==1)
        receive("current",hook,1,1,-5)
        assert(forwards==1)
        local x,y,z=Mission.slingPosition(run,m,0,1,-1)
        assert(x==12 and y==22 and z==24)
        now=1000
        assert(not Mission.slingPosition(run,m))
        receive("current",hook,0,0,-6)
        assert(forwards==2 and Mission.slingPosition(run,m))
    """)


def main():
    lua = LuaRuntime()
    lua.execute("""
        function getResourceFromName() return {} end
        function getResourceState() return "running" end
        math.randomseed(27)
        local function noop() end
        local function zero() return 0 end
        tickTime=100
        function getTickCount() return tickTime end
        function getTime() return 12,0 end
        function isElement(e) return type(e)=="table" and not e.destroyed end
        function destroyElement(e) e.destroyed=true end
        function getElementPosition(e) assert(isElement(e),"position requested on a destroyed element") return e.x,e.y,e.z end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        function getElementVelocity(e) return e.vx or 0,0,0 end
        function getElementMatrix(e) return {{1,0,0},{0,1,0},{0,0,1},{e.x,e.y,e.z}} end
        function getDistanceBetweenPoints2D(x,y,a,b) return math.sqrt((x-a)^2+(y-b)^2) end
        function getElementHealth(e) return e.health or 1000 end
        function setElementHealth(e,value) e.health=value end
        function isPedDead(e) return e.dead end
        function isVehicleBlown(e) return e.blown end
        function getPedOccupiedVehicle(e) return e.vehicle end
        function getPedOccupiedVehicleSeat(e) return e.seat end
        function getVehicleOccupant(e,seat) return e[seat] end
        function getVehicleMaxPassengers(e) return 3 end
        function sit(p,car,seat)
            if p.vehicle then p.vehicle[p.seat]=nil end
            p.vehicle,p.seat=car,seat
            if car then car[seat]=p end
        end
        function createObject(model,x,y,z) return {model=model,x=x,y=y,z=z} end
        function attachElements(e,parent) e.parent=parent return true end
        function detachElements(e) e.parent=nil end
        setElementData,setElementRotation,setElementInterior,setElementDimension=noop,noop,noop,noop
        setElementFrozen,setPedAnimation,setElementCollisionsEnabled=noop,noop,noop
        function setElementAlpha(e,a) e.alpha=a end
        getElementDimension,getElementInterior=zero,zero
        local function spawn(_,skin,x,y,z) return {model=skin,x=x,y=y,z=z} end
        exports={npchlc_traffic={},wanted={},frontend={showTextBox=noop}}
        local t=exports.npchlc_traffic
        t.createTrafficScriptPed=spawn
        function t:getTrafficPopulationAt() return {originalModelId=19} end
        function t:findTrafficPedestrianAnchor(x,y,z) return TrafficGraph.pedestrianAnchor(pathGraph,x,y,z) end
        function t:getTrafficNodePosition(i) local p=pathGraph.nodes[i+1] return p.x,p.y,p.z end
        function t:assignTrafficPedObjective(p,kind,target,seat)
            p.lastOrder,p.target,p.targetSeat=kind,target,seat
            p.calls=(p.calls or 0)+1
            return true
        end
        function t:isMissionPedSeated(p,car) return p.vehicle==car and not p.entering end
        function exports.wanted:getPlayerCrimeMultiplier(p) return p.multiplier or 1 end
        function exports.wanted:setPlayerCrimeMultiplier(p,v) p.multiplier=v end
        function exports.wanted:getPlayerWantedCap(p) return p.cap or 6 end
        function exports.wanted:setPlayerWantedCap(p,v) p.cap=v end
        defs={}
        Mission={message=noop,hud=noop,track=noop,notify=noop}
        function Mission.releaseSites(r) r.sites={} end
        function Mission.siteAvailable(r,k) return not r.sites[k] end
        function Mission.claimSite(r,k) if r.sites[k] then return false end r.sites[k]=true return true end
        function Mission.switchVehicle(r,v) r.vehicle=v return true end
        function Mission.driverOf(v) return getVehicleOccupant(v,0) end
        function Mission.register(id,def) defs[id]=def end
        function Mission.marker(r,x,y,z) return {x=x,y=y,z=z} end
        function Mission.model(car) return car.model end
        function Mission.fail(r,text) r.failure=text end
        function Mission.checkpointCue(r) r.cues=(r.cues or 0)+1 end
        function Mission.finishLevel(r,amount) r.amount,r.level=amount,r.level+1 end
        function start(id,level,location)
            location=location or {-823,1167,10}
            local v={x=location[1],y=location[2],z=location[3],model=defs[id].models[1]}
            local p={x=v.x,y=v.y,z=v.z}
            sit(p,v,0)
            local r={player=p,vehicle=v,level=level,def=defs[id]}
            r.def.start(r)
            assert(not r.failure,r.failure)
            return r
        end
        function step(r,delta)
            tickTime=tickTime+(delta or 200)
            if r.sling then r.sling.received=tickTime end
            r.def.tick(r,tickTime)
        end
    """)
    traffic = MISSION.parents[1] / "[traffic]/npchlc_traffic"
    data = json.loads((traffic / "paths/generated/vcs_traffic.json").read_text())
    lua.execute((traffic / "traffic_graph.lua").read_text())
    lua.globals().sourceGraph = lua.table_from({
        "schemaVersion": 1, "nodes": data["nodes"], "links": data["links"], "routes": [],
    }, recursive=True)
    lua.execute("pathGraph=TrafficGraph.build(sourceGraph,function() end)")
    lua.execute("function addEvent() end function addEventHandler() end")
    lua.execute((MISSION / "sling.lua").read_text())
    lua.execute("function removeElementData(e,key) e[key]=nil end")
    lua.execute((MISSION / "service_poses.lua").read_text())
    lua.execute((MISSION / "rescue_data.lua").read_text())
    lua.execute((MISSION / "rescue.lua").read_text())
    check_client_rig()
    check_sling()
    check_sling_sync()
    lua.execute("""
        assert(#RescueData.sites==60 and #RescueData.hospitals==4 and #RescueData.helipads==2)
        local r=start("paramedic",4)
        assert(#r.patients==4 and r.player.multiplier==0.5)
        local p=r.patients[1]
        setElementPosition(r.vehicle,p.ped.x,p.ped.y,p.ped.z)
        step(r)
        assert(p.state=="boarding" and p.ped.lastOrder=="enterVehicle")
        local calls=p.ped.calls
        step(r,2100)
        assert(p.ped.calls>calls,"interrupted boarding must be retried")
        r.vehicle.vx=1
        step(r)
        assert(p.state=="waiting" and p.ped.lastOrder=="clear")
        r.vehicle.vx=0
        step(r)
        sit(p.ped,r.vehicle,p.seat)
        p.ped.entering=true
        step(r)
        assert(p.state=="boarding" and r.aboard==0,"a reserved seat is not a finished passenger entry")
        p.ped.entering=false
        local deadline=r.deadline
        step(r)
        assert(p.state=="aboard" and r.aboard==1 and r.deadline>deadline)

        -- Returning to another ambulance with a patient aboard is rejected.
        local original=r.vehicle
        local spare={model=227,x=original.x,y=original.y,z=original.z}
        sit(r.player,nil)
        step(r)
        assert(r.returnBy and not r.allowReplacement)
        sit(r.player,spare,0)
        step(r)
        assert(r.returnBy)
        sit(r.player,original,0)
        step(r)
        assert(not r.returnBy)
        local h=r.hospital
        setElementPosition(original,h[1],h[2],h[3])
        step(r)
        assert(p.ped.lastOrder=="exitVehicle")
        sit(p.ped,nil)
        step(r)
        assert(p.state=="saved" and r.aboard==0 and r.saved==1)
        step(r,10200)
        assert(p.ped.destroyed and r.cues==1 and r.saved==1 and not r.failure)
        sit(r.player,nil)
        step(r)
        assert(r.allowReplacement)
        sit(r.player,spare,0)
        step(r)
        assert(r.vehicle==spare and not r.returnBy)
        r.patients[2].ped.dead=true
        step(r)
        assert(r.failure=="One of your patients has died.")
        r.def.stop(r)
        assert(r.player.multiplier==1)
        for _,hospital in ipairs(RescueData.hospitals) do
            assert(#start("paramedic",23,hospital).patients==15)
            assert(#start("paramedic",1,hospital).patients==1)
        end

        -- The helicopter is over the patient, but the swinging rig is outside pickup range.
        local swinging=start("airrescue",1)
        local patient=swinging.patients[1]
        setElementPosition(swinging.vehicle,patient.ped.x,patient.ped.y,patient.ped.z+4)
        swinging.sling.ox,swinging.sling.oz=4,-4
        step(swinging)
        assert(patient.state=="waiting")
        swinging.vehicle.x=swinging.vehicle.x-4
        step(swinging)
        assert(patient.state=="aboard")
        swinging.def.stop(swinging)
        -- All sling slots, patient separation, both hospitals and payout.
        r=start("airrescue",15)
        assert(r.player.cap==0 and #r.patients==4 and #r.recentSites==4)
        assert(r.hook.alpha==0 and r.hook.parent==r.vehicle)
        for i,v in ipairs(r.patients) do
            assert(r.recentSites[i] and v.state=="waiting")
            setElementPosition(r.vehicle,v.ped.x,v.ped.y,v.ped.z+25)
            step(r)
            assert(v.state=="waiting","high overflight collected a patient")
            setElementPosition(r.vehicle,v.ped.x,v.ped.y,v.ped.z+31*6/32)
            step(r)
            assert(v.state=="aboard" and v.slot==i and v.ped.parent==r.hook)
        end
        assert(r.aboard==4)
        h=RescueData.helipads[2]
        setElementPosition(r.vehicle,h[1],h[2],h[3]+31*6/32+1.4)
        step(r)
        assert(r.hospital==h and r.saved==4 and r.cues==4 and r.amount==6000 and r.level==16)
        step(r,5100)
        assert(#r.patients==4 and #r.recentSites==5 and r.saved==0)
        local heli=r.vehicle
        sit(r.player,nil)
        step(r)
        assert(not r.allowReplacement)
        sit(r.player,{model=189},0)
        step(r)
        assert(r.returnBy and r.vehicle==heli)
        step(r,45001)
        assert(r.failure=="You didn't return to the helicopter in time.")
        r.def.stop(r)
        assert(r.player.cap==6 and r.player.multiplier==1)
        for _,id in ipairs({"paramedic","airrescue"}) do
            local a,b=start(id,3),start(id,3)
            local first,second=a.patients[1],b.patients[1]
            assert(first.ped~=second.ped)
            local lift=id=="airrescue" and 31*6/32 or 0
            setElementPosition(a.vehicle,first.ped.x,first.ped.y,first.ped.z+lift)
            step(a)
            if id=="paramedic" then sit(first.ped,a.vehicle,first.seat) step(a) end
            assert(a.aboard==1 and b.aboard==0 and second.state=="waiting")
            if id=="airrescue" then assert(a.hook~=b.hook and first.ped.parent==a.hook) end
            a.def.stop(a)
            assert(isElement(second.ped) and not b.failure)
            b.def.stop(b)
        end
    """)
    print("Paramedic and Air Rescue Lua 5.1 regression checks passed")


if __name__ == "__main__":
    main()
