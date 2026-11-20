local poses, encounters = {}, {}
local turns = setmetatable({}, {__mode="k"})
local landType = {Automobile=true, Bike=true, Bicycle=true, Quad=true, ["Monster Truck"]=true}
local function age(now, before) return (now-before)%4294967296 end

local function scanCar(vehicle, now)
    if not isElementStreamedIn(vehicle) or not landType[getVehicleType(vehicle)] then return end
    local m = getElementMatrix(vehicle)
    local x1,y1,z1,x2,y2,z2 = getElementBoundingBox(vehicle)
    if not m or not x1 then return end
    local fx,fy = m[2][1],m[2][2]
    local length = math.sqrt(fx*fx+fy*fy)
    if length < 0.7 then return end
    fx,fy = fx/length,fy/length
    local sample,rate = turns[vehicle],0
    if sample then
        local dt = age(now,sample.time)/1000
        if dt > 0 and dt < 0.5 then
            rate = math.atan2(sample.fx*fy-sample.fy*fx,sample.fx*fx+sample.fy*fy)/dt
        end
    end
    turns[vehicle] = {fx=fx,fy=fy,time=now}
    local vx,vy,vz = getElementVelocity(vehicle)
    if vx*fx+vy*fy <= 0.05 then return end
    local width = math.max(-x1,x2)
    if getVehicleType(vehicle) == "Bike" then width = width*1.6 end
    return {x=m[4][1],y=m[4][2],z=m[4][3],fx=fx,fy=fy,vx=vx,vy=vy,vz=vz,
        front=y2,bottom=z1,top=z2,width=width,yawRate=rate}
end

local function canLand(ped, x, y, z, dx, dy, length)
    local lastHeight
    local steps = math.max(1, math.ceil(length/0.85))
    for i = 0,steps do
        local offset = length*i/steps
        local tx,ty = x+dx*offset,y+dy*offset
        local hit,_,_,height,_,_,_,normal = processLineOfSight(tx,ty,z+0.5,tx,ty,z-1.6,
            true,false,false,true,false,false,false,false,ped)
        if not hit or normal and normal < 0.7 or lastHeight and math.abs(lastHeight-height) > 0.4 then return false end
        lastHeight = height
    end
    for _, offset in ipairs({-0.28,0,0.28}) do
        local sx,sy = x+dy*offset,y-dx*offset
        if not isLineOfSightClear(sx,sy,z+0.1,sx+dx*length,sy+dy*length,z+0.1,
            true,true,true,true,false,false,false,ped) then return false end
    end
    return true
end

addEvent("npchlc_traffic:bulletLanding",true)
addEventHandler("npchlc_traffic:bulletLanding",resourceRoot,function(ped,sourcePed,id,kind)
    if not isElement(ped) or not isElement(sourcePed) or not isElementSyncer(ped)
        or not isPedOnGround(ped) or poses[ped] or kind~="ev_dive" and kind~="ev_step" then return end
    local x,y,z=getElementPosition(ped)
    local sx,sy=getElementPosition(sourcePed)
    local dx,dy=y-sy,sx-x
    local len=math.sqrt(dx*dx+dy*dy)
    if len<0.01 then return end
    local motion=VCS_TRAFFIC_EVADE_CLIPS[kind].motion
    local travel=motion[#motion][3]
    local sign=math.random(0,1)==0 and 1 or -1
    for _=1,2 do
        local nx,ny=sign*dx/len,sign*dy/len
        if canLand(ped,x,y,z,nx,ny,math.abs(travel)+0.15) then
            local facing=travel>0 and 1 or -1
            triggerServerEvent("npchlc_traffic:bulletLandingReply",resourceRoot,ped,id,facing*nx,facing*ny)
            return
        end
        sign=-sign
    end
end)

local function tryEvasion(ped, vehicle, driver, car, now)
    if poses[ped] or not isElementSyncer(ped) or isPedDead(ped) or isPedInVehicle(ped)
        or not isPedOnGround(ped) or getElementData(ped,"npchlc_traffic:visibility",false) ~= "pedestrian"
        or getElementData(ped,PedEvasion.key,false) or PedEvasion.activityBlocks(ped)
        or getElementData(ped,"npchlc_traffic:activityHeading",false) then return end
    local x,y,z = getElementPosition(ped)
    local pvx,pvy = getElementVelocity(ped)
    local kind,side = PedEvasion.threat(car,x,y,z,pvx,pvy)
    if not kind then return end
    local previous = encounters[ped]
    if previous and previous.vehicle == vehicle and (kind == "approach" or previous.kind ~= "approach")
        and age(now,previous.time) < 2500 then return end
    if not isLineOfSightClear(x,y,z+0.12,car.x,car.y,car.z+0.15,true,false,false,true,false,false,false,ped) then return end
    local matrix = getElementMatrix(ped)
    if not matrix then return end
    local towardX,towardY = car.x-x,car.y-y
    local dist = math.sqrt(towardX*towardX+towardY*towardY)
    if dist < 0.1 then return end
    towardX,towardY = towardX/dist,towardY/dist
    local behind = towardX*matrix[2][1]+towardY*matrix[2][2] < 0
    local horn = getVehicleType(vehicle) == "Automobile" and getPedControlState(driver,"horn")
    if kind == "approach" then
        encounters[ped] = {vehicle=vehicle,time=now,kind=kind}
        if horn or not behind then triggerServerEvent("npchlc_traffic:vehicleApproach",resourceRoot,ped,vehicle) end
        return
    end
    local model = PedAIModels[getElementData(ped,"npchlc_traffic:originalModel",false)]
    local flags = model and PedAIStats[model[2]].flags or 0
    if not horn then
        -- Keep a rejected awareness roll for this encounter. A blocked landing
        -- can be probed again as the pedestrian and the vehicle move.
        encounters[ped] = {vehicle=vehicle,time=now,kind=kind}
        if kind == "ev_step" and behind or kind == "ev_dive" and behind and math.random(0,7) ~= 0 then return end
        if kind == "ev_step" and math.random(0,1) == 1 then
            kind = "idle_taxi"
        elseif kind == "ev_dive" and not behind and math.random(0,1) == 1 then
            kind = "handsup"
        end
    end
    if kind == "ev_dive" and math.floor(flags/16)%2 == 1 then kind = "handsup" end
    if kind == "handsup" or kind == "idle_taxi" then
        if kind == "handsup" and not canLand(ped,x,y,z,-towardX,-towardY,0.75) then return end
        triggerServerEvent("npchlc_traffic:evadeCar",resourceRoot,ped,vehicle,kind,towardX,towardY,horn)
        return
    end
    -- Native EV_step retreats along local -Y; EV_dive travels along local +Y.
    local last = VCS_TRAFFIC_EVADE_CLIPS[kind].motion
    local travel = last[#last][3]
    local direction = side >= 0 and 1 or -1
    encounters[ped] = nil
    if math.abs(side) < 0.08 then direction = math.random(0,1) == 0 and 1 or -1 end
    local speed = math.sqrt(car.vx*car.vx+car.vy*car.vy)
    local normalX,normalY = car.vy/speed,-car.vx/speed
    if not horn and kind == "ev_dive" then
        normalX,normalY = -towardY,towardX
        direction = math.random(0,1) == 0 and 1 or -1
    end
    for _ = 1,2 do
        local dx,dy = normalX*direction,normalY*direction
        if canLand(ped,x,y,z,dx,dy,math.abs(travel)+0.15) then
            local forward = travel > 0 and 1 or -1
            encounters[ped] = {vehicle=vehicle,time=now,kind=kind}
            triggerServerEvent("npchlc_traffic:evadeCar",resourceRoot,ped,vehicle,kind,dx*forward,dy*forward,horn)
            return
        end
        direction = -direction
    end
end

setTimer(function()
    local now = getTickCount()
    for _, driver in ipairs(getElementsByType("player",root,true)) do
        local vehicle = getPedOccupiedVehicle(driver)
        if vehicle and getVehicleOccupant(vehicle,0) == driver then
            local car = scanCar(vehicle,now)
            if car then
                local peds = getElementsWithinRange(car.x,car.y,car.z,16,"ped",getElementInterior(vehicle),getElementDimension(vehicle))
                for _, ped in ipairs(peds or {}) do tryEvasion(ped,vehicle,driver,car,now) end
            end
        end
    end
end,50,0)

local function stop(ped)
    local state = poses[ped]
    poses[ped] = nil
    if not state or not isElement(ped) then return end
    local block, name = getPedAnimation(ped)
    if block and name and block:lower() == state.block and name:lower() == state.clip then setPedAnimation(ped) end
    if state.replaced then engineRestoreAnimation(ped,"ped",state.replaced) end
end

local function receive(ped, catchUp)
    local data = getElementData(ped,PedEvasion.key,false)
    if not data then stop(ped) return end
    if not isElementStreamedIn(ped) then return end
    local revision,kind,fx,fy = unpack(data)
    if not PedEvasion.clip(kind) then return end
    local previous = poses[ped]
    if previous and previous.id == revision then return end
    stop(ped)
    poses[ped] = {id=revision,kind=kind,fx=fx,fy=fy,start=getTickCount(),awaiting=catchUp,native=data[5]}
    if catchUp then triggerServerEvent("npchlc_traffic:evadeClock",resourceRoot,ped,revision) end
end

local function play(ped,state,now)
    if state.awaiting then return end
    local ms = age(now,state.start)
    if ms >= PedEvasion.duration(state.kind) or isPedDead(ped) or isPedInVehicle(ped) then stop(ped) return end
    local clip, clipMs = PedEvasion.pose(state.kind,ms)
    local owner = isElementSyncer(ped)
    local custom = VCS_TRAFFIC_EVADE_CLIPS[clip] ~= nil
    if state.clip == clip and state.owner == owner then return end
    if state.replaced then engineRestoreAnimation(ped,"ped",state.replaced); state.replaced = nil end
    state.owner, state.clip = owner, clip
    state.block = "ped"
    if owner then
        setElementRotation(ped,0,0,-math.deg(math.atan2(state.fx,state.fy)),"default",true)
    end
    -- Only the current syncer advances the physical ped with native root
    -- motion. Observers receive its synced position and play the in-place pose.
    if custom and not state.native then
        local name = owner and clip.."_root" or clip
        if engineReplaceAnimation(ped,"ped",clip,TrafficAnimationBanks.street,name) then state.replaced = clip end
    end
    setPedAnimation(ped,"ped",clip,-1,false,owner,false,false,80)
    if clipMs > 50 then
        setPedAnimationProgress(ped,clip,math.min(0.999,clipMs/PedEvasion.clip(clip).duration))
    end
end
addEventHandler("onClientPreRender",root,function()
    local now = getTickCount()
    for ped,state in pairs(poses) do play(ped,state,now) end
end)
addEventHandler("onClientElementDataChange",root,function(key)
    if key == PedEvasion.key and getElementType(source) == "ped" then receive(source,false) end
end)
addEvent("npchlc_traffic:evadeTime",true)
addEventHandler("npchlc_traffic:evadeTime",resourceRoot,function(ped,id,ms)
    local state = poses[ped]
    if state and state.id == id and type(ms) == "number" then
        state.start,state.awaiting = getTickCount()-ms,false
    end
end)
addEventHandler("onClientElementStreamIn",root,function()
    if getElementType(source) == "ped" and getElementData(source,PedEvasion.key,false) then receive(source,true) end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,ped in ipairs(getElementsByType("ped",root,true)) do
        if getElementData(ped,PedEvasion.key,false) then receive(ped,true) end
    end
end)
addEventHandler("onClientElementStreamOut",root,function() stop(source) end)
addEventHandler("onClientElementDestroy",root,function() poses[source],encounters[source] = nil,nil end)
addEventHandler("onClientResourceStop",resourceRoot,function() for ped in pairs(poses) do stop(ped) end end)
