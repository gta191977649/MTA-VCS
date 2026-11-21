local models = {207, 193, 234, 268, 191, 246, 275, 204}
local eligible, suspects, waitingForRoad = {}, {}, {}
for _, id in ipairs(models) do eligible[id] = true end

local function distance(a,b)
    local x,y,z = getElementPosition(a)
    return getDistanceBetweenPoints3D(x,y,z,getElementPosition(b))
end

local function clearBlip(record)
    if record.blip then record.run.elements[record.blip]=nil end
    if isElement(record.blip) then destroyElement(record.blip) end
    record.blip = nil
end

local function mark(r,record,element)
    if isElement(record.blip) and getElementAttachedTo(record.blip)==element then return end
    clearBlip(record)
    -- Match the frontend's ~b~ vehicle and ~r~ suspect objective colors.
    local vehicleTarget = element ~= record.ped
    local blip = createBlipAttachedTo(element,0,2,vehicleTarget and 0 or 174,0,
        vehicleTarget and 255 or 0,255,0,65535,r.player)
    if blip then
        setElementDimension(blip,getElementDimension(element))
        setElementInterior(blip,getElementInterior(element))
        record.blip = Mission.track(r,blip)
    end
end

local function clearWave(r)
    Mission.releaseSites(r)
    for car in pairs(r.borrowed or {}) do
        if car~=r.vehicle then Mission.releaseVehicle(r,car) end
    end
    r.borrowed={}
    for _,s in ipairs(r.suspects or {}) do
        suspects[s.ped] = nil
        if s.displaced then Mission.release(r,s.displaced) end
        clearBlip(s)
        r.elements[s.ped]=nil
        if isElement(s.ped) then destroyElement(s.ped) end
    end
    for _,car in ipairs(r.cars or {}) do
        waitingForRoad[car]=nil
        r.elements[car]=nil
        if isElement(car) then destroyElement(car) end
    end
    r.suspects,r.cars = {},{}
end

local function excluded(x,y)
    for _,box in ipairs(VigilanteExcludedRoads) do
        if x>box[1] and x<box[2] and y>box[3] and y<box[4] then return true end
    end
    return false
end

local function dispatch(r)
    local px,py,pz = getElementPosition(r.player)
    local island = exports.npchlc_traffic:getTrafficIslandAt(px,py,pz)==2 and "mainland" or "beach"
    local available = {}
    for index,point in ipairs(VigilanteSites[island]) do
        local key = "vigilante/"..island.."/"..index
        if Mission.siteAvailable(r,key) then available[#available+1]={point,key} end
    end
    if #available==0 then return nil,"busy" end
    local site
    local key
    for i=1,25 do
        site,key = unpack(available[math.random(#available)])
        local d = getDistanceBetweenPoints3D(px,py,pz,site[1],site[2],site[3])
        if d>150 and d<1000 then break end
    end
    Mission.claimSite(r,key)
    if r.group=="foot" then return site[1],site[2],site[3],0,site[4] end
    for i=1,25 do
        local x,y = site[1],site[2]
        local dir,step = math.random(4),math.random()*50
        if dir==1 then x=x+step elseif dir==2 then x=x-step elseif dir==3 then y=y+step else y=y-step end
        if i==25 then x,y=site[1],site[2] end
        local rx,ry,rz,yaw = exports.npchlc_traffic:getMissionTrafficRoad(x,y,site[3])
        if rx and (i==25 or not excluded(rx,ry)) then return rx,ry,rz,yaw,site[4] end
    end
end

-- VCS 8/19/25/29 are the gaff, pistol, compact SMG and assault rifle.
-- MTA's blunt melee and firearm slots provide their synced combat tasks.
local weapons = {7,22,28,28,30}
local function arm(ped,level)
    local index
    if level<2 then index=math.random(1,2)
    elseif level<4 or level>=10 and math.random(2)==1 then index=math.random(2,3)
    else index=math.random(4,5) end
    giveWeapon(ped,weapons[index],50,true)
end

local function spawnSuspect(r,x,y,z,car,seat,leader)
    local ped = exports.npchlc_traffic:createTrafficScriptPed(math.random(2)==1 and 55 or 58,x,y,z,r.interior,r.dimension)
    if not ped then return false end
    Mission.track(r,ped)
    local s = {run=r,ped=ped,car=car,seat=seat,leader=leader,state="waiting"}
    r.suspects[#r.suspects+1],suspects[ped] = s,s
    setElementData(ped,"mission:vigilanteTarget",r.player,"broadcast","deny")
    arm(ped,r.level)
    if car then
        if not warpPedIntoVehicle(ped,car,seat) then return false end
        s.state = "riding"
        if seat==0 then
            mark(r,s,car)
        end
    else
        mark(r,s,ped)
    end
    return true
end

local function wave(r,now)
    clearWave(r)
    local variant = math.random(4)
    r.group = variant<3 and "car" or variant==3 and "bike" or "foot"
    local tier = r.level<5 and 1 or r.level<10 and 2 or 3
    r.healthLimit,r.fastSpeed = 850-100*tier,15+tier*5
    local x,y,z,yaw,area = dispatch(r)
    if not x and y=="busy" then
        if not r.nextWave then Mission.message(r,"Waiting for another suspect report.") end
        r.nextWave=now+2000
        return
    end
    if not x then return Mission.fail(r,"Unable to locate the suspects.") end
    local count = tier+(r.group=="bike" and 1 or 0)
    local occupants = r.group=="bike" and 2 or tier+1
    local lastCar
    if r.group=="foot" then
        for i=1,2+tier*2 do
            if not spawnSuspect(r,x+math.random()*5-2.5,y+math.random()*5-2.5,z,nil,nil) then
                return Mission.fail(r,"Unable to locate the suspects.")
            end
        end
    else
        local id = r.group=="car" and (tier==1 and 195 or 274) or (tier==1 and 232 or 252)
        for i=1,count do
            local behind = (i-1)*7.5
            local angle = math.rad(yaw)
            local car = exports.vcs_vehicle:createVcsVehicle(id,x+math.sin(angle)*behind,y-math.cos(angle)*behind,z+0.8,0,0,yaw)
            if not car then return Mission.fail(r,"Unable to locate the suspects.") end
            Mission.track(r,car)
            r.cars[#r.cars+1] = car
            -- Road nodes can be outside streamed map collision when a distant
            -- dispatch is created. Keep gravity off until the driver sees its surface.
            setElementFrozen(car,true)
            setElementDimension(car,r.dimension)
            setElementInterior(car,r.interior)
            waitingForRoad[car]={run=r,z=z}
            setElementData(car,"mission:vigilanteRoad",r.player,"broadcast","deny")
            setVehicleEngineState(car,true)
            for seat=0,occupants-1 do
                if not spawnSuspect(r,x,y,z,car,seat,lastCar) then
                    return Mission.fail(r,"Unable to locate the suspects.")
                end
            end
            lastCar = car
        end
    end
    local groupName = r.group=="foot" and "on foot" or r.group=="bike" and "on ~b~motorbikes~w~" or count==1 and "in a ~b~car~w~" or "in ~b~cars~w~"
    Mission.message(r,("~r~Suspects~w~ last seen %s in the vicinity of %s"):format(groupName,area))
    Mission.hud(r,"Kills",r.kills)
    r.deadline,r.nextWave = now+300000,nil
end

local function onFoot(s,state)
    if s.state~=state then
        s.state=state
        if state=="waiting" then
            exports.npchlc_traffic:assignTrafficPedObjective(s.ped,"clear")
        else
            exports.npchlc_traffic:assignTrafficPedObjective(s.ped,state,s.run.player)
        end
    end
    mark(s.run,s,s.ped)
end

local function replacement(s,now)
    if now<(s.searchAt or 0) then return end
    s.searchAt=now+1000
    local r,ped=s.run,s.ped
    local x,y,z=getElementPosition(ped)
    for _,car in ipairs(getElementsWithinRange(x,y,z,20,"vehicle",r.interior,r.dimension) or {}) do
        local vx,vy=getElementPosition(car)
        local kind=getVehicleType(car)
        if math.abs(vx-x)<=15 and math.abs(vy-y)<=15 and car~=getPedOccupiedVehicle(r.player)
            and Mission.vehicleAvailable(r,car) and (kind=="Automobile" or kind=="Bike") and not isVehicleLocked(car) and getElementHealth(car)>=r.healthLimit then
            local driver=getVehicleOccupant(car,0)
            if not driver and exports.npchlc_traffic:assignTrafficPedObjective(ped,"enterVehicle",car,0) then
                Mission.claimVehicle(r,car)
                r.borrowed[car]=true
                s.car,s.state,s.enterAt = car,"entering",now
                return
            elseif driver and getElementType(driver)=="ped" and distance(ped,car)<6
                and exports.npchlc_traffic:acquireMissionTrafficDriver(driver) then
                Mission.lease(r,driver)
                if exports.npchlc_traffic:assignTrafficPedObjective(driver,"exitVehicle") then
                    Mission.claimVehicle(r,car)
                    r.borrowed[car]=true
                    s.car,s.state,s.enterAt,s.displaced=car,"displacing",now,driver
                    return
                end
                Mission.release(r,driver)
            end
        end
    end
end

local function suspectTick(s,now)
    local r,ped,car=s.run,s.ped,s.car
    local seatCar=getPedOccupiedVehicle(ped)
    if s.state=="displacing" then
        local canEnter=isElement(car) and not getVehicleOccupant(car,0) and distance(ped,car)<25
        if canEnter or not isElement(car) or now-s.enterAt>4500 then
            Mission.release(r,s.displaced)
            s.displaced=nil
            if canEnter and exports.npchlc_traffic:assignTrafficPedObjective(ped,"enterVehicle",car,0) then
                s.state,s.enterAt="entering",now
            else
                onFoot(s,"flee")
            end
        end
        return
    end
    if s.state=="entering" then
        if isElement(car) and exports.npchlc_traffic:isMissionPedSeated(ped,car,0) then
            s.state,s.seat,s.leader,s.fast,s.cruising="riding",0,nil,true,false
            setVehicleEngineState(car,true)
            mark(r,s,car)
        elseif not isElement(car) or distance(ped,car)>25 or getElementHealth(car)<250 or now-s.enterAt>12000 then
            onFoot(s,"flee")
        end
        return
    end
    if s.state=="leaving" then
        if not seatCar then onFoot(s,s.seat==0 and "flee" or "attack") end
        return
    end
    if s.state=="riding" then
        if waitingForRoad[car] then return end
        if not seatCar or not isElement(car) then return onFoot(s,s.seat==0 and "flee" or "attack") end
        local matrix=getElementMatrix(car)
        local upside=r.group~="bike" and matrix and matrix[3][3]<0
        local hp=getElementHealth(car)
        if hp<250 or upside or s.seat==0 and hp<r.healthLimit or s.seat~=0 and not getVehicleOccupant(car,0) then
            if exports.npchlc_traffic:assignTrafficPedObjective(ped,"exitVehicle") then s.state="leaving" end
            return
        end
        if s.seat~=0 then return end
        local playerCar=getPedOccupiedVehicle(r.player)
        local d=distance(ped,r.player)
        if not s.fast and (s.lastHealth and hp<s.lastHealth or r.group=="bike" and d<5 or playerCar and d<30 and getVehicleSirensOn(playerCar)) then
            s.fast,s.leader,s.cruising=true,nil,false
        end
        s.lastHealth=hp
        if isElement(s.leader) and getVehicleOccupant(s.leader,0) then
            if now>=(s.driveAt or 0) then
                local x,y,z=getElementPosition(s.leader)
                local gap=distance(car,s.leader)
                if gap>25 then
                    -- Rejoin a separated convoy along streets instead of
                    -- steering straight through the block toward its leader.
                    s.followRoad=exports.npchlc_traffic:driveMissionTrafficTo(ped,x,y,z,50)
                    s.driveAt=now+2000
                    if s.followRoad then s.cruising=true end
                    return
                end
                if s.followRoad then
                    exports.npchlc_traffic:assignTrafficPedObjective(ped,"clear")
                    s.followRoad=nil
                end
                local vx,vy,vz=getElementVelocity(s.leader)
                local speed=gap<8 and math.max(5,math.sqrt(vx*vx+vy*vy+vz*vz)*50) or 50
                exports.npc_hlc:setNPCDriveSpeed(ped,speed/50)
                exports.npc_hlc:setNPCTask(ped,{"driveToPos",x,y,z,4})
                s.driveAt=now+750
                s.cruising=false
            end
        elseif not s.cruising and now>=(s.retryAt or 0) then
            s.cruising=exports.npchlc_traffic:cruiseMissionTraffic(ped,s.fast and r.fastSpeed or 5)
            s.retryAt=now+1000
        end
        return
    end
    if s.state=="flee" then replacement(s,now) return end
    if getElementHealth(ped)<40 then return onFoot(s,"flee") end
    local visible=s.spottedAt and now-s.spottedAt<2000
    if visible then onFoot(s,"attack")
    elseif s.state=="attack" then onFoot(s,"waiting")
    else
        local x,y=getElementPosition(ped)
        local px,py=getElementPosition(r.player)
        setPedRotation(ped,math.deg(math.atan2(x-px,py-y)))
    end
end

addEvent("mission:vigilanteRoadReady",true)
addEventHandler("mission:vigilanteRoadReady",resourceRoot,function(car,surface,token)
    local pending=waitingForRoad[car]
    if not pending or Mission.forParticipant(client,token,"vigilante")~=pending.run or not isElement(car) or distance(car,client)>220
        or getElementInterior(client)~=pending.run.interior or getElementDimension(client)~=pending.run.dimension
        or type(surface)~="number" or not (math.abs(surface-pending.z)<=6) then return end
    local x,y=getElementPosition(car)
    setElementPosition(car,x,y,surface+0.8)
    setElementVelocity(car,0,0,0)
    setElementSyncer(car,client,false)
    setElementFrozen(car,false)
    waitingForRoad[car]=nil
    removeElementData(car,"mission:vigilanteRoad")
end,false)

addEvent("mission:vigilanteSpotted",true)
addEventHandler("mission:vigilanteSpotted",resourceRoot,function(ped,token)
    local s=suspects[ped]
    if s and Mission.forParticipant(client,token,"vigilante")==s.run and isElement(ped) and distance(ped,client)<=100 then s.spottedAt=getTickCount() end
end,false)

addEventHandler("npchlc_traffic:onNPCTrafficRouteDone",root,function()
    local s=suspects[source]
    if s then s.cruising=false end
end)

local function tick(r,now)
    local car=getPedOccupiedVehicle(r.player)
    if car and eligible[Mission.model(car)] and Mission.driverOf(car)==r.player and Mission.switchVehicle(r,car) then
        r.returnBy,r.returnShown=nil,nil
    else
        r.returnBy=r.returnBy or math.min(r.deadline or now+30000,now+30000)
        local remaining=math.ceil((r.returnBy-now)/1000)
        if remaining<=0 then return Mission.fail(r,"You failed to return to a police vehicle in time.") end
        if r.returnShown~=remaining then
            Mission.message(r,("You have %d second%s to get back in a ~b~police vehicle~w~."):format(remaining,remaining==1 and "" or "s"))
            r.returnShown=remaining
        end
    end
    if r.nextWave then
        if now>=r.nextWave then wave(r,now) end
        return
    end
    local alive=0
    for _,s in ipairs(r.suspects) do
        if not s.caught then
            if not isElement(s.ped) then return Mission.fail(r,"The suspects got away.") end
            if isPedDead(s.ped) then
                if s.displaced then Mission.release(r,s.displaced); s.displaced=nil end
                local reward=r.level<5 and 10 or r.level<10 and 30 or 50
                s.caught=true
                clearBlip(s)
                r.kills=r.kills+1
                Mission.pay(r,reward)
                Mission.message(r,"Suspect takedown! Reward: $"..reward)
                Mission.hud(r,"Kills",r.kills)
            else
                alive=alive+1
                suspectTick(s,now)
            end
        end
    end
    if alive==0 then
        if r.level==15 and r.profile.vigilante<15 then exports.wanted:setPlayerWanted(r.player,0,"vigilante") end
        Mission.finishLevel(r,0)
        Mission.message(r,"Time Extended.")
        r.deadline,r.nextWave=nil,now+3000
    end
end

Mission.register("vigilante",{
    models=models, title="Vigilante",
    start=function(r)
        r.kills,r.interior,r.dimension=0,getElementInterior(r.player),getElementDimension(r.player)
        r.crimeMultiplier=exports.wanted:getPlayerCrimeMultiplier(r.player)
        exports.wanted:setPlayerCrimeMultiplier(r.player,0.5)
        wave(r,getTickCount())
    end,
    tick=tick,
    stop=function(r)
        clearWave(r)
        local wanted=getResourceFromName("wanted")
        if isElement(r.player) and wanted and getResourceState(wanted)=="running" and exports.wanted:getPlayerCrimeMultiplier(r.player)==0.5 then
            exports.wanted:setPlayerCrimeMultiplier(r.player,r.crimeMultiplier or 1)
        end
    end
})
