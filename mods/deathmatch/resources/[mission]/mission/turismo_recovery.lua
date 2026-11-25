-- RACEHUB_4749 / LOU_A1_4718 use the previous authored driver aim.
local function nearPlayer(player,x,y)
    local px,py=getElementPosition(getPedOccupiedVehicle(player) or player)
    return math.abs(px-x)<=30 and math.abs(py-y)<=30
end

local function liveCar(car)
    if not isElement(car) or isVehicleBlown(car) or isElementInWater(car) then return false end
    if getElementSyncer(car) or getElementInterior(car)~=0 then return true end
    local x,y,z=getElementPosition(car)
    -- All 212 exterior VCS water quads have a surface at Z6. Without a
    -- syncer, MTA does not run buoyancy or refresh the vehicle's wet flag.
    if z>=6 then return true end
    local map=getResourceFromName("vcs")
    if not map or getResourceState(map)~="running" then return true end
    local water=exports.vcs:getVcsWaterQuadLevel(x,y)
    if not water or z>=water-0.25 then return true end
    -- Retain a lower, supported passage if terrain also covers it overhead.
    local floor=exports.npc_hlc:getVcsGroundHeight(x,y,z-0.8)
    if floor and floor<=z and z-floor<2 then
        local roof=exports.npc_hlc:getVcsGroundHeight(x,y,water+2)
        if roof and roof>z+2 then return true end
    end
    return false
end

-- RACEHUB_5209 searches up to three rings behind the player.
local function catchupPoint(r,s)
    local limits=r.course.limits.catchup
    if not limits or not s.place or not r.place or s.place<=r.place or not liveCar(s.car)
        or getVehicleOccupant(s.car,0)~=s.ped or isPedDead(r.player) then return end
    local px,py=getElementPosition(r.player)
    local cx,cy=getElementPosition(s.car)
    if math.abs(px-cx)<=limits[2] and math.abs(py-cy)<=limits[2] then return end
    local gates=r.course.checkpoints
    local index,lap=r.index,r.lap
    for _=1,3 do
        local nextIndex=index
        index=index-1
        if index==0 then index,lap=#gates,lap-1 end
        if lap<1 then return end
        local p=gates[index]
        local distance=math.max(math.abs(px-p[1]),math.abs(py-p[2]))
        if distance>limits[1] and distance<=limits[2] then
            return p[1],p[2],p[3],gates[nextIndex],nextIndex,lap
        end
    end
end

local function recoveryPoint(r,s)
    local gates=r.course.checkpoints
    local aim=s.aim
    local previous=(aim-2)%#gates+1
    -- An exit target still belongs to the ring already scored. Recover from
    -- that ring's authored aim, preserving the next pending checkpoint.
    if s.steerPoint=="exit" then
        previous,aim=aim,s.index
    elseif s.approachPassed then
        previous,aim=aim,aim%#gates+1
    elseif aim==1 and s.lap==1 then
        -- The ten SCM routes loop back to their starting area. Avoid moving
        -- a fresh starter to the far end of a point-to-point extension.
        local start=r.course.grid
        local last=gates[previous]
        if start and math.abs(start[1]-last[4])<=30 and math.abs(start[2]-last[5])<=30
            and math.abs(start[3]-last[6])<=8 then return last[4],last[5],last[6],gates[aim] end
        for i,rival in ipairs(r.rivals) do
            if rival==s then
                local grid=r.course.rivals[i]
                return grid[1],grid[2],grid[3],gates[aim]
            end
        end
    end
    local point=gates[previous]
    return point[4],point[5],point[6],gates[aim]
end

function Mission.turismoGridDamage(car)
    if getElementHealth(car)<=990 then return true end
    local fl,rl,fr,rr=getVehicleWheelStates(car)
    if fl==1 or rl==1 or fr==1 or rr==1 then return true end
    for panel=0,6 do
        if (getVehiclePanelState(car,panel) or 0)>0 then return true end
    end
    local quad=getVehicleType(car)=="Quad"
    for door=0,5 do
        local state=getVehicleDoorState(car,door) or 0
        -- A pristine MTA Quad reports its four absent side doors as state 4.
        if state>=2 and not (quad and door>=2 and state==4) then return true end
    end
    return false
end

local function clearOfPlayer(r,s,x,y)
    local px,py=getElementPosition(getPedOccupiedVehicle(s.ped) or s.ped)
    if nearPlayer(r.player,px,py) or nearPlayer(r.player,x,y) then return false end
    if liveCar(s.car) then
        local cx,cy=getElementPosition(s.car)
        if nearPlayer(r.player,cx,cy) then return false end
    end
    return true
end

local function movedSinceCheck(s,x,y)
    local matrix=getElementMatrix(s.car)
    return matrix and matrix[3][3]>-0.97 and (math.abs(x-s.progressX)>13 or math.abs(y-s.progressY)>13)
end

local function obstructed(r,s,x,y,z,width,height)
    width,height=width or 5,height or 10
    for _,kind in ipairs({"vehicle","ped","object"}) do
        for _,e in ipairs(getElementsWithinRange(x,y,z,40,kind,r.interior,r.dimension)) do
            if e~=s.car and e~=s.ped and (Mission.runForActor(e)
                or kind=="vehicle" and not Mission.vehicleAvailable(nil,e)) then
                local ex,ey,ez=getElementPosition(e)
                -- Mission prop attachments use the small crate proxy (1271).
                -- server_coldata provides model boxes for peds and vehicles.
                local radius=1
                if kind~="object" then
                    local ax,ay,az,bx,by,bz=exports.server_coldata:getModelBoundingBox(getElementModel(e))
                    if ax then radius=math.sqrt(math.max(ax^2,bx^2)+math.max(ay^2,by^2)+math.max(az^2,bz^2)) end
                end
                if math.abs(ex-x)<=width+radius and math.abs(ey-y)<=width+radius
                    and math.abs(ez-z)<=height+radius then return true end
            end
        end
    end
    return false
end

function Mission.turismoDriverReady(r,s,now)
    local catchup
    local driving=liveCar(s.car) and getVehicleOccupant(s.car,0)==s.ped
    if driving then
        if s.recovering then
            if not exports.npchlc_traffic:startMissionRaceDriver(s.ped,s.car,2) then return false end
            s.recovering,s.recoveryCheck,s.crossSample=nil,nil,nil
            s.driveAim,s.driveSpeed=nil,nil
            setElementHealth(s.car,1000)
            setElementData(s.car,"mission:turismoRival","racing","broadcast","deny")
            setVehicleLocked(s.car,true)
            setVehicleEngineState(s.car,true)
        end
        local x,y=getElementPosition(s.car)
        if isElementFrozen(s.car) or not getVehicleEngineState(s.car) then
            s.progressAt,s.recoveryCheck=nil,nil
            return true
        end
        if not s.progressAt or movedSinceCheck(s,x,y) then
            s.progressX,s.progressY,s.progressAt=x,y,now
            if not s.catchupIndex then s.recoveryCheck=nil end
        end
        if now-s.progressAt<=5000 then
            if now<(s.nextRecovery or 0) then return true end
            catchup=catchupPoint(r,s)
            if not catchup then return true end
        end
    elseif not s.recovering then
        exports.npchlc_traffic:stopMissionRaceDriver(s.ped)
        if isElement(s.car) and not isVehicleBlown(s.car) then
            setElementData(s.car,"mission:turismoRival","recovering","broadcast","deny")
        end
        s.recovering,s.crossSample=true,nil
        s.progressAt,s.nextRecovery,s.recoveryCheck=nil,nil,nil
    end
    -- RACEHUB_6839 relinquishes a live vehicle taken by a different driver.
    if not driving and liveCar(s.car) and getVehicleOccupant(s.car,0) then
        removeElementData(s.car,"mission:turismoRival")
        s.car=nil
    end
    if now<(s.nextRecovery or 0) then return driving end
    s.nextRecovery=now+1000
    if liveCar(s.car) and not getVehicleOccupant(s.car,0) then
        setVehicleLocked(s.car,false)
        exports.npchlc_traffic:assignTrafficPedObjective(s.ped,"enterVehicle",s.car,0)
    end
    local x,y,z=recoveryPoint(r,s)
    s.catchupIndex,s.catchupLap=nil,nil
    if catchup then
        local nextAim
        x,y,z,nextAim,s.catchupIndex,s.catchupLap=catchupPoint(r,s)
        s.clearance=7.5+math.random()*17.5
    end
    if x and clearOfPlayer(r,s,x,y) then
        z=exports.npc_hlc:getVcsGroundHeight(x,y,z) or z
        s.recoveryCheck,s.recoveryAim,s.recoveryIndex,s.recoveryLap=now,s.aim,s.index,s.lap
        s.recoveryApproach=s.approachPassed
        triggerClientEvent(r.player,"mission:checkRivalRecovery",resourceRoot,r.token,s.ped,liveCar(s.car) and s.car or false,x,y,z,now,catchup and 8 or 6)
    end
    return driving
end

function Mission.rivalParticipant(player,token,ped)
    if not isElement(ped) then return end
    local r=Mission.runForActor(ped)
    if r and r.rivals and r.player==player and Mission.forParticipant(player,token,r.id)==r then return r end
end

addEvent("mission:rivalRecoveryClear",true)
addEventHandler("mission:rivalRecoveryClear",resourceRoot,function(token,ped,check,ground)
    if source~=resourceRoot or not client or type(ground)~="number" or ground~=ground then return end
    local r=Mission.rivalParticipant(client,token,ped)
    if not r or r.phase~="racing" then return end
    for i,s in ipairs(r.rivals) do
        if type(check)=="number" and s.ped==ped and s.recoveryCheck==check and s.aim==s.recoveryAim
            and s.index==s.recoveryIndex and s.lap==s.recoveryLap and s.approachPassed==s.recoveryApproach
            and s.lap<=r.course.laps and isElement(ped) and not isPedDead(ped) then
            s.recoveryCheck=nil
            if getTickCount()-check>1500 then return end
            local x,y,z,aim=recoveryPoint(r,s)
            local nextIndex,nextLap
            if s.catchupIndex then
                x,y,z,aim,nextIndex,nextLap=catchupPoint(r,s)
                if not x or nextIndex~=s.catchupIndex or nextLap~=s.catchupLap then return end
            elseif liveCar(s.car) and getVehicleOccupant(s.car,0)==ped then
                if isElementFrozen(s.car) or not getVehicleEngineState(s.car) or not s.progressAt then return end
                if movedSinceCheck(s,getElementPosition(s.car)) then return end
            end
            z=exports.npc_hlc:getVcsGroundHeight(x,y,z) or z
            if isPedDead(client) or not clearOfPlayer(r,s,x,y) or obstructed(r,s,x,y,z,nextIndex and s.clearance,nextIndex and s.clearance) then return end
            local heading=math.deg(math.atan2(x-aim[4],aim[5]-y))
            local model=r.course.rivals[i][5]
            local height,pitch,roll=exports.npc_hlc:getVcsRoadSpawnPose(model,x,y,z,heading)
            if height and liveCar(s.car) then
                local loaded,rx,ry=exports.npc_hlc:getVcsRoadVehiclePose(s.car,x,y,height,heading)
                if loaded then height,pitch,roll=loaded,rx,ry end
            end
            if not height then
                height,pitch,roll=(math.abs(ground-z)<4 and ground or z)+0.8,0,0
            end
            if not liveCar(s.car) or (getVehicleOccupant(s.car,0) and getVehicleOccupant(s.car,0)~=ped) then
                local car=Mission.track(r,exports.vcs_vehicle:createVcsVehicle(model,x,y,height,pitch,roll,heading))
                if not car then return end
                if isElement(s.car) then removeElementData(s.car,"mission:turismoRival") end
                s.car=car
                setElementInterior(car,r.interior)
                setElementDimension(car,r.dimension)
                local paint=r.course.rivals[i][8] or i-1
                exports.vcs_vehicle:setVcsVehiclePaint(car,paint,paint)
                setElementData(car,"mission:turismoRival","racing","broadcast","deny")
            else
                exports.npchlc_traffic:stopMissionRaceDriver(ped)
                setElementPosition(s.car,x,y,height)
                setElementRotation(s.car,pitch,roll,heading,"ZXY")
            end
            if nextIndex then
                s.index,s.aim,s.lap=nextIndex,nextIndex,nextLap
                s.steerPoint,s.approachPassed,s.legGuides,s.guideIndex=nil,nil,nil,nil
            end
            s.catchupIndex,s.catchupLap=nil,nil
            s.crossSample=nil
            if s.steerPoint~="exit" and not s.approachPassed and r.course.driverGuides then
                s.legGuides=r.course.driverGuides[s.index]
                s.guideLap,s.guideIndex=s.lap,s.legGuides and 1 or nil
            end
            if getVehicleOccupant(s.car,0)~=ped then
                exports.npchlc_traffic:assignTrafficPedObjective(ped,"clear")
                if getPedOccupiedVehicle(ped) then removePedFromVehicle(ped) end
                if not warpPedIntoVehicle(ped,s.car,0) then return end
            end
            s.driveAim,s.driveSpeed,s.progressAt=nil,nil,nil
            s.recovering=true
            setElementHealth(s.car,1000)
            setElementAngularVelocity(s.car,0,0,0)
            -- 02E9 at 003D5680 converts the SCM forward speed by dividing by 60.
            local speed=(nextIndex and 15 or 10)/60
            local forward=getElementMatrix(s.car)[2]
            setElementVelocity(s.car,forward[1]*speed,forward[2]*speed,forward[3]*speed)
            setVehicleEngineState(s.car,true)
            return
        end
    end
end,false)

addEventHandler("onVehicleStartEnter",root,function(ped)
    if getElementType(ped)=="player" and getElementData(source,"mission:turismoRival",false) then cancelEvent() end
end)
