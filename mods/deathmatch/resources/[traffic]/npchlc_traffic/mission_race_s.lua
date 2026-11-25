TrafficRace = {}
local drivers, vehicles = {}, {}
local densities = {}
TrafficRoad.missionDensities = densities
local hlc = exports.npc_hlc

local function finite(v) return type(v)=="number" and math.abs(v)<math.huge end

local function seated(ped, car)
    return isElement(ped) and not isPedDead(ped) and isElement(car)
        and getPedOccupiedVehicle(ped)==car and getVehicleOccupant(car,0)==ped
end

function startMissionRaceDriver(ped, car, style)
    if style~=2 or not sourceResource or not seated(ped,car) then return false end
    local kind=getVehicleType(car)
    if kind~="Automobile" and kind~="Bike" and kind~="Quad" and kind~="Monster Truck" then return false end
    if vehicles[car] and vehicles[car]~=ped then return false end
    local existing=drivers[ped]
    if existing then return existing.owner==sourceResource and existing.car==car end
    local brain=PedAI.brain(ped)
    if not brain then return false end
    local adopted=not brain.scriptOwner
    if not acquireTrafficPed(ped) then return false end
    TrafficActors.endMissionPath(ped)
    hlc:clearNPCTasks(ped)
    vehicles[car]=ped
    drivers[ped]={owner=sourceResource,car=car,adopted=adopted,savedSpeed=hlc:getNPCDriveSpeed(ped)}
    return true
end

local function direct(ped,race)
    return hlc:setNPCTask(ped,{"driveRaceToPoint",race.driveX,race.driveY,race.z,race.nextX,race.nextY,
        race.nextX and race.arrivalRadius or nil})
end

function setMissionRaceTarget(ped,x,y,z,cruiseSpeed,nextX,nextY,straight,arrivalRadius)
    local race=drivers[ped]
    if not race or race.owner~=sourceResource or not seated(ped,race.car) then return false end
    if not finite(x) or not finite(y) or not finite(z) or not finite(cruiseSpeed)
        or math.max(math.abs(x),math.abs(y),math.abs(z))>16384
        or cruiseSpeed<1 or cruiseSpeed>127 then return false end
    if (nextX~=nil or nextY~=nil) and (not finite(nextX) or not finite(nextY)
        or math.max(math.abs(nextX),math.abs(nextY))>16384) then return false end
    if straight~=nil and type(straight)~="boolean" then return false end
    if arrivalRadius~=nil and (not finite(arrivalRadius) or arrivalRadius<=0 or arrivalRadius>32) then return false end
    straight=straight==true
    local model=getElementData(race.car,"vcs_vehicle:originalModel",false) or getElementData(race.car,"npchlc_traffic:originalModel",false)
    local cap=TrafficMaxCruiseSpeed[model]
    cruiseSpeed=math.floor(math.min(cruiseSpeed,cap or cruiseSpeed))
    if race.speed~=cruiseSpeed then
        if not hlc:setNPCDriveSpeed(ped,cruiseSpeed/50) then return false end
        race.speed=cruiseSpeed
    end
    if race.x==x and race.y==y and race.z==z and race.nextX==nextX and race.nextY==nextY
        and race.straight==straight and race.arrivalRadius==arrivalRadius then return true end
    TrafficActors.endMissionPath(ped,true)
    race.x,race.y,race.z=x,y,z
    race.nextX,race.nextY,race.straight,race.arrivalRadius=nextX,nextY,straight,arrivalRadius
    race.driveX,race.driveY=x,y
    if arrivalRadius and nextX and not straight then
        -- Aim into the outgoing tangent while retaining nearly half the
        -- ring radius as clearance for the physical vehicle's trajectory.
        local dx,dy=nextX-x,nextY-y
        local span=math.sqrt(dx^2+dy^2)
        if span>1 then
            local lead=math.min(.55*arrivalRadius,.45*span)
            race.driveX,race.driveY=x+dx*lead/span,y+dy*lead/span
        end
    end
    local exit={race.driveX,race.driveY,nextX or x,nextY or y,nextX and arrivalRadius or nil}
    if (not straight and TrafficRoad.beginRaceRoute(ped,race.driveX,race.driveY,z,cruiseSpeed,exit)) or direct(ped,race) then return true end
    race.x=nil
    hlc:clearNPCTasks(ped)
    return false
end

-- 00438A80 hands a completed mode-8 road search to point steering (mode 9).
addEventHandler("npchlc_traffic:onNPCTrafficRouteDone",root,function()
    local race=drivers[source]
    if race and race.x and seated(source,race.car) then direct(source,race) end
end)

function TrafficRace.release(ped)
    local race=drivers[ped]
    if not race then return end
    drivers[ped],vehicles[race.car]=nil,nil
    if seated(ped,race.car) and not getElementSyncer(race.car) then setElementVelocity(race.car,0,0,0) end
    if isElement(ped) then
        TrafficActors.endMissionPath(ped)
        if TrafficActors.hlcRunning() then
            hlc:clearNPCTasks(ped)
            if race.savedSpeed then hlc:setNPCDriveSpeed(ped,race.savedSpeed) end
        end
    end
end

local function stop(ped,race)
    TrafficRace.release(ped)
    if race.adopted then TrafficActors.releaseScriptPed(ped,race.owner) end
end

function stopMissionRaceDriver(ped)
    local race=drivers[ped]
    if not race then return true end
    if race.owner~=sourceResource then return false end
    stop(ped,race)
    return true
end

addEventHandler("onVehicleExit",root,function(ped,seat)
    local race=drivers[ped]
    if seat==0 and race and race.car==source then stop(ped,race) end
end)

addEventHandler("onElementDestroy",root,function()
    local race=drivers[source]
    if race then drivers[source],vehicles[race.car]=nil,nil end
    local ped=vehicles[source]
    if ped then stop(ped,drivers[ped]) end
end)

-- The SCM density multiplier belongs to the race participant's spawn budget.
function setMissionTrafficDensity(player,factor)
    if not sourceResource or not isElement(player) or getElementType(player)~="player" then return false end
    local state=densities[player]
    if state and state.owner~=sourceResource then return false end
    if factor==false then densities[player]=nil return true end
    if not finite(factor) or factor<0 or factor>10 then return false end
    densities[player]={owner=sourceResource,factor=factor}
    return true
end

addEventHandler("onPlayerQuit",root,function() densities[source]=nil end)
addEventHandler("onResourceStop",root,function(stopped)
    for player,state in pairs(densities) do
        if state.owner==stopped then densities[player]=nil end
    end
end)
