"""Check incident ownership, responder selection and interruptible service tasks in Lua 5.1."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def main():
    vm = LuaRuntime()
    vm.execute("""
        root, resourceRoot, now, world = {}, {}, 100, {}
        function addEventHandler() end
        function setTimer() return {} end
        function isTimer() return false end
        function getTickCount() return now end
        function isElement(e) return type(e)=="table" and not e.removed end
        function getElementsByType(kind) return world[kind] or {} end
        function getElementModel(e) return e.model end
        TrafficVisibility={retiringKey="retiring"}
        function getElementData(e,key) return key=="retiring" and e.retiring or e.original end
        function getElementType(e) return e.kind or "ped" end
        function getElementPosition(e) return e.x,0,e.z end
        function getElementInterior(e) return 0 end
        function getElementDimension(e) return e.dim or 0 end
        function getDistanceBetweenPoints2D(x,y,a,b) return math.sqrt((x-a)^2+(y-b)^2) end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function getElementHealth(e) return e.hp end
        function isPedDead(e) return e.hp==0 end
        function isPedHeadless(e) return e.headless end
        function isPedInVehicle(e) return false end
        function isPedOnFire(e) return e.burning end
        function getElementsWithinRange(x,y,z,r,kind) return world[kind] or {} end
        function setPedAnimation(e,block,clip) e.animation=clip end
        function setPedRotation(e,h) e.heading=h end
        function getElementRotation(e) return 0,0,e.heading or 0 end
        function setPedWeaponSlot(p,slot) p.armed=slot end
        function setPedArmor(p,armor) p.armor=armor end
        function giveWeapon(p,id,ammo,equip)
            p[id]=ammo
            if equip then p.armed=id end
        end
        exports={npc_hlc={
            setNPCWalkSpeed=function() end,
            setNPCTask=function(_,p,task) p.task=task;return true end,
            clearNPCTasks=function(_,p) p.task=nil end}}
        PedAI={brain=function(e) return e.brain end,
               returnServiceDriver=function(p,road) p.returning=road; return true end,
               profile=function(e) return {pedType=e.role} end,
               isScriptControlled=function(e) return e.mission end}
        TrafficAmbient={isManagedPed=function(e) return not e.foreign end,getPedestrianModel=function(m) return m end}
        TrafficModelBindings={get=function(m) return ({[227]=416,[194]=407})[m] end}
        PedVoice={emit=function(e,k) e[k]=(e[k] or 0)+1 end}
        function actor(x,z,role,hp) return {x=x,z=z,role=role,hp=hp or 100} end
    """)
    vm.execute((RESOURCE / "ped_services.lua").read_text(encoding="utf-8"))
    vm.execute("""
        PedServices.start({edition="SLUS-21590 USA v1.00"})
        local officer=actor(0,0,6)
        PedServices.initializeOfficer(officer,8)
        assert(officer[3]==1000 and officer[22]==1000 and officer.armed==0)
        PedServices.initializeOfficer(officer,9)
        assert(officer[28]==1000 and officer.armed==28 and officer.armor==50)
        PedServices.initializeOfficer(officer,11)
        assert(officer[29]==1000 and officer.armed==29 and officer.armor==100)
        local suspect=actor(15,0,0)
        officer.original,officer.brain,officer.armed=8,{},0
        local enrolled,stars,contact=1,1,true
        TrafficGroundPolice={target=function() return suspect end, updateSpecial=function() end,
            enroll=function() return true end,officerCount=function() return enrolled end,releaseOfficer=function() end}
        TrafficWanted={tryArrest=function() return false end, driverArrestCar=function() return false end, officerCanPursue=function() return true end}
        TrafficActors={isPolicePed=function(p) return p.role==6 end}
        PedAIRules={ranged=function(w) return w>=22 end, attackRange=function() return 30 end}
        function getPlayerWantedLevel() return stars end
        function getPedOccupiedVehicle() return false end
        function getPedContactElement() return contact end
        function getPedWeapon(p,slot) return ({[0]=0,[1]=3,[2]=22})[slot or p.armed] end
        assert(PedServices.update(officer,8,now) and officer.armed==0)
        assert(not officer.pursuitGroup and not suspect.pursuitReply)
        contact=false
        assert(PedServices.update(officer,8,now) and officer.armed==1)
        stars,enrolled,now=2,2,now+1000
        world.ped={officer}
        assert(PedServices.update(officer,8,now) and officer.armed==1)
        assert(officer.pursuitGroup==1 and suspect.pursuitReply==1)
        officer.armed,now=0,now+1000
        world.ped={officer,officer,officer,officer}
        assert(PedServices.update(officer,8,now) and officer.armed==2)
        assert(officer.pursuitGroup==1 and suspect.pursuitReply==1)
        local stopped=actor(15,0,0)
        local shoot,locked=false,false
        function getPedOccupiedVehicle(p) return p==suspect and stopped end
        function getElementVelocity() return 0,0,0 end
        TrafficWanted.vehicleFireDue=function() return shoot end
        TrafficWanted.driverArrestCar=function() return not locked and stopped end
        TrafficWanted.tryDriverArrest=function() return false end
        TrafficWanted.driverDoorApproach=function() return -1.55,.4 end
        assert(PedServices.update(officer,8,now) and officer.task[1]=="approachDriverDoor")
        shoot=true
        assert(PedServices.update(officer,8,now) and officer.task[1]=="attackOccupiedVehicle" and officer.task[6]==1)
        shoot,locked=false,true
        assert(PedServices.update(officer,8,now) and officer.task[1]=="attackOccupiedVehicle" and officer.task[6]==0)
        locked=false
        assert(PedServices.update(officer,8,now) and officer.task[1]=="approachDriverDoor")
        function getPedOccupiedVehicle() return false end
        local casualty=actor(0,0,4,0)
        local elevated=actor(1,10,4,0)
        elevated.mission=true
        assert(not PedServices.accident(elevated))
        elevated.mission=false
        assert(PedServices.accident(elevated))
        assert(not PedServices.dispatch(1.5,0,0,0))
        now=now+30001
        assert(not PedServices.dispatch(.5,0,0,0))
        assert(PedServices.accident(casualty) and not PedServices.accident(casualty))
        world.vehicle={{model=416},{original=227}}
        assert(not PedServices.dispatch(.5,0,0,0))
        world.vehicle={}
        local car,original,_,slot=PedServices.dispatch(.5,0,0,0)
        assert(car==416 and original==227 and slot.element==casualty)
        local vehicle=actor(50,0,0)
        local driver=actor(50,0,16)
        local state={driver=driver,vehicle=vehicle,originalVehicle=227,dimension=0}
        function getElementSyncer() return driver end
        function getElementVelocity(e) return e.speed or 0,0,0 end
        function setVehicleSirensOn(e,on) e.siren=on end
        TrafficRoad={serviceRoute=function() return {{30,0,0},{15,0,0}} end}
        TrafficPassengers={requestExit=function(p,v,seat) assert(seat==0); p.exits=(p.exits or 0)+1 end}
        PedServices.linkCrew(state,slot,true)
        local function advance()
            return PedServices.inVehicle(state,now,function() end,function() state.resumed=true end)
        end
        assert(advance() and driver.task[1]=="driveToPos" and driver.task[2]==30)
        vehicle.x=30
        assert(advance() and advance() and driver.task[2]==15)
        vehicle.x,vehicle.speed=15,0.01
        assert(advance() and driver.task[1]=="stopVehicle" and not driver.exits)
        vehicle.speed=.009
        assert(advance() and driver.exits==1)
        PedServices.interrupt(driver)
        assert(PedServices.crewModel(original)==12 and PedServices.crewModel(194)==13)
        for vehicle,model in pairs({[219]=8,[207]=8,[261]=8,[191]=119,[193]=10,[218]=11,[246]=11,[234]=9}) do
            assert(PedServices.policeCrewModel(vehicle)==model)
        end
        assert(not PedServices.policeCrewModel(227) and not PedServices.policeCrewModel(204))
        local medic,second,third=actor(.55,0,16),actor(3,0,16),actor(3,0,16)
        assert(PedServices.update(medic,12,now) and medic.animation=="CPR")
        assert(PedServices.update(second,12,now) and second.treat==1 and not second.animation)
        assert(not PedServices.update(third,12,now))
        PedServices.interrupt(medic)
        second.x=.5
        assert(PedServices.update(second,12,now) and second.animation=="CPR")
        local road={driver=second,vehicle=actor(1,0,0),dimension=0}
        PedServices.linkCrew(road,slot,true)
        assert(PedServices.needsParkedVehicle(road))
        assert(not PedServices.dispatch(.5,0,0,0))
        assert(PedServices.keepCasualty(casualty))
        casualty.headless=true
        for i=1,5 do PedServices.update(second,12,now) end
        now=now+500
        PedServices.update(second,12,now)
        assert(PedServices.keepCasualty(casualty))
        now=now+1
        PedServices.update(second,12,now)
        assert(not PedServices.keepCasualty(casualty) and casualty.hp==0)
        assert(PedServices.update(second,12,now) and second.returning==road)
        assert(not PedServices.needsParkedVehicle(road))
        local fire,fireman=actor(20,0,4),actor(21,0,17)
        fire.burning=true
        world.ped={fire}
        PedServices.observeFire(20,0,0,0)
        local engine,model=PedServices.dispatch(21,0,0,0)
        assert(engine==407 and model==194)
        assert(PedServices.update(fireman,13,now) and fireman.fireScene==1)
        PedServices.update(fireman,13,now)
        assert(fireman.fireScene==1 and fire.burning)
        fire.dim=1
        assert(not PedServices.update(fireman,13,now))
        PedServices.stop()
    """)
    print("Verified paramedic and firefighter selection, assistance, cancellation and incident lifetime")


if __name__ == "__main__":
    main()
