-- USA SCM missions 37 through 43. All stored record times are milliseconds.
local data=AerialCourses
local pink,green,red={237,130,180,215},{0,255,0,215},{225,35,45,215}
local configs={
    skywolf={title="Skywolf",model=275,start={-1175.069,-1103.0935,15.4104},limit=240000,kind="combat"},
    crimsonwings={title="Crims on Wings",model=222,start={-1276.8235,-1085.3788,14.7235},limit=240000,kind="air"},
    crimsonwater={title="Crims on Water Wings",model=278,start={587.21,-1758.72,7.7},limit=150000,kind="air",
        small={[6]=true,[8]=true,[9]=true,[10]=true,[11]=true,[18]=true,[20]=true}},
    landseaair={title="Land, Sea and Air Ace",model=205,start={488.4949,-1725.0143,8.801},limit=270000,kind="relay",
        ramps={{"ndc_bikerampnarrow",398.3329,-1696.699,8.4352,280}},
        -- SCM X=455.1637 grounds the MTA Jet Ski hull. Two metres east clears the beach.
        changes={[16]={233,457.1637,-1671.4535,6.3272,273,"Jet Ski"},[37]={263,136.9071,40.6358,6.9703,185,"Sea Sparrow"}}},
    hymanodt={title="Hyman Memorial O.D.T.",model=222,start={-1776.08,-1151.25,14.23},limit=290000,kind="relay",
        changes={[17]={258,-1182.88,176.51,5.8,0,"Jetmax"},[28]={212,-1308.12,1137.09,7.74,95,"PCJ-600"}}},
    playtown={title="Playground on the Town",model=212,start={-583.6983,826.2472,11.121},limit=95000,kind="play",ramps=data.townRamps},
    playpoint={title="Playground on the Point",model=212,start={339.3391,972.6107,11.5248},limit=90000,kind="play"},
    playdock={title="Playground on the Dock",model=212,start={-806.17,-1229.219,11.227},limit=75000,kind="play"},
    playpark={title="Playground on the Park",model=212,start={138.152,-1230.781,16.741},limit=70000,kind="play",ramps=data.parkRamps},
    harborhover={title="Harbor Hover Race",model=198,start={-259.352,-1658.676,6.41},limit=225000,kind="hover",
        ramps={{"ndc_boatrampwide",-286.659,-230.889,5.2,180},{"ndc_bikerampnarrow",-535.143,-588.179,9.524,180}}},
    haitihover={title="Haiti Hover Race",model=198,start={-1179.552,-40.727,6.534},limit=105000,kind="hover"},
}
local function within(element,p,range)
    local x,y,z=getElementPosition(element)
    return math.abs(x-p[1])<=range and math.abs(y-p[2])<=range and math.abs(z-p[3])<=range
end
local function drop(e) if isElement(e) then destroyElement(e) end end
local function direction(marker,p,nextP)
    local target=p[4] and not (p[4]==0 and p[5]==0 and p[6]==0) and {p[4],p[5],p[6]} or nextP
    if target then exports.marker:setMarkerTarget(marker,target[1],target[2],target[3]) end
end
local function shape(r)
    local a=r.aerial
    if a.cfg.kind=="combat" then return "ring",6,10.5 end
    if a.cfg.kind=="air" then return "ring",a.cfg.small and a.cfg.small[a.index] and 3 or 6,11 end
    if a.cfg.kind=="hover" then return "checkpoint",8,4 end
    if r.id=="landseaair" then
        if a.index<=37 then return "checkpoint",8,5 end
        return "ring",6,9
    end
    if a.index==1 then return "checkpoint",15,9 end
    if a.index<=17 then return "ring",6,9 end
    if a.index<=28 then return "checkpoint",12,9 end
    return "checkpoint",8,5
end
local function clearGate(a)
    drop(a.gate)
    drop(a.nextBlip)
    a.gate,a.nextBlip=nil,nil
end
local function showGate(r)
    local a=r.aerial
    clearGate(a)
    local p=a.points[a.index]
    local nextP=a.points[a.index+1]
    local style,size,reach=shape(r)
    a.reach=reach
    a.gate=Mission.marker(r,p[1],p[2],p[3]-(style=="checkpoint" and 0.5 or 0),style,size,nextP and pink or green,true)
    if not a.gate then return Mission.fail(r,"The race checkpoint is unavailable.") end
    if r.id=="landseaair" and a.index==37 then
        local change=a.cfg.changes[37]
        exports.marker:setMarkerTarget(a.gate,change[2],change[3],change[4])
    elseif style=="checkpoint" then
        if nextP then exports.marker:setMarkerTarget(a.gate,nextP[1],nextP[2],nextP[3]) end
    else direction(a.gate,p,nextP) end
    local nextIsFinish=a.index+1==#a.points
    if nextP and not (a.cfg.kind=="combat" and nextIsFinish) then
        local color=nextIsFinish and green or pink
        a.nextBlip=Mission.track(r,createBlip(nextP[1],nextP[2],nextP[3],0,1,color[1],color[2],color[3],255,0,65535,r.player))
        if a.nextBlip then
            setElementDimension(a.nextBlip,r.dimension)
            setElementInterior(a.nextBlip,r.interior)
        end
    end
end
local function courseVisible(r,visible)
    local a=r.aerial
    if a.gate then
        exports.marker:setMarkerVisibleTo(a.gate,r.player,visible)
        exports.marker:setMarkerBlipVisible(a.gate,visible)
    end
    if isElement(a.nextBlip) then setElementVisibleTo(a.nextBlip,r.player,visible) end
    for _,m in pairs(a.pickups) do
        exports.marker:setMarkerVisibleTo(m,r.player,visible)
        exports.marker:setMarkerBlipVisible(m,visible)
    end
    for _,t in pairs(a.targets) do
        if isElement(t.marker) then exports.marker:setMarkerBlipVisible(t.marker,visible) end
    end
end
local function spawn(r,id,x,y,z,heading)
    local car=exports.vcs_vehicle:createVcsVehicle(id,x,y,z,0,0,heading)
    if not car then return end
    Mission.track(r,car)
    if not Mission.claimVehicle(r,car) then drop(car) return end
    setElementInterior(car,r.interior)
    setElementDimension(car,r.dimension)
    return car
end
local groups={[2]={1,2},[4]={3,7},[5]={8,12}}
local patrols={[6]={214,data.northBoat,15},[7]={214,data.southBoat,15},[11]={221,data.droneTruck,10},[12]={262,data.droneHeli,8}}
local function wave(r,group)
    local a=r.aerial
    clearGate(a)
    for i=group[1],group[2] do
        local p=data.drones[i]
        local path=patrols[i]
        local car=spawn(r,path and path[1] or 221,p[1]+a.shift,p[2],p[3],p[4])
        if not car then return Mission.fail(r,"The drone targets are unavailable.") end
        setVehicleLocked(car,true)
        setElementFrozen(car,true)
        local marker=Mission.marker(r,p[1]+a.shift,p[2],p[3]+2,"arrow",0.9,red,true)
        if not marker then return Mission.fail(r,"A target could not be marked.") end
        attachElements(marker,car,0,0,2.3)
        a.targets[i]={car=car,marker=marker,path=path,at=1}
    end
    Mission.message(r,"Destroy the drone targets using the Hunter's rockets or cannon.")
end
local function moveTarget(t,shift,dt)
    if not t.path then return end
    local route=t.path[2]
    local to=route[t.at]
    local x,y,z=getElementPosition(t.car)
    local dx,dy,dz=to[1]+shift-x,to[2]-y,to[3]-z
    local distance=math.sqrt(dx*dx+dy*dy+dz*dz)
    local step=t.path[3]*dt
    if distance<=step then
        setElementPosition(t.car,to[1]+shift,to[2],to[3])
        t.at=t.at%#route+1
    elseif distance>0 then
        setElementPosition(t.car,x+dx*step/distance,y+dy*step/distance,z+dz*step/distance)
        setElementRotation(t.car,0,0,-math.deg(math.atan2(dx,dy)))
    end
end
local function checkTargets(r,now)
    local a=r.aerial
    local dt=math.min(1,(now-a.lastTargetTick)/1000)
    a.lastTargetTick=now
    for i,t in pairs(a.targets) do
        if not isElement(t.car) or isVehicleBlown(t.car) or getElementHealth(t.car)<=0 then
            drop(t.marker)
            drop(t.car)
            a.targets[i]=nil
        else moveTarget(t,a.shift,dt) end
    end
    if not next(a.targets) then
        Mission.message(r,"All targets destroyed. Head for the next checkpoint.")
        showGate(r)
    end
end
local function unfreeze(a)
    if isElement(a.frozen) then setElementFrozen(a.frozen,a.wasFrozen) end
    a.frozen=nil
end
local function launch(r,now)
    local a=r.aerial
    if a.cfg.kind=="relay" or a.cfg.kind=="combat" then
        for slot=0,31 do
            if Mission.claimSite(r,r.id.."/dispatch/"..slot) then a.shift=slot*8 break end
        end
        if not a.shift then
            if not a.retry then Mission.message(r,"Waiting for a course vehicle.") end
            a.retry=now+2000
            return
        end
    end
    a.retry=nil
    if a.cfg.ramps then Mission.notify(r,"mission:trialRamps",r.token,a.cfg.ramps,r.interior,r.dimension,r.id) end
    if a.cfg.kind=="play" then
        for i,p in ipairs(a.points) do
            local marker=Mission.marker(r,p[1],p[2],p[3],"corona",5,pink,true)
            if not marker then return Mission.fail(r,"A playground checkpoint is unavailable.") end
            a.pickups[i]=marker
        end
        Mission.message(r,"Collect the checkpoints in any order. The first pickup starts the clock.")
    else
        showGate(r)
        if not Mission.active(r) then return end
        Mission.message(r,("Beat the course record of %d:%02d."):format(math.floor(a.limit/60000),math.floor(a.limit/1000)%60))
        if a.cfg.kind=="combat" then r.elapsedFrom=now
        else
            a.go=now+(a.cfg.kind=="hover" and 7000 or 6000)
            a.frozen,a.wasFrozen=r.vehicle,isElementFrozen(r.vehicle)
            setElementFrozen(r.vehicle,true)
        end
    end
end
local function start(r,now)
    local cfg=configs[r.id]
    local record=Mission.courseRecord(r,r.id)
    if not record then return Mission.fail(r,"The course record could not be loaded.") end
    r.aerial={cfg=cfg,points=data[r.id],index=1,collected=0,limit=math.min(cfg.limit,record.time or cfg.limit),
        targets={},pickups={},lastTargetTick=now}
    launch(r,now)
end
local function finish(r,now)
    local a=r.aerial
    local elapsed=now-a.startTime
    if elapsed>=a.limit then return Mission.fail(r,"You failed to beat the course record.") end
    Mission.finishCourse(r,r.id,{time=elapsed},500,true)
end
local function enterLeg(r,change,now)
    local a=r.aerial
    local car=spawn(r,change[1],change[2]+a.shift,change[3],change[4],change[5])
    if not car then return Mission.fail(r,"The next course vehicle is unavailable.") end
    if not Mission.switchVehicle(r,car) then return Mission.fail(r,"The next vehicle is occupied.") end
    a.returnAt=now+30000
    Mission.showReturnVehicle(r,car)
    Mission.message(r,"Switch to the "..change[6].." and continue the course.")
end
local function tick(r,now)
    local a=r.aerial
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return Mission.fail(r,"Your course vehicle was destroyed.") end
    if a.retry then
        if now>=a.retry then launch(r,now) end
        return
    end
    if a.go then
        if now<a.go then
            local left=math.ceil((a.go-now)/1000)
            if left<=3 and left~=a.count then
                a.count=left
                Mission.countdown(r,left)
            end
            return
        end
        unfreeze(a)
        r.elapsedFrom,a.go=now,nil
        Mission.countdown(r,"GO")
    end
    if Mission.driverOf(r.vehicle)~=r.player then
        if not a.returnAt then
            a.returnAt=now+30000
            courseVisible(r,false)
            Mission.showReturnVehicle(r,r.vehicle)
            Mission.message(r,"You have 30 seconds to return to your course vehicle.")
        end
        if now>=a.returnAt then Mission.fail(r,"You took too long to return to your vehicle.") end
        return
    end
    if a.returnAt then
        a.returnAt=nil
        Mission.clearReturnVehicle(r)
        if not a.gate and not next(a.pickups) and not next(a.targets) then showGate(r) end
        courseVisible(r,true)
    end
    if a.cfg.kind=="play" then
        for i,marker in pairs(a.pickups) do
            if CourseGates.crossed(r,now,a.points[i],4) then
                if not a.startTime then a.startTime,r.deadline=now,now+a.limit end
                Mission.checkpointCue(r)
                a.collected=a.collected+1
                drop(marker)
                a.pickups[i]=nil
                Mission.hud(r,"Checkpoints",("%d/%d"):format(a.collected,#a.points))
                if a.collected==#a.points then return finish(r,now) end
            end
        end
        return
    end
    a.startTime=r.elapsedFrom
    if next(a.targets) then return checkTargets(r,now) end
    if not CourseGates.crossed(r,now,a.points[a.index],a.reach) then return end
    Mission.checkpointCue(r)
    local passed=a.index
    a.index=passed+1
    if a.index>#a.points then return finish(r,now) end
    if a.cfg.kind=="combat" and groups[passed] then
        a.lastTargetTick=now
        return wave(r,groups[passed])
    end
    if a.cfg.changes and a.cfg.changes[passed] then
        clearGate(a)
        return enterLeg(r,a.cfg.changes[passed],now)
    end
    showGate(r)
end
for id,cfg in pairs(configs) do
    local point=cfg.start
    Mission.register(id,{title=cfg.title,models={cfg.model},course=true,
        canStart=function(player,vehicle)
            return within(vehicle,{point[1],point[2],point[3]-1},8)
        end,
        start=start,tick=tick,stop=function(r) if r.aerial then unfreeze(r.aerial) end end,
        timeout="You ran out of time!"})
end
