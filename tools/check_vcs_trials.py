"""Run the authored VCS trials with Lua 5.1 and verify their converted ramp assets."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"


def script(lua, name):
    lua.execute((MISSION / name).read_text(encoding="utf8"))


def check_courses():
    lua = LuaRuntime()
    lua.execute("""
        Mission,defs,events,resourceRoot,clock,locks,active={},{},{},{},1000,{},{}
        local function nop() end
        addEvent=nop
        function addEventHandler(n,host,cb) events[n]=cb end
        function getTickCount() return clock end
        function isElement(e) return type(e)=="table" and not e.gone end
        function destroyElement(e) assert(isElement(e));e.gone=true end
        function getElementPosition(e) return unpack((e.car or e).p) end
        function setElementPosition(e,...) e.p={...} end
        function getElementRotation(e) return 0,0,0 end
        function setElementDimension(e,d) e.dimension=d end
        function getElementDimension(e) return e.dimension or 0 end
        function getElementInterior(e) return e.interior or 0 end
        function setElementInterior(e,i) e.interior=i end
        function setElementHealth(e,h) e.health=h end
        function getElementHealth(e) return e.health or 1000 end
        function getElementMatrix(e) return {{},{0,0,e.pitch or 0}} end
        function getVehicleOccupants(e) return e.seats end
        function getVehicleOccupant(e,s) return e.seats[s] end
        function getPedOccupiedVehicle(e) return e.car end
        function isElementFrozen(e) return e.frozen end
        function setElementFrozen(e,v) e.frozen=v end
        setElementVelocity=nop
        setElementRotation=nop
        function isVehicleBlown(e) return e.blown end
        function createBlip(...) return {...} end
        exports={marker={setMarkerTarget=nop,setMarkerVisibleTo=function(_,m,p,v)m.visible=v end}}
        function exports.marker:setMarkerBlipVisible(m,v) m.blip=v and {} or false end
        function exports.marker:getMarkerBlip(m) return m.blip end
        function setBlipSize(b,n) b.size=n end
        exports.wanted={getPlayerWanted=function(_,p)return p.wanted end,
            setPlayerWanted=function(_,p,n)p.wanted=n end}
        function Mission.driverOf(v) return getVehicleOccupant(v,0) end
        function Mission.register(id,def) defs[id]=def end
        function Mission.courseRecord(r,i) return i=="best_air" and {wins=0} or {wins=i<r.want and 1 or 0,time=r.old} end
        function Mission.recordCourse(r,i,s) r.stats[i]=s;return true end
        function Mission.selectCourse(r,opts,fn) assert(#opts==r.want);fn(r,r.want) end
        function Mission.forParticipant(p,t,id) local r=active[p];if r and r.token==t and r.id==id then return r end end
        function Mission.claimSite(r,k) if locks[k] and locks[k]~=r then return false end;locks[k]=r;return true end
        function Mission.releaseSite(r,k) assert(locks[k]==r); locks[k]=nil end
        function Mission.marker(r,x,y,z,style,size,color,blip) return {p={x,y,z},style=style,color=color,blip=blip} end
        function Mission.track(r,e) return e end
        function Mission.countdown(r,v) r.cues[#r.cues+1]=v end
        function Mission.checkpointCue(r) r.gates=(r.gates or 0)+1 end
        function Mission.pay(r,n) r.paid=(r.paid or 0)+n end
        function Mission.finishCourse(r,i,m,amount,won) r.result={i,m,amount,won};return true end
        function Mission.fail(r,msg) r.failure=msg end
        function Mission.showReturnVehicle(r,v) r.returnBlip=v end
        function Mission.clearReturnVehicle(r) r.returnBlip=nil end
        Mission.notify=nop;Mission.message=nop;Mission.hud=nop
        coords={watersports={-140.44,1031.14,5.91},quadtrial={-445.2,1383.27,11.39},
            bmxtrial={-427.43,1551.35,11.32},sancheztrial={-566.92,1387.33,11.76},
            caddydaddy={98.07,310.27,19.36},mallbmx={384.95,1226.62,-198.45}}
        function new(id,index)
            local player,car={}, {p=coords[id],dimension=id=="mallbmx" and 3090 or 0}
            car.seats={[0]=player};player.car=car
            local r={vehicle=car,player=player,id=id,dimension=car.dimension,interior=0,want=index,
                token=tostring(player),cues={},stats={}}
            active[player]=r;assert(defs[id].canStart(player,car));return r
        end
        function tick(r,dt) clock=clock+dt;defs[r.id].tick(r,clock) end
        function start(r)
            defs[r.id].start(r);tick(r,1000);tick(r,1000);tick(r,1000)
            assert(r.phase=="racing" and table.concat(r.cues,",")=="3,2,1,GO!")
        end
        function sample(r,pose,landed,token)
            client=r.player;source=resourceRoot
            events["mission:trialSample"](token or r.token,r.id,pose,0,landed)
        end
    """)
    script(lua, "course_gates.lua")
    script(lua, "trials_data.lua")
    script(lua, "trials.lua")
    lua.execute("""
        local count={watersports=8,quadtrial=4,bmxtrial=8,sancheztrial=12,caddydaddy=1}
        for id,n in pairs(count) do
            assert(#TrialCourses[id]==n)
            for index,c in ipairs(TrialCourses[id]) do
                local r=new(id,index);start(r)
                for lap=1,3 do
                    for j=1,#c.points do
                        local i=j%#c.points+1
                        assert(r.lap==lap and r.index==i and not r.failure)
                        local final=lap==3 and i==1
                        assert((r.gate.color[1]==0)==final and (r.preview==nil)==final)
                        r.vehicle.p=c.points[i];tick(r,250)
                    end
                end
                assert(r.result[1]==index and r.result[2].lap==250*#c.points)
                assert(r.result[2].time==750*#c.points and r.result[3]==(index==n and 2600 or 100))
                assert(r.result[4] and r.gates==3*#c.points and r.stats[index].lap==250*#c.points)
                defs[id].stop(r);assert(r.vehicle.p[1]==coords[id][1])
            end
        end
        local a,b=new("watersports",1),new("watersports",1)
        start(a);defs[b.id].start(b);assert(b.phase=="waiting")
        a.vehicle.p=a.course.points[2];tick(a,250);tick(b,250);assert(b.phase=="countdown")
        local gate=a.gate
        a.player.p=a.vehicle.p;a.player.car=nil;tick(a,250)
        assert(a.returnBlip==a.vehicle and gate.gone)
        a.player.car=a.vehicle;tick(a,250);assert(not a.returnBlip and isElement(a.gate))
        local function jump(z,landed) clock=clock+200;a.vehicle.p={0,0,z};sample(a,0,landed) end
        jump(1,false);jump(10,false);jump(1,true)
        assert(a.paid==10 and a.stats.best_air.score==1000)
        jump(1,false);jump(1,false);jump(1,true);assert(a.paid==10)
        a.vehicle.p={100000,0,0};tick(a,250);assert(a.failure=="You left the course!")
        local m=new("mallbmx",1)
        assert(not defs.bmxtrial.canStart(m.player,m.vehicle))
        m.player.wanted=1;m.vehicle.health=648
        defs.mallbmx.start(m);assert(m.player.wanted==0 and #m.coronas==50 and not m.coronas[1].blip)
        tick(m,3000);assert(m.coronas[1].blip.size==1)
        m.player.wanted=3
        m.player.p=m.vehicle.p;m.player.car=nil;tick(m,200)
        assert(m.returnBlip==m.vehicle and m.coronas[1].visible==false)
        m.player.car=m.vehicle;tick(m,200);assert(not m.returnBlip and m.coronas[1].visible)
        for i=50,1,-1 do
            local p=TrialCourses.mallbmx[i];m.vehicle.p=p;tick(m,250)
            if p[4]~=0 then
                assert(m.coronas[i]);m.vehicle.pitch=p[4]==1 and 0.4 or -0.4
                sample(m,p[4],true,"different-run");assert(m.coronas[i])
                sample(m,3-p[4],true);assert(m.coronas[i]);clock=clock+100
                sample(m,p[4],true)
                assert(not m.coronas[i])
                clock=clock+250
            end
        end
        assert(m.collected==50 and m.result[4] and m.result[3]==500 and m.vehicle.health==1000 and m.player.wanted==0)
        defs.mallbmx.stop(m);assert(m.vehicle.health==648)
        m.vehicle.health=420;defs.mallbmx.stop(m);assert(m.vehicle.health==420)
        local f=new("bmxtrial",1)
        start(f);f.player.p=f.vehicle.p;f.player.car=nil;tick(f,200);tick(f,30000)
        assert(f.failure=="You didn't return to your vehicle in time." and not f.result)
        local c=new("caddydaddy",1);start(c);c.vehicle.blown=true;tick(c,200);assert(c.failure and not c.result)
        local stop=new("sancheztrial",1);defs.sancheztrial.start(stop)
        assert(stop.vehicle.frozen);defs.sancheztrial.stop(stop)
        assert(not stop.vehicle.frozen and stop.vehicle.p[1]==coords.sancheztrial[1] and not stop.result)
        local old=new("quadtrial",1);old.old=1;start(old)
        while not old.result do old.vehicle.p=old.course.points[old.index];tick(old,200) end
        assert(not old.result[4] and old.result[3]==0)
    """)


def check_client():
    lua = LuaRuntime()
    lua.execute("""
        local function nop() end
        resourceRoot,events,objects,freed,tick={},{},{},0,0
        MissionRunToken="a";addEvent=nop
        function addEventHandler(n,h,f) events[n]=events[n] or {};table.insert(events[n],f) end
        function fire(n,...) for _,f in ipairs(events[n]) do f(...) end end
        function isElement(e) return type(e)=="table" and not e.gone end
        function destroyElement(e) e.gone=true end
        function engineRequestModel() return 1000 end
        function engineLoadDFF() return {} end
        function engineLoadTXD() return {} end
        function engineLoadCOL() if not breakCol then return {} end end
        engineReplaceModel=function() return true end;engineImportTXD=engineReplaceModel;engineReplaceCOL=engineReplaceModel
        engineSetModelLODDistance=nop;engineRestoreModel=nop;engineRestoreCOL=nop
        function engineFreeModel(id) freed=freed+1 end
        function createObject(id,x,y,z) local e={z=z};table.insert(objects,e);return e end
        setElementDimension=nop;setElementInterior=nop;setElementDoubleSided=nop;setElementFrozen=nop
        function setTimer(f) timer={f=f};return timer end
        function isTimer(t) return t and not t.dead end
        function killTimer(t) t.dead=true end
        function triggerServerEvent(n,root,...) report={n,...} end
        function getTickCount() return tick end
        localPlayer={};car={};getPedOccupiedVehicle=function() return car end
        function isVehicleWheelOnGround(v,w) return flat or w=="rear_left" end
        function getElementPosition() return 0,0,airborne and 15 or 5 end
        function getGroundPosition() return 0 end
        function getWaterLevel() return 5 end
        function isVehicleOnGround() return false end
        function isElementInWater() return not airborne end
    """)
    script(lua, "trials_c.lua")
    lua.execute("""
        local rows={{"ndc_boathump",1,2,5.43,0}}
        assert(not TrialRamps.show("a",rows,0,0))
        rows={{"ndc_boatramphump",1,2,5.43,0},{"ndc_boatramphump",4,5,5.43,90}}
        assert(TrialRamps.show("a",rows,0,0));assert(#objects==2 and math.abs(objects[1].z-5.901534)<0.001)
        fire("mission:trialObserve","a","mallbmx",car);timer.f();assert(not report)
        tick=100;timer.f();assert(report[1]=="mission:trialSample" and report[4]==1)
        flat=true;tick=200;timer.f();assert(report[4]==0)
        fire("mission:end",nil,nil,"stale");assert(not timer.dead and not objects[1].gone)
        fire("mission:end",nil,nil,"a");assert(timer.dead and objects[2].gone and freed==1)
        breakCol=true;fire("mission:trialRamps","a",rows,0,0);assert(report[1]=="mission:trialRampFailure" and freed==2)
        report=nil
        fire("mission:trialObserve","a","watersports",car);timer.f();assert(not report)
        airborne=true;timer.f();assert(report[6]==false and report[5]==5)
        airborne=false;timer.f();assert(report[6]==true and report[5]==5)
        report=nil;timer.f();assert(not report)
        fire("onClientResourceStop");assert(timer.dead)
    """)
    for name in ("ndc_boatramphump", "ndc_boatrampwide", "ndc_boatrampnarrow"):
        for ext, magic in (("col", b"COL3"), ("txd", b"\x16\0\0\0"), ("dff", b"\x10\0\0\0")):
            raw = (MISSION / "assets" / f"{name}.{ext}").read_bytes()
            assert raw.startswith(magic) and len(raw) > 80, (name, ext)


if __name__ == "__main__":
    check_courses()
    check_client()
    print("33 circuits, 50 mall coronas, jump records, owner isolation, ramp assets and cleanup passed")

