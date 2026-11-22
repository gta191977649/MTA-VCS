local setFire = setElementOnFire or setPedOnFire
-- Generic SCM-style ownership. The resource which acquired the actor owns its
-- orders until release or resource stop. Ordinary street actors stay in their pool.
local owned = {}
local boarding, seated = {}, {}
addEventHandler("onVehicleEnter",root,function(ped,seat)
    if owned[ped] then seated[ped]={car=source,seat=seat} end
end)
addEventHandler("onVehicleExit",root,function(ped)
    if seated[ped] and seated[ped].car==source then seated[ped]=nil end
end)

-- MTA can report the reserved seat before the entry animation finishes.
function isMissionPedSeated(ped,car,seat)
    local record=seated[ped]
    return record~=nil and record.car==car and isElement(car) and (seat==nil or record.seat==seat)
        and getPedOccupiedVehicle(ped)==car and getVehicleOccupant(car,record.seat)==ped
end
local function cancelBoarding(ped)
    local job = boarding[ped]
    if not job then return end
    boarding[ped] = nil
    if isElement(ped) and job.requested and not isMissionPedSeated(ped,job.car) then
        if getPedOccupiedVehicle(ped)==job.car then removePedFromVehicle(ped) end
        local syncer = getElementSyncer(ped)
        if syncer then triggerClientEvent(syncer,"npchlc_traffic:cancelMissionEntry",resourceRoot,ped) end
    end
end

local function reserved(car, seat, except)
    for ped, job in pairs(boarding) do
        if ped ~= except and job.car == car and job.seat == seat then return true end
    end
    return false
end

addEventHandler("onVehicleStartEnter",root,function(ped,seat)
    if reserved(source,seat,ped) then cancelEvent() end
end)
local hlc = exports.npc_hlc
local function finite(v) return type(v)=="number" and math.abs(v)<math.huge end
local function sameWorld(a,b)
    return isElement(a) and isElement(b) and getElementInterior(a)==getElementInterior(b)
        and getElementDimension(a)==getElementDimension(b)
end

local function acquire(ped,owner)
    local brain = PedAI.brain(ped)
    if not owner or not brain or isPedDead(ped) or brain.burning then return false end
    if brain.scriptOwner then return brain.scriptOwner == owner end
    if getElementData(ped,TrafficVisibility.retiringKey,false) then return false end
    brain.beforeScript = brain.event and brain.event.intent == "flee" and brain.event or nil
    if brain.beforeScript then brain.beforeScript.task=nil end
    brain.scriptOwner,owned[ped] = owner,brain
    if PedServices then PedServices.interrupt(ped) end
    TrafficAmbient.suspend(ped)
    PedSpecial.interrupt(ped)
    PedVehicleEvasion.cancel(ped)
    brain.tasks:clear(true)
    brain.objectives:clear()
    PedCarjack.cancelExtraction(ped, brain.event)
    brain.event = nil
    if TrafficRoad.driverScriptChanged then TrafficRoad.driverScriptChanged(ped,true) end
    return true
end

function acquireTrafficPed(ped) return acquire(ped,sourceResource) end

function acquireMissionTrafficDriver(ped)
    if not isElement(ped) then return false end
    local brain = PedAI.brain(ped)
    if not brain or brain.scriptOwner then return false end
    local car = getPedOccupiedVehicle(ped)
    return car and TrafficRoad.isDriving(ped,car) and acquire(ped,sourceResource) or false
end

-- The PS2 pool scans high slots first (01C4). MTA has no pool index API,
-- so the allocator serial determines order among eligible streamed actors.
function acquireTrafficPedInArea(x1,y1,x2,y2,z,interior,dimension,civilians,gangs,special,previous)
    if not (finite(x1) and finite(x2) and finite(y1) and finite(y2) and finite(z)
        and finite(interior) and finite(dimension)) then return false end
    local x,y = (x1+x2)/2,(y1+y2)/2
    local radius = math.sqrt((x2-x)^2+(y2-y)^2+25)
    local best
    for _,ped in ipairs(getElementsWithinRange(x,y,z,radius,"ped",interior,dimension) or {}) do
        local brain = PedAI.brain(ped)
        if brain and not brain.scriptOwner and ped ~= previous and not isPedInVehicle(ped) and not isPedDead(ped)
            and not brain.wait and not PedAI.busy(ped) and not PedActivity.active(ped)
            and not TrafficAmbient.isWaiting(ped) then
            local px,py,pz = getElementPosition(ped)
            local group = brain.profile.pedType
            if px>=math.min(x1,x2) and px<=math.max(x1,x2) and py>=math.min(y1,y2) and py<=math.max(y1,y2)
                and math.abs(pz-z)<=5 and (civilians and (group==4 or group==5) or gangs and group>=7 and group<=15
                or special and (group==18 or group==20)) and (not best or brain.poolSlot>best.poolSlot) then best=brain end
        end
    end
    return best and acquireTrafficPed(best.ped) and best.ped or false
end

function createTrafficScriptPed(original,x,y,z,interior,dimension)
    local owner = sourceResource
    local model = PedAIModels[original] and TrafficAmbient.getPedestrianModel(original)
    if not owner then return false,"Missing owning resource" end
    if not model then return false,"Missing VCS model binding" end
    if not PedAI.graph then return false,"Traffic graph is loading" end
    if not (finite(x) and finite(y) and finite(z))
        or not (finite(interior or 0) and finite(dimension or 0)) then return false end
    local ped = createPed(model,x,y,z)
    if not ped then return false end
    -- Native setters may defer their return when the element already has the
    -- requested world. Validate the resulting world before adopting the actor.
    setElementInterior(ped,interior or 0)
    setElementDimension(ped,dimension or 0)
    if getElementInterior(ped)~=(interior or 0) or getElementDimension(ped)~=(dimension or 0) then
        destroyElement(ped)
        return false,"Invalid mission interior or dimension"
    end
    if not hlc:enableHLCForNPC(ped,"walk") then destroyElement(ped) return false,"HLC enrollment failed" end
    TrafficModelBindings.tag(ped,original,true)
    PedAI.attach(ped,original)
    if not TrafficAmbient.adoptDriver(ped,nil,nil,original) or not acquire(ped,owner) then
        destroyElement(ped)
        return false,"Mission actor adoption failed"
    end
    return ped
end

local function release(brain)
    local ped = brain.ped
    cancelBoarding(ped)
    owned[ped],seated[ped],brain.scriptOwner = nil,nil,nil
    if not isElement(ped) then return end
    TrafficActors.endMissionPath(ped)
    if brain.burning then
        setFire(ped,false)
        PedSpecial.cancel(ped)
        brain.burning,brain.wait,brain.objectives.body=nil,nil,1
    end
    brain.tasks:clear(true)
    brain.objectives:clear()
    if not isPedDead(ped) then
        setElementHealth(ped,100)
        brain.health,brain.sampled = getElementHealth(ped),getTickCount()
        local previous = brain.beforeScript
        if previous and (previous.origin or sameWorld(ped,previous.target)) then
            brain.event = previous
            brain.objectives:request(previous)
        end
    end
    brain.beforeScript = nil
    if brain.profile.pedType == 20 and PedCarService then PedCarService.scriptReleased(ped) end
    if TrafficRoad.driverScriptChanged then TrafficRoad.driverScriptChanged(ped,false) end
end

function releaseTrafficPed(ped)
    local brain = owned[ped]
    if not brain or brain.scriptOwner ~= sourceResource then return false end
    release(brain)
    return true
end

function assignTrafficPedObjective(ped,order,target,y,z,pace)
    local brain = owned[ped]
    if not brain or brain.scriptOwner ~= sourceResource or isPedDead(ped) then return false end
    if order == "cashEligible" then
        if type(target) ~= "boolean" then return false end
        brain.dropCash = target
        return true
    end
    if order == "extinguish" then return setFire(ped,false) end
    if order == "ignite" then
        if isPedInVehicle(ped) or brain.burning or not setFire(ped,true) then return false end
        PedSpecial.observeFire(brain,true)
        return true
    end
    if brain.burning then return false end
    if order == "clear" then
        cancelBoarding(ped)
        TrafficActors.endMissionPath(ped)
        brain.objectives:clear()
        brain.tasks:clear(true)
        return true
    end
    local job = {order=order,target=target,started=getTickCount()}
    if order == "enterVehicle" then
        local old = boarding[ped]
        if old and old.car == target and old.seat == y then return true end
        if not sameWorld(ped,target) or getElementType(target) ~= "vehicle" or isVehicleBlown(target)
            or not finite(y) or y % 1 ~= 0 or y < 0 or y > (getVehicleMaxPassengers(target) or 0)
            or isPedInVehicle(ped) or getVehicleOccupant(target,y) or reserved(target,y,ped) then return false end

        job.id, job.car, job.seat = y == 0 and 0x12 or 0x11,target,y
        brain.objectives:clear()
    elseif order == "waitInCar" or order == "exitVehicle" then
        local car = getPedOccupiedVehicle(ped)
        if not isElement(car) then return false end
        job.vehicle,job.target=car,nil
        if order=="waitInCar" then
            if not finite(target) or target<0 or target>=2147483648 then return false end
            job.id,job.duration=7,target
        else
            job.id=0x10
        end
    elseif order == "walk" then
        if not finite(target) or not finite(y) or not finite(z) or pace and pace~="walk" and pace~="run" then return false end
        job.origin,job.target,job.id,job.pace = {target,y,z},nil,0x18,pace or "walk"
    elseif order == "attack" or order == "follow" or order == "flee" then
        if not sameWorld(ped,target) or target == ped then return false end
        local kind = getElementType(target)
        if kind ~= "ped" and kind ~= "player" or isPedDead(target) then return false end
        job.id = order == "attack" and 8 or order == "follow" and 0x0C or 10
    else return false end
    if isPedInVehicle(ped) and not job.vehicle and not (brain.objectives.current and brain.objectives.current.id == 0x10) then return false end
    if not brain.objectives:request(job) then return false end
    if brain.objectives.current == job then
        TrafficActors.endMissionPath(ped)
        cancelBoarding(ped)
        brain.tasks:clear()
        if order == "enterVehicle" then boarding[ped] = job end
    end
    return true
end

local function execute(brain,graph,now)
    local ped = brain.ped
    if isPedDead(ped) then release(brain) return end
    if PedSpecial.update(ped,graph) then return end
    local job = brain.objectives.current
    if not job then return end
    if job.order == "enterVehicle" then
        local car, seat = job.car,job.seat
        local aboard = getPedOccupiedVehicle(ped)
        local confirmed = isMissionPedSeated(ped,car)
        local occupant = isElement(car) and getVehicleOccupant(car,seat)
        if confirmed or (aboard and aboard~=car) or not sameWorld(ped,car) or isVehicleBlown(car)
            or (occupant and occupant~=ped) or (now-job.started)%4294967296 >= 20000 then
            -- Native passenger entry chooses the nearest accessible door.
            -- Reconcile a free reserved seat only after the entry animation finishes.
            if confirmed and getPedOccupiedVehicleSeat(ped) ~= seat and not occupant then
                warpPedIntoVehicle(ped,car,seat)
            end
            cancelBoarding(ped)
            brain.tasks:clear(true)
            brain.objectives:complete()
        else
            local cx,cy,cz=getElementPosition(car)
            local px,py,pz=getElementPosition(ped)
            local distance=getDistanceBetweenPoints3D(cx,cy,cz,px,py,pz)
            -- Let the native enter-car task route around the body and open the
            -- door. Walking straight to the far door competes with that task.
            if distance>9.5 and not aboard then
                if not job.walkX or (cx-job.walkX)^2+(cy-job.walkY)^2>1 then
                    hlc:setNPCWalkSpeed(ped,"run")
                    hlc:setNPCTask(ped,{"walkTrafficToPoint",cx,cy,cz,4})
                    job.walkX,job.walkY=cx,cy
                end
                job.firstRequest,job.requested=nil,nil
                return
            end
            if job.walkX then
                brain.tasks:clear(true)
                job.walkX,job.walkY=nil,nil
            end

            -- Timed passenger entry for inaccessible seats (e.g. ambulance rear).
            -- Only finish beside a stopped vehicle, after giving native entry time.
            if seat>0 and job.firstRequest and (now-job.firstRequest)%4294967296>=(aboard and 9500 or 4500)
                and distance<=3.8 and math.abs(pz-cz)<1.8 and not isVehicleLocked(car) then
                local vx,vy,vz=getElementVelocity(car)
                if vx*vx+vy*vy+vz*vz<0.0004 then
                    if aboard==car then removePedFromVehicle(ped) end
                    if not getVehicleOccupant(car,seat) and warpPedIntoVehicle(ped,car,seat) then return end
                end
            end
            if aboard then return end
            local syncer=getElementSyncer(ped)
            if syncer and (syncer~=job.syncer or not job.requested or (now-job.requested)%4294967296>=1800) then
                triggerClientEvent(syncer,"npchlc_traffic:missionEntry",resourceRoot,ped,car,seat)
                job.firstRequest,job.requested,job.syncer=job.firstRequest or now,now,syncer
            end
        end
        return
    end
    if job.vehicle then
        if getPedOccupiedVehicle(ped) ~= job.vehicle then
            brain.objectives:complete()
        elseif job.order == "waitInCar" then
            brain.objectives.body = 0x37
            if job.duration > 0 and (now-job.started)%4294967296 > job.duration then brain.objectives:complete() end
        elseif not job.requested or (now-job.requested)%4294967296 >= 1500 then
            job.requested = now
            TrafficPassengers.requestExit(ped,job.vehicle,getPedOccupiedVehicleSeat(ped))
        end
        return
    end
    if job.target and (not sameWorld(ped,job.target) or isPedDead(job.target)) or isPedInVehicle(ped) then
        brain.objectives:complete()
        brain.tasks:clear(true)
        return
    end
    if job.order == "attack" then
        job.intent = "fight"
        brain.tasks:execute(graph,job,now)
    elseif job.order == "flee" then
        brain.tasks:flee(graph,job,now)
    elseif job.order == "walk" then
        local x,y,z = getElementPosition(ped)
        local pos = job.origin
        if getDistanceBetweenPoints3D(x,y,z,pos[1],pos[2],pos[3]) < 1.25 then
            brain.tasks:clear(true)
            brain.objectives:complete()
        elseif not job.task then
            hlc:setNPCWalkSpeed(ped,job.pace)
            job.task = hlc:setNPCTask(ped,{"walkTrafficToPoint",pos[1],pos[2],pos[3],1})
        end
    elseif job.order == "follow" and not job.task then
        hlc:setNPCWalkSpeed(ped,"walk")
        job.task = hlc:setNPCTask(ped,{"walkFollowElement",job.target,1.7})
    end
end

setTimer(function()
    local now = getTickCount()
    for _,brain in pairs(owned) do execute(brain,PedAI.graph,now) end
end,150,0)
addEventHandler("onResourceStop",root,function(stopped)
    for _,brain in pairs(owned) do if brain.scriptOwner == stopped then release(brain) end end
end)
addEventHandler("onElementDestroy",root,function()
    boarding[source],owned[source],seated[source] = nil,nil,nil
    for ped,job in pairs(boarding) do
        if job.car == source then cancelBoarding(ped) end
    end
end)
