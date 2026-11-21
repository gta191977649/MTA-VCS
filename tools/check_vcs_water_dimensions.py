"""Exercise Eagle's indexed water pool against both MTA dimension event orders."""
from pathlib import Path
from lupa.lua51 import LuaRuntime


def check():
    vm = LuaRuntime()
    vm.execute("""
        localPlayer,root,camera={},{},{}
        managerDimension,playerDimension=0,0
        slots={}
        function createWater(...)
            local e={dim=0,logical={},native=managerDimension==0}
            local values={...}
            for i=1,4 do local j=(i-1)*3;e.logical[i]={values[j+1],values[j+2],values[j+3]} end
            slots[#slots+1]=e
            return e
        end
        function setWaterLevel() return true end
        function setElementDimension(e,d)
            if e.native and d~=managerDimension then
                assert(e.logical[1][3]==-900,"dropped an exterior polygon before parking its native vertices")
            end
            e.dim=d;e.native=d==managerDimension
        end
        function setWaterVertexPosition(e,i,x,y,z)
            assert(e.native,"moving logical snapshots without their native vertices")
            e.logical[i]={x,y,z}
        end
        function setElementPosition() return true end
        function getElementPosition() return 0,0,0 end
        function getCameraMatrix() return 0,0,0 end
        function getCamera() return camera end
        function getElementDimension(e) return e==camera and managerDimension or playerDimension end
        function getWaterLevel(x,y,z)
            for _,e in ipairs(slots) do
                local a,b=e.logical[1],e.logical[4]
                if e.native and a[1]<=x and x<=b[1] and a[2]<=y and y<=b[2] then return a[3] end
            end
            return false
        end
        function addEventHandler(name,_,fn) if name=="onClientElementDimensionChange" then transition=fn end end
        function addCommandHandler() end
        function setTimer(fn) refresh=fn;return {} end
        function isTimer() return false end
        function isElement() return true end
        function destroyElement(e) e.native=false end
        function switchManager(d)
            managerDimension=d
            for _,e in ipairs(slots) do e.native=e.dim==managerDimension end
        end
        function change(d,spawn)
            local old=playerDimension
            if not spawn then switchManager(d) end
            playerDimension=d;transition(old,d)
            if spawn then switchManager(d) end
            refresh()
        end
    """)
    path = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[vcs]/eagleLoader/client/water_loader.lua"
    vm.execute(path.read_text(encoding="utf-8-sig"))
    vm.execute("""
        local polygon={x1=-16,y1=-16,z1=6,x2=16,y2=-16,z2=6,x3=-16,y3=16,z3=6,x4=16,y4=16,z4=6}
        createWaterPlanes({polygon},"test",true)
        for _,spawn in ipairs({true,false,true,false}) do
            assert(getWaterLevel(0,0,6)==6)
            change(3090,spawn);assert(not getWaterLevel(0,0,6))
            change(0,spawn);assert(getWaterLevel(0,0,6)==6 and #slots==1)
        end
        stopStreamedWater("test")
    """)
    print("Indexed water parking passed for respawns and ordinary dimension changes.")


if __name__ == "__main__":
    check()
