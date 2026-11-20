"""Run the original sensor thresholds and MTA owner/revision lifecycle with Lua 5.1."""

from pathlib import Path

from lupa.lua51 import LuaRuntime

RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def main():
    lua = LuaRuntime(unpack_returned_tuples=True)
    for name in ("ped_models/groups.lua", "ped_evasion.lua"):
        lua.execute((RESOURCE / name).read_text())
    lua.execute("""
        local car = {x=0,y=0,z=0,fx=0,fy=1,vx=0,vy=.2,vz=0,
            front=2,width=1,bottom=-.8,top=1,yawRate=0}
        local function threat(x,y,z) return PedEvasion.threat(car,x,y,z or .8,0,0) end
        assert(threat(0,8) == "ev_dive" and threat(.7,8) == "ev_step")
        car.vy = .4
        assert(threat(.8,8) == "ev_dive" and threat(1.3,8) == "ev_step")
        assert(not threat(1.6,8) and not threat(0,11) and not threat(0,-4))
        assert(not threat(0,6,4) and not threat(0,6,2.8))
        car.yawRate = 3
        assert(not threat(0,10))
        car.yawRate, car.vx = 0, .4
        assert(not threat(0,10))
        car.vx, car.vy = 0, .12
        assert(threat(0,8) == "approach" and threat(0,7.9) == "ev_dive")
        car.vy = .10
        assert(not threat(0,6))
        car.vy = -.2
        assert(not threat(0,8))
        local dive = PedEvasion.clip("ev_dive")
        local nextClip,t = PedEvasion.pose("ev_dive",dive.duration)
        assert(dive.motion[#dive.motion][3]>6.72 and nextClip=="getup_front" and t==0)
        assert(PedEvasion.pose("ev_dive",dive.duration-1)=="ev_dive")
        local step = PedEvasion.clip("ev_step").motion
        local sy = step[#step][3]
        assert(sy < -1.17 and sy > -1.18 and PedEvasion.duration("ev_dive")==3700)
    """)
    lua.execute("""
        root,resourceRoot,handlers,data = {},{},{},{}
        ped,car,player,other={kind="ped"},{kind="vehicle"},{kind="player"},{kind="player"}
        PedVoice={emit=function() barks=barks+1 end}
        brain={profile={flags=0},tasks={clear=function() clears=clears+1 end},
            react=function(self,kind) self.event={kind=kind} end}
        PedAI={attach=function() return brain end}
        PedActivity={cancel=function() end}
        TrafficAmbient={isManagedPed=function(p) return p==ped end}
        function addEvent() end
        function addEventHandler(k,_,f) handlers[k]=f end
        function getTickCount() return now end
        function isElement(e) return type(e)=="table" end
        function getElementType(e) return e.kind end
        function getElementSyncer(e) return player end
        function isPedDead(e) return false end
        function isPedInVehicle(e) return false end
        function getElementInterior(e) return 0 end
        function getElementDimension(e) return e.dim or 0 end
        function getElementData(e,k) return data[k] end
        function getVehicleOccupant() return player end
        function getElementPosition(e) return 0,e==ped and 8 or 0,.8 end
        function getElementVelocity() return 0,.25,0 end
        function getElementMatrix() return {{1,0,0},{0,1,0}} end
        function setElementData(e,k,v) data[k]=v end
        function removeElementData(e,k) data[k]=nil end
        function setTimer(f,t) return {f=f,t=t} end
        function isTimer(t) return t and not t.dead end
        function killTimer(t) t.dead=true end
        function triggerClientEvent() clocks=clocks+1 end
        now,barks,clears,clocks=0,0,0,0
        source,client=resourceRoot,other
    """)
    lua.execute((RESOURCE / "ped_evasion_s.lua").read_text())
    lua.execute("""
        local issue = handlers["npchlc_traffic:evadeCar"]
        local function run() issue(ped,car,"ev_dive",1,0,false) end
        run()
        assert(not PedVehicleEvasion.active(ped))
        client = player
        data["npchlc_traffic:activityMotion"]={}
        run()
        assert(not PedVehicleEvasion.active(ped))
        data["npchlc_traffic:activityMotion"]=nil
        issue(ped,car,"ev_dive",9,0,false)
        assert(not PedVehicleEvasion.active(ped))
        handlers["npchlc_traffic:vehicleApproach"](ped,car)
        assert(brain.event.kind=="approach")
        run()
        assert(PedVehicleEvasion.active(ped) and barks==1 and clears==1)
        run()
        local id=data[PedEvasion.key][1]
        handlers["npchlc_traffic:evadeClock"](ped,id-1)
        handlers["npchlc_traffic:evadeClock"](ped,id)
        assert(clocks==1 and clears==1)
        source=ped
        handlers.onPedDamage()
        assert(not PedVehicleEvasion.active(ped) and not data[PedEvasion.key])
        source=resourceRoot
        run()
        assert(not PedVehicleEvasion.active(ped))
        now=3000
        brain.profile.flags=16
        issue(ped,car,"ev_dive",1,0,true)
        assert(data[PedEvasion.key][2]=="handsup" and barks==1)
        handlers.onResourceStop()
        assert(not PedVehicleEvasion.active(ped))
    """)
    lua.execute("""
        handlers={}
        data={["npchlc_traffic:visibility"]="pedestrian",["npchlc_traffic:originalModel"]=23}
        function setTimer(callback) scan=callback end
        function isElementStreamedIn() return true end
        function getVehicleType() return "Automobile" end
        function getPedOccupiedVehicle() return car end
        function getElementsByType() return {player} end
        function getElementsWithinRange() return {ped} end
        function getElementBoundingBox() return -1,-2,-.7,1,2,1 end
        function getElementMatrix(e)
            if e==ped then return {{-1,0,0},{0,-1,0},{0,0,1},{0,8,.8}} end
            return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}}
        end
        function getElementVelocity(e) return 0,e==car and .25 or 0,0 end
        function isElementSyncer() return owner end
        function isPedOnGround() return true end
        function isLineOfSightClear() return true end
        function processLineOfSight() return not blocked,0,0,0,false,0,0,1 end
        function getPedControlState() return true end
        function triggerServerEvent(k,r,...) reports=reports+1;args={...} end
        function setElementRotation(e,x,y,z) yaw=z end
        TrafficAnimationBanks={street="test_street"}
        function engineReplaceAnimation(e,b,clip,custom,name) assert(custom==TrafficAnimationBanks.street); replacement=name; return true end
        function engineRestoreAnimation() replacement=nil; restores=restores+1 end
        function setPedAnimation(e,b,n,_,_,move) block,name,moved=b,n,move end
        function setPedAnimationProgress(e,n,t) progress=t end
        function getPedAnimation() return block,name end
        PedAIModels={[23]={0,0}}; PedAIStats={[0]={flags=0}}
        reports,restores,owner,blocked,now=0,0,true,true,0
    """)
    lua.execute((RESOURCE / "ped_evasion_c.lua").read_text())
    lua.execute("""
        scan()
        assert(reports==0) -- both escape routes end over empty space
        now=3000; blocked=false; owner=false
        scan()
        assert(reports==0)
        owner=true; scan()
        assert(reports==1 and args[1]==ped and args[2]==car and args[3]=="ev_dive")
        local dx,dy=args[4],args[5]
        assert(math.abs(dx)>.99 and math.abs(dy)<.01)
        data[PedEvasion.key]={3,"ev_dive",dx,dy}
        source=ped; handlers.onClientElementDataChange(PedEvasion.key)
        handlers.onClientPreRender(16)
        assert(moved and replacement=="ev_dive_root" and math.abs(yaw)==90)
        owner=false; handlers.onClientPreRender(16)
        assert(not moved and replacement=="ev_dive")
        now=5500; handlers.onClientPreRender(16)
        assert(replacement=="getup_front" and not moved and progress>0)
        handlers.onClientElementStreamOut()
        assert(not replacement and not name)
        handlers.onClientElementStreamIn()
        handlers["npchlc_traffic:evadeTime"](ped,3,3000)
        handlers.onClientPreRender(16)
        assert(replacement=="getup_front" and progress>.4)
        data[PedEvasion.key]=nil; handlers.onClientElementDataChange(PedEvasion.key)
        assert(not replacement and not name)
        owner=true
        data[PedEvasion.key]={4,"ev_dive",dx,dy,true}
        handlers.onClientElementDataChange(PedEvasion.key)
        handlers.onClientPreRender(16)
        assert(not replacement and moved and name=="ev_dive")
        now=now+VCS_TRAFFIC_EVADE_CLIPS.ev_dive.duration
        handlers.onClientPreRender(16)
        assert(not replacement and name=="getup_front")
    """)
    print("Vehicle sensor, blocked landings, PS2 animation, owner migration and recovery passed.")


if __name__ == "__main__":
    main()
