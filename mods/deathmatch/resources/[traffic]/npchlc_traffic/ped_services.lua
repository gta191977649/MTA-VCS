local onFire = isElementOnFire or isPedOnFire
-- VCS emergency and police ped updates. Each assignment belongs to one world.
PedServices = {}
local hlc = exports.npc_hlc
local accidents, fires, workers, crews = {}, {}, {}, {}
local timer,enabled
local serviceModels = {[12]=227,[13]=194}
local function age(now, before) return (now-before)%4294967296 end
local function sameWorld(ped, slot)
    return getElementDimension(ped)==slot.dimension and getElementInterior(ped)==slot.interior
end
local function slotFor(element)
    local x,y,z=getElementPosition(element)
    return {element=element,x=x,y=y,z=z,dimension=getElementDimension(element),
        interior=getElementInterior(element),created=getTickCount(),assigned=0,treating=0}
end
local function position(slot)
    if isElement(slot.element) then slot.x,slot.y,slot.z=getElementPosition(slot.element) end
    return slot.x,slot.y,slot.z
end
local function valid(slot)
    if not slot or slot.closed then return false end
    if slot.casualty and isElement(slot.element) and getElementData(slot.element,TrafficVisibility.retiringKey,false) then return false end
    local element=slot.element
    if element and (not isElement(element) or not sameWorld(element,slot)) then return false end
    if slot.casualty then return getElementHealth(element)==0 end
    if slot.worldFire then return age(getTickCount(),slot.created)<12000 end
    if not isElement(element) then return false end
    if getElementType(element)=="vehicle" then return not isVehicleBlown(element) and getElementHealth(element)<=250 end
    return onFire(element)
end
local function insert(slots,slot,cap)
    for i=1,cap do
        local old=slots[i]
        if not valid(old) then slots[i]=slot return slot end
    end
end
local function hasElement(slots,element,cap)
    for i=1,cap do local s=slots[i]; if s and s.element==element and valid(s) then return s end end
end
function PedServices.accident(ped)
    if not enabled or not PedAI.profile(ped) or PedAI.isScriptControlled(ped) or not TrafficAmbient.isManagedPed(ped)
        or getElementHealth(ped)~=0 or hasElement(accidents,ped,20) then return end
    local slot=slotFor(ped)
    slot.casualty=true
    return insert(accidents,slot,20)
end
function PedServices.keepCasualty(ped)
    local s=hasElement(accidents,ped,20)
    return s and (s.assigned>0 or isElement(s.crew) and not isPedDead(s.crew)) and age(getTickCount(),s.created)<45000
end
-- The first free-treatment slot wins a distance tie. Height comparison is signed.
local function nearest(model,x,y,z,interior,dimension,maxDistance,associated,unassigned)
    local medical=model==12
    local slots,cap=medical and accidents or fires,medical and 20 or 40
    for pass=0,(medical and 1 or 0) do
        local best,distance=nil,maxDistance or math.huge
        for i=1,cap do
            local s=slots[i]
            if valid(s) and s.interior==interior and s.dimension==dimension
                and (not medical or s.treating==pass)
                and (not unassigned or s.assigned==0 and not isElement(s.crew)) then
                local a,b,c=position(s)
                local d=getDistanceBetweenPoints2D(x,y,a,b)
                if d<distance and (not medical or c-z<d*.5)
                    and (not isElement(associated) or getDistanceBetweenPoints3D(a,b,c,getElementPosition(associated))<=30) then
                    best,distance=s,d
                end
            end
        end
        if best then return best,distance end
    end
end
-- 00324D08 selects weapons by subtype. These model IDs preserve the
-- distinction after MTA has assigned a shared native ped skin.
local officerGun = {[9]=28,[10]=29,[11]=29,[117]=28,[118]=28}
function PedServices.initializeOfficer(ped,model)
    if not enabled then return end
    if model==8 or model==119 then
        giveWeapon(ped,3,1000,true)
        giveWeapon(ped,22,1000,false)
    elseif officerGun[model] then
        giveWeapon(ped,officerGun[model],1000,true)
    end
end
function PedServices.crewModel(original)
    if original==227 then return 12 elseif original==194 then return 13 end
end
-- Unconditional police branches in 002B3CA0, resolved through constructor 00324D08.
local policeCrew = {[219]=8,[207]=8,[261]=8,[191]=119,[193]=10,[218]=11,[246]=11,[234]=9}
function PedServices.policeCrewModel(original)
    return policeCrew[original]
end
local medicalDispatch={}
local dispatchStarted
local function canDispatchAmbulance(dimension,now)
    if age(now,medicalDispatch[dimension] or dispatchStarted)<=30000 then return false end
    local count=0
    for i=1,20 do
        local s=accidents[i]
        if valid(s) and s.dimension==dimension and s.interior==0 then
            count=count+1
            if s.crew and isElement(s.crew) then return false end
        end
    end
    if count<2 then return false end
    local existing=0
    for _,car in ipairs(getElementsByType("vehicle")) do
        if getElementDimension(car)==dimension and (getElementData(car,"npchlc_traffic:originalModel",false)==227
            or getElementModel(car)==416) then
            existing=existing+1
            if existing>=2 then return false end
        end
    end
    return true
end
function PedServices.dispatch(x,y,z,dimension,player)
    for _,model in ipairs({12,13}) do
        local slot
        if model==13 then slot=nearest(model,x,y,z,0,dimension,100,nil,true)
        elseif canDispatchAmbulance(dimension,getTickCount()) then
            local px,py,pz=x,y,z
            if player then px,py,pz=getElementPosition(player) end
            slot=nearest(model,px,py,pz,0,dimension,nil,nil,true)
        end
        if slot then
            local vehicle=TrafficModelBindings.get(serviceModels[model])
            if vehicle and TrafficAmbient.getPedestrianModel(model) then return vehicle,serviceModels[model],1,slot end
        end
    end
end
function PedServices.linkCrew(state,slot,dispatched)
    if dispatched and slot and slot.casualty then medicalDispatch[state.dimension]=getTickCount() end
    if not slot then return end
    slot.crew=state.driver
    crews[state.driver]={slot=slot,vehicle=state.vehicle,road=state}
end
local function abandonApproach(state,job,now,resume)
    if job.slot.crew==state.driver then job.slot.crew=nil end
    crews[state.driver]=nil
    state.serviceRetryAt=now
    setVehicleSirensOn(state.vehicle,false)
    resume(state)
    return false
end
function PedServices.inVehicle(state,now,enterPhysics,resume)
    local job=crews[state.driver]
    local model=PedServices.crewModel(state.originalVehicle)
    if not model or (not job and state.serviceRetryAt and age(now,state.serviceRetryAt)<20000) then return end
    local car=state.vehicle
    if not getElementSyncer(car) then return end
    local x,y,z=getElementPosition(car)
    local slot=job and job.slot
    if not valid(slot) then
        if job and slot and slot.crew==state.driver then slot.crew=nil end
        crews[state.driver]=nil
        if job and job.driving and not state.rail then setVehicleSirensOn(car,false); resume(state) end
        slot=nearest(model,x,y,z,getElementInterior(car),state.dimension,25,nil,true)
        if not slot then return end
        PedServices.linkCrew(state,slot)
        job=crews[state.driver]
    end
    local a,b,c=position(slot)
    local distance=getDistanceBetweenPoints2D(x,y,a,b)
    if not job.driving then
        if state.rail then enterPhysics(state) end
        if state.rail then return end
        job.driving=true
        setVehicleSirensOn(car,true)
    end
    if model==12 and not job.stopping then
        if not job.route then
            -- A stopped ambulance already inside the original dismount gate
            -- can let the crew out at its present road position.
            local vx,vy,vz=getElementVelocity(car)
            if distance>=25 or vx*vx+vy*vy+vz*vz>=.01^2 then
                job.route=TrafficRoad.serviceRoute(state,a,b,c)
                if not job.route then return abandonApproach(state,job,now,resume) end
                job.index=1
            end
        end
        local point=job.route and job.route[job.index]
        local remaining=point and getDistanceBetweenPoints3D(x,y,z,unpack(point))
        if remaining and remaining>4 then
            if job.command~=point or remaining<(job.remaining or math.huge)-1 then
                job.progressAt,job.remaining=now,remaining
            elseif age(now,job.progressAt)>20000 then
                -- A blocked approach releases the incident and the road controller.
                return abandonApproach(state,job,now,resume)
            end
            if job.command~=point then
                job.command=point
                hlc:setNPCTask(state.driver,{"driveToPos",point[1],point[2],point[3],3})
            end
            return true
        elseif point and job.index<#job.route then
            job.index=job.index+1
            return true
        end
    elseif model~=12 and distance>=25 then
        if not job.driveAt or age(now,job.driveAt)>1800 and (job.x~=a or job.y~=b or job.z~=c) then
            job.driveAt,job.x,job.y,job.z=now,a,b,c
            hlc:setNPCTask(state.driver,{"driveToPos",a,b,c,12})
        end
        return true
    end
    if not job.stopping then
        setVehicleSirensOn(car,false)
        job.stopping=now
        hlc:setNPCTask(state.driver,{"stopVehicle"})
    end
    local vx,vy,vz=getElementVelocity(car)
    if age(now,job.stopping)>20000 then return abandonApproach(state,job,now,resume) end
    if distance>=25 and job.stopping then job.stopping,job.route,job.command=nil,nil,nil return true end
    if distance<25 and vx*vx+vy*vy+vz*vz<.01^2 and (not job.requested or age(now,job.requested)>=1500) then
        job.requested=now
        if model==12 then PedVoice.emit(state.driver,"arrive") end
        TrafficPassengers.requestExit(state.driver,car,0)
    end
    return true
end
function PedServices.needsParkedVehicle(road)
    local ped=road.driver
    if not isElement(ped) or isPedDead(ped) then return false end
    local crew=crews[ped]
    local brain=PedAI.brain(ped)
    return crew and crew.road==road or brain and brain.event and brain.event.road==road
end
local function releaseReservation(ped)
    local w,job=workers[ped],crews[ped]
    if job and job.slot.crew==ped then job.slot.crew=nil end
    if w and w.slot then
        w.slot.assigned=math.max(0,w.slot.assigned-1)
        if w.treating then w.slot.treating=math.max(0,w.slot.treating-1) end
    end
    workers[ped],crews[ped]=nil,nil
    return w
end
-- Script ownership can change after a mission has already assigned a task.
PedServices.relinquish=releaseReservation
local function release(ped)
    local w=releaseReservation(ped)
    if not w then return end
    if isElement(ped) and not isPedDead(ped) then
        hlc:clearNPCTasks(ped)
        if w.anim then setPedAnimation(ped) end
        hlc:setNPCWalkSpeed(ped,"walk")
    end
end
PedServices.interrupt=release
local function revive(corpse)
    if not isElement(corpse) or getElementHealth(corpse)~=0 or isPedHeadless(corpse)
        or isPedInVehicle(corpse) or not TrafficAmbient.isManagedPed(corpse) then return end
    local original=getElementData(corpse,"npchlc_traffic:originalModel",false)
    local x,y,z=getElementPosition(corpse)
    local _,_,r=getElementRotation(corpse)
    local new=createPed(getElementModel(corpse),x,y,z,r)
    if not new then return end
    setElementInterior(new,getElementInterior(corpse))
    setElementDimension(new,getElementDimension(corpse))
    TrafficModelBindings.tag(new,original)
    if not hlc:enableHLCForNPC(new,"walk") or not TrafficAmbient.adoptDriver(new,nil,nil,original,nil,1367) then
        destroyElement(new)
        return
    end
    PedAI.attach(new,original)
    if TrafficActors.isPolicePed(corpse) or original==8 then setTrafficPolicePed(new,true) end
    setPedAnimation(new,"PED","getup_front",1367,false,false,true,false)
    PedVoice.emit(new,"revived")
    destroyElement(corpse)
    return new
end
local function approach(ped,w,x,y,z,stop,now)
    if w.walkAt and age(now,w.walkAt)<1200 then return end
    w.walkAt=now
    hlc:setNPCWalkSpeed(ped,"run")
    hlc:setNPCTask(ped,{"walkToPos",x,y,z,stop})
end
local function treat(ped,w,d,now)
    local s=w.slot
    local a,b,c=position(s)
    local x,y=getElementPosition(ped)
    if w.waiting and s.treating==1 then
        s.treating,w.treating,w.waiting=0,false,false
    end
    if not w.treating then
        if s.treating>=2 then release(ped) return end
        if d>=4.5 or (d>=1 and s.treating==0) or isPedInVehicle(s.element) then
            approach(ped,w,a,b,c,.65,now)
            return
        end
        hlc:clearNPCTasks(ped)
        w.treating=true
        s.treating=s.treating+1
        PedVoice.emit(ped,"treat")
        if s.treating>1 then w.waiting=true return end
        w.aligning=true
        setPedAnimation(ped,"MEDIC","CPR",2000,false,false,true,false)
        w.anim=true
        -- 00409208 calls the write-if-expired timer with 500, then 2000
        -- on the same tick. The second write cannot extend the first deadline.
        w.started,w.deadline=now,500
    elseif w.aligning then
        local desired=-math.deg(math.atan2(a-x,b-y))
        local _,_,heading=getElementRotation(ped)
        local delta=(desired-heading+180)%360-180
        if math.abs(delta)>=45 then setPedRotation(ped,heading+delta*0.5)
        else w.aligning=false end
    elseif not w.waiting and age(now,w.started)>w.deadline then
        s.closed=true
        revive(s.element)
        release(ped)
    end
end
local function attendFire(ped,w,d,now)
    local x,y,z=position(w.slot)
    if d>=5 then approach(ped,w,x,y,z,1,now) return end
    if not w.onScene then
        hlc:clearNPCTasks(ped)
        w.onScene=now
        PedVoice.emit(ped,"fireScene")
    end
    -- The PS2 firefighter update itself only tracks the fire. Its owner or native simulation clears it.
end
local function pursueStreetPed(officer,x,y,z)
    local mask=PedAITypes[6].avoid
    local brain=PedAI.brain(officer)
    for _,target in ipairs(getElementsWithinRange(x,y,z,22,"ped",getElementInterior(officer),getElementDimension(officer)) or {}) do
        local victim=PedAI.brain(target)
        if victim and not PedAI.isScriptControlled(target) and not isPedInVehicle(target) and not isPedDead(target) then
            local t=victim.profile.pedType
            local identity=PedAITypes[t].identity
            local fleeing=victim.event and victim.event.intent=="flee" and victim.event.target
            local fromCop=isElement(fleeing) and PedAI.profile(fleeing) and PedAI.profile(fleeing).pedType==6
            if (t==18 or t>=7 and t<=15) and math.floor(mask/identity)%2==0 and (not fromCop or fleeing==officer) then
                if brain:react("serviceDuty",target,0,"fight","run",20000) then
                    victim:react("serviceDuty",officer,0,"flee","run",20000)
                    return true
                end
            end
        end
    end
end
local function pursue(ped,w,now)
    local x,y,z=getElementPosition(ped)
    local suspect=w and w.target
    if not isElement(suspect) or not TrafficWanted.officerCanPursue(ped,suspect) then
        if w then release(ped) end
        local d=50
        for _,player in ipairs(getElementsWithinRange(x,y,z,d,"player",getElementInterior(ped),getElementDimension(ped)) or {}) do
            local r=getDistanceBetweenPoints3D(x,y,z,getElementPosition(player))
            if r<d and TrafficWanted.officerCanPursue(ped,player) then d,suspect=r,player end
        end
        if not isElement(suspect) or not TrafficWanted.officerCanPursue(ped,suspect) then return pursueStreetPed(ped,x,y,z) end
        w={target=suspect}
        workers[ped]=w
    end
    if TrafficWanted.tryArrest(ped,suspect,now) then release(ped) return true end
    if not w.follow then
        w.follow=hlc:setNPCTask(ped,{"walkFollowElement",suspect,1})
        hlc:setNPCWalkSpeed(ped,"run")
    end
    return true
end
function PedServices.update(ped,model,now)
    local profile=PedAI.profile(ped)
    if not enabled or not profile then return end
    local w=workers[ped]
    if profile.pedType==6 then
        local brain=PedAI.brain(ped)
        if not w and brain.serviceScan and age(now,brain.serviceScan)<500 then return end
        brain.serviceScan=now
        return pursue(ped,w,now)
    end
    if model~=12 and model~=13 then return end
    local x,y,z=getElementPosition(ped)
    local job=crews[ped]
    if w and (not valid(w.slot) or not sameWorld(ped,w.slot)) then release(ped);w=nil end
    if not w then
        local slot=nearest(model,x,y,z,getElementInterior(ped),getElementDimension(ped),nil,job and job.vehicle)
        if not slot then
            if job then
                releaseReservation(ped)
                return PedAI.returnServiceDriver(ped,job.road)
            end
            return
        end
        w={slot=slot}
        if job then crews[ped]=job end
        workers[ped]=w
        slot.assigned=slot.assigned+1
    end
    local a,b=position(w.slot)
    local distance=getDistanceBetweenPoints2D(x,y,a,b)
    if job and not w.treating and not w.onScene then
        if not w.progressAt or distance < w.bestDistance-0.5 then
            w.progressAt,w.bestDistance=now,distance
        elseif age(now,w.progressAt)>20000 then
            job.road.serviceRetryAt=now
            release(ped)
            return PedAI.returnServiceDriver(ped,job.road)
        end
    end
    if model==12 then treat(ped,w,distance,now) else
        local nextFire=nearest(13,x,y,z,getElementInterior(ped),getElementDimension(ped))
        if nextFire~=w.slot and ((not w.onScene and distance>=5) or (w.onScene and nextFire)) then
            release(ped)
        else
            attendFire(ped,w,distance,now)
        end
    end
    if not workers[ped] and job then
        -- Reassess nearby incidents before the driver returns to the ambulance.
        crews[ped]=job
    end
    return true
end
local function noteFire(element)
    if not hasElement(fires,element,40) then insert(fires,slotFor(element),40) end
end
function PedServices.observeFire(x,y,z,dimension)
    for _,kind in ipairs({"ped","player","vehicle"}) do
        for _,e in ipairs(getElementsWithinRange(x,y,z,65,kind,0,dimension) or {}) do
            if kind=="vehicle" and getElementHealth(e)<=250 and not isVehicleBlown(e)
                or kind~="vehicle" and onFire(e) then noteFire(e) end
        end
    end
end
addEventHandler("onPedWasted",root,function() PedServices.accident(source);release(source) end)
addEventHandler("onElementDestroy",root,function()
    PedServices.relinquish(source)
end)
addEventHandler("onExplosion",root,function(x,y,z,kind)
    if enabled and kind==1 and not wasEventCancelled() and isElement(source) and getElementType(source)=="player" then
        insert(fires,{worldFire=true,x=x,y=y,z=z,interior=getElementInterior(source),
            dimension=getElementDimension(source),created=getTickCount(),assigned=0,treating=0},40)
    end
end,true,"low")
function PedServices.start(graph)
    dispatchStarted,medicalDispatch=getTickCount(),{}
    enabled=graph.edition=="SLUS-21590 USA v1.00"
    if not enabled then return end
    local cursor=0
    timer=setTimer(function()
        local players=getElementsByType("player")
        for _=1,math.min(4,#players) do
            cursor=cursor%#players+1
            local p=players[cursor]
            if getElementInterior(p)==0 then
                local x,y,z=getElementPosition(p)
                PedServices.observeFire(x,y,z,getElementDimension(p))
            end
        end
    end,500,0)
end
function PedServices.stop()
    enabled=false
    if timer and isTimer(timer) then killTimer(timer) end
    for ped in pairs(workers) do release(ped) end
    accidents,fires,crews={},{},{}
end
