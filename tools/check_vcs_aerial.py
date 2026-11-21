"""Play every VCS SCM 37–43 variant through its production Lua state machine."""
from pathlib import Path

from lupa.lua51 import LuaRuntime

from check_vcs_beach_tours import HOST, MISSION
from import_vcs_aerial import COURSES, render


def check_directed_ground_gate():
    vm = LuaRuntime()
    vm.execute(HOST)
    vm.execute("""
        root,sourceResource,localPlayer={},{},entity("player")
        handlers,positions={},{}
        function addEventHandler(n,e,f) handlers[n]=f end
        function getResourceFromName(n) return n end
        function getResourceName(r) return "marker" end
        function getResourceState(r) return "loaded" end
        function dxCreateTexture() return entity("texture") end
        exports.skygfx={createVcsMarkerMaterial=function() return entity("material") end}
        function getCameraMatrix() return 0,-15,15 end
        function getCameraInterior() return 0 end
        function getElementInterior() return 0 end
        function getElementDimension() return 0 end
        function getGameSpeed() return 1 end
        function getMarkerSize() return 8 end
        function getGroundPosition() return 10 end
        function bitAnd() return 0 end
        function tocolor() return 0 end
        function dxDrawMaterialPrimitive3D(_,_,_,a,b,c) positions={a,b,c};return true end
    """)
    frontend = MISSION.parents[1] / "[hud]/frontend/world_markers_c.lua"
    vm.execute(frontend.read_text(encoding="utf-8-sig"))
    vm.execute("""
        local mesh={texture="zonewhite64",vertices={{0,0,0,0,0},{0.5,0,0,1,0},{0,0,1.98,0,1}},indices={1,2,3}}
        registerWorldMarkerAssets({[6]=mesh},{checkpoint={native=6,period=128,pulse=0,rotation=0,height=100}})
        local gate=entity("marker",1,2,10)
        for _,target in ipairs({false,{15,10,7},{1,2,10}}) do
            assert(setWorldMarker(gate,{style="checkpoint",color={237,130,180,215},target=target}))
            handlers.onClientPreRender()
            local state=getWorldMarkerState(gate)
            assert(state.visible and math.abs(positions[1][3]-9.6)<0.001)
            assert(math.abs(positions[3][3]-positions[1][3]-198)<0.001,"checkpoint extends underground")
        end
    """)


def check():
    check_directed_ground_gate()
    vm = LuaRuntime()
    vm.execute(HOST)
    vm.execute("""
        defs={}
        function exports.marker:setMarkerVisibleTo(m,p,v) m.visible=v end
        function Mission.driverOf(v) return getVehicleOccupant(v,0) end
        function Mission.register(id,d) defs[id]=d end
        function Mission.active(r) return not r.failed and not r.finished end
        function Mission.courseRecord(r) return {time=r.record,wins=0} end
        function Mission.finishCourse(r,id,metrics,cash,won)
            assert(id==r.id and won and cash==500 and not r.finished)
            r.finished=metrics.time
        end
        function Mission.countdown(r,v) r.countdown=v end
        function Mission.checkpointCue(r) r.cues=(r.cues or 0)+1 end
        function Mission.switchVehicle(r,v) r.vehicle=v;return true end
        function isElementFrozen(e) return e.frozen or false end
        function createBlip(x,y,z) return entity("blip",x,y,z) end
        function setElementRotation(e,x,y,z) e.yaw=z end
        function setVehicleLocked(e,v) e.locked=v end
        function setElementVisibleTo(e,p,v) e.show=v end
        function course(id,record)
            local r={id=id,def=defs[id],vehicle=entity("vehicle"),player=entity("player"),record=record,dimension=1,interior=0}
            r.token=tostring(r)
            assert(warpPedIntoVehicle(r.player,r.vehicle,0))
            r.def.start(r,clock);assert(not r.failed,r.failed)
            local start=r.aerial.cfg.start
            assert(not r.def.canStart(r.player,r.vehicle))
            setElementPosition(r.vehicle,unpack(start));assert(r.def.canStart(r.player,r.vehicle))
            return r
        end
    """)
    for name in ("course_gates.lua", "aerial_data.lua", "aerial.lua"):
        vm.execute((MISSION / name).read_text(encoding="utf-8-sig"))
    vm.execute("""
        for id,def in pairs(defs) do
            local r=course(id)
            local a=r.aerial
            local n,swapped,drones=#a.points,0,0
            if a.go then
                assert(r.vehicle.frozen);clock=a.go-1000;def.tick(r,clock);assert(r.countdown==1)
                clock=a.go;def.tick(r,clock);assert(not r.vehicle.frozen and r.countdown=="GO")
            end
            if a.cfg.kind=="play" then
                assert(not r.deadline)
                for i=n,1,-1 do
                    local p=a.points[i];setElementPosition(r.vehicle,p[1],p[2],p[3]);step(r,50)
                    assert(not a.pickups[i] and r.deadline)
                end
            else
                for i=1,n do
                    assert(i==a.index and a.gate.owner==r)
                    local p=a.points[i];setElementPosition(r.vehicle,p[1],p[2],p[3]);step(r,50)
                    if next(a.targets) then
                        assert(not a.gate and id=="skywolf")
                        step(r,100)
                        for _,t in pairs(a.targets) do drones=drones+1;t.car.health=0 end
                        step(r,100);assert(a.gate)
                    end
                    if a.returnAt then
                        assert(r.returnCar==r.vehicle and not a.gate)
                        step(r,100);assert(a.returnAt and not a.gate)
                        assert(warpPedIntoVehicle(r.player,r.vehicle,0));step(r,200)
                        assert(not a.returnAt and a.gate);swapped=swapped+1
                    end
                end
            end
            assert(not r.failed and r.finished and r.finished>0 and r.cues==n,id)
            assert(drones==(id=="skywolf" and 12 or 0))
            assert(swapped==(a.cfg.kind=="relay" and 2 or 0))
            def.stop(r)
        end
        local a,b=course("skywolf"),course("skywolf")
        assert(a.aerial.shift~=b.aerial.shift and a.aerial.gate~=b.aerial.gate)
        exit(a.player);step(a);assert(a.returnCar==a.vehicle and a.aerial.gate.blip==false and not b.returnCar)
        clock=clock+30000;a.def.tick(a,clock);assert(a.failed)
        local c=course("crimsonwings");assert(c.vehicle.frozen);c.def.stop(c);assert(not c.vehicle.frozen)
        local d=course("crimsonwater",1)
        clock=d.aerial.go;d.def.tick(d,clock)
        d.aerial.index=#d.aerial.points
        setElementPosition(d.vehicle,unpack(d.aerial.points[d.aerial.index]))
        clock=clock+1;d.def.tick(d,clock);assert(d.failed and not d.finished)
    """)
    for name, *_ in COURSES:
        assert vm.eval(f"#AerialCourses.{name}") > 0
    source = Path(r"D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)\MAIN.txt")
    if source.exists():
        assert render(source.read_text(encoding="latin1").splitlines()) == (MISSION / "aerial_data.lua").read_text(encoding="utf-8-sig")
    for ext in ("col", "dff", "txd"):
        assert (MISSION / f"assets/ndc_bikerampnarrow.{ext}").stat().st_size > 100
    print("Aerial/relay/playground/hover checks passed for all 11 variants.")


if __name__ == "__main__":
    check()
