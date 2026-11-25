-- Existing traffic exports forward to the server authority.
TrafficWanted = {}
local responseByPlayer, responseByLevel = {}, {}
function TrafficWanted.getPoliceResponse(level, player)
    if not player then
        if not responseByLevel[level] then responseByLevel[level] = exports.wanted:getWantedResponseForLevel(level) end
        return responseByLevel[level]
    end
    local entry = responseByPlayer[player]
    if not entry or entry.level ~= level then
        local response = exports.wanted:getPlayerPoliceResponse(player)
        if not response then return false end
        entry = {level=level, response=response}
        responseByPlayer[player] = entry
    end
    return entry.response
end
local function forgetResponse() responseByPlayer[source] = nil end
addEventHandler("onPlayerPoliceResponseChange", root, forgetResponse)
addEventHandler("onPlayerQuit", root, forgetResponse)
addEventHandler("onResourceStop", root, function(resource)
    if getResourceName(resource) == "wanted" then responseByPlayer, responseByLevel = {}, {} end
end)
TrafficWantedRules = {getPoliceResponse = TrafficWanted.getPoliceResponse}
function setPlayerWanted(...) return exports.wanted:setPlayerWanted(...) end
function getPlayerWanted(...) return exports.wanted:getPlayerWanted(...) end
function reportWantedCrime(...) return exports.wanted:reportWantedCrime(...) end
function suspendPlayerWanted(...) return exports.wanted:suspendPlayerWanted(...) end

function isWantedPoliceNearby(player, range)
    return TrafficActors.isPoliceNearby(player, range)
end
addEventHandler("onResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == "wanted" then
        exports.wanted:registerPolicePresenceProvider()
    end
end)
local function isPlayer(element)
    return isElement(element) and getElementType(element) == "player"
end
-- 0x002C6460 and 0x002C7C28 submit an additional firearm hit report after
-- the general damage report in 0x001D7940. MTA only exposes full attribution
-- for a ped on the server when the damage was fatal.
addEventHandler("onPedWasted", root, function(_, killer, weapon)
    local victim = source
    if type(weapon) ~= "number" or not isPlayer(killer)
        or not TrafficActors.isManagedPed(victim)
        or getElementInterior(killer) ~= getElementInterior(victim)
        or getElementDimension(killer) ~= getElementDimension(victim) then
        return
    end

    local police = TrafficActors.isPolicePed(victim)
    local immediate = isWantedPoliceNearby(killer, 14) == true
    if police and not immediate then
        local x, y, z = getElementPosition(killer)
        local vx, vy, vz = getElementPosition(victim)
        local dx, dy, dz = x - vx, y - vy, z - vz
        immediate = dx * dx + dy * dy + dz * dz < 14 * 14
    end
    PedAIRules.reportPlayerStrike(killer, victim, police, weapon, immediate)
end)

local entering, arrests, restrained = {}, {}, {}
addEvent("onTrafficPlayerArrest",false)
addEventHandler("onVehicleStartEnter",root,function(p,seat)
    if getElementType(p)=="player" and seat==0 then entering[p]={vehicle=source,at=getTickCount()} end
end)
addEventHandler("onVehicleEnter",root,function(p) entering[p]=nil end)
addEventHandler("onPlayerQuit",root,function() entering[source]=nil; arrests[source]=nil; restrained[source]=nil end)

-- The game mode owns the player control state. It can report its native
-- equivalent of 0x41 while retaining authority over jail or release.
function setTrafficPlayerRestrained(player,active)
    if not isPlayer(player) or type(active)~="boolean" then return false end
    restrained[player]=active or nil
    return true
end
addEventHandler("onPlayerSpawn",root,function() restrained[source],entering[source]=nil,nil end)
local function eligibleOfficer(officer,player,allowWasted)
    if TrafficCustody.isActive(player) or not isElement(player) or getElementType(player)~="player" or (isPedDead(player) and not allowWasted)
        or not isElement(officer) or not TrafficActors.isPolicePed(officer) or isPedDead(officer)
        or getPlayerWantedLevel(player)==0 or getElementInterior(officer)~=getElementInterior(player)
        or getElementDimension(officer)~=getElementDimension(player) then return false end
    local x,y,z=getElementPosition(officer)
    return getDistanceBetweenPoints3D(x,y,z,getElementPosition(player))<=65
end
function TrafficWanted.officerCanPursue(officer,player)
    if not eligibleOfficer(officer,player,false) then return false end
    local response = TrafficWanted.getPoliceResponse(getPlayerWantedLevel(player), player)
    return response and (restrained[player] or not (response.suppressPolice or response.suppressGarage)) or false
end
local function arrest(officer,player,now,wasted,seatedDriver)
    if not eligibleOfficer(officer,player,wasted) then return false end
    local entry=entering[player]
    local x,y,z=getElementPosition(player)
    local officerDistance=getDistanceBetweenPoints3D(x,y,z,getElementPosition(officer))
    local duringEntry=entry and isElement(entry.vehicle) and (now-entry.at)%4294967296<=1800
        and not isPedInVehicle(player) and getDistanceBetweenPoints3D(x,y,z,getElementPosition(entry.vehicle))<=4
    if not (seatedDriver or (wasted or restrained[player]) and officerDistance<5 or duringEntry and officerDistance<1.3) then return false end
    if arrests[player] then return false end
    arrests[player]=officer
    local level=getPlayerWantedLevel(player)
    -- The game mode may cancel this event and process the arrest itself.
    local accepted=triggerEvent("onTrafficPlayerArrest",player,officer,level,wasted and "wasted" or "alive")
    arrests[player],entering[player]=nil,nil
    if not accepted or not isElement(player) or not isElement(officer) then return false end
    restrained[player]=nil
    if not wasted and not TrafficCustody.begin(player,level,officer) then return false end
    local ox,oy=getElementPosition(officer)
    setPedRotation(officer,-math.deg(math.atan2(x-ox,y-oy)))
    if getPedWeapon(officer,2)==22 then setPedWeaponSlot(officer,2) end
    if seatedDriver then
        setPedAnimation(officer)
        setElementData(officer,"npchlc_traffic:seatedArrestAim",player,"broadcast","deny")
    else
        setPedAnimation(officer,"PED","ARRESTgun",wasted and 1200 or -1,false,false,false,not wasted)
    end
    PedVoice.emit(officer,"arrest")
    PedVoice.emit(player,"arrested")
    return true
end

-- Door-open callback 002FD098 / seat resolver 003EF018. When the resolved
-- suspect is the driver the PS2 returns before starting the drag-out task.
local openingDoors={}
function TrafficWanted.driverArrestCar(officer,player)
    local car=getPedOccupiedVehicle(player)
    if not car or getVehicleOccupant(car,0)~=player or isPedInVehicle(officer) or isVehicleLocked(car) then return false end
    local kind=getVehicleType(car)
    if kind~="Automobile" and kind~="Monster Truck" and kind~="Bike" and kind~="Quad" and kind~="BMX" then return false end
    local vx,vy,vz=getElementVelocity(car)
    return vx*vx+vy*vy+vz*vz<0.05^2 and car
end

-- Objective 8, 00100BA0. The shot and recovery deadlines belong to the
-- officer. The sync owner may change while the officer is recovering.
local vehicleFireClocks=setmetatable({}, {__mode="k"})
function TrafficWanted.vehicleFireDue(officer,player,car,range,now,seekRadius)
    local x,y,z=getElementPosition(officer)
    local tx,ty,tz=getElementPosition(player)
    local distance=getDistanceBetweenPoints3D(x,y,z,tx,ty,tz)
    if distance<=3 or distance>=range then return false end
    local clock=vehicleFireClocks[officer]
    if clock then
        local elapsed=(now-clock.start)%4294967296
        if elapsed<=clock.burst then return true end
        if elapsed<=clock.recover then return false end
    end
    local burst=math.random(500,1999)
    local vx,vy=getElementVelocity(car)
    local speed=math.sqrt(vx*vx+vy*vy)
    local delay
    if speed>.2 then
        local cx,cy=getElementPosition(car)
        local dx,dy=x-cx,y-cy
        local length=math.sqrt(dx*dx+dy*dy)
        local projection=length>0 and (vx*dx+vy*dy)/(speed*length) or vx/speed
        delay=projection>.8 and math.random(200,499) or 0
    else
        delay=distance>(seekRadius or .5) and math.random(2000,4999) or math.random(200,499)
    end
    vehicleFireClocks[officer]={start=now,burst=burst,recover=burst+delay}
    return true
end

function TrafficWanted.driverDoorApproach(car)
    local left,_,_,_,front=exports.server_coldata:getModelBoundingBox(getElementModel(car))
    if left then return left-.55,front*.2 end
end

local function atDriverDoor(officer,car)
    local x,y,z=getElementPosition(officer)
    local cx,cy,cz=getElementPosition(car)
    local m=getElementMatrix(car)
    if not m or getDistanceBetweenPoints3D(x,y,z,cx,cy,cz)>=3.5 then return false end
    local lateral=(x-cx)*m[1][1]+(y-cy)*m[1][2]
    local longitudinal=(x-cx)*m[2][1]+(y-cy)*m[2][2]
    local side,along=TrafficWanted.driverDoorApproach(car)
    return side and lateral<-.45 and math.abs(lateral-(side+.55))<1.05
        and math.abs(longitudinal-along)<1.15 and math.abs(z-cz)<1.8
end

TrafficWanted.atDriverDoor = atDriverDoor

local serial=0
local function clearDoor(car,attempt)
    if openingDoors[car]~=attempt then return end
    openingDoors[car]=nil
    if attempt.work then attempt.work.doorRetry=getTickCount() end
    if isElement(attempt.owner) then
        triggerClientEvent(attempt.owner,"npchlc_traffic:cancelPoliceDriverDoor",resourceRoot,attempt.officer,attempt.id)
    end
end

local function validDoor(car,a)
    return isElement(car) and isElement(a.officer) and isElement(a.player)
        and getElementSyncer(a.officer)==a.owner
        and TrafficWanted.driverArrestCar(a.officer,a.player)==car
        and TrafficWanted.officerCanPursue(a.officer,a.player)
        and TrafficGroundPolice.target(a.officer)==a.player and atDriverDoor(a.officer,car)
end

addEventHandler("onVehicleStartEnter",root,function(officer,seat,driver,door)
    local a=openingDoors[source]
    if not a or officer~=a.officer then return end
    if seat~=0 or driver~=a.player or door~=0 or isVehicleLocked(source) or wasEventCancelled() then
        cancelEvent()
        clearDoor(source,a)
        return
    end
    a.started=getTickCount()
end,true,"low-100")

-- Vehicle synchronization can arrive after the script notification. Confirm
-- the independently replicated hinge angle for this vehicle and reach.
local function confirmDoor(car,a,remaining)
    if openingDoors[car]~=a then return end
    if not validDoor(car,a) then
        clearDoor(car,a)
        return
    end
    if not isPedInVehicle(a.officer) and getVehicleDoorOpenRatio(car,2)>=.75 then
        clearDoor(car,a)
        if TrafficWanted.driverArrestCar(a.officer,a.player)==car then arrest(a.officer,a.player,getTickCount(),false,true) end
    elseif remaining>0 then
        setTimer(function() confirmDoor(car,a,remaining-1) end,50,1)
    else
        clearDoor(car,a)
    end
end

addEvent("npchlc_traffic:observedDriverDoor",true)
addEventHandler("npchlc_traffic:observedDriverDoor",resourceRoot,function(car,id,opened)
    local a=openingDoors[car]
    if not a or a.id~=id or a.owner~=client or not isElement(a.officer) or getElementSyncer(a.officer)~=client or a.reported then return end
    a.reported=true
    local now=getTickCount()
    if opened~=true or not a.started or (now-a.started)%4294967296<50 or (now-a.at)%4294967296>5000 then
        clearDoor(car,a)
        return
    end
    confirmDoor(car,a,8)
end,false)

function TrafficWanted.tryDriverArrest(officer,player,now,work)
    local current=getPedOccupiedVehicle(player)
    local pending=current and openingDoors[current]
    if pending and (not validDoor(current,pending) or (now-pending.at)%4294967296>=5000) then
        clearDoor(current,pending)
        pending=nil
    end
    if pending and pending.officer==officer then return false,true end
    local car=TrafficWanted.driverArrestCar(officer,player)
    if not car or TrafficGroundPolice.target(officer)~=player or not TrafficWanted.officerCanPursue(officer,player)
        or not atDriverDoor(officer,car) then return false end
    if work and work.doorRetry and (now-work.doorRetry)%4294967296<250 then return false,true end
    if work and work.follow then
        exports.npc_hlc:clearNPCTasks(officer)
        work.follow=nil
    end
    if pending then return false,true end
    local kind=getVehicleType(car)
    if kind=="Bike" or kind=="BMX" or kind=="Quad" or getVehicleDoorState(car,2)==4 or getVehicleDoorOpenRatio(car,2)>=.85 then
        local accepted=arrest(officer,player,now,false,true)
        if not accepted and work then work.doorRetry=now end
        return accepted,true
    end
    local owner=getElementSyncer(officer)
    if not owner then return false end
    serial=serial+1
    local a={officer=officer,player=player,owner=owner,at=now,id=serial,work=work}
    openingDoors[car]=a
    triggerClientEvent(owner,"npchlc_traffic:openPoliceDriverDoor",resourceRoot,officer,car,player,serial)
    setTimer(function() clearDoor(car,a) end,5200,1)
    return false,true
end

function TrafficWanted.tryArrest(officer,player,now,work,deferDoor)
    if arrest(officer,player,now,false) then return true end
    if deferDoor then
        local car=getPedOccupiedVehicle(player)
        local pending=car and openingDoors[car]
        if pending and (not validDoor(car,pending) or (now-pending.at)%4294967296>=5000) then
            clearDoor(car,pending)
            pending=nil
        end
        return false,pending and pending.officer==officer
    end
    return TrafficWanted.tryDriverArrest(officer,player,now,work)
end
-- The PS2 corpse branch leaves the player in its dying/wasted state.
-- Emit the ownership notification while preserving MTA's respawn lifecycle.
addEventHandler("onPlayerWasted",root,function()
    local player=source
    if not isPedDead(player) or getPlayerWantedLevel(player)==0 then return end
    local x,y,z=getElementPosition(player)
    local best,distance=nil,5
    for _,officer in ipairs(getElementsWithinRange(x,y,z,5,"ped",getElementInterior(player),getElementDimension(player)) or {}) do
        if eligibleOfficer(officer,player,true) then
            local d=getDistanceBetweenPoints3D(x,y,z,getElementPosition(officer))
            if d<distance then best,distance=officer,d end
        end
    end
    if best then arrest(best,player,getTickCount(),true) end
end)
