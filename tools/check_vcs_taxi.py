"""Run the Taxi Driver state machine with deterministic dispatches and a Lua 5.1 host."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"

HOST = """
root,resourceRoot={},{}
local handlers={}
function addEvent() end
function addEventHandler(name,_,handler) handlers[name]=handler end
function emit(name,element,...) source=element; handlers[name](...) end
function triggerClientEvent() end
function entity(kind,x,y,z)
    return {kind=kind,x=x or 0,y=y or 0,z=z or 0,health=1000,valid=true,seats={}}
end
function isElement(e) return type(e)=="table" and e.valid end
function destroyElement(e) e.valid=false end
function getElementType(e) return e.kind end
function getElementPosition(e) return e.x,e.y,e.z end
function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
function getDistanceBetweenPoints2D(x,y,a,b) return math.sqrt((a-x)^2+(b-y)^2) end
function getElementDimension() return 0 end
function getElementInterior() return 0 end
function setElementDimension() end
function setElementInterior() end
function createBlipAttachedTo(e) local b=entity("blip"); b.target=e; return b end
function setVehicleTaxiLightOn(e,v) e.light=v end
function isVehicleTaxiLightOn(e) return e.light or false end
function getVehicleMaxPassengers() return 3 end
function getPedOccupiedVehicle(e) return e.car end
function getPedOccupiedVehicleSeat(e) return e.seat end
function getVehicleOccupant(c,seat) return c.seats[seat or 0] end
function getVehicleType() return "Automobile" end
function getElementVelocity() return 0,0,0 end
function setPedAnimation() end
function getElementHealth(e) return e.health end
function getTickCount() return clock end
function isVehicleBlown(e) return e.blown or false end
function isElementInWater(e) return e.water or false end
function isVehicleLocked(e) return e.locked or false end
function setVehicleLocked(e,locked) e.locked=locked end
function isPedDead(p) return p.health<=0 end
function setCameraMatrix(p,...) p.fixed=true; p.camera={...} end
function setCameraTarget(p,target) p.fixed=false; p.cameraTarget=target; p.camera=target end
function getCameraTarget(p) if not p.fixed then return p.cameraTarget or p end end
function getCameraMatrix(p) return unpack(p.camera or {}) end
function getPedWeapon(e) return e.weapon or 0 end
function getPedTotalAmmo() return 10 end
function getPedWeaponSlot() return 0 end
function setPedWeaponSlot() end
function setPedRotation(p,angle) p.heading=angle end
function isControlEnabled(p,name) return not p.disabled or not p.disabled[name] end
function toggleControl(p,name,enabled) p.disabled=p.disabled or {};p.disabled[name]=not enabled end
function giveWeapon(p,id) p.weapon=id end
function takeWeapon(p,id) assert(p.weapon==id);p.weapon=nil end
function removePedFromVehicle(p)
    if p.car then p.car.seats[p.seat]=nil; p.car,p.seat=nil,nil end
end
function enter(p,car,seat)
    removePedFromVehicle(p)
    assert(not car.seats[seat])
    p.car,p.seat,car.seats[seat]=car,seat,p
end
function getElementsWithinRange() return trafficCars end
local traffic={}
function traffic:isMissionPedSeated(p,v,seat) return p.confirmed and p.car==v and p.seat==seat end
function traffic:acquireTrafficPedInArea() return prospective end
function traffic:releaseTrafficPed(p) p.released=true end
function traffic:acquireMissionTrafficDriver(p) return p.available end
function traffic:driveMissionTrafficTo(p,x,y,z,speed)
    assert(speed==23);p.destination={x,y,z};return p.available
end
function traffic:assignTrafficPedObjective(p,order,target,y,z,pace)
    if order=="enterVehicle" then p.confirmed=not delayedBoarding;enter(p,target,y)
    elseif order=="exitVehicle" then removePedFromVehicle(p)
    elseif order=="walk" then assert(pace=="run");setElementPosition(p,target,y,z) end
    return true
end
function traffic:setPlayerWanted(p,n) p.stars=n end
function traffic:getPlayerWanted(p) return p.stars or 0 end
exports={npchlc_traffic=traffic}
Mission={}
function Mission.vehicleAvailable() return true end
function Mission.claimVehicle() return true end
function Mission.releaseVehicle() end
function Mission.switchVehicle(r,v) r.vehicle=v return true end
function Mission.notify(r,event,...) triggerClientEvent(r.player,event,resourceRoot,...) end
function Mission.forParticipant(p,token) return token==17 and p and p.run end
function Mission.lease(r,e) assert(not r.leases[e]);r.leases[e]=true end
function Mission.release(r,e) assert(r.leases[e]);r.leases[e]=nil;e.released=true end
function Mission.track(r,e) return e end
function Mission.hud(r,label,value,bar,amount) r.hud={label,value,bar,amount} end
function Mission.marker(r,x,y,z,style,size,rgba,blip)
    assert(style=="cylinder" and size==5 and blip);return entity("marker",x,y,z)
end
function Mission.entityArrow(r,e,color,blip) assert(blip);local m=entity("marker");m.target=e;return m end
function Mission.taxiFare(r,amount) r.money=r.money+amount end
function Mission.fail(r,why) r.failed=why end
function Mission.checkpointCue(r) r.cues=(r.cues or 0)+1 end
function Mission.message(r,m) r.message=m end
function Mission.model(v) return v.model end
function Mission.driverOf(v) return getVehicleOccupant(v,0) end
function Mission.register(id,def) assert(id=="taxi");taxi=def end
function run()
    clock=10000
    local r={player=entity("player"),vehicle=entity("vehicle"),dimension=0,interior=0,money=0,leases={}}
    r.player.run=r
    r.vehicle.model=226;enter(r.player,r.vehicle,0)
    trafficCars={}
    prospective=entity("ped",32,0,0)
    taxi.start(r)
    return r
end
function tick(r,ms)
    clock=clock+(ms or 0);taxi.tick(r,clock)
    assert(not r.failed,r.failed)
end
function toStop(r)
    local marker=r.taxi.goal
    assert(isElement(marker))
    setElementPosition(r.vehicle,getElementPosition(marker))
    tick(r)
end
function dispatch(r,roll,fares)
    local t=r.taxi
    t.fares=fares or 0
    if t.fares>0 then r.deadline=clock+90000 end
    tick(r);assert(t.phase=="pickup" and r.leases[prospective] and t.focus.target==prospective)
    setElementPosition(r.vehicle,getElementPosition(prospective))
    tick(r);assert(prospective.car==r.vehicle)
    local original=math.random
    math.random=function(a,b)
        if b then assert(roll>=a and roll<=b); return roll end
        return 1
    end
    tick(r);math.random=original
    assert(not r.vehicle.light and t.tip==100)
end
function ambientCar(r)
    local car=entity("vehicle",70,0,0)
    local driver=entity("ped")
    driver.available=true
    enter(driver,car,0); trafficCars={car}
    return car,driver
end
function finishFare(r)
    local t=r.taxi
    toStop(r);assert(t.phase=="dropoff")
    tick(r);assert(t.phase=="search" and r.vehicle.light and not next(r.leases))
end
"""

CHECKS = """
assert(#TaxiDestinations==34 and #taxi.models==2)
-- Initial single fare, an actual 51-point body hit and its percentage penalty.
local r=run()
delayedBoarding=true
tick(r);setElementPosition(r.vehicle,getElementPosition(prospective))
tick(r);tick(r,2500)
assert(r.taxi.phase=="pickup" and r.taxi.boardSeat==1 and prospective.car==r.vehicle)
enter(prospective,r.vehicle,3);tick(r,500)
assert(r.taxi.phase=="pickup" and r.taxi.boardSeat==1)
prospective.confirmed=true
tick(r);assert(r.taxi.phase=="drive" and r.taxi.boardSeat==3)
delayedBoarding=false
r=run()
dispatch(r,2)
local t=r.taxi
assert(t.kind=="single" and r.hud[1]=="Fares" and r.hud[3]=="Tip")
assert(r.deadline==clock+math.floor(t.firstDistance)*70+20000)
r.vehicle.health=949
tick(r,1000)
local tip=80-12*100/(0.9*t.firstDistance)
assert(math.abs(t.tip-tip)<0.001 and r.hud[4]==math.floor(tip))
local expected=math.floor(math.max(5,math.floor(t.firstDistance/30))*(1.25+3*tip/100))
finishFare(r);assert(r.money==expected and t.fares==1 and r.cues==1 and prospective.released)
-- Non-tipped fare and fifth-in-a-row payout are independent.
r=run();dispatch(r,2,4);t=r.taxi
for i=1,5 do r.vehicle.health=r.vehicle.health-51;tick(r,100) end
assert(not t.tip and not r.hud[3]);expected=math.max(5,math.floor(t.firstDistance/30))+125
finishFare(r);assert(r.money==expected and t.fares==5)
for _,roll in ipairs({6,8}) do
    r=run();dispatch(r,roll,1);t=r.taxi
    assert(t.kind==(roll==6 and "robbery" or "shopping"))
    local clockLeft=r.deadline-clock
    toStop(r);assert(t.phase=="shopExit" and not r.deadline and r.player.camera~=r.player)
    tick(r);assert(t.phase=="shopping" and not prospective.car)
    assert(not isControlEnabled(r.player,"accelerate"))
    tick(r,2000);assert(t.phase=="shopReturn" and prospective.heading)
    tick(r,500);assert(t.phase=="reboard" and r.player.camera==r.player and isControlEnabled(r.player,"accelerate"))
    assert((prospective.weapon==22)==(roll==6))
    setElementPosition(r.vehicle,getElementPosition(prospective))
    tick(r);tick(r)
    assert(t.leg==2 and t.phase=="drive" and r.deadline-clock==clockLeft and r.player.camera==r.player)
    assert((r.player.stars or 0)==(roll==6 and 2 or 0))
    expected=math.floor(math.max(5,math.floor((t.firstDistance+t.secondDistance)/30))*
        (1.25+3*(0.9*t.secondDistance+100)/(0.9*t.firstDistance)))+(roll==6 and 50 or 0)
    finishFare(r)
    assert(r.money==expected and (r.player.stars or 0)==0 and not prospective.weapon)
end
-- Complete a tail normally, or lose it by proximity, distance, collision or destruction.
for _,reason in ipairs({"delivered","close","far","collision","blown","routeFailed"}) do
    r=run();local car,driver=ambientCar(r);dispatch(r,0,1);t=r.taxi
    assert(t.kind=="tail" and t.phase=="tail" and not r.deadline and t.savedTime==90000)
    assert(car.locked and r.leases[driver] and driver.destination)
    if reason=="delivered" then
        emit("npchlc_traffic:onNPCTrafficRouteDone",driver,true);tick(r)
        assert(t.phase=="drive" and not car.locked and driver.released)
        finishFare(r);assert(r.money>0 and r.deadline-clock==90000)
    else
        if reason=="collision" then
            setElementPosition(car,r.vehicle.x+4,0,0)
            client=entity("player");emit("mission:tailCollision",resourceRoot,car,17,t.tailNumber);assert(not t.collision)
            client=r.player;emit("mission:tailCollision",resourceRoot,car,16,t.tailNumber);assert(not t.collision)
            emit("mission:tailCollision",resourceRoot,car,17,t.tailNumber-1);assert(not t.collision)
            emit("mission:tailCollision",resourceRoot,car,17,t.tailNumber);assert(t.collision)
        elseif reason=="blown" then car.blown=true
        elseif reason=="routeFailed" then emit("npchlc_traffic:onNPCTrafficRouteDone",driver,false)
        else
            local d=reason=="close" and 20 or 88
            setElementPosition(car,r.vehicle.x+d,0,0)
            tick(r);tick(r,7999);assert(t.phase=="tail")
            setElementPosition(car,r.vehicle.x+45,0,0)
            tick(r);assert(not t.alertSince)
            setElementPosition(car,r.vehicle.x+d,0,0)
            tick(r);tick(r,7999);assert(t.phase=="tail")
        end
        tick(r,1)
        assert(t.phase=="lostFare" and not car.locked and driver.released)
        assert((reason=="close" or reason=="collision")==not not r.message:find("spotted"))
        assert(r.deadline-clock==((reason=="blown" or reason=="routeFailed") and 100000 or 90000))
        tick(r);assert(t.phase=="search" and not next(r.leases) and r.money==0)
    end
end
-- Damaged vehicle replacement, time outside, passenger death and cancellation.
local cut=run()
dispatch(cut,6,1)
cut.player.disabled={accelerate=true}
local spectator=entity("player")
setCameraTarget(cut.player,spectator)
toStop(cut)
assert(cut.taxi.cutscene)
taxi.stop(cut)
assert(getCameraTarget(cut.player)==spectator and cut.player.disabled.accelerate)
assert(not cut.player.disabled.enter_exit and not next(cut.leases))
cut=run()
dispatch(cut,8,1)
toStop(cut)
setCameraMatrix(cut.player,90,91,92,100,101,102)
taxi.stop(cut)
assert(cut.player.fixed and cut.player.camera[1]==90 and not next(cut.leases))
local cabA=run()
dispatch(cabA,2)
local firstPed=cabA.taxi.ped
local cabB=run()
dispatch(cabB,2)
assert(firstPed~=cabB.taxi.ped and firstPed.car==cabA.vehicle)
finishFare(cabB)
assert(cabB.money>0 and cabA.money==0 and not firstPed.released and cabA.leases[firstPed])
finishFare(cabA)
assert(cabA.money>0)
r=run();dispatch(r,2);r.vehicle.health=500;tick(r)
assert(r.taxi.phase=="repair" and not next(r.leases))
local other=entity("vehicle");other.model=183;enter(r.player,other,0);tick(r)
assert(r.vehicle==other and r.taxi.phase=="search")
removePedFromVehicle(r.player);tick(r)
clock=r.taxi.returnBy;taxi.tick(r,clock);assert(r.failed:find("return"))
r=run();dispatch(r,2);prospective.health=0;taxi.tick(r,clock);assert(r.failed:find("dead"))
r=run();taxi.toggle(r,clock);assert(not r.failed);taxi.toggle(r,clock+1000);assert(r.failed:find("cancelled"))
"""

if __name__ == "__main__":
    lua = LuaRuntime()
    lua.execute(HOST)
    for script in ("taxi_data.lua", "taxi.lua"):
        lua.execute((MISSION / script).read_text(encoding="utf-8-sig"), name=script)
    lua.execute(CHECKS)
    print("Taxi dispatch, four fare types, six tail outcomes, timers, payouts, repairs and cancellation passed.")
