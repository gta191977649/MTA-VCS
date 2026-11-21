"""Run the Fire Fighter and Fire Copter mission state machines under Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "mods/deathmatch/resources/[mission]/mission"


def check_client_effects():
    lua = LuaRuntime()
    lua.execute("""
        events,fx,root,resourceRoot,localPlayer={},{},{},{},{}
        function addEventHandler(name,host,cb) events[name]=cb end
        function event(name,e,...) source=e events[name](...) end
        function isElement(e) return type(e)=="table" and not e.gone end
        function destroyElement(e) assert(isElement(e)) e.gone=true end
        function isElementStreamedIn(e) return e.stream end
        function getElementType(e) return e.kind end
        function getElementDimension(e) return 0 end
        function getElementInterior(e) return 0 end
        function getElementPosition(e) assert(isElement(e)) return 0,0,0 end
        function getElementData(e,k) return e[k] end
        function setElementPosition() end
        function setElementDimension() end
        function setElementInterior() end
        function getDistanceBetweenPoints3D() return 1 end
        function createEffect(name) local e={name=name} fx[#fx+1]=e return e end
        function setTimer(cb) timer={fn=cb} return timer end
        function isTimer(t) return t and not t.stopped end
        function killTimer(t) assert(isTimer(t)) t.stopped=true end
        function getPedOccupiedVehicle() return false end
    """)
    lua.execute((MISSION / "firefighting_c.lua").read_text(encoding="utf8"))
    lua.execute("""
        MissionRunToken="first"
        local target,tag,spray="mission:fireTarget","mission:airRescueCable","mission:bucketSpraying"
        local m={kind="marker",stream=true,[target]={"first",false}}
        local n={kind="marker",stream=true,[target]={"second",false}}
        local b={kind="object",stream=true,[tag]=7350,[spray]=true}
        for _,e in ipairs({m,n,b}) do event("onClientElementStreamIn",e) end
        timer.fn()
        assert(#fx==2 and fx[1].name=="fire_med" and fx[2].name=="water_hydrant")
        m[target]=false
        event("onClientElementDataChange",m,target)
        assert(fx[1].gone and not fx[2].gone)
        b[tag]=false
        event("onClientElementDataChange",b,tag)
        assert(fx[2].gone)
        MissionRunToken="second"
        b[tag]=7350
        event("onClientElementStreamIn",b)
        timer.fn()
        assert(#fx==4 and not fx[3].gone and not fx[4].gone)
        event("mission:end",resourceRoot,false,false,"first")
        assert(not fx[3].gone)
        event("mission:end",resourceRoot,false,false,"second")
        assert(fx[3].gone)
        event("onClientElementStreamOut",n)
        event("onClientElementDestroy",b)
        assert(fx[4].gone and timer.stopped)
        event("onClientElementStreamIn",b)
        timer.fn()
        event("onClientResourceStop",resourceRoot)
        assert(timer.stopped and fx[5].gone)
    """)


def main():
    lua = LuaRuntime()
    lua.globals().waterFile = (MISSION.parents[1] / "[vcs]/vcs/water.dat").read_text()
    lua.execute("""
        function getResourceFromName() return {} end
        function getResourceState() return "running" end
        math.randomseed(35)
        events,defs,runs,sites={},{},{},{}
        root,resourceRoot,t={},{},100
        function addEvent() end
        function addEventHandler(name,host,cb) events[name]=cb end
        function getTickCount() return t end
        function getTime() return 12,0 end
        function isElement(e) return type(e)=="table" and not e.gone end
        function getElementPosition(e) assert(isElement(e)) return e.x,e.y,e.z end
        function getElementMatrix(e) return {{1,0,0},{0,1,0},{0,0,1},{e.x,e.y,e.z}} end
        function getElementHealth(e) return e.health or 1000 end
        function setElementHealth(e,h) e.health=h end
        function setElementData(e,k,v) e[k]=v end
        function attachElements(e,parent) e.parent=parent return true end
        function destroyElement(e) assert(isElement(e)) e.gone=true end
        function fileOpen(path) assert(path=="water.dat") return {} end
        function fileRead() return waterFile end
        function fileGetSize() return #waterFile end
        function fileClose() end
        local function noop() end
        setElementFrozen,setElementInterior,setElementDimension=noop,noop,noop
        setVehicleEngineState,setElementSyncer,setElementVelocity=noop,noop,noop
        function removeElementData(e,k) e[k]=nil end
        function getElementInterior() return 0 end
        function getElementDimension() return 0 end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        setElementAlpha,setElementCollisionsEnabled=noop,noop
        function getDistanceBetweenPoints2D(x,y,px,py) return math.sqrt((x-px)^2+(y-py)^2) end
        function createObject(model,x,y,z) return {model=model,x=x,y=y,z=z} end
        function isVehicleBlown(e) return e.blown end
        function isPedDead(e) return e.dead end
        function killPed(e) e.dead=true end
        function isElementInWater(e) return e.wet end
        function getVehicleOccupant(e,seat) return e[seat] end
        function getPedOccupiedVehicle(e) return e.vehicle end
        function warpPedIntoVehicle(p,e,seat) e[seat]=p p.vehicle=e p.seat=seat return true end
        function removePedFromVehicle(p) p.vehicle[p.seat]=nil p.vehicle=nil end
        local traffic={}
        function traffic:getTrafficPopulationAt() return {originalModelId=55} end
        function traffic:getMissionTrafficRoad(x,y,z) return x,y,z,0 end
        function traffic:createTrafficScriptPed(skin,x,y,z) return createObject(skin,x,y,z) end
        function traffic:assignTrafficPedObjective(p,job)
            if job=="exitVehicle" then removePedFromVehicle(p) end
            p.job=job return true
        end
        exports={npchlc_traffic=traffic,vcs_vehicle={},marker={setMarkerVisibleTo=function(_,m,p,v) m.visible=v end}}
        function exports.vcs_vehicle:createVcsVehicle(...) return createObject(...) end
        Mission={driverOf=function(v) return getVehicleOccupant(v,0) end,register=function(id,d) defs[id]=d end,track=noop,message=noop,hud=noop}
        function Mission.showReturnVehicle(r,v) r.indicator=v end
        function Mission.clearReturnVehicle(r) r.indicator=nil end
        function Mission.participants(r) return {r.player} end
        function Mission.fail(r,text) r.error=text r.active=false end
        function Mission.claimSite(r,k)
            if sites[k] then return false end
            sites[k]=r return true
        end
        function Mission.releaseSites(r) for k,v in pairs(sites) do if v==r then sites[k]=nil end end end
        function Mission.model(v) return v.model end
        function Mission.switchVehicle(r,v) r.vehicle=v return true end
        function Mission.active(r) return r.active end
        function Mission.marker(r,x,y,z) return createObject(0,x,y,z) end
        function Mission.finishLevel(r,amount)
            r.pay=(r.pay or 0)+amount
            if r.air and r.level==5 then r.active=false end
            r.level=r.level+1
        end
        function Mission.forParticipant(p,token,id)
            local r=runs[p]
            if r and r.active and r.token==token and r.id==id then return r end
        end
        function start(id,level)
            local d=defs[id]
            local v=createObject(d.models[1],-783.38,923.28,11.09)
            local p=createObject(1,v.x,v.y,v.z)
            warpPedIntoVehicle(p,v,0)
            local r={token=tostring(p),id=id,vehicle=v,player=p,level=level or 1,
                     dimension=0,interior=0,active=true}
            runs[p]=r d.start(r,t)
            assert(not r.error,r.error)
            return r
        end
        function tick(r,ms) t=t+(ms or 200) if r.sling then r.sling.received=t end defs[r.id].tick(r,t) end
        function input(r,pressed,other,deep)
            source,client=resourceRoot,other and other.player or r.player
            events["mission:fireControls"](r.token,r.id,pressed,0,1,0,deep)
        end
        function pos(v,x,y,z) v.x,v.y,v.z=x,y,z end
    """)
    lua.execute((MISSION.parents[1] / "[vcs]/vcs/water_s.lua").read_text())
    lua.execute("""
        events["onResourceStart"]()
        exports.vcs={getVcsWaterQuadLevel=function(_,x,y) return getVcsWaterQuadLevel(x,y) end}
        assert(getVcsWaterQuadLevel(1048,-437)==6)
        assert(not getVcsWaterQuadLevel(-783.38,923.28))
    """)
    for script in ("sling.lua", "firefighting_data.lua", "firefighting.lua"):
        lua.execute((MISSION / script).read_text())
    check_client_effects()
    lua.execute("""
        local a,b=start("firefighter"),start("firefighter")
        assert(a.fires[1].entity~=b.fires[1].entity)
        local f=a.fires[1]
        pos(a.player,f.x,f.y-12,f.z)
        source,client=resourceRoot,b.player
        events["mission:fireRoadReady"](a.token,f.entity,f.z+1.5)
        assert(not f.grounded)
        client=a.player
        events["mission:fireRoadReady"](a.token,f.entity,f.z+100)
        assert(not f.grounded)
        events["mission:fireRoadReady"](a.token,f.entity,f.z+1.5)
        assert(f.grounded and math.abs(f.entity.z-f.z-2.35)<0.0001)
        pos(a.vehicle,f.x,f.y-12,f.z)
        input(a,true,b)
        tick(a)
        assert(not f.done and not a.sprayUntil and b.level==1)
        input(a,true)
        tick(a)
        assert(a.level==2 and a.pay==20 and f.done and not b.fires[1].done)
        tick(a,5100)
        f=a.fires[1]
        assert(#f.crew==1)
        pos(a.vehicle,f.x,f.y-12,f.z)
        input(a,true) tick(a)
        local victim=a.fires[2]
        assert(victim and victim.entity.job=="exitVehicle" and a.level==2)
        input(a,true) tick(a)
        assert(a.level==3 and a.pay==60 and victim.done)
        local expected={0,1,2,3,4,4,4,5,5,5,6,9,9,9,10}
        for level,n in ipairs(expected) do
            local run=start("firefighter",level)
            local occupants=0
            for _,fire in ipairs(run.fires) do occupants=occupants+#fire.crew end
            assert(occupants==n)
            Mission.releaseSites(run)
        end
        local lost=start("firefighter",2)
        local car=lost.fires[1]
        pos(lost.vehicle,car.x,car.y-12,car.z)
        input(lost,true) tick(lost)
        input(lost,false) tick(lost)
        local burned=lost.fires[2]
        assert(burned.entity.job=="ignite")
        tick(lost,22001)
        assert(lost.pay==20 and burned.entity.dead and not lost.perfect)
        local aborted=start("firefighter",2)
        local dispatch=aborted.fires[1]
        pos(aborted.vehicle,dispatch.x,dispatch.y-12,dispatch.z)
        input(aborted,true) tick(aborted)
        input(aborted,false) tick(aborted)
        assert(aborted.fires[2].entity.job=="ignite")
        defs.firefighter.stop(aborted)
        assert(aborted.fires[2].entity.job=="extinguish")
        local high=start("firefighter",15)
        assert(#high.fires==3 and #high.fires[1].crew==4 and #high.fires[3].crew==2)
        removePedFromVehicle(high.player)
        tick(high)
        assert(high.indicator==high.vehicle and high.fires[1].marker.visible==false)
        high.vehicle.blown=true
        tick(high)
        assert(not high.indicator)
        tick(high,30001)
        assert(high.error)
        local c,d=start("firecopter"),start("firecopter")
        assert(defs.firecopter.canStart(c.player,c.vehicle))
        assert(#FireCopterSites==79 and #c.fires==12)
        assert(c.bucket["mission:airRescueCable"]==7350)
        removePedFromVehicle(d.player)
        tick(d)
        assert(d.indicator==d.vehicle and d.fires[1].marker.visible==false)
        warpPedIntoVehicle(d.player,d.vehicle,0)
        tick(d)
        assert(not d.indicator and d.fires[1].marker.visible)
        local first=c.fires[1]
        pos(c.vehicle,first.x,first.y,first.z+6)
        assert(not defs.firecopter.canStart(c.player,c.vehicle))
        input(c,true,d) tick(c)
        assert(c.water==100 and not first.done and not d.fires[1].done)
        c.sling.ox=4
        pos(c.vehicle,first.x+3,first.y,first.z+6)
        input(c,true) tick(c)
        assert(not first.done,"bucket swung clear of the fire")
        pos(c.vehicle,first.x-7,first.y,first.z+6)
        input(c,true) tick(c)
        c.sling.ox=0
        assert(c.water==88 and first.done and not d.fires[1].done)
        for level,n in ipairs({12,17,19,19,12}) do
            assert(c.level==level and #c.fires==n)
            for _,fire in ipairs(c.fires) do
                if not fire.done then
                    if c.water<=6 then
                        pos(c.vehicle,-2800,0,12)
                        for i=1,5 do input(c,false,nil,true) tick(c) end
                        assert(c.water>0)
                    end
                    pos(c.vehicle,fire.x,fire.y,fire.z+7)
                    input(c,true) tick(c)
                    assert(fire.done)
                end
            end
            assert(c.returning and c.level==level and c.active)
            pos(c.vehicle,-742.272,858.7609,11.781)
            tick(c)
            assert(c.level==level+1 and c.pay>0)
            if level<5 then tick(c,5100) end
        end
        assert(not c.active and d.active and d.water==100 and not d.fires[1].done)
        defs.firecopter.stop(c)
        assert(not c.bucket["mission:bucketSpraying"] and not c.bucket["mission:airRescueCable"])
        assert(d.bucket["mission:airRescueCable"]==7350)
        d.water=60
        pos(d.vehicle,-783.38,923.28,12)
        input(d,false,nil,true) tick(d)
        assert(d.water==60,"land refill")
        pos(d.vehicle,-2800,0,12) input(d,false,nil,true) tick(d)
        assert(d.water==65)
        input(d,false,nil,true) tick(d) assert(d.water==65)
    """)
    print("Fire Fighter and Fire Copter gameplay and concurrent-run isolation checks passed")


if __name__ == "__main__":
    main()
