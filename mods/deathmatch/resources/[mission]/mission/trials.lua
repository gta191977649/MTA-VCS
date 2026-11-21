local starts = {
    watersports={title="Watersports",model=233,x=-140.44,y=1031.14,z=5.91},
    quadtrial={title="Quad Bike Time Trials",model=230,x=-445.2,y=1383.27,z=11.39},
    bmxtrial={title="BMX Time Trials",model=178,x=-427.43,y=1551.35,z=11.32},
    sancheztrial={title="Sanchez Time Trials",model=205,x=-566.92,y=1387.33,z=11.76},
    caddydaddy={title="Caddy Daddy",model=184,x=98.07,y=310.27,z=19.36},
    mallbmx={title="Mashin' Up the Mall",model=178,x=384.95,y=1226.62,z=-198.45,dimension=3090}
}
local pink,green={237,130,180,255},{0,255,0,255}
local coronaColors={{255,0,0,255},green,{0,0,255,255}}

local function discard(e)
    if isElement(e) then destroyElement(e) end
end

local function driving(r)
    return isElement(r.vehicle) and getPedOccupiedVehicle(r.player)==r.vehicle and Mission.driverOf(r.vehicle)==r.player
end

local function clearGate(r)
    discard(r.gate)
    discard(r.preview)
    r.gate,r.preview=nil,nil
end

local function drawGate(r)
    clearGate(r)
    local points=r.course.points
    local p,q=points[r.index],points[r.index%#points+1]
    local finish=r.index==1 and r.lap==3
    r.gate=Mission.marker(r,p[1],p[2],p[3]-0.7,"checkpoint",8,finish and green or pink,true)
    if not r.gate then return Mission.fail(r,"The next checkpoint could not be placed.") end
    if not finish then
        exports.marker:setMarkerTarget(r.gate,q[1],q[2],q[3]-0.7)
        r.preview=Mission.track(r,createBlip(q[1],q[2],q[3]-0.7,0,2,237,130,180,130,0,65535,r.player))
        if r.preview then
            setElementInterior(r.preview,r.interior)
            setElementDimension(r.preview,r.dimension)
        end
    end
end

local function showCoronas(r,visible)
    for _,marker in pairs(r.coronas or {}) do
        if isElement(marker) then exports.marker:setMarkerVisibleTo(marker,r.player,visible) end
    end
end

local function placeCoronas(r)
    r.coronas,r.collected,r.score={},0,0
    for i,p in ipairs(TrialCourses.mallbmx) do
        local marker=Mission.marker(r,p[1],p[2],p[3],"corona",1,coronaColors[p[4]+1],false)
        if not marker then return false end
        r.coronas[i]=marker
    end
    return true
end

local function startClock(r,now)
    r.phase,r.elapsedFrom,r.lapStart="racing",now,now
    if r.unfreeze then setElementFrozen(r.vehicle,false) r.unfreeze=false end
    Mission.countdown(r,"GO!")
    if r.id=="mallbmx" then
        for _,marker in ipairs(r.coronas) do
            exports.marker:setMarkerBlipVisible(marker,true)
            local blip=exports.marker:getMarkerBlip(marker)
            if isElement(blip) then setBlipSize(blip,1) end
        end
        Mission.hud(r,"Checkpoints","0/50")
        Mission.message(r,"Wheelie through the green coronas and stoppie through the blue. Collect the red coronas any way you want.")
    else
        r.index,r.lap=2,1
        Mission.hud(r,"Lap","1/3")
        drawGate(r)
    end
    Mission.notify(r,"mission:trialObserve",r.token,r.id,r.vehicle)
end

local function startGrid(r,now)
    local car=r.vehicle
    if not driving(r) then return Mission.fail(r,"You left your trial vehicle.") end
    -- A parked trial vehicle can carry spectators. Leave their car in place.
    for seat in pairs(getVehicleOccupants(car)) do
        if seat~=0 then
            local x,y,z=getElementPosition(car)
            local copy=exports.vcs_vehicle:createVcsVehicle(starts[r.id].model,x,y,z+1)
            if not copy then return Mission.fail(r,"The trial vehicle is unavailable.") end
            Mission.track(r,copy)
            setElementInterior(copy,r.interior)
            setElementDimension(copy,r.dimension)
            removePedFromVehicle(r.player)
            if not warpPedIntoVehicle(r.player,copy,0) or not Mission.switchVehicle(r,copy) then
                if getPedOccupiedVehicle(r.player)==copy then removePedFromVehicle(r.player) end
                if not getVehicleOccupant(car,0) then warpPedIntoVehicle(r.player,car,0) end
                return Mission.fail(r,"The trial vehicle is unavailable.")
            end
            r.originalVehicle=car
            car=copy
            break
        end
    end
    r.origin={getElementPosition(car)}
    r.rotation={getElementRotation(car)}
    r.unfreeze=not isElementFrozen(car)
    setElementFrozen(car,true)
    setElementVelocity(car,0,0,0)
    if r.id=="mallbmx" then
        r.bikeHealth=getElementHealth(car)
        if not placeCoronas(r) then return Mission.fail(r,"The mall course could not be placed.") end
        if exports.wanted:getPlayerWanted(r.player)==1 then exports.wanted:setPlayerWanted(r.player,0,r.id) end
    elseif r.course then
        local p,q=r.course.points[1],r.course.points[2]
        setElementPosition(car,p[1],p[2],r.id=="watersports" and p[3] or p[3]+0.3)
        setElementRotation(car,0,0,math.deg(math.atan2(p[1]-q[1],q[2]-p[2])))
        if r.course.ramps then Mission.notify(r,"mission:trialRamps",r.token,r.course.ramps,r.interior,r.dimension,r.id) end
    end
    r.phase,r.goAt,r.lastCountdown="countdown",now+3000,3
    Mission.countdown(r,3)
end

local function choose(r,index)
    local record=Mission.courseRecord(r,index)
    if not record then return Mission.fail(r,"Your course record could not be read.") end
    r.record,r.courseIndex=record,index
    if r.id~="mallbmx" then r.course=TrialCourses[r.id][index] end
    r.gridKey=r.id.."/grid/"..index
    if not Mission.claimSite(r,r.gridKey) then
        r.phase="waiting"
        Mission.message(r,"The starting grid is occupied. Your trial will start when it clears.")
        return
    end
    startGrid(r,getTickCount())
end

local function begin(r)
    if r.id=="mallbmx" or #TrialCourses[r.id]==1 then return choose(r,1) end
    local options={}
    for i,c in ipairs(TrialCourses[r.id]) do
        local record=Mission.courseRecord(r,i)
        if not record then return Mission.fail(r,"Your course records could not be read.") end
        local best=record.time and math.min(c.target,record.time) or c.target
        options[i]=("Course %d   %d:%02d"):format(i,math.floor(best/60000),math.floor(best/1000)%60)
        if record.wins==0 then break end
    end
    r.phase="select"
    Mission.selectCourse(r,options,choose)
end

local function collectMall(r,now,x,y,z)
    for i,marker in pairs(r.coronas) do
        local p=TrialCourses.mallbmx[i]
        local valid=p[4]==0 or (r.pose==p[4] and r.poseUntil and now<=r.poseUntil)
        if valid and CourseGates.crossed(r,now,p,2) then
            discard(marker)
            r.coronas[i]=nil
            r.collected,r.score=r.collected+1,r.score+1+p[4]
            Mission.checkpointCue(r)
            Mission.hud(r,"Checkpoints",r.collected.."/50")
        end
    end
    if r.collected==50 then
        local time=now-r.elapsedFrom
        local won=time<math.min(270000,r.record.time or math.huge)
        if Mission.finishCourse(r,1,{time=time,score=r.score},won and 500 or 0,won) and won then
            exports.wanted:setPlayerWanted(r.player,0,r.id)
        end
    end
end

local function checkGate(r,now,x,y,z)
    local points=r.course.points
    local p=points[r.index]
    if not CourseGates.crossed(r,now,p,8,50,-0.7) then return end
    Mission.checkpointCue(r)
    if r.index==1 then
        local lapTime=now-r.lapStart
        if lapTime<math.min(r.bestLap or math.huge,r.record.lap or math.huge) then
            Mission.recordCourse(r,r.courseIndex,{lap=lapTime})
        end
        r.bestLap=math.min(r.bestLap or math.huge,lapTime)
        if r.lap==3 then
            local time=now-r.elapsedFrom
            local won=time<math.min(r.course.target,r.record.time or math.huge)
            local first=won and r.record.wins==0
            local payout=first and (r.courseIndex==#TrialCourses[r.id] and 2600 or 100) or 0
            local outcome
            if first then
                outcome=r.courseIndex==#TrialCourses[r.id] and "You beat the target time. All courses complete!"
                    or "You beat the target time. Next course unlocked."
            end
            return Mission.finishCourse(r,r.courseIndex,{time=time,lap=r.bestLap},payout,won,outcome)
        end
        r.lap,r.lapStart=r.lap+1,now
        Mission.hud(r,"Lap",r.lap.."/3")
    end
    r.index=r.index%#points+1
    drawGate(r)
end

local function tick(r,now)
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return Mission.fail(r,"You destroyed the trial vehicle!") end
    if r.phase=="select" or r.phase=="waiting" then
        if not driving(r) then return Mission.fail(r,"You left the trial vehicle.") end
        if r.phase=="waiting" and Mission.claimSite(r,r.gridKey) then startGrid(r,now) end
        return
    end
    if r.phase=="countdown" then
        if not driving(r) then return Mission.fail(r,"You left the starting grid.") end
        local count=math.ceil((r.goAt-now)/1000)
        if count<=0 then return startClock(r,now) end
        if r.lastCountdown~=count then r.lastCountdown=count Mission.countdown(r,count) end
        return
    end
    if r.phase~="racing" then return end
    local x,y,z=getElementPosition(r.player)
    if r.gridKey then
        local grid=r.course and r.course.points[1] or r.origin
        if math.abs(x-grid[1])>8 or math.abs(y-grid[2])>8 then
            Mission.releaseSite(r,r.gridKey)
            r.gridKey=nil
        end
    end
    if r.course then
        local b=r.course.bounds
        if x<math.min(b[1],b[3]) or x>math.max(b[1],b[3]) or y<math.min(b[2],b[4]) or y>math.max(b[2],b[4]) then
            return Mission.fail(r,"You left the course!")
        end
    end
    if not driving(r) then
        if not r.returnBy then
            r.returnBy=now+30000
            r.pose,r.poseUntil,r.jump=nil,nil,nil
            clearGate(r)
            showCoronas(r,false)
            Mission.showReturnVehicle(r,r.vehicle)
        end
        local seconds=math.ceil((r.returnBy-now)/1000)
        if seconds<=0 then return Mission.fail(r,"You didn't return to your vehicle in time.") end
        if r.returnSecond~=seconds then
            r.returnSecond=seconds
            Mission.message(r,("Get back to your vehicle within %d seconds."):format(seconds))
        end
        return
    end
    if r.returnBy then
        r.returnBy,r.returnSecond=nil,nil
        Mission.clearReturnVehicle(r)
        if r.course then drawGate(r) else showCoronas(r,true) end
    end
    if r.course then
        checkGate(r,now,x,y,z)
    else
        setElementHealth(r.vehicle,1000)
        collectMall(r,now,x,y,z)
    end
end

addEvent("mission:trialSample",true)
addEventHandler("mission:trialSample",resourceRoot,function(token,id,pose,ground,onGround)
    if source~=resourceRoot or not client or not starts[id] or type(ground)~="number" or not (ground>=-500 and ground<=2000) then return end
    local r=Mission.forParticipant(client,token,id)
    if not r or r.phase~="racing" or not driving(r) then return end
    local now=getTickCount()
    if now<(r.nextSample or 0) then return end
    r.nextSample=now+70
    if id=="mallbmx" then
        if pose==0 then r.pose,r.poseUntil=nil,nil return end
        local m=getElementMatrix(r.vehicle)
        if m and (pose==1 and m[2][3]>0 or pose==2 and m[2][3]<0) then
            r.pose,r.poseUntil=pose,now+200
            collectMall(r,now,getElementPosition(r.player))
        end
        return
    end
    local _,_,z=getElementPosition(r.vehicle)
    if onGround==false then
        if not r.jump then r.jump={first=z,peak=z,height=0} end
        r.jump.peak=math.max(r.jump.peak,z)
        r.jump.height=math.max(r.jump.height,z-ground)
    elseif onGround==true and r.jump then
        local j=r.jump
        r.jump=nil
        -- Limit a reported surface sample by the altitude change witnessed by the server.
        local height=math.min(j.height,j.peak-math.min(j.first,z)+2)
        if id=="watersports" then height=math.floor(height) end
        if height>0 then
            local cm=math.floor(height*100)
            if cm>(r.bestAir or 0) then
                r.bestAir=cm
                local previous=Mission.courseRecord(r,"best_air")
                if previous and cm>(previous.score or 0) then Mission.recordCourse(r,"best_air",{score=cm}) end
            end
            if height>2 then
                if height>=8 then Mission.pay(r,10) end
                Mission.message(r,("Air: %.1f meters.%s"):format(height,height>=8 and " $10 bonus." or ""))
            end
        end
    end
end,false)

addEvent("mission:trialRampFailure",true)
addEventHandler("mission:trialRampFailure",resourceRoot,function(token,id)
    local r=source==resourceRoot and client and Mission.forParticipant(client,token,id)
    if r and ((r.course and r.course.ramps) or (r.aerial and r.aerial.cfg.ramps)) then
        Mission.fail(r,"The course ramps could not be loaded.")
    end
end,false)

local function stop(r)
    if r.unfreeze and isElement(r.vehicle) then setElementFrozen(r.vehicle,false) end
    if not r.origin or not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return end
    if r.bikeHealth and getElementHealth(r.vehicle)>r.bikeHealth then
        setElementHealth(r.vehicle,r.bikeHealth)
    end
    if getElementInterior(r.vehicle)~=r.interior or getElementDimension(r.vehicle)~=r.dimension then return end
    for _,p in pairs(getVehicleOccupants(r.vehicle)) do if p~=r.player then return end end
    setElementVelocity(r.vehicle,0,0,0)
    setElementPosition(r.vehicle,unpack(r.origin))
    setElementRotation(r.vehicle,unpack(r.rotation))
    if isElement(r.originalVehicle) and driving(r) and not isPedDead(r.player)
        and not getVehicleOccupant(r.originalVehicle,0) and getElementInterior(r.originalVehicle)==r.interior
        and getElementDimension(r.originalVehicle)==r.dimension then
        removePedFromVehicle(r.player)
        warpPedIntoVehicle(r.player,r.originalVehicle,0)
    end
end

for id,entry in pairs(starts) do
    local site=entry
    Mission.register(id,{course=true,title=site.title,models={site.model},canStart=function(player,car)
        local x,y,z=getElementPosition(car)
        return getElementInterior(car)==0 and getElementDimension(car)==(site.dimension or 0)
            and math.abs(x-site.x)<=8 and math.abs(y-site.y)<=8 and math.abs(z-(site.z-1))<=8
    end,start=begin,tick=tick,stop=stop})
end
