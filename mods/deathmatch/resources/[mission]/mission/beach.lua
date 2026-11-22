local blue,red={0,0,255,225},{225,65,65,225}
local clinic={598,-393.42,10}
local mooring={936.2432,-404.9839,5.8728}
local helpers={}
local function distance(a,b)
    local x,y,z=getElementPosition(a)
    local bx,by,bz=getElementPosition(b)
    return getDistanceBetweenPoints3D(x,y,z,bx,by,bz)
end
local function dead(ped) return not isElement(ped) or isPedDead(ped) end
local function wreck(car) return not isElement(car) or isVehicleBlown(car) end
local function remove(e) if isElement(e) then destroyElement(e) end end
local function world(r,e)
    if not e then return end
    Mission.track(r,e)
    setElementDimension(e,r.dimension)
    setElementInterior(e,r.interior)
    return e
end
local function ped(r,id,x,y,z)
    local p=exports.npchlc_traffic:createTrafficScriptPed(id,x,y,z,r.interior,r.dimension)
    if p then
        Mission.track(r,p)
        setElementData(p,"mission:beachOwner",r.player,"broadcast","deny")
    end
    return p
end
local function vehicle(r,id,x,y,z,yaw)
    local car=world(r,exports.vcs_vehicle:createVcsVehicle(id,x,y,z,0,0,yaw or 0))
    if car then Mission.claimVehicle(r,car) end
    return car
end
local function mark(r,element,color)
    local x,y,z=getElementPosition(element)
    local m=Mission.marker(r,x,y,z+1,"arrow",1.5,color,not r.beach.returnAt)
    if m then attachElements(m,element,0,0,1.2) end
    return m
end
local function removeTarget(r,t)
    remove(t.marker)
    remove(t.actor)
    remove(t.car)
    Mission.releaseSite(r,t.key)
end
local function completeTarget(r,t)
    local b=r.beach
    removeTarget(r,t)
    b.targets[t]=nil
    if next(b.targets) then
        Mission.message(r,b.job=="bikers" and "One down! Stop another biker!" or b.job=="medic" and "Patient rescued! Get to the next patient!" or "Swimmer saved! Get to the next swimmer!")
        return
    end
    r.deadline=nil
    local level=r.level
    if Mission.finishLevel(r,0) then
        Mission.message(r,("Level %d passed!"):format(level))
        Mission.checkpointCue(r)
        b.nextWave=getTickCount()+8000
        if level%5==0 and level~=15 then b.checkpointAt=b.nextWave-4000 end
        if not wreck(b.buggy) then setElementHealth(b.buggy,1000) end
    end
end
local function nextPoint(r)
    local b=r.beach
    local sea=b.job=="swimmers"
    local points=sea and BeachPatrolData.sea or BeachPatrolData.shore
    local x,y,z=getElementPosition(r.player)
    local candidates={}
    -- The swimmer array has sixteen entries, but the SCM's exclusive upper bound is 15.
    for i=1,sea and 15 or #points do
        local p=points[i]
        local key=("beach/%s/%d"):format(sea and "sea" or "shore",i)
        if getDistanceBetweenPoints3D(x,y,z,p[1],p[2],p[3])>=50 and Mission.siteAvailable(r,key) then
            candidates[#candidates+1]={point=p,key=key}
        end
    end
    if #candidates==0 then return end
    local choice=candidates[math.random(#candidates)]
    if Mission.claimSite(r,choice.key) then return choice end
end
local function beginWave(r,now)
    local b=r.beach
    local count=math.min(r.level,b.job=="bikers" and 4 or 3)
    local batch={}
    for i=1,count do
        local t=nextPoint(r)
        if not t then
            for _,reserved in ipairs(batch) do Mission.releaseSite(r,reserved.key) end
            if not b.waiting then Mission.message(r,"Waiting for a beach patrol assignment.") end
            b.waiting,b.nextWave,r.deadline=true,now+2000,nil
            return
        end
        batch[i]=t
    end
    b.waiting=nil
    local total=0
    for _,t in ipairs(batch) do
        local p=t.point
        b.targets[t]=true
        if b.job=="bikers" then
            t.car=vehicle(r,205,p[1],p[2],p[3]+0.65,math.random(359))
            t.actor=ped(r,58,p[1],p[2],p[3]+1)
            if not t.actor or not t.car or not warpPedIntoVehicle(t.actor,t.car,0) then
                return Mission.fail(r,"The bikers could not reach the beach.")
            end
            setElementFrozen(t.car,true)
            setElementData(t.car,"mission:beachRoad",r.player,"broadcast","deny")
        else
            -- The sea coordinates in MAIN are spawn heights above the 6 m ocean.
            t.actor=ped(r,b.job=="medic" and 46 or 64,p[1],p[2],b.job=="medic" and p[3] or 5.9)
            if not t.actor then return Mission.fail(r,"A rescue target is unavailable.") end
            setElementFrozen(t.actor,true)
            if b.job=="medic" then setPedAnimation(t.actor,"CRACK","crckidle2",-1,true,false,false,false)
            else Mission.servicePose(t.actor,"oj_swim_wave") end
        end
        t.marker=mark(r,t.actor,b.job=="bikers" and red or blue)
        if not t.marker then return Mission.fail(r,"The patrol location could not be marked.") end
        total=total+math.floor(distance(r.player,t.actor)*1000/6)
    end
    local minTime=b.job=="medic" and 45000 or 60000
    local maxTime=b.job=="bikers" and 270000 or b.job=="medic" and 240000 or 180000
    r.deadline=now+math.min(maxTime,math.max(total,minTime))
    b.nextWave=nil
    Mission.message(r,b.job=="bikers" and "Knock the gang members off their bikes before they get away!" or b.job=="medic" and "Get the medic to the patients before it's too late!" or "Get to the ~b~swimmers~w~ in trouble before they drown!")
end
local function depot(r,kind)
    for i=0,31 do
        if Mission.claimSite(r,"beach/depot/"..kind.."/"..i) then return i*8 end
    end
end
local function prepareDepot(r,now)
    local b=r.beach
    local shift=depot(r,b.job)
    if not shift then
        if not b.awaitDepot then Mission.message(r,"Waiting for a beach patrol vehicle.") end
        b.awaitDepot=now+2000
        return
    end
    b.awaitDepot=nil
    if b.job=="medic" then
        b.ambulance=vehicle(r,227,clinic[1]+shift,clinic[2],clinic[3]+0.6,0)
        b.helper=ped(r,12,601.87+shift,-395.84,10.5)
        if not b.ambulance or not b.helper then return Mission.fail(r,"The paramedic is unavailable.") end
        setElementFrozen(b.ambulance,true)
        setElementFrozen(b.helper,true)
        b.pickup=mark(r,b.helper,blue)
        Mission.message(r,"The ambulance is stuck. Collect the paramedic!")
    else
        b.boat=vehicle(r,277,mooring[1],mooring[2]+shift,mooring[3],248.2955)
        b.helper=ped(r,65,mooring[1],mooring[2]+shift,mooring[3]+1.5)
        if not b.boat or not b.helper then return Mission.fail(r,"The patrol boat is unavailable.") end
        attachElements(b.helper,b.boat,0,1.5,1.5)
        setElementCollisionsEnabled(b.helper,false)
        b.pickup=mark(r,b.boat,blue)
        Mission.message(r,"Swimmers are in trouble. Get to the patrol boat!")
    end
    helpers[b.helper]=r
    if not b.pickup then Mission.fail(r,"The patrol pickup could not be marked.") end
end

local function start(r,now)
    local b={buggy=r.vehicle,targets={},job=({"bikers","swimmers","medic"})[math.random(3)]}
    r.beach=b
    if b.job=="bikers" then beginWave(r,now) else prepareDepot(r,now) end
end

local function board(r,now)
    local b=r.beach
    if exports.npchlc_traffic:isMissionPedSeated(b.helper,b.buggy,1) then b.boardAt=nil return true end
    if (not b.boardAt or now>=b.boardAt) and distance(b.helper,b.buggy)<14 then
        setElementFrozen(b.helper,false)
        exports.npchlc_traffic:assignTrafficPedObjective(b.helper,"enterVehicle",b.buggy,1)
        b.boardAt=now+1500
    end
    return false
end
local function treat(r,now)
    local b=r.beach
    local t=b.patient
    if t then
        if getPedOccupiedVehicle(b.helper) then return end
        if not b.walking then
            local x,y,z=getElementPosition(t.actor)
            exports.npchlc_traffic:assignTrafficPedObjective(b.helper,"walk",x+0.7,y,z,"run")
            b.walking=true
        end
        if distance(b.helper,t.actor)<2.5 then
            if not b.cpr then
                exports.npchlc_traffic:assignTrafficPedObjective(b.helper,"clear")
                setPedAnimation(b.helper,"MEDIC","CPR",-1,true,false,false,false)
                b.cpr=now
            elseif now-b.cpr>=4000 then
                setPedAnimation(b.helper)
                b.cpr,b.walking,b.patient=nil,nil,nil
                completeTarget(r,t)
            end
        end
        return
    end
    if not board(r,now) then return end
    local vx,vy,vz=getElementVelocity(b.buggy)
    if vx*vx+vy*vy+vz*vz>=(2/50)^2 then return end
    for target in pairs(b.targets) do
        if distance(b.helper,target.actor)<10 and exports.npchlc_traffic:assignTrafficPedObjective(b.helper,"exitVehicle") then
            b.patient=target
            return
        end
    end
end
local function steer(t)
    local x,y,z=getElementPosition(t.car)
    if t.to and getDistanceBetweenPoints3D(x,y,z,unpack(t.to))>5 then return end
    local nearby={}
    for _,p in ipairs(BeachPatrolData.shore) do
        local d=getDistanceBetweenPoints3D(x,y,z,unpack(p))
        if d>5 and d<255 then nearby[#nearby+1]=p end
    end
    if #nearby>0 then
        t.to=nearby[math.random(#nearby)]
        exports.npc_hlc:setNPCDriveSpeed(t.actor,30/50)
        exports.npc_hlc:setNPCTask(t.actor,{"driveToPos",t.to[1],t.to[2],t.to[3],5})
    end
end
addEvent("mission:beachRoad",true)
addEventHandler("mission:beachRoad",resourceRoot,function(token,car,z)
    local r=client and Mission.forParticipant(client,token,"beachpatrol")
    if source~=resourceRoot or not r or client~=r.player or type(z)~="number" or z~=z then return end
    for t in pairs(r.beach.targets) do
        if t.car==car and isElement(car) and not t.ready and math.abs(z-t.point[3])<=7 and distance(client,car)<200 then
            setElementPosition(car,t.point[1],t.point[2],z+0.8)
            setElementData(car,"mission:beachRoad",false)
            setElementFrozen(car,false)
            t.ready=true
            steer(t)
            return
        end
    end
end,false)
local function throwRing(r,side,now)
    local b=r.beach
    if b.job~="swimmers" or b.pickup or b.nextWave or b.throw or Mission.driverOf(b.boat)~=r.player then return end
    local ring=world(r,createObject(1271,getElementPosition(b.helper)))
    if not ring then return end
    setElementAlpha(ring,0)
    setElementCollisionsEnabled(ring,false)
    setElementData(ring,"mission:throwSide",side,"broadcast","deny")
    setElementData(ring,"mission:attachmentModel",7375,"broadcast","deny")
    attachElements(ring,b.helper,0,0.45,0.4)
    Mission.servicePose(b.helper,side==-1 and "amb_ls_thw_floatl" or "amb_ls_thw_float")
    b.throw={ring=ring,at=now,side=side}
end
addEvent("mission:throwPreserver",true)
addEventHandler("mission:throwPreserver",resourceRoot,function(token,side)
    local r=client and Mission.forParticipant(client,token,"beachpatrol")
    if source==resourceRoot and r and client==r.player and (side==-1 or side==1) and r.beach and isElement(r.beach.boat) then
        throwRing(r,side,getTickCount())
    end
end,false)
local function swimmerTick(r,now)
    local b=r.beach
    local flight=b.throw
    if not b.throwHelp then
        for t in pairs(b.targets) do
            if distance(t.actor,b.boat)<30 then
                Mission.notify(r,"mission:help",r.token,"Hold vehicle look left or right to aim, then press vehicle fire to throw a life preserver.",6500)
                b.throwHelp=true
                break
            end
        end
    end
    if not flight then return end
    if not isElement(flight.ring) then b.throw=nil return end
    local elapsed=now-flight.at-700
    if elapsed<0 then return end
    if not flight.origin then
        detachElements(flight.ring)
        local x,y,z=getElementPosition(b.helper)
        local _,_,yaw=getElementRotation(b.boat)
        flight.origin={x+flight.side,y,z+0.5}
        flight.dx,flight.dy=math.cos(math.rad(yaw))*flight.side,math.sin(math.rad(yaw))*flight.side
        local near=false
        for t in pairs(b.targets) do
            if distance(t.actor,b.boat)<10 then near=true break end
        end
        -- SCM 0229 / SLUS 0030FA30 applies the 15/1 or 30/4 m/s impulse.
        flight.speed,flight.vz=near and 15 or 30,near and 1 or 4
        flight.waterAt=(flight.vz+math.sqrt(flight.vz^2+40*math.max(0,flight.origin[3]-6.1)))/20
        setElementPosition(flight.ring,unpack(flight.origin))
        setElementData(flight.ring,"mission:preserverFlight",{
            x=flight.origin[1],y=flight.origin[2],z=flight.origin[3],
            vx=flight.dx*flight.speed,vy=flight.dy*flight.speed,vz=flight.vz,
            gravity=20,waterAt=flight.waterAt,start=flight.at+700,age=elapsed,side=flight.side
        },"broadcast","deny")
    end
    local travel=math.min(flight.waterAt,elapsed/1000)
    local x=flight.origin[1]+flight.dx*flight.speed*travel
    local y=flight.origin[2]+flight.dy*flight.speed*travel
    local z=flight.origin[3]+flight.vz*travel-10*travel^2
    -- BEACHPL_18446 resolves splashes; BEACHPL_17666 also checks a stalled ring.
    local inWater=elapsed/1000>=flight.waterAt
    if not inWater and elapsed<=3000 then return end
    for t in pairs(b.targets) do
        local sx,sy,sz=getElementPosition(t.actor)
        local dx,dy=math.abs(x-sx),math.abs(y-sy)
        if (inWater and dx<=10 and dy<=10 and math.abs(z-sz)<=20)
            or (elapsed>3000 and dx<=3 and dy<=3) then
            remove(flight.ring)
            b.throw=nil
            completeTarget(r,t)
            return
        end
    end
    remove(flight.ring)
    b.throw=nil
end

local function patrolBlips(b,visible)
    if b.pickup then exports.marker:setMarkerBlipVisible(b.pickup,visible) end
    for t in pairs(b.targets) do
        if isElement(t.marker) then exports.marker:setMarkerBlipVisible(t.marker,visible) end
    end
end

local function tick(r,now)
    local b=r.beach
    if wreck(b.buggy) or (isElementInWater(b.buggy) and not b.atSea) then return Mission.fail(r,"You wrecked the patrol buggy!") end
    if b.awaitDepot then
        if now>=b.awaitDepot then prepareDepot(r,now) end
        return
    end
    if b.helper and dead(b.helper) then return Mission.fail(r,b.job=="medic" and "The paramedic is dead!" or "The lifeguard is dead!") end
    if b.job=="swimmers" then
        if wreck(b.boat) then return Mission.fail(r,"You destroyed the boat!") end
        if getElementAttachedTo(b.helper)~=b.boat then return Mission.fail(r,"The lifeguard is out of the boat!") end
    end
    local current=getPedOccupiedVehicle(r.player)
    local aboard=(current==b.buggy and not b.atSea or b.job=="swimmers" and current==b.boat) and Mission.driverOf(current)==r.player
    if not aboard then
        if not b.returnAt then
            b.returnAt=now+30000
            patrolBlips(b,false)
            Mission.showReturnVehicle(r,b.job=="swimmers" and b.boat or b.buggy)
            Mission.message(r,"You have 30 seconds to get back in the patrol vehicle!")
        end
        if now>=b.returnAt then return Mission.fail(r,"You didn't get back in the patrol vehicle in time!") end
    elseif b.returnAt then
        Mission.clearReturnVehicle(r)
        patrolBlips(b,true)
        b.returnAt=nil
    end
    if b.pickup then
        local ready=b.job=="medic" and aboard and board(r,now)
            or b.job=="swimmers" and current==b.boat and aboard
        if ready then
            if b.job=="swimmers" then
                b.atSea=true
            end
            remove(b.pickup)
            b.pickup=nil
            beginWave(r,now)
        end
        return
    end
    if b.nextWave then
        if b.checkpointAt and now>=b.checkpointAt then
            b.checkpointAt=nil
            Mission.checkpointCue(r)
        end
        if now>=b.nextWave then beginWave(r,now) end
        return
    end
    for t in pairs(b.targets) do
        if b.job=="bikers" then
            if dead(t.actor) or wreck(t.car) or getVehicleOccupant(t.car,0)~=t.actor then
                if not t.fellAt or now-t.fellAt>=1200 then
                    completeTarget(r,t)
                    return
                end
            elseif t.ready then steer(t) end
        elseif dead(t.actor) then
            return Mission.fail(r,b.job=="medic" and "One of the patients is dead!" or "One of the swimmers died!")
        end
    end
    if b.job=="medic" and aboard then treat(r,now)
    elseif b.job=="swimmers" and (aboard or b.throw) then swimmerTick(r,now) end
end

addEventHandler("onPedDamage",root,function(attacker)
    local r=helpers[source]
    if not r or not isElement(attacker) then return end
    if getElementType(attacker)=="vehicle" then attacker=getVehicleController(attacker) end
    if r.player==attacker then Mission.fail(r,"You attacked a member of the rescue crew!") end
end)
addEvent("mission:beachBikeHit",true)
addEventHandler("mission:beachBikeHit",resourceRoot,function(token,bike)
    local r=client and Mission.forParticipant(client,token,"beachpatrol")
    if source~=resourceRoot or not r or r.player~=client or r.beach.job~="bikers"
        or Mission.driverOf(r.vehicle)~=client or not isElement(bike)
        or distance(r.vehicle,bike)>9 then return end
    for t in pairs(r.beach.targets) do
        if t.car==bike and t.ready and not t.fellAt and getVehicleOccupant(bike,0)==t.actor then
            local vx,vy,vz=getElementVelocity(r.vehicle)
            exports.npc_hlc:clearNPCTasks(t.actor)
            if removePedFromVehicle(t.actor) then
                t.fellAt=getTickCount()
                local x,y,z=getElementPosition(bike)
                setElementPosition(t.actor,x,y,z+0.7)
                setPedAnimation(t.actor,"PED","BIKE_fall_off",1200,false,false,false,true)
                setElementVelocity(t.actor,vx*0.7,vy*0.7,math.max(vz,0.12))
            end
            return
        end
    end
end,false)
Mission.register("beachpatrol",{title="Beach Patrol",models={255},start=start,tick=tick,stop=function(r)
    if r.beach and r.beach.helper then helpers[r.beach.helper]=nil end
end,timeout="You ran out of time!"})
