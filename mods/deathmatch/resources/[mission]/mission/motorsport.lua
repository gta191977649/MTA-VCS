local hubs = {{-1053.4585,-795.2299,10.9704,1,5}, {251.511,-304.312,11.1,6,9}}
-- Collision can stream out beneath a synchronized vehicle. Keep the original
-- 2D ring extents but require the vehicle to be on the course's vertical level.
local gateHeight=8
-- These SCM exits lie on the road *after* the following
-- scoring ring. The next directed leg passes them on its way out.
local downstreamExits={
    RACTIT4={[8]=true,[9]=true,[14]=true},
    RACTIT7={[2]=true,[7]=true},
}
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
        r.preview=CourseGates.nextBlip(r,n,0,r.lap==r.course.laps and r.index==#gates-1)
    end
end

-- RACEHUB_5569 compares lap, checkpoint, then planar distance to the ring.
local function raceOrder(r)
    local order={}
    local function add(racer,element,slot)
        local x,y=getElementPosition(element)
        local gate=r.course.checkpoints[racer.index]
        order[#order+1]={racer=racer,slot=slot,distance=(gate[1]-x)^2+(gate[2]-y)^2}
    end
    add(r,r.player,4)
    for i,s in ipairs(r.rivals) do add(s,isElement(s.car) and s.car or s.ped,i) end
    table.sort(order,function(a,b)
        if a.racer.lap~=b.racer.lap then return a.racer.lap>b.racer.lap end
        if a.racer.index~=b.racer.index then return a.racer.index>b.racer.index end
        if a.distance~=b.distance then return a.distance<b.distance end
        return a.slot<b.slot
    end)
    for place,entry in ipairs(order) do
        entry.racer.place=place
    end
end

-- Compare the authored steering offset with the local direction of travel.
-- An offset ahead of the ring is an exit; an offset behind it is an approach.
local function offsetStage(gates,index)
    local p=gates[index]
    local previous=gates[(index-2)%#gates+1]
    local following=gates[index%#gates+1]
    local dx,dy=p[4]-p[1],p[5]-p[2]
    local ix,iy=p[1]-previous[1],p[2]-previous[2]
    local ox,oy=following[1]-p[1],following[2]-p[2]
    local il,ol=math.max(1,math.sqrt(ix*ix+iy*iy)),math.max(1,math.sqrt(ox*ox+oy*oy))
    if dx*dx+dy*dy<=1 then return "gate" end
    if dx*(ix/il+ox/ol)+dy*(iy/il+oy/ol)>0 then return "exit" end
    return "approach"
end

local function aimForGate(r,s)
    local stage=offsetStage(r.course.checkpoints,s.index)
    s.aim=s.index
    s.approachPassed=nil
    s.hasExit=stage=="exit"
    s.steerPoint=stage=="approach" and "approach" or "gate"
    local guides=r.course.driverGuides and r.course.driverGuides[s.index]
    if guides and (guides~=s.legGuides or s.guideLap~=s.lap) then
        s.legGuides,s.guideLap,s.guideIndex=guides,s.lap,1
    end
end

local function nextSteeringPoint(r,s)
    local gates=r.course.checkpoints
    local p=gates[s.aim]
    if s.steerPoint=="approach" or s.steerPoint=="reenter" then return p[1],p[2] end
    if s.steerPoint=="gate" and s.lap==r.course.laps and s.aim==#gates then return end
    if s.steerPoint=="gate" and s.hasExit then return p[4],p[5] end
    local index=s.aim%#gates+1
    local nextGate=gates[index]
    local offset=offsetStage(gates,index)=="approach" and 3 or 0
    return nextGate[offset+1],nextGate[offset+2]
end

local function inside(x,y,z,p,radius)
    return math.abs(x-p[1])<=radius and math.abs(y-p[2])<=radius and math.abs(z-p[3])<=gateHeight
end

-- Intersect one sampled driving segment with the ring's X/Y extents and
-- height band. Keep the entry fraction so finishes in one tick can be ordered.
local function clipAxis(lo,hi,origin,delta,center,radius)
    if delta==0 then
        if math.abs(origin-center)>radius then return end
        return lo,hi
    end
    local a,b=(center-radius-origin)/delta,(center+radius-origin)/delta
    if a>b then a,b=b,a end
    lo,hi=math.max(lo,a),math.min(hi,b)
    if lo<=hi then return lo,hi end
end

local function crossingTime(r,racer,car,now)
    local x,y,z=getElementPosition(car)
    local old=racer.crossSample
    racer.crossSample={x=x,y=y,z=z,at=now,car=car,index=racer.index,lap=racer.lap}
    local p=r.course.checkpoints[racer.index]
    local radius=racer.lap==r.course.laps and racer.index==#r.course.checkpoints and 15 or 12
    if not old or old.car~=car then
        return nil,inside(x,y,z,p,radius)
    end
    if now<=old.at then return end
    local dx,dy,dz=x-old.x,y-old.y,z-old.z
    local d2=dx*dx+dy*dy+dz*dz
    local dt=now-old.at
    -- A discontinuity is a new baseline; never sweep a teleport across a ring.
    if d2>(10+dt*0.125*getGameSpeed())^2 then return nil,inside(x,y,z,p,radius) end
    if dx==0 and dy==0 then return nil,false,old end
    if old.index==racer.index and old.lap==racer.lap
        and math.abs(old.x-p[1])<=radius and math.abs(old.y-p[2])<=radius then return nil,false,old end
    local lo,hi=clipAxis(0,1,old.x,dx,p[1],radius)
    if lo then lo,hi=clipAxis(lo,hi,old.y,dy,p[2],radius) end
    -- Enter through the ring footprint at road height. Falling through its
    -- top or rising into its bottom cannot complete a checkpoint.
    if lo and math.abs(old.z+dz*lo-p[3])<=gateHeight then return old.at+lo*dt,false,old end
    return nil,false,old
end

local function steerAfterSample(r,s,crossed,previous)
    local gates=r.course.checkpoints
    local aim=gates[s.aim]
    local x,y,z=getElementPosition(s.car)
    local guide=s.guideIndex and s.legGuides[s.guideIndex]
    if guide then
        local gx,gy,gz=x,y,z
        if previous then
            local dx,dy=x-previous.x,y-previous.y
            local length=dx*dx+dy*dy
            if length>0 then
                local t=math.max(0,math.min(1,((guide[1]-previous.x)*dx+(guide[2]-previous.y)*dy)/length))
                gx,gy,gz=previous.x+t*dx,previous.y+t*dy,previous.z+t*(z-previous.z)
            end
        end
        if (gx-guide[1])^2+(gy-guide[2])^2<=2.5^2 and math.abs(gz-guide[3])<gateHeight then
            s.guideIndex=s.legGuides[s.guideIndex+1] and s.guideIndex+1 or nil
        end
    end
    local distance=r.course.aimRadius or 15
    local reached=math.abs(x-aim[4])<=distance and math.abs(y-aim[5])<=distance and math.abs(z-aim[6])<=gateHeight
    if crossed then
        local downstream=downstreamExits[r.course.key]
        if s.aim==s.index and s.hasExit and not reached and not (downstream and downstream[s.aim]) then
            s.steerPoint="exit"
        else s.steerPoint=nil end
        s.index=s.index+1
        if s.index>#gates then s.index,s.lap=1,s.lap+1 end
        if not s.steerPoint then aimForGate(r,s) end
    elseif s.steerPoint=="reenter" then
        local radius=s.lap==r.course.laps and s.index==#gates and 15 or 12
        if not inside(x,y,z,gates[s.index],radius) then s.steerPoint="gate" end
    elseif s.steerPoint=="exit" and reached then aimForGate(r,s)
    elseif s.steerPoint=="approach" and reached then
        s.approachPassed=true
        s.steerPoint="gate"
    end
end

local function resetSyncedCrossing()
    local run=Mission.runForActor(source)
    if not run or not run.rivals then return end
    for _,rival in ipairs(run.rivals) do
        if source==rival.car or source==rival.ped then rival.crossSample=nil end
    end
end

addEventHandler("npc_hlc:onRaceVehicleReposition",root,resetSyncedCrossing)

local function drive(r,s)
    local p=r.course.checkpoints[s.aim]
    local offset=s.steerPoint=="gate" and 0 or 3
    local x,y,z=p[offset+1],p[offset+2],p[offset+3]
    if s.steerPoint=="reenter" then
        -- Restore/takeover inside the pending gate must drive out and return.
        -- Pick a point on the approach, beyond the widest (finish) ring.
        local gates=r.course.checkpoints
        local guided=r.course.driverGuides and r.course.driverGuides[s.index]
        local prev=guided and gates[s.index%#gates+1] or gates[(s.index-2)%#gates+1]
        local dx,dy=prev[1]-p[1],prev[2]-p[2]
        local scale=24/math.max(1,math.abs(dx),math.abs(dy))
        x,y,z=p[1]+dx*scale,p[2]+dy*scale,p[3]+(prev[3]-p[3])*math.min(1,scale)
    end
    local speed=r.course.speed
    local sx,sy=getElementPosition(s.car)
    local limits=r.course.limits
    local limit=limits[p[7]]
    if limit and math.abs(sx-x)<=limit[1] and math.abs(sy-y)<=limit[1] then
        speed=math.min(speed,limit[2])
    elseif p[7]<1000 and limits.addOffsets then
        speed=speed+p[7]
    end
    if s.place and r.place and s.place<r.place then
        local px,py=getElementPosition(r.player)
        local leader=limits.leader
        if math.abs(px-sx)>leader[1] or math.abs(py-sy)>leader[1] then speed=math.min(speed,leader[2]) end
    end
    for _,other in ipairs(r.rivals) do
        if not other.finishAt and s.place and other.place==s.place-1 and isElement(other.car) and getVehicleOccupant(other.car,0)==other.ped then
            local ox,oy=getElementPosition(other.car)
            local pack=limits.pack
            if math.abs(sx-ox)<=pack[1] and math.abs(sy-oy)<=pack[1] then speed=speed+pack[2] end
        end
    end
    speed=math.floor(math.max(limits.cruise[1],math.min(limits.cruise[2],speed)))
    local nextX,nextY=nextSteeringPoint(r,s)
    local guide=s.guideIndex and s.legGuides[s.guideIndex]
    if guide then
        local following=s.legGuides[s.guideIndex+1]
        nextX,nextY=following and following[1] or x,following and following[2] or y
        x,y,z=unpack(guide)
        speed=math.min(speed,guide[4] or 14)
    end
    if s.driveAim==s.aim and s.drivePoint==s.steerPoint and s.driveSpeed==speed and s.driveGuide==guide then return true end
    local arrivalRadius
    if not guide and s.steerPoint~="reenter" then
        if s.steerPoint=="gate" then
            arrivalRadius=s.lap==r.course.laps and s.aim==#r.course.checkpoints and 15 or 12
        else
            arrivalRadius=r.course.aimRadius or 15
        end
    end
    if not exports.npchlc_traffic:setMissionRaceTarget(s.ped,x,y,z,speed,nextX,nextY,guide~=nil,arrivalRadius) then return false end
    s.driveAim,s.drivePoint,s.driveSpeed,s.driveGuide=s.aim,s.steerPoint,speed,guide
    return true
end

local function gridPose(slot,model)
    if model then
        local z,pitch,roll=exports.npc_hlc:getVcsRoadSpawnPose(model,slot[1],slot[2],slot[3],slot[4])
        if z then return z,pitch,roll end
    end
    return slot[3],0,0
end

local function startGrid(r,car,now)
    local c=r.course
    if not Mission.claimSite(r,"turismo/grid/"..c.key) then
        if c.playerModel then Mission.fail(r,"The starting grid is in use.") end
        return
    end
    local g=c.grid
    local model=c.playerModel or (isElement(car) and (getElementData(car,"vcs_vehicle:originalModel",false)
        or getElementData(car,"npchlc_traffic:originalModel",false)))
    local playerZ,playerPitch,playerRoll=gridPose(g,model)
    if c.playerModel then
        car=Mission.track(r,exports.vcs_vehicle:createVcsVehicle(c.playerModel,g[1],g[2],playerZ,playerPitch,playerRoll,g[4]))
        if not car or not warpPedIntoVehicle(r.player,car,0) then
            return Mission.fail(r,"The starting grid could not be prepared.")
        end
        r.requiredVehicle=car
        exports.vcs_vehicle:setVcsVehiclePaint(car,c.playerPaint,c.playerPaint)
        setVehicleEngineState(car,true)
    end
    if not Mission.switchVehicle(r,car) then
        Mission.releaseSite(r,"turismo/grid/"..c.key)
        return
    end
    clearGate(r)
    r.rivals={}
    for i,v in ipairs(c.rivals) do
        local z,pitch,roll=gridPose(v,v[5])
        exports.npchlc_traffic:clearAreaOfCars(v[1],v[2],v[3],20,r.interior,r.dimension,car)
        local vehicle=Mission.track(r,exports.vcs_vehicle:createVcsVehicle(v[5],v[1],v[2],z,pitch,roll,v[4]))
        local ped=Mission.track(r,exports.npchlc_traffic:createTrafficScriptPed(v[6] or 14,v[1],v[2],z,r.interior,r.dimension,v[7]))
        if not vehicle or not ped or not warpPedIntoVehicle(ped,vehicle,0) then
            return Mission.fail(r,"The starting grid could not be prepared.")
        end
        setElementDimension(vehicle,r.dimension)
        local paint=v[8] or i-1
        exports.vcs_vehicle:setVcsVehiclePaint(vehicle,paint,paint)
        setVehicleLocked(vehicle,true)
        setElementData(vehicle,"mission:turismoRival","grid","broadcast","deny")
        setElementData(ped,"mission:turismoRival","driver","broadcast","deny")
        setElementFrozen(vehicle,true)
        setVehicleEngineState(vehicle,true)
        r.rivals[i]={car=vehicle,ped=ped,index=1,aim=1,lap=1}
    end
    for _,slot in ipairs(c.rivals) do
        exports.npchlc_traffic:clearAreaOfCars(slot[1],slot[2],slot[3],100,r.interior,r.dimension,car)
    end
    exports.npchlc_traffic:clearAreaOfCars(g[1],g[2],g[3],100,r.interior,r.dimension,car)
    setElementPosition(car,g[1],g[2],playerZ)
    setElementRotation(car,playerPitch,playerRoll,g[4])
    setElementVelocity(car,0,0,0)
    r.unfreeze=not isElementFrozen(car)
    setElementFrozen(car,true)
    r.startAt=now+3000
    r.phase="countdown"
    exports.npchlc_traffic:setMissionTrafficDensity(r.player,0)
end

local function correctVehicle(r,car)
    if not car or Mission.driverOf(car)~=r.player or not Mission.vehicleAvailable(r,car) then return false end
    if r.requiredVehicle then return car==r.requiredVehicle end
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
        return Mission.selectCourse(r,r.options,choose,index)
    end
    if not takePlayerMoney(r.player,c.fee) then return Mission.fail(r,"The entry fee could not be paid.") end
    if r.unfreezeAtOrganizer then setElementFrozen(r.player,false) r.unfreezeAtOrganizer=nil end
    r.course,r.phase=c,"grid"
    exports.npchlc_traffic:setMissionTrafficDensity(r.player,10)
    r.gate=Mission.marker(r,c.grid[1],c.grid[2],c.grid[3],"checkpoint",3.5,pink,true)
    Mission.message(r,"Get a "..(c.kind==2 and "motorbike" or "car").." and head for the start line.")
end

local function startRace(r)
    r.hub=hubFor(r.player)
    r.unfreezeAtOrganizer=not isElementFrozen(r.player)
    if r.unfreezeAtOrganizer then setElementFrozen(r.player,true) end
    r.options={}
    for i=r.hub[4],r.hub[5] do
        local c=TurismoCourses[i]
        local rec=Mission.courseRecord(r,c.key)
        r.options[#r.options+1]={
            key=c.key, name=c.name, number=i, model=c.previewModel, board=r.hub==hubs[1] and "mainla" or "beach",
            fee=c.fee, prize=c.prize, kind=c.kind==2 and "Motorbike" or "Car", laps=c.laps,
            position=rec and rec.position, time=rec and rec.time,
        }
    end
    Mission.selectCourse(r,r.options,choose)
end

local function inRaceBounds(player,areas)
    local x,y=getElementPosition(player)
    for _,area in ipairs(areas) do
        if x>area[1] and y>area[2] and x<area[3] and y<area[4] then return true end
    end
    return false
end

local function raceTick(r,now)
    if not r.course then return end
    local c,car=r.course,getPedOccupiedVehicle(r.player)
    if r.phase=="grid" then
        if correctVehicle(r,car) and near(car,c.grid,3.5,10) then startGrid(r,car,now) end
        return
    end
    if r.requiredVehicle and (not isElement(r.requiredVehicle) or isVehicleBlown(r.requiredVehicle)) then
        return Mission.fail(r,"Your Quad was destroyed.")
    end
    if c.bounds then
        if inRaceBounds(r.player,c.bounds.warn) then
            if r.warnedBounds then r.warnedBounds=nil Mission.message(r,false) end
        elseif not r.warnedBounds then
            r.warnedBounds=true
            Mission.message(r,"Don't leave the trailer park.")
        elseif not inRaceBounds(r.player,c.bounds.fail) then
            return Mission.fail(r,"You left the trailer park.")
        end
    end
    -- A dead driver is state 7, even after crossing the finish (RACEHUB_6591).
    for _,s in ipairs(r.rivals) do
        if not isElement(s.ped) or isPedDead(s.ped) then
            return Mission.fail(r,"One of the racers has died - the race has been called off.")
        end
    end
    if r.phase=="countdown" then
        for _,s in ipairs(r.rivals) do
            -- A damaged grid vehicle starts the race early (RACEHUB_7495/12362).
            if isElement(s.car) and not isVehicleBlown(s.car) and Mission.turismoGridDamage(s.car) then r.startAt=now end
        end
        if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) or car~=r.vehicle or Mission.driverOf(car)~=r.player then
            return Mission.fail(r,"You left the starting grid.")
        end
        if now<r.startAt then
            local n=math.ceil((r.startAt-now)/1000)
            if n~=r.count then r.count=n Mission.countdown(r,n) end
            return
        end
        if r.unfreeze then setElementFrozen(car,false) r.unfreeze=false end
        r.elapsedFrom,r.lapStart,r.lap,r.index,r.phase=now,now,1,1,"racing"
        exports.npchlc_traffic:setMissionTrafficDensity(r.player,c.density)
        raceOrder(r)
        for _,s in ipairs(r.rivals) do
            -- RACEHUB_5808 uses display 1 for race rivals (world arrow only).
            aimForGate(r,s)
            s.marker=Mission.entityArrow(r,s.ped,{0,0,255,255},false)
            if isElement(s.car) then
                setElementData(s.car,"mission:turismoRival","racing","broadcast","deny")
                setElementFrozen(s.car,false)
                if not isVehicleBlown(s.car) then setElementHealth(s.car,1000) end
            end
            if isElement(s.car) and not isVehicleBlown(s.car) and getVehicleOccupant(s.car,0)==s.ped then
                if not exports.npchlc_traffic:startMissionRaceDriver(s.ped,s.car,2) or not drive(r,s) then
                    return Mission.fail(r,"The starting grid could not be prepared.")
                end
                -- RACEHUB_6029 starts the leading two rivals with 02E9.
                if s.place<=2 then
                    local forward=getElementMatrix(s.car)[2]
                    local launch=(s.place==1 and 20 or 15)/60
                    setElementVelocity(s.car,forward[1]*launch,forward[2]*launch,forward[3]*launch)
                end
            end
        end
        Mission.releaseSite(r,"turismo/grid/"..c.key)
        Mission.countdown(r,0)
        drawGate(r)
    end

    raceOrder(r)
    local eligible=isElement(car) and not isVehicleBlown(car) and correctVehicle(r,car)
        and (r.vehicle==car or Mission.switchVehicle(r,car))
    local playerCrossed
    if eligible then playerCrossed=crossingTime(r,r,car,now) else r.crossSample=nil end
    for _,s in ipairs(r.rivals) do
        if s.lap<=c.laps and Mission.turismoDriverReady(r,s,now) then
            if not s.steerPoint then aimForGate(r,s) end
            local crossed,resetInside,previous=crossingTime(r,s,s.car,now)
            if resetInside then
                aimForGate(r,s)
                s.guideIndex=nil
                s.steerPoint="reenter"
            end
            steerAfterSample(r,s,crossed,previous)
            if s.lap>c.laps then
                s.finishAt=crossed
                exports.npchlc_traffic:stopMissionRaceDriver(s.ped)
                if isElement(s.marker) then destroyElement(s.marker) end
                removeElementData(s.car,"mission:turismoRival")
                -- RACEHUB_6469 gives finishers action 5 for 3, 2 and 1 seconds.
                r.finishedRivals=(r.finishedRivals or 0)+1
                exports.npc_hlc:setNPCTask(s.ped,{"stopVehicle",(4-r.finishedRivals)*1000,tempAction=5})
            elseif not drive(r,s) then return Mission.fail(r,"The race has been called off.") end
        end
    end
    local kind=c.kind==3 and "Quad" or c.kind==2 and "motorbike" or "car"
    if r.returnAt and math.floor((r.returnAt-now)/1000)<1 then
        return Mission.fail(r,"You have been disqualified for leaving your "..kind..".")
    end
    -- All Turismo courses allow any vehicle of the requested class ($5776=-1).
    if not eligible then
        if not r.returnAt then
            r.returnAt=now+30400
            clearGate(r)
            if r.requiredVehicle then Mission.showReturnVehicle(r,r.requiredVehicle) end
            exports.npchlc_traffic:setMissionTrafficDensity(r.player,10)
        end
        local left=math.floor((r.returnAt-now)/1000)
        if left~=r.returnSeconds then
            r.returnSeconds=left
            local action=r.requiredVehicle and "get back on the " or "find a "
            Mission.message(r,("You have %d second%s to %s%s."):format(left,left==1 and "" or "s",action,kind))
        end
        return
    elseif r.returnAt then
        r.returnAt,r.returnSeconds=nil,nil
        if r.requiredVehicle then Mission.clearReturnVehicle(r) end
        Mission.message(r,false)
        exports.npchlc_traffic:setMissionTrafficDensity(r.player,c.density)
        drawGate(r)
    end
    local pos=r.place
    Mission.hud(r,"Lap",("%d/%d   %s"):format(r.lap,c.laps,({"1st","2nd","3rd","4th"})[pos]))
    if playerCrossed then
        Mission.checkpointCue(r,r.index==#c.checkpoints)
        if r.index==#c.checkpoints then
            local at=math.floor(playerCrossed+0.5)
            local lap=at-r.lapStart
            r.bestLap=math.min(r.bestLap or lap,lap)
            if r.lap==c.laps then
                local place=1
                for _,rival in ipairs(r.rivals) do
                    if rival.finishAt and rival.finishAt<=playerCrossed then place=place+1 end
                end
                return Mission.finishCourse(r,c.key,{time=at-r.elapsedFrom,lap=r.bestLap,position=place},
                    place==1 and c.prize or 0,place==1,"You finished "..({"1st","2nd","3rd","4th"})[place]..".")
            end
            r.lap,r.index,r.lapStart=r.lap+1,1,at
            if r.lap==c.laps then Mission.message(r,"Final lap!") end
        else r.index=r.index+1 end
        drawGate(r)
    end
end

local function weaponHit(weapon)
    return type(weapon)=="number" and weapon%1==0 and (weapon>=1 and weapon<=18 or weapon>=22 and weapon<=42)
end

local function racerAttacked(player,ped,weapon)
    if not isElement(ped) or getElementType(ped)~="ped" or not weaponHit(weapon) then return end
    local run=Mission.runForActor(ped)
    if run and run.rivals and run.player==player and (run.phase=="countdown" or run.phase=="racing") then
        for _,s in ipairs(run.rivals) do
            if s.ped==ped then
                Mission.fail(run,"You attacked a racer - the race has been called off.")
                return
            end
        end
    end
end

addEventHandler("onPedWasted",root,function(_,killer,weapon)
    racerAttacked(killer,source,weapon)
end)

-- The ped damage event identifies the victim, including a seated driver.
-- The server weapon-fire event alone cannot confirm that a ped took a hit.
addEvent("mission:turismoWeaponHit",true)
addEventHandler("mission:turismoWeaponHit",resourceRoot,function(token,ped,weapon)
    if source~=resourceRoot or not client or not isElement(ped) or not weaponHit(weapon) then return end
    local r=Mission.rivalParticipant(client,token,ped)
    if not r then return end
    -- Player-attributed weapon fire can arrive after changing weapons or
    -- exhausting a thrown weapon. Neither damage type proves a current slot.
    local areaDamage=weapon==18 or weapon==37
    if not areaDamage and not getPedOccupiedVehicle(client) then
        local slot=getSlotFromWeapon(weapon)
        if not slot or getPedWeapon(client,slot)~=weapon then return end
    end
    local x,y,z=getElementPosition(client)
    -- The server can retain a streamed-out driver's last on-foot position
    -- while the unowned race vehicle continues to move.
    local px,py,pz=getElementPosition(getPedOccupiedVehicle(ped) or ped)
    local range=areaDamage and 300 or weapon<=15 and 8 or (getWeaponProperty(weapon,"pro","weapon_range") or 150)+25
    if getDistanceBetweenPoints3D(x,y,z,px,py,pz)<=range then racerAttacked(client,ped,weapon) end
end,false)


local function stopRace(r)
    if r.unfreezeAtOrganizer and isElement(r.player) then setElementFrozen(r.player,false) end
    local traffic=getResourceFromName("npchlc_traffic")
    if traffic and getResourceState(traffic)=="running" then
        if isElement(r.player) and r.course then exports.npchlc_traffic:setMissionTrafficDensity(r.player,false) end
        for _,s in ipairs(r.rivals or {}) do
            if isElement(s.ped) then exports.npchlc_traffic:stopMissionRaceDriver(s.ped) end
        end
    end
    if r.unfreeze and isElement(r.vehicle) then setElementFrozen(r.vehicle,false) end
end

Mission.register("turismo",{course=true,title="Turismo",models={},onFoot=true,canStart=hubFor,start=startRace,tick=raceTick,stop=stopRace})

local function atQuadOrganizer(player)
    return getElementDimension(player)==0 and getElementInterior(player)==0 and not getPedOccupiedVehicle(player)
        and near(player,LouiseQuadRace.entry,2,2)
end

Mission.register("louisequadrace",{course=true,title=LouiseQuadRace.name,models={},onFoot=true,canStart=atQuadOrganizer,
    start=function(r,now)
        r.course=LouiseQuadRace
        startGrid(r,nil,now)
    end,tick=raceTick,stop=stopRace})

addEventHandler("onResourceStart",resourceRoot,function()
    local e=LouiseQuadRace.entry
    local marker=exports.marker:createMarker(e[1],e[2],e[3]-0.8,"cylinder",2,237,130,180,228)
    if marker then
        addEventHandler("onMarkerHit",marker,function(player,sameDimension)
            if sameDimension and getElementType(player)=="player" and atQuadOrganizer(player) then
                Mission.startActivity(player,"louisequadrace")
            end
        end,false)
    end
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
