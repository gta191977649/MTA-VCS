"""Exercise the PS2 objective slots, fire, cash, gunpoint and mission ownership via Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def main():
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute("""
        root,resourceRoot,sourceResource={},{},{}
        local hooks,timers={},{}
        now,paid,spawns,submits,voices=0,0,0,0,0
        function addEvent() end
        function addEventHandler(n,r,fn) hooks[n]=hooks[n] or {}; table.insert(hooks[n],fn) end
        function send(n,s,...) source=s; for _,f in ipairs(hooks[n] or {}) do f(...) end end
        function setTimer(f,d) timers[d]=f end
        function tick(n) timers[n]() end
        function getTickCount() return now end
        function isElement(e) return type(e)=="table" and e.kind~=nil and not e.gone end
        function getElementType(e) return e.kind end
        function getElementInterior(e) return 0 end
        function getElementDimension(e) return e.dim or 0 end
        function getElementPosition(e) return e.x,e.y,0 end
        function getElementHealth(e) return e.hp or 100 end
        function setElementHealth(e,v) e.hp=v end
        function isPedDead(e) return e.dead end
        function isPedInVehicle() return false end
        function getPedOccupiedVehicle() return false end
        function getPedRotation() return 0 end
        function getPedWeapon(e) return e.weapon or 0 end
        function getPedTotalAmmo() return 10 end
        function getElementSyncer(e) return e.owner end
        function getElementData(e,k) return e[k] end
        function setElementData(e,k,v) e[k]=v; return true end
        function removeElementData(e,k) e[k]=nil end
        function getElementsWithinRange() return candidates or {} end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function getDistanceBetweenPoints2D(x,y,a,b) return math.sqrt((x-a)^2+(y-b)^2) end
        function setPedOnFire(e,v) e.fire=v; return true end
        function isPedOnFire(e) return e.fire end
        function person(kind,x,y) return {kind=kind,x=x,y=y} end
        function destroyElement(e) e.gone=true; send("onElementDestroy",e) end
        function createPickup(x,y) spawns=spawns+1; pickup=person("pickup",x,y); return pickup end
        function setElementDimension(e,d) e.dim=d end
        function setElementInterior() end
        function givePlayerMoney(e,v) paid=paid+v end
        function triggerClientEvent(to,n,root,p,id,points)
            if n=="npchlc_traffic:cashGround" then batch={ped=p,id=id,points=points} end
        end
        PedVoice={emit=function() voices=voices+1 end}
        PedVehicleEvasion={active=function() return false end,cancel=function() end}
        PedActivity={cancel=function() end}
        TrafficVisibility={retiringKey="retiring"}
        TrafficAmbient={suspend=function() end,resumeWander=function(p,h)
            assert(h>=0 and h<8); p.rejoins=(p.rejoins or 0)+1
        end}
        TrafficRoad={driverScriptChanged=function(e,v) e.controlled=v end}
        exports={npc_hlc={clearNPCTasks=function(_,p) p.task=nil end,
            setNPCWalkSpeed=function(_,p,v) p.pace=v end,
            setNPCTask=function(_,p,t) submits=submits+1; p.task=t; return true end}}
    """)
    for name in ("ped_ai_profiles", "ped_ai_rules", "ped_objectives", "ped_combat_navigation", "ped_ai_tasks", "ped_ai",
                 "ped_carjack", "ped_special", "traffic_actors", "ped_script_control"):
        vm.execute((RESOURCE / (name + ".lua")).read_text(encoding="utf-8-sig"))
    vm.execute("""
        local slots=PedObjectives.new()
        local follow,enter,attack={id=12,target={}}, {id=18,target={}}, {id=8,target={}}
        assert(slots:request(follow) and slots:request(enter) and slots.current==enter)
        assert(not slots:request(enter))
        assert(slots:request(attack) and slots.saved==attack and slots.current==enter)
        assert(slots:complete()==attack and not slots.saved and not slots:request(attack))
        slots.body=0x20; assert(not slots:request(enter))
        slots:clear();slots.body=0x37
        local car=person("vehicle",1,1)
        assert(slots:request({id=7,vehicle=car}) and slots:complete().vehicle==car and slots.current.id==0x10)
        local flight={lastSeen=500}
        assert(not PedObjectives.flightExpired(flight,1500,1000,0))
        assert(not PedObjectives.flightExpired(flight,1501,1000,899.9) and flight.duration==5000)
        assert(PedObjectives.flightExpired(flight,6502,5000,900))
        flight.origin={0,0,0}; assert(PedObjectives.flightExpired(flight,6502,5000,0))
        assert(not PedObjectives.flightExpired(flight,99000,0,9999))

        local aimed=person("ped",0,0); local shooter=person("player",0,15.01)
        shooter.weapon=22; aimed.owner=shooter
        local brain=PedAI.attach(aimed,40); brain.dropCash=true
        send("onPlayerTarget",shooter,aimed); assert(not brain.wait)
        shooter.y=15; send("onPlayerTarget",shooter,aimed); assert(brain.wait==17 and batch and not brain.dropCash)
        local id=batch.id; send("onPlayerTarget",shooter,aimed); assert(batch.id==id and voices==1)
        local heights={}; for i=1,#batch.points do heights[i]=0 end
        client=person("player",0,0)
        send("npchlc_traffic:cashGroundReply",resourceRoot,aimed,id,heights); assert(spawns==0)
        client=shooter;send("npchlc_traffic:cashGroundReply",resourceRoot,aimed,id,heights)
        assert(spawns>=3 and spawns<=8)
        send("npchlc_traffic:cashGroundReply",resourceRoot,aimed,id,heights); assert(spawns==#batch.points)
        send("onPickupHit",pickup,shooter,true); local once=paid
        send("onPickupHit",pickup,shooter,true); assert(once>0 and paid==once)
        send("onPlayerTarget",shooter,person("vehicle",1,1)); now=300; tick(250); assert(brain.wait==17)
        send("onPlayerTarget",shooter,false); tick(250); assert(not brain.wait and not brain.event and aimed.rejoins==1)
        send("onPlayerTarget",shooter,aimed)
        assert(brain.wait==17)
        now=7000; tick(250); tick(250)
        assert(not brain.wait and aimed.rejoins==2)
        local armed=person("ped",0,0); armed.weapon=22; local ab=PedAI.attach(armed,40)
        send("onPlayerTarget",shooter,armed); assert(ab.wait==17)
        send("onPlayerTarget",shooter,false); tick(250); assert(ab.event.intent=="fight" and ab.event.duration==20000)
        local shy=person("ped",0,0); local b=PedAI.attach(shy,27)
        send("onPlayerTarget",shooter,shy); assert(b.wait==18)
        send("onPlayerTarget",shooter,false); tick(250); assert(b.event.intent=="flee")

        -- A wall blocks the target directly. Walk toward the first reachable
        -- sidewalk link connected to the goal, then resume the attack once clear.
        local path={pedestrianCells={},nodes={},links={{to=1},{to=0},{to=2},{to=1}}}
        for i=0,2 do path.nodes[i+1]={kind="pedestrian",id=i,x=i*5,y=0,z=0,flags=0} end
        path.nodes[1].firstLink,path.nodes[1].linkCount=0,1
        path.nodes[2].firstLink,path.nodes[2].linkCount=1,2
        path.nodes[3].firstLink,path.nodes[3].linkCount=3,1
        TrafficGraph={pedestrianAnchor=function(_,x) return x>8 and 2 or 0 end}
        TrafficWorld={reachable=function() return {1} end}
        local enemy=person("ped",10,0)
        local chase={target=enemy}
        assert(PedCombatNavigation.update(brain.tasks,chase,path,now))
        assert(aimed.task[1]=="walkTrafficToPoint" and aimed.task[2]==5)
        TrafficWorld.reachable=function() return {-1} end
        assert(not PedCombatNavigation.update(brain.tasks,chase,path,now+800) and not chase.detour)
        local owner=sourceResource
        assert(acquireTrafficPed(shy) and acquireTrafficPed(shy) and shy.controlled)
        sourceResource={}; assert(not acquireTrafficPed(shy) and not releaseTrafficPed(shy))
        sourceResource=owner
        assert(assignTrafficPedObjective(shy,"walk",10,0,0,"run")); tick(150)
        assert(shy.task[1]=="walkTrafficToPoint" and shy.pace=="run")
        assert(assignTrafficPedObjective(shy,"clear") and not shy.task and PedAI.isScriptControlled(shy))
        assert(releaseTrafficPed(shy) and not shy.controlled and b.event.intent=="flee")
        now=300;aimed.fire=true;PedSpecial.observeFire(brain);now=10300
        PedSpecial.update(aimed,nil);assert(aimed.fire and brain.objectives.body==0x20)
        now=10301;PedSpecial.update(aimed,nil);assert(not aimed.fire)
        PedSpecial.update(aimed,nil);assert(brain.wait==0x14)
        now=12802;PedSpecial.update(aimed,nil);assert(brain.wait==3)
        now=14803;assert(not PedSpecial.update(aimed,nil) and not brain.wait)
        assert(acquireTrafficPed(aimed) and assignTrafficPedObjective(aimed,"ignite"))
        now=30000; tick(150); assert(aimed.fire and not assignTrafficPedObjective(aimed,"attack",shooter))
        send("onResourceStop",resourceRoot,owner);assert(not aimed.fire and not PedAI.isScriptControlled(aimed))
    """)
    vm.execute("""
        TrafficAnimationBanks={street="test_street"}
        function isElementStreamedIn() return true end
        function getPedAnimation(p) return p.block,p.clip end
        function setPedAnimation(p,b,c,ms,loop,move,interrupt,freeze)
            p.block,p.clip,p.duration,p.freeze=b,c,ms,freeze
            if not b then p.clears=(p.clears or 0)+1 end
            return true
        end
    """)
    vm.execute((RESOURCE / "ped_special_c.lua").read_text())
    vm.execute("""
        local k="npchlc_traffic:threatPose"
        local p=person("ped",0,0)
        p[k]={"handsup",10,4800}; send("onClientElementDataChange",p,k)
        assert(p.clip=="handsup_wait" and p.duration==4800 and p.freeze==false)
        p.block,p.clip,p[k]=false,false,nil
        send("onClientElementDataChange",p,k); assert(p.clears==1)
        p[k]={"handscower",11,3500}; send("onClientElementStreamIn",p)
        assert(p.clip=="handscower_wait" and p.freeze==false)
        send("onClientElementStreamOut",p); assert(p.clears==2)
        send("onClientElementStreamIn",p); p.block,p.clip,p[k]="PED","FALL_front",nil
        send("onClientElementDataChange",p,k); assert(p.clears==2 and p.clip=="FALL_front")
    """)
    print("Objective arbitration, gunpoint wander/flee/fight, pose release, cash, fire and ownership passed")


if __name__ == "__main__":
    main()
