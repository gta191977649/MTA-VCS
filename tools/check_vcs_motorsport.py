"""Exercise the PS2 Turismo, Crash! and Rush! state machines in Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"

HOST = """
local handlers={}
root,resourceRoot={},{}
function addEvent() end
function addEventHandler(event,element,fn) handlers[event]=fn end
function emit(name,...) source=resourceRoot;return handlers[name](...) end
function obj(kind,x,y,z) return {kind=kind,x=x or 0,y=y or 0,z=z or 0,valid=true,hp=1000} end
function isElement(e) return type(e)=="table" and e.valid end
function destroyElement(e)e.valid=false end
function getTickCount() return now end
function getElementType(e)return e.kind end
function getElementPosition(e)return e.x,e.y,e.z end
function setElementPosition(e,x,y,z)e.x,e.y,e.z=x,y,z end
function getElementRotation(e)return 0,0,e.heading or 0 end
function setElementRotation(e,x,y,z)e.heading=z end
function getElementMatrix(e)return {{},{},{0,0,e.up or 1}} end
function setElementDimension()end
function getElementInterior()return 0 end
function getElementDimension()return 0 end
function isVehicleOnGround(e)return not e.air end
function isElementInWater(e)return e.water end
function getElementHealth(e)return e.hp end
function setElementHealth(e,v)e.hp=v end
function setVehicleEngineState()end
function setElementVelocity()end
function isVehicleBlown(e)return e.blown end
function isPedDead(e)return e.hp<=0 end
function setElementFrozen(e,v)e.frozen=v end
function isElementFrozen(e)return e.frozen end
function getVehicleOccupant(e)return e.driver end
function warpPedIntoVehicle(p,v)p.car=v;v.driver=p;return true end
function getPedOccupiedVehicle(p)return p.car end
function getVehicleType(v)return v.class end
function createBlip(x,y,z)return obj("blip",x,y,z)end
function getDistanceBetweenPoints2D(x,y,a,b)return math.sqrt((x-a)^2+(y-b)^2) end
function getPlayerMoney(p)return p.cash end
function takePlayerMoney(p,n)p.cash=p.cash-n return true end
function getDistanceBetweenPoints3D(x,y,z,a,b,c)return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
exports={npc_hlc={},vcs_vehicle={},npchlc_traffic={},marker={}}
function exports.npchlc_traffic:driveMissionTrafficTo(p,x,y,z,s)p.goal={x,y,z,s};return true end
function exports.npc_hlc:setNPCDriveSpeed(p,s)p.speed=s end
function exports.npc_hlc:setNPCTask(p,t)p.task=t end
function exports.marker:setMarkerTarget(m,x,y,z)m.nextPoint={x,y,z}end
function exports.vcs_vehicle:setVcsVehiclePaint(v,a,b)assert(a==b);v.gridPaint=a end
function exports.vcs_vehicle:createVcsVehicle(id,x,y,z)local v=obj("vehicle",x,y,z);v.model=id;return v end
function exports.npchlc_traffic:createTrafficScriptPed(id,x,y,z)local p=obj("ped",x,y,z);p.model=id;return p end
Mission={};activities={};local sites={}
function Mission.driverOf(v) return getVehicleOccupant(v,0) end
function Mission.register(id,t)activities[id]=t end
function Mission.track(r,e)return e end
function Mission.marker(r,x,y,z,t,size,c,blip)local m=obj("marker",x,y,z);m.owner=r;m.size=size;return m end
function Mission.entityArrow(r,e,c,blip) assert(blip==false);local m=obj("marker");m.target=e;return m end
function Mission.selectCourse(r,opt,fn)r.select=fn;r.options=opt end
function Mission.courseRecord(r,key)return {wins=r.wins or 0} end
function Mission.recordCourse(r,key,t)r.record=t end
function Mission.claimSite(r,key)if sites[key]then return false end;sites[key]=r;return true end
function Mission.releaseSite(r,key)if sites[key]==r then sites[key]=nil end end
function Mission.switchVehicle(r,v)r.vehicle=v return true end
function Mission.vehicleAvailable(r,v)return not v.owner or v.owner==r end
function Mission.hud(r,k,v)r.hud={k,v}end
function Mission.countdown(r,n)r.countCue=n end
function Mission.checkpointCue(r)r.cues=(r.cues or 0)+1 end
function Mission.message(r,text)r.text=text end
function Mission.notify()end
function Mission.showReturnVehicle(r,v)r.returnBlip=v end
function Mission.clearReturnVehicle(r)r.returnBlip=nil end
function Mission.fail(r,s)r.fail=s end
function Mission.finishCourse(r,key,t,payout,won)assert(not r.finish);r.finish={key=key,t=t,cash=payout,won=won};r.courseFinished=true end
function Mission.forParticipant(p,token,id)return p.run and p.run.id==id and p.run.token==token and p.run end
"""

CASES = """
now=1000
local race=activities.turismo
local function signup(index)
    local p=index<=5 and obj("player",-1053.46,-795.23,10.97) or obj("player",251.51,-304.31,11.1)
    local r={id="turismo",player=p,dimension=0,interior=0}
    p.cash=0
    assert(race.canStart(p))
    race.start(r);assert(#r.options==(index<=5 and 5 or 4))
    local localIndex=index<=5 and index or index-5
    r.select(r,localIndex);assert(not r.course and p.cash==0)
    p.cash=2000;r.select(r,localIndex)
    local c=TurismoCourses[index]
    assert(r.course==c and p.cash==2000-c.fee)
    local v=obj("vehicle",unpack(c.grid))
    v.class="Boat";warpPedIntoVehicle(p,v);race.tick(r,now);assert(not r.rivals)
    v.class=c.kind==1 and "Automobile" or "Bike"
    return r
end
local function grid(r)
    race.tick(r,now);assert(#r.rivals==3 and r.vehicle.frozen)
    for i,rival in ipairs(r.rivals)do assert(rival.car.gridPaint==i-1) end
    race.tick(r,now+10);assert(r.countCue==3)
    now=now+3050;race.tick(r,now)
    for _,rival in ipairs(r.rivals) do assert(rival.marker.target==rival.ped) end
    assert(r.countCue==0 and not r.vehicle.frozen and r.gate.owner==r and r.arrow.nextPoint)
end
local total=0
for i,c in ipairs(TurismoCourses)do
    local r=signup(i);grid(r)
    if i==1 then
        local other=signup(i);grid(other);assert(other.gate~=r.gate and other.rivals[1].car~=r.rivals[1].car)
        other.rivals[2].ped.hp=0;race.tick(other,now);assert(other.fail and not r.fail)
    end
    local v=r.vehicle
    r.player.car=nil;v.driver=nil;race.tick(r,now);assert(r.returnBlip==v and not r.gate)
    warpPedIntoVehicle(r.player,v);race.tick(r,now);assert(not r.returnBlip and r.gate)
    for lap=1,c.laps do
        for n,gate in ipairs(c.checkpoints) do
            local s=r.rivals[1]
            assert(s.ped.goal or s.ped.task)
            -- The opponents use separately authored targets for each race leg.
            if i==2 and s.lap<=c.laps then
                local target=c.checkpoints[s.index];setElementPosition(s.car,target[4],target[5],target[6])
            end
            now=now+1200;setElementPosition(v,gate[1],gate[2],gate[3]);race.tick(r,now);total=total+1
            assert(not r.fail,r.fail)
        end
    end
    assert(r.finish and r.finish.t.time>1000 and r.finish.t.lap<=r.finish.t.time)
    assert(r.cues==#c.checkpoints*c.laps)
    if i==2 then assert(r.finish.t.position==2 and r.finish.cash==0)
    else assert(r.finish.t.position==1 and r.finish.cash==c.prize) end
end
for id,coord in pairs({crash={-89,916,11},rush={-949,-1459,12}}) do
    for wins=0,1 do
        local def=activities[id];local p,v=obj("player"),obj("vehicle",unpack(coord))
        local r={id=id,player=p,token=88,vehicle=v,wins=wins,dimension=0,interior=0}
        p.run=r;client=p;warpPedIntoVehicle(p,v)
        assert(def.canStart(p,v));def.start(r,now);assert(r.deadline==now+180000 and v.hp==1800)
        local other=obj("vehicle",unpack(coord))
        emit("mission:crashContact",87,id,v,other);assert(not next(r.targets))
        for j=1,7 do
            local target=obj("vehicle",unpack(coord));target.class="Automobile"
            emit("mission:crashContact",88,id,v,target);assert(r.targets[target])
            target.hp=200;now=now+5100;def.tick(r,now);assert(r.score==300*j)
        end
        def.expire(r,r.deadline);assert(r.finish.won and r.finish.cash==(wins==0 and 1000 or 250))
        def.stop(r)
    end
end
local p,v=obj("player"),obj("vehicle",-89,916,11)
local r={id="crash",token=17,player=p,vehicle=v,dimension=0,interior=0}
local crash=activities.crash;client=p;p.run=r;warpPedIntoVehicle(p,v);crash.start(r,now)
local function stunt(expected,act)
    local target=obj("vehicle",-89,916,11)
    target.class="Automobile";target.driver=obj("ped")
    emit("mission:crashContact",17,"crash",v,target)
    local old=r.score;act(target);now=now+5100;crash.tick(r,now);assert(r.score-old==expected)
end
stunt(50,function(t)t.class="Bike";t.driver=nil end)
stunt(150,function(t)t.up=-1 end)
stunt(10,function(t)t.heading=90 end)
stunt(25,function(t)t.z=t.z+2;t.air=true end)
stunt(250,function(t)t.water=true end)
stunt(300,function(t)t.blown=true end)
local far=obj("vehicle",450,1700,10)
emit("mission:crashContact",17,"crash",v,far);assert(not r.targets[far])
crash.expire(r,r.deadline);assert(r.fail:find("destruction"));crash.stop(r);assert(r.record.score==785)
v.hp=1000;p.car=v;v.driver=p
r={id="crash",token=19,player=p,vehicle=v,dimension=0,interior=0};p.run=r;crash.start(r,now)
v.driver=nil;p.car=nil;crash.tick(r,now);assert(r.returnBlip==v)
crash.tick(r,now+30000);assert(r.fail:find("return"));crash.stop(r)
-- Cancellation removes only this run's bonus, preserves damage, and cannot
-- repair the car across reentry or make an already burning car healthier.
for _,case in ipairs({{800,1700,700},{700,1800,700},{700,253,251},{700,195,195},{251,1800,251}})do
    local hp,after,expected=unpack(case);v.hp=hp;v.driver=p;p.car=v
    local r={id="crash",player=p,vehicle=v,dimension=0,interior=0}
    crash.start(r,now);v.hp=after;crash.stop(r);assert(v.hp==expected)
end
v.hp=248;assert(not crash.canStart(p,v))
return total
"""

if __name__ == "__main__":
    lua=LuaRuntime()
    lua.execute(HOST)
    for name in ("course_gates.lua","motorsport_data.lua","motorsport.lua"):
        lua.execute((MISSION/name).read_text(encoding="utf-8-sig"),name=name)
    count=lua.execute(CASES)
    print(f"Nine Turismo courses, {count} checkpoint crossings, both Crash/Rush payouts and run isolation passed.")
