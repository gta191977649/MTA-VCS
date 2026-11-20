"""Execute the arrest camera client in Lua 5.1 with deterministic shot geometry."""
from pathlib import Path
from lupa.lua51 import LuaRuntime


def main():
    script = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic/custody_camera_c.lua"
    vm = LuaRuntime()
    vm.execute("""
        root,resourceRoot,localPlayer,officer,vehicle={},{},{},{x=0,y=-2,z=1},{}
        handlers={}
        function addEventHandler(n,e,f) handlers[n]=f end
        function removeEventHandler(n,e,f) assert(handlers[n]==f); handlers[n]=nil end
        function getPedBonePosition(p,node) assert(node==3); return 0,0,1 end
        function getElementPosition(e) return e.x,e.y,e.z end
        function getPedOccupiedVehicle(p) return p.vehicle end
        function getVehicleOccupant(v,seat) return localPlayer end
        function isPedDead() return false end
        function isElement(e) return type(e)=="table" end
        function getElementInterior() return 0 end
        function getElementDimension() return 0 end
        function getElementsWithinRange(x,y,z,r,kind) return kind=="object" and objects or {} end
        function isElementStreamedIn() return true end
        function getElementID(e) return e.name end
        function getElementMatrix(e) return {{1,0,0},{0,1,0},{0,0,1}} end
        function processLineOfSight(x,y,z,tx,ty,tz)
            if x==tx and y==ty and tz<z-50 then return true,x,y,0 end
            return false
        end
        function isLineOfSightClear() return true end
        target=localPlayer;matrix={2,3,5,2,4,5,0,70}
        function getCameraTarget() return target end
        function setCameraTarget(e) target=e end
        function getCameraMatrix() return unpack(matrix) end
        function setCameraMatrix(...) target=false;matrix={...} end
        function math.random(lo,hi) if lo then return selected end; return roll end
        objects={}
    """)
    vm.execute(script.read_text())
    vm.execute("""
        roll,selected=.9,4
        assert(TrafficCustodyCamera.begin(officer))
        assert(matrix[8]==45 and math.abs(math.sqrt(matrix[1]^2+matrix[2]^2)-8)<.001)
        assert(matrix[1]>0 and matrix[2]<0)
        handlers.onClientPreRender(20)
        TrafficCustodyCamera.finish()
        assert(target==localPlayer and handlers.onClientPreRender==nil)

        roll=.1
        assert(TrafficCustodyCamera.begin(officer))
        assert(matrix[1]==10 and matrix[2]==5 and matrix[3]==.7)
        handlers.onClientPreRender(20)
        assert(math.abs(matrix[3]-.75)<.001)
        setCameraMatrix(50,51,52,10,20,30,0,60)
        handlers.onClientPreRender(20)
        assert(handlers.onClientPreRender==nil and matrix[1]==50)
        TrafficCustodyCamera.finish()
        assert(matrix[1]==50 and target==false)

        local street={name="lamppost2_0d311",x=17,y=0,z=0}
        objects={street}
        assert(TrafficCustodyCamera.begin(officer))
        assert(math.abs(matrix[1]-20.7528)<.001)
        local z=matrix[3]
        handlers.onClientPreRender(20)
        assert(matrix[3]==z and matrix[1]~=20.7528)
        handlers.onClientResourceStop()
        assert(matrix[1]==50 and matrix[8]==60)

        localPlayer.vehicle=vehicle
        assert(TrafficCustodyCamera.begin(officer))
        assert(matrix[1]==10 and matrix[3]==.7)
        setCameraTarget(vehicle)
        TrafficCustodyCamera.finish()
        assert(target==vehicle)

        assert(TrafficCustodyCamera.begin(officer))
        localPlayer.vehicle=nil
        TrafficCustodyCamera.finish()
        assert(target==localPlayer)
        target=localPlayer
        roll=.9
        local oldSet=setCameraMatrix
        local deferred
        function setCameraMatrix(...) deferred={...} end
        assert(TrafficCustodyCamera.begin(officer))
        target=false
        matrix={-10,-20,-30,1,1,1,0,70}
        handlers.onClientPreRender(10)
        assert(handlers.onClientPreRender)
        local x,y,z,tx,ty,tz=unpack(deferred)
        local n=math.sqrt((tx-x)^2+(ty-y)^2+(tz-z)^2)
        matrix={x,y,z,x+(tx-x)/n,y+(ty-y)/n,z+(tz-z)/n,0,45}
        setCameraMatrix=oldSet
        handlers.onClientPreRender(10)
        TrafficCustodyCamera.finish()
        assert(target==localPlayer and not handlers.onClientPreRender)

        -- Original ground camera beyond a roof edge would be clipped
        -- to a fraction of a unit from the actor. Keep the shot upstairs.
        objects={}; roll=.1; selected=2
        function processLineOfSight(x,y,z,tx,ty,tz)
            if x==tx and y==ty and tz<z-50 then return true,x,y,-30 end
            if tz < -10 then return true,.2,.2,.5 end
            return false
        end
        assert(TrafficCustodyCamera.begin(officer))
        assert(matrix[3]>1 and matrix[1]^2+matrix[2]^2>63)
        handlers.onClientPreRender(20)
        assert(matrix[3]>1)
        TrafficCustodyCamera.finish()
        assert(target==localPlayer)
    """)
    print("Busted officer, ground, moving, street-anchor and vehicle camera choices and ownership restoration passed")


if __name__ == "__main__":
    main()
