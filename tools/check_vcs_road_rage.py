"""Exercise committed road rage against changing native seats and sync ownership."""

from lupa.lua51 import LuaRuntime

from check_vcs_traffic import RUNTIME, SERVER_MOCK, load


def check_decisions():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
        exports={npc_hlc={}}
        TrafficWanted={atDriverDoor=function(ped, car) return ped.atDoor end,
            driverDoorApproach=function() return -1.55,.4 end}
        function exports.npc_hlc:clearNPCTasks(ped) ped.task=nil end
        function exports.npc_hlc:setNPCTask(ped, task) ped.task=task return true end
        function exports.npc_hlc:setNPCWalkSpeed(ped, pace) ped.pace=pace end
        function getPedWeapon(ped) return ped.weapon or 0 end
        function getPedTotalAmmo() return 50 end
        function setPedWeaponSlot(ped, slot) if slot==0 then ped.weapon=0 end end
        function isVehicleLocked(car) return car.locked end
        function isVehicleBlown(car) return car.health==0 end
        function isPedOnGround() return true end
        function getPedOccupiedVehicleSeat(ped) return ped.vehicle and ped.seat or 0 end
        function cancelEvent() cancelled=true end
        TrafficPassengers={requestExit=function(ped,car,seat)
            assert(ped.vehicle==car and seat==0)
            ped.exitRequests=(ped.exitRequests or 0)+1
        end}
    """)
    load(lua, RUNTIME, ["ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_weapons.lua", "ped_objectives.lua",
                        "ped_ai_tasks.lua", "ped_carjack.lua", "ped_ai.lua"])
    lua.execute("""
        local ped,car,original=element("ped"),element("vehicle"),element("vehicle")
        local target,other,owner=element("player"),element("player"),element("player")
        local road={driver=ped,vehicle=original}
        local brain=PedAI.attach(ped,24)
        ped.syncer,ped.weapon=owner,24
        target.vehicle,car.driver=car,target
        PedAI.committedRoadRage(ped,target,road)
        local event=brain.event
        assert(event.committed and event.originalRoad==road and ped.weapon==0)
        local function update(ms) now=now+(ms or 10);return PedAI.update(ped) end
        local function nativeEntry(seat,jacked,door)
            cancelled=false
            deliver("onVehicleStartEnter",car,ped,seat,jacked,door or 0)
            return not cancelled
        end
        car.x,target.x=20,20
        assert(update() and ped.task[1]=="approachDriverDoor" and ped.task[2]==target)
        car.x,target.x=4,4
        car.locked=true
        assert(update() and event.maneuver=="Driver door locked" and not ped.task and not event.extractId)
        car.locked,car.vx=false,0.1
        assert(update() and event.maneuver=="Waiting for driver to stop" and not event.extractId)
        car.vx=0
        assert(update() and ped.task[1]=="approachDriverDoor" and not event.extractId)
        local order=ped.task[5]
        deliver("npc_hlc:onDriverDoorArrival",ped,car,order-1)
        assert(update() and not event.extractId)
        deliver("npc_hlc:onDriverDoorArrival",ped,car,order)
        assert(update() and event.extractId and event.extractOwner==owner)
        local id=event.extractId
        local count=#packets
        assert(nativeEntry(0,target) and not nativeEntry(1,target) and not nativeEntry(0,other))
        assert(nativeEntry(0,target,2) and not nativeEntry(0,other,2))
        assert(not nativeEntry(0,target,1) and not nativeEntry(0,target,3))
        now=now+150
        brain:react("damage",target,24,"flee")
        assert(brain.event==event and event.lastSeen==now and event.intent=="fight" and event.extractId==id)
        brain:react("gunshot",other,24,"flee")
        assert(brain.event==event and event.target==target)
        assert(update() and #packets==count)
        client=other
        deliver("npchlc_traffic:pullOutStarted",resourceRoot,ped,id)
        assert(not event.extractStatus)
        deliver("npchlc_traffic:pullOutBlocked",resourceRoot,ped,id)
        assert(event.maneuver~="Driver door blocked")
        client=owner
        deliver("npchlc_traffic:pullOutStarted",resourceRoot,ped,id)
        assert(event.extractStatus=="active")
        deliver("npchlc_traffic:pullOutBlocked",resourceRoot,ped,id)
        deliver("npchlc_traffic:pullOutStarted",resourceRoot,ped,id)
        assert(event.maneuver=="Driver door blocked" and event.extractStatus=="blocked")
        ped.syncer=other
        -- Server-side isPedInVehicle includes this pending native entry.
        ped.vehicle=car
        assert(update() and not event.extractId and ped.task[1]=="approachDriverDoor")
        deliver("npc_hlc:onDriverDoorArrival",ped,car,ped.task[5])
        assert(update() and event.extractOwner==other and event.extractId~=id)
        assert(not ped.exitRequests and not event.extractStatus)
        ped.vehicle=nil
        assert(packets[#packets-1].owner==owner and packets[#packets-1][1][2]==id)
        assert(packets[#packets].owner==other and packets[#packets][1][4]==event.extractId)
        deliver("npchlc_traffic:pullOutBlocked",resourceRoot,ped,id)
        assert(event.maneuver~="Driver door blocked")
        client=other
        deliver("npchlc_traffic:pullOutStarted",resourceRoot,ped,id)
        assert(not event.extractStatus)
        car.driver=owner
        assert(not nativeEntry(0,target))
        assert(update() and not event.extractId and event.maneuver=="Waiting for target to exit")
        target.vehicle=nil
        assert(update() and ped.task[1]=="killPed" and ped.task[2]==target and not event.maneuver)
        -- GTA may finish the driver's entry before the client sees the target leave.
        ped.vehicle,car.driver=car,ped
        assert(update() and ped.exitRequests==1 and brain.event==event)
        assert(update() and ped.exitRequests==1)
        ped.vehicle,car.driver=nil,nil
        assert(update() and brain.event==event and ped.task[2]==target)

        target.vehicle,car.driver=car,target
        ped.atDoor=true
        assert(update() and event.extractId)
        target.dimension=1
        assert(update() and not event.extractId and brain.event.kind=="returnCar")
        assert(brain.event.road==road)
        original.driver=owner
        assert(not update() and not brain.event and not ped.task and ped.pace=="walk")
        target.dimension=0
        PedAI.committedRoadRage(ped,target,road)
        event=brain.event
        assert(update() and event.extractId)
        PedAI.detach(ped)
        assert(not PedAI.brain(ped) and not event.extractId)
        assert(packets[#packets].name=="npchlc_traffic:cancelPullOut")
    """)


def check_native_requests():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
        localPlayer=element("player")
        function isElementSyncer(ped) return ped.syncer==localPlayer end
        function getPedOccupiedVehicle(ped) return ped.vehicle or ped.entering end
        function isElementStreamedIn(e) return not e.streamedOut end
        function isVehicleLocked(car) return car.locked end
        function getPedTask(ped) return ped.primary end
        function getElementBoundingBox(car) return -1,-2,-.5,1,2,1 end
        function isLineOfSightClear() return clearDoor end
        function setPedEnterVehicle(ped,car,passenger)
            assert(not passenger and isElementSyncer(ped))
            entries=entries+1
            return true
        end
        function setPedAnimation(ped,block,name) ped.anim=name end
        function triggerServerEvent(name,resource,ped,id)
            assert(resource==resourceRoot)
            reports[#reports+1]={name,ped,id}
        end
        function removeEventHandler(name,resource,handler)
            for i,fn in ipairs(events[name] or {}) do
                if fn==handler then table.remove(events[name],i) return true end
            end
        end
    """)
    load(lua, RUNTIME, ["traffic_passengers_c.lua"])
    lua.execute("""
        local ped,target,car=element("ped"),element("player"),element("vehicle")
        ped.syncer,car.driver,target.vehicle=localPlayer,target,car
        ped.x,ped.y=-1.5,.4
        entries,reports,clearDoor=0,{},false
        local function pull(id) deliver("npchlc_traffic:pullDriverOut",resourceRoot,ped,car,target,id) end
        pull(1)
        assert(entries==0 and #reports==1 and reports[1][3]==1)
        clearDoor=true
        pull(2)
        assert(entries==1)
        deliver("npchlc_traffic:cancelPullOut",resourceRoot,ped,1)
        assert(not ped.anim)
        car.driver=nil
        deliver("onClientPreRender",root)
        assert(ped.anim=="IDLE_stance" and #reports==1)
        ped.anim,car.driver=nil,target
        pull(3)
        ped.syncer=element("player")
        deliver("onClientPreRender",root)
        assert(not ped.anim and #reports==1)
        pull(4)
        assert(entries==2)
        ped.syncer=localPlayer
        pull(5)
        now=now+5100
        deliver("onClientPreRender",root)
        assert(ped.anim=="IDLE_stance" and #reports==2 and reports[2][3]==5)
        ped.anim=nil
        pull(6)
        deliver("npchlc_traffic:cancelPullOut",resourceRoot,ped,6)
        assert(ped.anim=="IDLE_stance")
        pull(7)
        deliver("onClientPreRender",root)
        assert(#reports==2)
        ped.primary="TASK_COMPLEX_ENTER_CAR_AS_DRIVER"
        deliver("onClientPreRender",root)
        deliver("onClientPreRender",root)
        assert(#reports==3 and reports[3][1]=="npchlc_traffic:pullOutStarted" and reports[3][3]==7)
        ped.primary=nil
        deliver("onClientPreRender",root)
        assert(#reports==4 and reports[4][1]=="npchlc_traffic:pullOutBlocked" and reports[4][3]==7)
    """)


if __name__ == "__main__":
    check_decisions()
    check_native_requests()
    print("Committed road rage, native seat guards, sync handoff and target-loss cleanup passed")
