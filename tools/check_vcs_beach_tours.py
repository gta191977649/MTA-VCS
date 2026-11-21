"""Exercise Beach Patrol and Vice Sights with overlapping runs and real Lua state machines."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"
HOST = """
clock=20000
root,resourceRoot={},{}
local handlers,definitions,sites,byOwner={},{},{},{}
function addEvent() end
function addEventHandler(name,_,fn) handlers[name]=fn end
function send(player,name,...) client=player; source=resourceRoot; handlers[name](...) end
function damage(ped,attacker) source=ped; handlers.onPedDamage(attacker) end
function entity(kind,x,y,z)
    return {kind=kind,x=x or 0,y=y or 0,z=z or 0,health=1000,seats={},valid=true,data={}}
end
function isElement(e) return type(e)=="table" and e.valid end
function destroyElement(e) assert(isElement(e));e.valid=false end
function getElementPosition(e)
    if e.car then return getElementPosition(e.car) end
    if e.parent then local x,y,z=getElementPosition(e.parent);return x+(e.ox or 0),y+(e.oy or 0),z+(e.oz or 0) end
    return e.x,e.y,e.z
end
function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
function getElementVelocity(e) return e.vx or 0,0,0 end
function setElementVelocity(e,x,y,z) e.vx,e.vy,e.vz=x,y,z end
function getElementRotation() return 0,0,0 end
function getElementMatrix() return {{0,-1,0},{1,0,0},{0,0,1}} end
function isPedDead(e) return e.health<=0 end
function getElementHealth(e) return e.health end
function setElementHealth(e,hp) e.health=hp end
function getTickCount() return clock end
function isVehicleBlown(e) return e.health<=0 end
function getPedOccupiedVehicle(e) return e.car end
function getVehicleOccupant(e,seat) return e.seats[seat] end
function getVehicleMaxPassengers() return 3 end
function setElementInterior() end
function setElementDimension() end
function setElementFrozen(e,f) e.frozen=f end
function isElementInWater() return false end
function setElementData(e,k,v) e.data[k]=v end
function setElementCollisionsEnabled() end
function setElementAlpha() end
function setPedAnimation() end
function getElementType(e) return e.kind end
function attachElements(e,p,x,y,z) e.parent,e.ox,e.oy,e.oz=p,x,y,z;return true end
function getElementAttachedTo(e) return e.parent end
function detachElements(e) e.parent=nil end
function createObject(_,x,y,z) return entity("object",x,y,z) end
function warpPedIntoVehicle(p,v,seat)
    if v.seats[seat] then return false end
    if p.car then p.car.seats[p.seat]=nil end
    p.car,p.seat,v.seats[seat]=v,seat,p
    return true
end
function exit(p)
    local x,y,z=getElementPosition(p)
    p.car.seats[p.seat]=nil;p.car=nil;setElementPosition(p,x,y,z)
end
local traffic={}
function removePedFromVehicle(p) exit(p);return true end
function traffic:createTrafficScriptPed(model,x,y,z) local p=entity("ped",x,y,z);p.model=model;return p end
function traffic:isMissionPedSeated(p,car,seat) return p.car==car and p.seat==seat end
function traffic:assignTrafficPedObjective(p,job,car,a,b)
    if job=="enterVehicle" then return warpPedIntoVehicle(p,car,a) end
    if job=="exitVehicle" then exit(p) end
    if job=="walk" then setElementPosition(p,car,a,b) end
    return true
end
exports={npchlc_traffic=traffic,npc_hlc={setNPCDriveSpeed=function() end,setNPCTask=function() end,clearNPCTasks=function() end},
    marker={setMarkerTarget=function() end,setMarkerBlipVisible=function(_,m,v) m.blip=v end},
    vcs_vehicle={createVcsVehicle=function(_,id,x,y,z) return entity("vehicle",x,y,z) end}}
Mission={}
function Mission.track(r,e) return e end
function Mission.marker(r,x,y,z) local m=entity("marker",x,y,z);m.owner=r;return m end
function Mission.siteAvailable(r,k) return not sites[k] end
function Mission.claimSite(r,k) if sites[k] then return false end sites[k]=r;return true end
function Mission.releaseSite(r,k) assert(sites[k]==r);sites[k]=nil end
function Mission.claimVehicle() return true end
function Mission.showReturnVehicle(r,car) r.returnCar=car end
function Mission.clearReturnVehicle(r) r.returnCar=nil end
function Mission.forParticipant(p,token,id) local r=byOwner[p];return r and r.token==token and r.id==id and r end
function Mission.driverOf(v) return getVehicleOccupant(v,0) end
function Mission.register(id,def) definitions[id]=def end
function Mission.fail(r,why) r.failed=why end
function Mission.message(r,m) r.message=m end
function Mission.notify(r,event,token,v) assert(token==r.token);r.photo=v end
function Mission.hud(r,l,v,b,n) r.hud=n end
function Mission.finishLevel(r,amount) r.paid=r.paid+amount;r.level=r.level+1;return r.id=="beachpatrol" or r.level<=5 end
function make(id,job,level)
    local d=definitions[id]
    local r={player=entity("player"),vehicle=entity("vehicle"),id=id,level=level or 1,interior=0,dimension=0,paid=0,def=d}
    r.token=tostring(r);byOwner[r.player]=r
    setElementPosition(r.vehicle,10,20,30)
    if d.canStart then
        assert(not d.canStart(r.player,r.vehicle))
        setElementPosition(r.vehicle,-1236.3562,-901.2057,14.9299)
        assert(d.canStart(r.player,r.vehicle))
    end
    assert(warpPedIntoVehicle(r.player,r.vehicle,0))
    local rng=math.random
    if job then math.random=function() math.random=rng;return job end end
    d.start(r,clock);assert(not r.failed,r.failed)
    return r
end
function step(r,ms) clock=clock+(ms or 200);r.def.tick(r,clock);assert(not r.failed,r.failed) end
"""

CHECKS = """
assert(#BeachPatrolData.shore==39 and #BeachPatrolData.sea==16 and #ViceSightsData==18)
local a,b=make("beachpatrol",1,4),make("beachpatrol",1,4)
local t=next(a.beach.targets)
local q=next(b.beach.targets)
assert(t.key~=q.key and t.car~=q.car and t.marker.owner==a and q.marker.owner==b)
exit(a.player);step(a);assert(a.returnCar==a.vehicle and t.marker.blip==false and not b.returnCar)
warpPedIntoVehicle(a.player,a.vehicle,0);step(a);assert(not a.returnCar and t.marker.blip)
setElementPosition(a.vehicle,getElementPosition(t.car))
send(b.player,"mission:beachRoad",a.token,t.car,t.point[3])
send(b.player,"mission:beachRoad",b.token,t.car,t.point[3])
assert(not t.ready)
send(a.player,"mission:beachRoad",a.token,t.car,t.point[3])
assert(t.ready and not t.car.frozen)
send(b.player,"mission:beachBikeHit",a.token,t.car);assert(not t.fellAt)
send(a.player,"mission:beachBikeHit",a.token,t.car);assert(t.fellAt and not t.actor.car)
step(a);assert(isElement(t.actor));step(a,1200);assert(not isElement(t.actor))
for i=1,3 do local target=next(a.beach.targets);exit(target.actor);step(a) end
assert(a.level==5 and a.paid==0 and b.level==4 and isElement(q.actor))
local medic=make("beachpatrol",3)
setElementPosition(medic.vehicle,getElementPosition(medic.beach.helper))
step(medic);step(medic)
local patient=next(medic.beach.targets)
setElementPosition(medic.vehicle,getElementPosition(patient.actor))
step(medic);step(medic);step(medic,4100);assert(medic.level==2)
local s1,s2=make("beachpatrol",2),make("beachpatrol",2)
assert(s1.beach.boat.y~=s2.beach.boat.y)
for _,r in ipairs({s1,s2}) do warpPedIntoVehicle(r.player,r.beach.boat,0);step(r) end
local swimmer=next(s1.beach.targets)
assert(swimmer.actor.z<6 and swimmer.actor.z>5)
exit(s1.player);step(s1);assert(s1.returnCar==s1.beach.boat and not swimmer.marker.blip)
warpPedIntoVehicle(s1.player,s1.beach.boat,0);step(s1);assert(not s1.returnCar and swimmer.marker.blip)
setElementPosition(s1.beach.boat,swimmer.actor.x-20,swimmer.actor.y-1.5,5.8)
send(s2.player,"mission:throwPreserver",s1.token,1);assert(not s1.beach.throw)
send(s1.player,"mission:throwPreserver",s1.token,1)
local ring=s1.beach.throw.ring
send(s1.player,"mission:throwPreserver",s1.token,-1);assert(ring==s1.beach.throw.ring)
step(s1,700);assert(s1.level==1);step(s1,1500)
assert(s1.level==2 and not isElement(ring) and s2.level==1)
local otherSwimmer=next(s2.beach.targets)
setElementPosition(s2.beach.boat,otherSwimmer.actor.x+8,otherSwimmer.actor.y,6)
step(s2);step(s2,4100);assert(not s2.beach.throw and s2.level==1)
send(s2.player,"mission:throwPreserver",s2.token,1);step(s2,3900);assert(not s2.beach.throw and s2.level==1)
send(s2.player,"mission:throwPreserver",s2.token,-1);step(s2,3900);assert(s2.level==2 and not isElement(otherSwimmer.actor))
local tour,other=make("vicesights"),make("vicesights")
assert(tour.tour.sights[1].owner==tour and other.tour.sights[1].owner==other)
exit(tour.player);step(tour);assert(tour.returnCar==tour.vehicle and tour.tour.sights[1].blip==false)
warpPedIntoVehicle(tour.player,tour.vehicle,0);step(tour);assert(not tour.returnCar and tour.tour.sights[1].blip)
send(other.player,"mission:tourGround",tour.token,tour.vehicle,10);assert(not tour.tour.ground)
send(tour.player,"mission:tourGround",tour.token,tour.vehicle,10);assert(tour.tour.ground.z==10)
setElementPosition(tour.vehicle,unpack(ViceSightsData[1]))
tour.vehicle.vx=.25;step(tour);assert(not tour.tour.viewing)
tour.vehicle.vx=0;step(tour);assert(tour.tour.viewing)
tour.vehicle.vx=.25;step(tour,1900);assert(not tour.tour.viewing and tour.photo==false)
tour.vehicle.vx=0
for level=1,5 do
    local n=0
    while next(tour.tour.sights) do
        local i=next(tour.tour.sights);n=n+1
        setElementPosition(tour.vehicle,unpack(ViceSightsData[i]))
        step(tour);step(tour,4100)
    end
    assert(n==(level<=2 and 3 or 4))
    exit(tour.player);step(tour);assert(tour.returnCar==tour.vehicle and tour.tour.base.blip==false)
    warpPedIntoVehicle(tour.player,tour.vehicle,0);step(tour);assert(not tour.returnCar and tour.tour.base.blip)
    setElementPosition(tour.vehicle,-1236.1198,-924.8318,14.8681)
    step(tour);assert(tour.level==level+1)
end
assert(tour.paid>5000 and other.level==1 and other.tour.remaining==3)
exit(other.player);step(other);clock=clock+30001;other.def.tick(other,clock)
assert(other.failed:find("too long"))
local bored=make("vicesights")
setElementPosition(bored.vehicle,0,0,100)
bored.tour.fun=4;clock=clock+2501;bored.def.tick(bored,clock)
assert(bored.failed:find("Bored"))
local damaged=make("vicesights")
damaged.vehicle.health=780
step(damaged);assert(damaged.tour.fun==70)
damaged.tour.passengers[1].health=0
damaged.def.tick(damaged,clock);assert(damaged.failed:find("passenger"))
local hurt=make("beachpatrol",3)
damage(hurt.beach.helper,b.player)
assert(not hurt.failed)
damage(hurt.beach.helper,hurt.player)
assert(hurt.failed:find("rescue crew"))
-- A full beach never leaves a half-dispatched wave or consumes its clock.
local blockedSites={}
local blocker={}
for i=1,39 do
    local key="beach/shore/"..i
    if Mission.claimSite(blocker,key) then blockedSites[#blockedSites+1]=key end
end
for i=1,2 do Mission.releaseSite(blocker,blockedSites[i]) end
local waiting=make("beachpatrol",1,4)
assert(waiting.beach.nextWave and not waiting.deadline and not next(waiting.beach.targets))
for i=1,2 do assert(Mission.siteAvailable(waiting,blockedSites[i])) end
for i=3,#blockedSites do Mission.releaseSite(blocker,blockedSites[i]) end
step(waiting,2001);assert(waiting.deadline and not waiting.beach.nextWave)
local depots={}
for i=0,31 do
    local key="beach/depot/swimmers/"..i
    if Mission.claimSite(blocker,key) then depots[#depots+1]=key end
end
local launched=make("beachpatrol",2)
assert(launched.beach.awaitDepot and not launched.deadline)
Mission.releaseSite(blocker,depots[1])
step(launched,2001);assert(launched.beach.boat and not launched.beach.awaitDepot)
"""


def verify_cleanup():
    """Use the production mission lifecycle, including its scoped actor and site registries."""
    lua=LuaRuntime()
    lua.execute(HOST)
    lua.execute("""
        all={}
        local create=entity
        function entity(...) local e=create(...);all[e]=true;return e end
        function addCommandHandler() end
        function isControlEnabled() return true end
        function outputDebugString(m) error(m) end
        function setTimer(cb) update=cb end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getElementData(e,k) return e.data[k] end
        function removeElementData(e,k) e.data[k]=nil end
        function getPedOccupiedVehicleSeat(p) return p.seat end
        function triggerClientEvent(p,event,_,...)
            if event=="mission:start" then p.token=select(2,...) end
            if event=="mission:end" then p.ended=true end
        end
        function exports.marker:createMarker(x,y,z)
            if failMarker then return false end
            return entity("marker",x,y,z)
        end
        function createBlipAttachedTo(car)
            local blip=entity("blip");attachElements(blip,car);return blip
        end
        function destroyElement(e)
            if e.car then exit(e) end
            for _,p in pairs(e.seats) do exit(p) end
            e.valid=false
            fire("onElementDestroy",e)
        end
        local handlers={}
        function addEventHandler(name,_,handler) handlers[name]=handler end
        function fire(name,e,...) source=e;handlers[name](...) end
    """)
    for name in ("main","beach_data","beach","vicesights_data","vicesights"):
        lua.execute((MISSION/(name+".lua")).read_text(encoding="utf-8-sig"))
    lua.execute("""
        function getElementModel(e) return e.model end
        function Mission.profile(p) return not p.noProfile and {} end
        function setup(id,job,partial)
            local p=entity("player");local car=entity("vehicle")
            p.persistent,car.persistent=true,true
            if id=="vicesights" then
                car.data["vcs_vehicle:originalModel"]=213;setElementPosition(car,-1236,-901,14)
            else
                car.model=424;setElementPosition(car,700,-200,12)
            end
            fire("onVehicleStartEnter",car,p,0)
            warpPedIntoVehicle(p,car,0)
            Mission.toggle(p);assert(not p.token)
            fire("onVehicleEnter",car,p,0);clock=clock+250
            if partial=="full" then
                for i=2,3 do local q=entity("player");q.persistent=true;warpPedIntoVehicle(q,car,i) end
            end
            if partial=="profile" then p.noProfile=true end
            failMarker=partial=="marker"
            if job then local rng=math.random;math.random=function() math.random=rng;return job end end
            Mission.toggle(p);failMarker=false
            local r=Mission.forParticipant(p,p.token,id)
            if partial then assert(not r) else assert(r) end
            return r,p,car
        end
        function clean(p,car)
            for e in pairs(all) do
                if not e.persistent then assert(not isElement(e),"orphan "..e.kind) end
            end
            assert(Mission.vehicleAvailable(nil,car))
            assert(isElement(car) and isElement(p))
            for _,occupant in pairs(car.seats) do assert(occupant.persistent) end
            for i=1,39 do
                assert(Mission.siteAvailable({dimension=0,interior=0},"beach/shore/"..i))
            end
        end
        local _,p,car=setup("vicesights",nil,"profile");clean(p,car)
        _,p,car=setup("vicesights",nil,"full");assert(p.ended);clean(p,car)
        _,p,car=setup("beachpatrol",1,"marker");assert(p.ended);clean(p,car)
        local r,p,car=setup("beachpatrol",3)
        local b=r.beach;setElementPosition(car,getElementPosition(b.helper))
        update();update()
        local t=next(b.targets);setElementPosition(car,getElementPosition(t.actor));update();update()
        assert(b.cpr)
        clock=clock+250;Mission.toggle(p);clock=clock+250;Mission.toggle(p)
        assert(p.ended);clean(p,car)
        local r,p,car=setup("beachpatrol",2);local b=r.beach
        fire("onVehicleStartEnter",b.boat,p,0)
        warpPedIntoVehicle(p,b.boat,0);update()
        assert(b.pickup and not b.atSea)
        fire("onVehicleEnter",b.boat,p,0);update()
        assert(not b.pickup and b.atSea)
        client=p;fire("mission:throwPreserver",resourceRoot,r.token,1)
        assert(isElement(b.throw.ring));clock=clock+901;update()
        fire("onPlayerWasted",p);assert(p.ended);clean(p,car)
        local r,p,car=setup("vicesights");exit(p);update()
        assert(isElement(r.returnBlip));r.deadline=clock-1;update()
        assert(p.ended);clean(p,car)
        local r,p,car=setup("vicesights");fire("onResourceStop",resourceRoot);clean(p,car)
    """)


def verify_client_cleanup():
    for module,title in (("beach_c","Beach Patrol"),("vicesights_c","Vice Sights")):
        lua=LuaRuntime()
        lua.execute("""
            clock=0;root={};resourceRoot={};localPlayer={};heli={};handlers={};timers={};keys={};effects={}
            function addEvent() end
            function addEventHandler(k,_,fn) assert(not handlers[k]);handlers[k]=fn end
            function removeEventHandler(k,_,fn) assert(handlers[k]==fn);handlers[k]=nil end
            function setTimer(fn) local t={};timers[t]=fn;return t end
            function isTimer(t) return timers[t]~=nil end
            function killTimer(t) timers[t]=nil end
            function bindKey(k,_,fn) assert(not keys[k]);keys[k]=fn end
            function unbindKey(k,_,fn) assert(keys[k]==fn);keys[k]=nil end
            function isElement(e) return e==heli or effects[e]==true end
            function destroyElement(e) effects[e]=nil end
            function getTickCount() return clock end
            function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
            function getVehicleOccupant() return localPlayer end
            function getPedOccupiedVehicle() return heli end
            function getElementPosition() return 0,0,0 end
            function getElementDimension() return 0 end
            function getElementInterior() return 0 end
            function setElementDimension() end
            function setElementInterior() end
            function getElementsByType() return {} end
            function processLineOfSight() return false end
            function getWaterLevel() return false end
            function createEffect() local e={};effects[e]=true;return e end
            function clean()
                assert(not next(effects) and not next(timers) and not next(keys) and not handlers.onClientPreRender)
            end
        """)
        lua.execute((MISSION/(module+".lua")).read_text(encoding="utf-8-sig"))
        lua.globals().title=title
        lua.execute("""
            clean()
            for i,event in ipairs({"mission:end","onClientPlayerWasted","onClientResourceStop","mission:start"}) do
                MissionRunToken=tostring(i)
                handlers["mission:start"](title,MissionRunToken)
                handlers["mission:start"](title,MissionRunToken)
                if title=="Vice Sights" then
                    handlers["mission:tourPhotos"](MissionRunToken,heli)
                    clock=clock+260;handlers.onClientPreRender();assert(next(effects))
                else assert(next(timers) and keys.vehicle_fire) end
                if event=="mission:end" then
                    handlers[event](false,false,"expired")
                    assert(next(effects) or next(timers))
                    handlers[event](false,false,MissionRunToken)
                else handlers[event]("Other mission","new") end
                clean()
                if handlers["mission:tourPhotos"] then handlers["mission:tourPhotos"](MissionRunToken,heli) end
                clean()
            end
        """)


def main():
    lua=LuaRuntime()
    lua.execute(HOST)
    for name in ("beach_data","beach","vicesights_data","vicesights"):
        path=MISSION/(name+".lua")
        lua.execute(path.read_text(encoding="utf-8-sig"),name=str(path))
    lua.execute(CHECKS)
    verify_cleanup()
    verify_client_cleanup()
    print("Verified all Beach Patrol duties, Vice Sights tours, concurrent ownership, and server/client cleanup.")


if __name__=="__main__":
    main()
