local hubs = {{-1053.4585,-795.2299,10.9704,1,5}, {251.511,-304.312,11.1,6,9}}
local pink, green = {237,130,180,255}, {0,255,0,255}
local function near(e,p,xy,zTolerance)
    local x,y,z = getElementPosition(e)
    return math.abs(x-p[1])<=xy and math.abs(y-p[2])<=xy and math.abs(z-p[3])<=zTolerance
end

local function hubFor(player)
    if getElementDimension(player)~=0 or getElementInterior(player)~=0 or getPedOccupiedVehicle(player) then return end
    for _,hub in ipairs(hubs) do
        if near(player,hub,2,2) then return hub end
    end
end

local function clearGate(r)
    for _,key in ipairs({"gate","arrow","preview"}) do
        if isElement(r[key]) then destroyElement(r[key]) end
        r[key]=nil
    end
end

local function drawGate(r)
    clearGate(r)
    local gates=r.course.checkpoints
    local p=gates[r.index]
    local finish=r.lap==r.course.laps and r.index==#gates
    r.gate=Mission.marker(r,p[1],p[2],p[3],"checkpoint",finish and 35 or 12,finish and green or pink,true)
    if not finish then
        local n=gates[r.index%#gates+1]
        r.arrow=Mission.marker(r,p[1],p[2],p[3]+4.75,"pointer",3.2,{237,130,180,200},false)
        if r.arrow then exports.marker:setMarkerTarget(r.arrow,n[1],n[2],n[3]) end
        -- The following checkpoint has a dim radar dot without a world cylinder.
        r.preview=Mission.track(r,createBlip(n[1],n[2],n[3],0,2,237,130,180,255,0,65535,r.player))
        if r.preview then setElementDimension(r.preview,r.dimension) end
    end
end

local function drive(r,s,now)
    local p=r.course.checkpoints[s.aim]
    local x,y,z=p[4],p[5],p[6]
    local speed=r.course.speed
    local sx,sy=getElementPosition(s.car)
    local px,py=getElementPosition(r.player)
    local limit=r.course.limits[p[7]]
    if limit and getDistanceBetweenPoints2D(sx,sy,x,y)<limit[1] then
        speed=math.min(speed,limit[2])
    elseif p[7]<1000 then
        speed=math.max(15,math.min(60,speed+p[7]))
    end
    local ahead=s.lap>r.lap or s.lap==r.lap and s.index>r.index
    local leader=r.course.limits.leader
    if ahead and getDistanceBetweenPoints2D(sx,sy,px,py)>leader[1] then speed=math.min(speed,leader[2]) end
    -- SCM 004A passes the authored AI goal (independent of the player's ring).
    -- The Escobar runway has no ordinary traffic lanes.
    s.road=r.course~=TurismoCourses[1] and exports.npchlc_traffic:driveMissionTrafficTo(s.ped,x,y,z,speed)
    if not s.road then
        exports.npc_hlc:setNPCDriveSpeed(s.ped,speed/50)
        exports.npc_hlc:setNPCTask(s.ped,{"driveToPos",x,y,z,7})
    end
    s.refresh=now+5000
end

local function startGrid(r,car,now)
    local c=r.course
    if not Mission.claimSite(r,"turismo/grid/"..c.key) then return end
    if not Mission.switchVehicle(r,car) then
        Mission.releaseSite(r,"turismo/grid/"..c.key)
        return
    end
    clearGate(r)
    r.rivals={}
    for i,v in ipairs(c.rivals) do
        local vehicle=Mission.track(r,exports.vcs_vehicle:createVcsVehicle(v[5],v[1],v[2],v[3],0,0,v[4]))
        local ped=Mission.track(r,exports.npchlc_traffic:createTrafficScriptPed(14,v[1],v[2],v[3],r.interior,r.dimension))
        if not vehicle or not ped or not warpPedIntoVehicle(ped,vehicle,0) then
            return Mission.fail(r,"The starting grid could not be prepared.")
        end
        setElementDimension(vehicle,r.dimension)
        exports.vcs_vehicle:setVcsVehiclePaint(vehicle,i-1,i-1)
        setElementFrozen(vehicle,true)
        setVehicleEngineState(vehicle,true)
        r.rivals[i]={car=vehicle,ped=ped,index=1,aim=1,lap=1}
    end
    setElementPosition(car,c.grid[1],c.grid[2],c.grid[3])
    setElementRotation(car,0,0,c.grid[4])
    setElementVelocity(car,0,0,0)
    r.unfreeze=not isElementFrozen(car)
    setElementFrozen(car,true)
    r.startAt=now+3000
    r.phase="countdown"
end

local function correctVehicle(r,car)
    if not car or Mission.driverOf(car)~=r.player or not Mission.vehicleAvailable(r,car) then return false end
    local kind=getVehicleType(car)
    if r.course.kind==2 then return kind=="Bike" end
    return kind=="Automobile" or kind=="Monster Truck" or kind=="Quad"
end

local function choose(r,index)
    local hub=r.hub
    if hubFor(r.player)~=hub then return Mission.fail(r,"You left the race organizer.") end
    local c=TurismoCourses[hub[4]+index-1]
    if getPlayerMoney(r.player)<c.fee then
        Mission.message(r,"You don't have enough money to enter this race.")
        return Mission.selectCourse(r,r.options,choose)
    end
    if not takePlayerMoney(r.player,c.fee) then return Mission.fail(r,"The entry fee could not be paid.") end
    r.course,r.phase=c,"grid"
    r.gate=Mission.marker(r,c.grid[1],c.grid[2],c.grid[3],"checkpoint",3.5,pink,true)
    Mission.message(r,"Get a "..(c.kind==2 and "motorbike" or "car").." and head for the start line.")
end

local function startRace(r)
    r.hub=hubFor(r.player)
    r.options={}
    for i=r.hub[4],r.hub[5] do
        local c=TurismoCourses[i]
        local rec=Mission.courseRecord(r,c.key)
        local best=rec and rec.time and ("   Best %d:%02d"):format(math.floor(rec.time/60000),math.floor(rec.time/1000)%60) or ""
        r.options[#r.options+1]=("%s   Entry $%d   Prize $%d%s"):format(c.name,c.fee,c.prize,best)
    end
    Mission.selectCourse(r,r.options,choose)
end

local function ranking(r)
    local position=1
    local p=r.course.checkpoints[r.index]
    local function distance(car)
        local x,y,z=getElementPosition(car)
        return getDistanceBetweenPoints3D(x,y,z,p[1],p[2],p[3])
    end
    for _,s in ipairs(r.rivals) do
        if s.lap>r.lap or s.lap==r.lap and (s.index>r.index or s.index==r.index and distance(s.car)<distance(r.vehicle)) then
            position=position+1
        end
    end
    return position
end

local function raceTick(r,now)
    if not r.course then return end
    local c,car=r.course,getPedOccupiedVehicle(r.player)
    if r.phase=="grid" then
        if correctVehicle(r,car) and near(car,c.grid,3.5,10) then startGrid(r,car,now) end
        return
    end
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return Mission.fail(r,"Your race vehicle was destroyed.") end
    if r.phase=="countdown" then
        if car~=r.vehicle or Mission.driverOf(car)~=r.player then return Mission.fail(r,"You left the starting grid.") end
        if now<r.startAt then
            local n=math.ceil((r.startAt-now)/1000)
            if n~=r.count then r.count=n Mission.countdown(r,n) end
            return
        end
        if r.unfreeze then setElementFrozen(car,false) r.unfreeze=false end
        r.elapsedFrom,r.lapStart,r.lap,r.index,r.phase=now,now,1,1,"racing"
        for _,s in ipairs(r.rivals) do
            -- RACEHUB_5808 uses display 1 for race rivals (world arrow only).
            s.marker=Mission.entityArrow(r,s.ped,{0,0,255,255},false)
            setElementFrozen(s.car,false)
            drive(r,s,now)
        end
        Mission.releaseSite(r,"turismo/grid/"..c.key)
        Mission.countdown(r,0)
        drawGate(r)
    end

    for _,s in ipairs(r.rivals) do
        if not isElement(s.ped) or isPedDead(s.ped) or not isElement(s.car) or isVehicleBlown(s.car) then
            return Mission.fail(r,"One of the racers has died. The race has been called off.")
        end
        if s.lap<=c.laps then
            local p,aim=c.checkpoints[s.index],c.checkpoints[s.aim]
            local x,y=getElementPosition(s.car)
            local atAim=math.abs(x-aim[4])<=15 and math.abs(y-aim[5])<=15
            local radius=s.lap==c.laps and s.index==#c.checkpoints and 15 or 12
            local atGate=math.abs(x-p[1])<=radius and math.abs(y-p[2])<=radius
            if atAim then s.aim=s.aim%#c.checkpoints+1 end
            -- RACEHUB_6779 advances a missed ring if the driver's next aim
            -- is already ahead, without redirecting the car at the ring.
            if atGate or atAim and s.aim>s.index then
                s.index=s.index+1
                if s.index>#c.checkpoints then s.index,s.lap=1,s.lap+1 end
            end
            if s.lap>c.laps then
                if isElement(s.marker) then destroyElement(s.marker) end
                exports.npc_hlc:setNPCTask(s.ped,{"stopVehicle"})
            elseif atAim or now>=s.refresh then drive(r,s,now) end
        end
    end
    if car~=r.vehicle or Mission.driverOf(r.vehicle)~=r.player then
        if not r.returnAt then
            r.returnAt=now+30400
            clearGate(r)
            Mission.showReturnVehicle(r,r.vehicle)
            Mission.message(r,"Get back in your race vehicle within 30 seconds.")
        elseif now>=r.returnAt then return Mission.fail(r,"You have been disqualified for leaving your vehicle.") end
        return
    elseif r.returnAt then
        r.returnAt=nil
        Mission.clearReturnVehicle(r)
        drawGate(r)
    end
    local pos=ranking(r)
    Mission.hud(r,"Lap",("%d/%d   %s"):format(r.lap,c.laps,({"1st","2nd","3rd","4th"})[pos]))
    local gate=c.checkpoints[r.index]
    local radius=r.lap==c.laps and r.index==#c.checkpoints and 15 or 12
    local x,y=getElementPosition(car)
    if math.abs(x-gate[1])<=radius and math.abs(y-gate[2])<=radius then
        Mission.checkpointCue(r)
        if r.index==#c.checkpoints then
            local lap=now-r.lapStart
            r.bestLap=math.min(r.bestLap or lap,lap)
            if r.lap==c.laps then
                -- Finish order counts opponents that actually crossed the finish.
                pos=1
                for _,s in ipairs(r.rivals) do if s.lap>c.laps then pos=pos+1 end end
                return Mission.finishCourse(r,c.key,{time=now-r.elapsedFrom,lap=r.bestLap,position=pos},pos==1 and c.prize or 0,pos==1,
                    "You finished "..({"1st","2nd","3rd","4th"})[pos]..".")
            end
            r.lap,r.index,r.lapStart=r.lap+1,1,now
            if r.lap==c.laps then Mission.message(r,"Final lap!") end
        else r.index=r.index+1 end
        drawGate(r)
    end
end

Mission.register("turismo",{course=true,title="Turismo",models={},onFoot=true,canStart=hubFor,start=startRace,tick=raceTick,
    stop=function(r)
        if r.unfreeze and isElement(r.vehicle) then setElementFrozen(r.vehicle,false) end
    end})

addEventHandler("onResourceStart",resourceRoot,function()
    for _,hub in ipairs(hubs) do
        local marker=exports.marker:createMarker(hub[1],hub[2],hub[3]-0.8,"cylinder",2,237,130,180,228)
        if marker then
            addEventHandler("onMarkerHit",marker,function(player,sameDimension)
                if sameDimension and getElementType(player)=="player" and hubFor(player) then
                    Mission.startActivity(player,"turismo")
                end
            end,false)
        end
    end
end)
local crashRuns={}
local crashStarts={
    crash={title="Crash!",model=237,point={-89.03,916.2,10.15},goal=2000},
    rush={title="Rush!",model=216,point={-949.2,-1458.8,11.6},goal=1700}
}

local function award(r,kind,amount)
    if r.score>=9999 then return end
    r.score=r.score+amount
    Mission.hud(r,"Damage","$"..r.score)
    Mission.message(r,("%s  $%d"):format(kind,amount))
end

local function candidate(r,from,to)
    if not isElement(to) or getElementType(to)~="vehicle" or to==r.vehicle or to==from or to==r.lastContact
        or r.wrecks[to] or isVehicleBlown(to) or isElementInWater(to)
        or not Mission.vehicleAvailable(r,to) or getElementInterior(to)~=r.interior
        or getElementDimension(to)~=r.dimension or r.targets[to] then return end
    if not isElement(from) or from~=r.vehicle and not r.targets[from] then return end
    local x,y,z=getElementPosition(from)
    local tx,ty,tz=getElementPosition(to)
    if getDistanceBetweenPoints3D(x,y,z,tx,ty,tz)>14 then return end
    local count=0
    for _ in pairs(r.targets) do count=count+1 end
    if count>=10 then return end
    local _,_,yaw=getElementRotation(to)
    local now=getTickCount()
    r.lastContact=to
    r.targets[to]={z=tz,yaw=yaw,turns=0,driver=getVehicleOccupant(to),untilTime=now+5000}
    if from~=r.vehicle then
        r.chain=now<(r.chainUntil or 0) and r.chain+1 or 1
        r.chainUntil=math.max(r.chainUntil or now,now)+1000
        Mission.message(r,("Knockon! X%d"):format(r.chain))
    end
end

addEvent("mission:crashContact",true)
addEventHandler("mission:crashContact",resourceRoot,function(token,id,from,to)
    if source~=resourceRoot or not client or not crashStarts[id] then return end
    local r=Mission.forParticipant(client,token,id)
    if r and Mission.driverOf(r.vehicle)==client then candidate(r,from,to) end
end,false)

local function settle(r,t)
    if t.amount then award(r,t.kind,t.amount) end
end

local function observe(r,now)
    for car,t in pairs(r.targets) do
        if isElement(car) then
            local x,y,z=getElementPosition(car)
            local matrix=getElementMatrix(car)
            local _,_,yaw=getElementRotation(car)
            if isElementInWater(car) then t.kind,t.amount="Car sunk!",250
            elseif isVehicleBlown(car) or getElementHealth(car)<=250 then t.kind,t.amount="Car destroyed!",300
            elseif getVehicleType(car)=="Bike" and t.driver and not getVehicleOccupant(car) then t.kind,t.amount="Bike dismount!",50
            elseif matrix and matrix[3][3]<0 then t.kind,t.amount="Car flipped!",150
            elseif z-t.z>1 and not isVehicleOnGround(car) then t.kind,t.amount="High flier!",25
            elseif math.abs((yaw-t.yaw+180)%360-180)>=60 then
                t.turns=t.turns+1
                t.yaw=yaw
                t.kind,t.amount=("Car spun! %d degrees"):format(t.turns*90),10*t.turns*(1+(r.chain or 0))
            end
        end
        if now>=t.untilTime or not isElement(car) then
            if t.kind=="Car destroyed!" or t.kind=="Car sunk!" then r.wrecks[car]=true end
            settle(r,t)
            r.targets[car]=nil
        end
    end
    if r.chainUntil and now>=r.chainUntil then r.chain,r.chainUntil=0,nil end
end

addEventHandler("onVehicleExplode",root,function()
    for _,r in pairs(crashRuns) do
        local t=r.targets[source]
        if t then t.kind,t.amount="Car destroyed!",300 end
    end
end)

-- CRASH_3645 counts pedestrians hit within a two-second combo window.
-- The PS2 table initializes monetary bonuses for vehicles (slots 1-6).
addEventHandler("onPedWasted",root,function(_,killer,weapon)
    if not isElement(killer) then return end
    local driver=getElementType(killer)=="vehicle" and getVehicleController(killer) or killer
    local r=crashRuns[driver]
    if not r or Mission.driverOf(r.vehicle)~=driver or (killer~=r.vehicle and weapon~=49 and weapon~=50) then return end
    if getElementDimension(source)~=r.dimension or getElementInterior(source)~=r.interior then return end
    local x,y,z=getElementPosition(r.vehicle)
    local px,py,pz=getElementPosition(source)
    if getDistanceBetweenPoints3D(x,y,z,px,py,pz)>12 then return end
    local now=getTickCount()
    r.splats=now<(r.splatUntil or 0) and r.splats+1 or 1
    r.splatUntil=math.max(now,r.splatUntil or 0)+2000
    if r.splats>1 then Mission.message(r,("SPLAT X%d"):format(r.splats)) end
end)

local function startCrash(r,now)
    local spec=crashStarts[r.id]
    r.score,r.chain,r.targets=0,0,{}
    r.wrecks=setmetatable({},{__mode="k"})
    r.deadline=now+180000
    crashRuns[r.player]=r
    r.startHealth=getElementHealth(r.vehicle)
    r.healthBonus=math.max(0,1800-r.startHealth)
    if r.healthBonus>0 then setElementHealth(r.vehicle,1800) end
    Mission.hud(r,"Damage","$0")
    Mission.message(r,("Cause $%d worth of destruction within the time limit."):format(spec.goal))
    Mission.notify(r,"mission:crashWatch",r.token,r.id,r.vehicle)
end

local function crashTick(r,now)
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) or isElementInWater(r.vehicle) then
        return Mission.fail(r,"Vehicle destroyed!")
    end
    if Mission.driverOf(r.vehicle)~=r.player then
        if not r.returnAt then
            r.returnAt=math.min(now+30000,r.deadline-1)
            Mission.showReturnVehicle(r,r.vehicle)
            Mission.message(r,"Get back in your vehicle within 30 seconds.")
        elseif now>=r.returnAt then return Mission.fail(r,"You failed to return to your vehicle.") end
    elseif r.returnAt then
        r.returnAt=nil
        Mission.clearReturnVehicle(r)
    end
    observe(r,now)
end

local function endCrash(r,now)
    observe(r,now)
    if r.returnAt then return Mission.fail(r,"You failed to return to your vehicle.") end
    if r.score<crashStarts[r.id].goal then return Mission.fail(r,"You failed to cause enough destruction.") end
    local record=Mission.courseRecord(r,r.id)
    if not record then return Mission.fail(r,"Your result could not be saved.") end
    Mission.finishCourse(r,r.id,{score=r.score},record.wins==0 and 1000 or 250,true)
end

local function stopCrash(r)
    crashRuns[r.player]=nil
    if r.healthBonus and r.healthBonus>0 and isElement(r.vehicle) and not isVehicleBlown(r.vehicle) then
        -- Subtract this run's boost while preserving damage. Finishing an event
        -- must never ignite an otherwise surviving road vehicle or repair it.
        local current=getElementHealth(r.vehicle)
        local ordinary=math.min(current,r.startHealth,math.max(251,current-r.healthBonus))
        if ordinary<current then setElementHealth(r.vehicle,ordinary) end
    end
    if r.score>0 and not r.courseFinished then Mission.recordCourse(r,r.id,{score=r.score}) end
end

for id,config in pairs(crashStarts) do
    local spec=config
    Mission.register(id,{course=true,title=spec.title,models={spec.model},start=startCrash,tick=crashTick,expire=endCrash,stop=stopCrash,
        canStart=function(player,vehicle)
            return getElementDimension(player)==0 and getElementInterior(player)==0 and getElementHealth(vehicle)>250 and near(vehicle,spec.point,8,8)
        end})
end
