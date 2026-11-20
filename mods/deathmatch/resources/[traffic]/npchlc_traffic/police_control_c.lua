local missions = {}
local createdRopes = setmetatable({}, {__mode="k"})
local render, watching
local function refreshRender()
    local needed=next(missions)~=nil
    if needed and not watching then
        addEventHandler("onClientPreRender",root,render)
    elseif watching and not needed then
        removeEventHandler("onClientPreRender",root,render)
    end
    watching=needed
end
local commandKey, ropeKey = "traffic:policeMission", "traffic:policeRope"
local function clamp(n,lo,hi) return math.min(hi,math.max(lo,n)) end
local function angleDelta(a,b) return (a-b+math.pi)%(2*math.pi)-math.pi end

local function release(vehicle)
    local state = missions[vehicle]
    if state and isElement(state.light) then destroyElement(state.light) end
    missions[vehicle] = nil
end

local function observe(element)
    if not isElementStreamedIn(element) then return end
    if getElementType(element) == "vehicle" then
        local command = getElementData(element,commandKey,false)
        release(element)
        if type(command) == "table" and isElement(command[1]) then
            missions[element] = {player=command[1], kind=command[2], level=command[3], pitch=0}
        end
    elseif getElementType(element)=="ped" then
        local data = getElementData(element,ropeKey,false)
        if type(data)~="table" then
            createdRopes[element]=nil
        elseif not createdRopes[element] then
            local _,_,z=getElementPosition(element)
            local speed=TrafficPoliceFlight.ropeSpan*TrafficPoliceFlight.ropeProgressPerMs
            local duration=TrafficPoliceFlight.ropeLifetimeMs-math.max(0,data[4]-z)/speed
            if duration>0 then createdRopes[element]=createSWATRope(data[2],data[3],data[4],math.floor(duration)) end
        end
    end
    refreshRender()
end

addEventHandler("onClientElementDataChange",resourceRoot,function(key)
    if key==commandKey or key==ropeKey then observe(source) end
end)
addEventHandler("onClientElementStreamIn",resourceRoot,function() observe(source) end)
local function forget()
    if missions[source] then release(source) end
    refreshRender()
end
addEventHandler("onClientElementStreamOut",resourceRoot,forget)
addEventHandler("onClientElementDestroy",resourceRoot,forget)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,kind in ipairs({"vehicle","ped"}) do
        for _,element in ipairs(getElementsByType(kind,resourceRoot,true)) do observe(element) end
    end
end)

addEvent("traffic:policeTerrain",true)
addEventHandler("traffic:policeTerrain",resourceRoot,function(id,x,y)
    local hit,_,_,z = processLineOfSight(x,y,1000,x,y,-1000,true,false,false,true,false)
    triggerServerEvent("traffic:policeTerrainResult",resourceRoot,id,hit and z or true)
end,false)

-- SA POL_ANN voice bank, boat samples 0..29 and helicopter 30..81.
addEvent("traffic:policeCallout",true)
addEventHandler("traffic:policeCallout",resourceRoot,function(vehicle,sample)
    if not isElement(vehicle) or not isElementStreamedIn(vehicle) then return end
    local x,y,z=getElementPosition(vehicle)
    local sound=playSFX3D("spc_fa",10,sample,x,y,z)
    if sound then
        setElementDimension(sound,getElementDimension(vehicle))
        setSoundMaxDistance(sound,100)
        attachElements(sound,vehicle)
    end
end,false)

local function sampleFloor(x,y,z)
    local hit,_,_,floor = processLineOfSight(x,y,z,x,y,z-120,true,false,false,true,false)
    return hit and floor or nil
end

addEvent("traffic:policeSurvey",true)
addEventHandler("traffic:policeSurvey",resourceRoot,function(heli,id,count)
    if not isElement(heli) or not isElementStreamedIn(heli) then return end
    local target = getPedOccupiedVehicle(localPlayer) or localPlayer
    local x,y,z = getElementPosition(heli)
    local tx,ty,tz = getElementPosition(target)
    local clear = isLineOfSightClear(x,y,z-1,tx,ty,tz,true,false,false,true,false,false,false,heli)
    local floor
    if count > 0 then
        local m = getElementMatrix(heli)
        local slot = count-1
        local ox,oy = slot%2 == 0 and -1.2 or 1.2,slot<2 and -1 or 1
        local ax,ay,az = x+ox*m[1][1]+oy*m[2][1]-.5*m[3][1], y+ox*m[1][2]+oy*m[2][2]-.5*m[3][2],z+ox*m[1][3]+oy*m[2][3]-.5*m[3][3]
        floor=sampleFloor(ax,ay,az)
        local water=getWaterLevel(ax,ay,az,true)
        if floor and water and water>=floor then floor=nil end
    end
    triggerServerEvent("traffic:policeSurveyResult",resourceRoot,heli,id,clear,floor or false)
end,false)

addEvent("traffic:policeVolley",true)
addEventHandler("traffic:policeVolley",resourceRoot,function(gun,player,id,shots)
    if not isElement(gun) or not isElementStreamedIn(gun) then return end
    local target = isElement(player) and (getPedOccupiedVehicle(player) or player)
    local hits=0
    for _,shot in ipairs(shots) do
        local x,y,z,tx,ty,tz=unpack(shot)
        local dx,dy,dz=tx-x,ty-y,tz-z
        local norm=math.max(.01,math.sqrt(dx*dx+dy*dy+dz*dz))
        dx,dy,dz=dx/norm,dy/norm,dz/norm
        fxAddGunshot(x,y,z,dx,dy,dz,true)
        if player==localPlayer then
            local hit,_,_,_,element=processLineOfSight(x,y,z,tx,ty,tz,true,true,true,true,true,false,false,false,gun)
            if hit and element==target then hits=hits+1 end
        end
    end
    -- GENRL starts at absolute bank 7. AK_SHOT_L is sample 3 of weapon bank 143.
    local sound=playSFX3D("genrl",136,3,shots[1][1],shots[1][2],shots[1][3])
    if sound then
        setElementDimension(sound,getElementDimension(gun))
        setSoundMaxDistance(sound,100)
    end
    if hits>0 then triggerServerEvent("traffic:policeImpacts",resourceRoot,gun,id,hits) end
end,false)

local function helicopter(vehicle,state,target,dt,now)
    local x,y,z=getElementPosition(vehicle)
    local tx,ty,tz=getElementPosition(target)
    local retiring=state.kind=="retire"
    local tracked = not retiring and not isPedDead(state.player) and
        (target == state.player or (getVehicleType(target)~="Helicopter" and getVehicleType(target)~="Plane"))
    if tracked then
        local tvx,tvy=getElementVelocity(target)
        state.track=TrafficPoliceFlight.track(state.track,target,tx,ty,tvx,tvy,now)
    else
        state.track=nil
    end
    local sx,sy=tx,ty
    if state.track then sx,sy=state.track.x,state.track.y end
    local distance=math.sqrt((sx-x)^2+(sy-y)^2)
    if tracked and distance < 60 then
        local radius=12*clamp((60-distance)/20,0,1)
        if not isElement(state.light) then
            state.light=createSearchLight(x,y,z-1,sx,sy,tz,0.2,radius)
            if state.light then setElementDimension(state.light,getElementDimension(vehicle)) end
        else
            setSearchLightStartPosition(state.light,x,y,z-1)
            setSearchLightEndPosition(state.light,sx,sy,tz)
            setSearchLightEndRadius(state.light,radius)
        end
    elseif isElement(state.light) then
        destroyElement(state.light)
        state.light=nil
    end
    if not isElementSyncer(vehicle) then return end
    local matrix=getElementMatrix(vehicle)
    local vx,vy,vz=getElementVelocity(vehicle)
    local heading=math.atan2(matrix[2][2],matrix[2][1])
    local airborne=target~=state.player and (getVehicleType(target)=="Helicopter" or getVehicleType(target)=="Plane")
    local aim,range,desired=TrafficPoliceFlight.intent(x,y,tx,ty,tz,airborne,retiring)
    if not state.probeAt or (now-state.probeAt)%4294967296 >= 500 then
        state.probeAt=now
        local fx,fy=math.cos(aim),math.sin(aim)
        local aheadX,aheadY=x+vx*50+fx*18,y+vy*50+fy*18
        local ground=sampleFloor(aheadX,aheadY,z+40) or sampleFloor(x,y,z+20)
        local obstructed,_,_,oz=processLineOfSight(x,y,z,aheadX,aheadY,z-5,true,false,false,true,false)
        state.floor=math.max(ground and ground+18 or -1000,obstructed and oz+18 or -1000)
        state.lateral=0
        if obstructed then
            local right=isLineOfSightClear(x,y,z,x+fy*18,y-fx*18,z,true,false,false,true,false)
            state.lateral=right and .5 or -.5
        end
        state.noise=math.random(0,15)
    end
    local maxHeight=math.max(desired,state.floor,tz+(retiring and 0 or 15))
    local forward=vx*matrix[2][1]+vy*matrix[2][2]+vz*matrix[2][3]
    local yaw,pitch,lateral,collective=TrafficPoliceFlight.controls({x=x,y=y,z=z,vx=vx,vy=vy,vz=vz,
        heading=heading,forwardSpeed=forward,horizontalForwardSpeed=vx*matrix[2][1]+vy*matrix[2][2],
        previousPitch=state.pitch,targetX=tx,targetY=ty},aim,range,maxHeight,state.noise,retiring,state.lateral)
    state.pitch=pitch
    local nextHeading=heading-yaw*dt*1.45
    local blend=1-math.exp(-dt*2.4)
    local speed=-pitch*0.83
    -- Map native control outputs to velocity on the vehicle's one MTA syncer.
    local desiredVX=math.cos(nextHeading)*speed+math.sin(nextHeading)*lateral*.32
    local desiredVY=math.sin(nextHeading)*speed-math.cos(nextHeading)*lateral*.32
    if not retiring and range<20 then
        desiredVX=clamp((tx-x)*.018,-.35,.35)
        desiredVY=clamp((ty-y)*.018,-.35,.35)
    end
    local rx,ry=getElementRotation(vehicle,"ZXY")
    -- MTA can report a small negative pitch as e.g. 359 degrees. Interpolate
    -- over the shortest arc so a forward command does not flip the aircraft.
    local desiredPitch,desiredRoll=pitch*14,yaw*10+lateral*15
    local pitchDelta=(desiredPitch-rx+180)%360-180
    local rollDelta=(desiredRoll-ry+180)%360-180
    setElementRotation(vehicle,rx+pitchDelta*blend,ry+rollDelta*blend,math.deg(nextHeading)-90,"ZXY")
    setElementVelocity(vehicle,vx+(desiredVX-vx)*blend,vy+(desiredVY-vy)*blend,vz+(.38*collective-vz)*blend)
    setVehicleRotorSpeed(vehicle,1)
end

local function boat(vehicle,state,target,dt)
    if not isElementSyncer(vehicle) then return end
    -- Match the original nominal 30 Hz control update. The hull controller
    -- consumes the complete elapsed time for both thrust and angular limits.
    state.boatElapsed=(state.boatElapsed or 0)+dt
    if state.boatElapsed < 1/30 then return end
    dt,state.boatElapsed=math.min(.15,state.boatElapsed),0
    local x,y,z=getElementPosition(vehicle)
    local tx,ty,tz=getElementPosition(target)
    local tvx,tvy=getElementVelocity(target)
    local vx,vy,vz=getElementVelocity(vehicle)
    local m=getElementMatrix(vehicle)
    local facing=math.atan2(m[2][2],m[2][1])
    local speed=math.sqrt(vx*vx+vy*vy)
    local bearing,throttle=TrafficPoliceFlight.boatIntent(state.level or 2,x,y,z,tx,ty,tz,tvx,tvy,facing,speed)
    local kind=target~=state.player and getVehicleType(target)
    if TrafficPoliceFlight.boatPaused(state,kind,getTickCount()) then bearing,throttle=facing,-0.2 end
    local aimed=facing+clamp(angleDelta(bearing,facing),-dt*1.55,dt*1.55)
    local ms=math.max(0,speed*50+throttle*dt*12)
    exports.vcs_vehicle:steerBoatTraffic(vehicle,math.cos(aimed),math.sin(aimed),0,0,0,0,0,ms,vz,dt*1000)
end

render=function(ms)
    local dt,now=math.min(ms,150)/1000,getTickCount()
    for vehicle,state in pairs(missions) do
        if not isElement(vehicle) or not isElementStreamedIn(vehicle) then
            release(vehicle)
            refreshRender()
        elseif isElement(state.player) and getElementDimension(vehicle)==getElementDimension(localPlayer)
            and getElementType(getVehicleOccupant(vehicle,0) or vehicle)=="ped" then
            local target=getPedOccupiedVehicle(state.player) or state.player
            if state.kind=="boat" then boat(vehicle,state,target,dt) else helicopter(vehicle,state,target,dt,now) end
        end
    end
end
