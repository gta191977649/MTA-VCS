-- The server advances movement when no MTA client owns the physical simulation.
local collisionResource

function configureNPCFallbackCollision()
    local enabled = get("npc_hlc.server_colchecking")
    if enabled == true or enabled == "true" then
        collisionResource = getResourceFromName("server_coldata")
    end
end

local raceBounds={}
local function raceFootprint(car)
    local model=getElementModel(car)
    local bounds=raceBounds[model]
    if not bounds and collisionResource and getResourceState(collisionResource)=="running" then
        bounds={call(collisionResource,"getModelBoundingBox",model)}
        raceBounds[model]=bounds
    end
    return getNPCTrafficModelFootprint(car,unpack(bounds or {}))
end

-- Use the same swept vehicle footprints as the streamed style-2 controller.
-- A stopped finisher can occupy the exact centreline of the incoming lane.
local function raceNearby(car,x,y,z,range)
    local others={}
    for _,other in ipairs(getElementsWithinRange(x,y,z,range,"vehicle",getElementInterior(car),getElementDimension(car))) do
        if other~=car then
            local box=raceFootprint(other)
            if box and math.abs(box.z-z)<8 then
                box.vx,box.vy=getNPCTrafficVelocity(other,getTickCount(),box.x,box.y)
                box.parked=box.vx^2+box.vy^2<.3^2 and not getVehicleOccupant(other,0)
                others[#others+1]=box
            end
        end
    end
    return others
end

function getRaceFallbackTarget(car,x,y,z,tx,ty,tz,speed,cruise,road)
    local dx,dy=tx-x,ty-y
    local length=math.sqrt(dx*dx+dy*dy)
    if length<1 then return tx,ty,tz end
    local reach=math.min(length,12+math.min(12,speed*0.6))
    local others=raceNearby(car,x,y,z,math.sqrt(2)*getNPCRaceLeadRange(speed)+8)
    if #others==0 then return tx,ty,tz end
    local own=raceFootprint(car)
    if not own then return tx,ty,tz end
    local function roadClear(cx,cy,fx,fy,span)
        local traffic=getResourceFromName("npchlc_traffic")
        if traffic and getResourceState(traffic)=="running"
            and not call(traffic,"isMissionRacePassingLane",cx,cy,z,fx,fy,span,own.width) then return false end
        local previous=getVcsGroundHeight(cx,cy,z-0.7)
        if not previous then return false end
        for step=1,math.ceil(span/3) do
            local d=math.min(span,step*3)
            local last=math.min(span,(step-1)*3)
            for side=-1,1 do
                local h=getVcsGroundHeight(cx+fx*d+fy*side*own.width,cy+fy*d-fx*side*own.width,previous)
                if not h or math.abs(h-previous)>1.4 then return false end
                local sx,sy=cx+fy*side*own.width,cy-fx*side*own.width
                if not isVcsRoadPassClear(sx+fx*last,sy+fy*last,previous+0.7,sx+fx*d,sy+fy*d,h+0.7) then return false end
            end
            previous=getVcsGroundHeight(cx+fx*d,cy+fy*d,previous)
            if not previous then return false end
        end
        return true
    end
    local function corridorTraffic(range) return raceNearby(car,x,y,z,range) end
    local ax,ay,cap=getNPCRaceOvertake(own,others,dx/length,dy/length,speed,cruise or speed,roadClear,corridorTraffic,road)
    if ax then return x+ax*reach,y+ay*reach,z+(tz-z)*reach/length,cap end
    return tx,ty,tz
end

local function stepToPoint(actor, tx, ty, tz, elapsed, driveSpeed, x, y, z, pace)
    recordNPCDebugFallback(actor, tx, ty, tz)
    local dx, dy, dz = tx - x, ty - y, tz - z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    if distance == 0 then return end

    local speed = driveSpeed and driveSpeed * 50 or NPC_SPEED_ONFOOT[pace or getNPCWalkSpeed(actor)]
    if not speed or speed <= 0 then return end
    local fraction = math.min(1, speed * elapsed * 0.001 / distance)
    local nx, ny, nz = x + dx * fraction, y + dy * fraction, z + dz * fraction
    local heading = -math.deg(math.atan2(dx, dy))
    if collisionResource and getResourceState(collisionResource) == "running"
        and call(collisionResource, "hasNearbyModelCollision", actor, nx, ny, nz, heading) then
        return
    end
    setElementPosition(actor, nx, ny, nz, false)
    if driveSpeed then
        setElementRotation(actor, math.deg(math.asin(dz / distance)), 0, heading)
    else
        setPedRotation(actor, heading)
    end
end

function stepNPCToPoint(actor, tx, ty, tz, elapsed, driveSpeed, pace)
    local x, y, z = getElementPosition(actor)
    stepToPoint(actor, tx, ty, tz, elapsed, driveSpeed, x, y, z, pace)
end

function stepNPCAlongLine(actor, task, elapsed, driveSpeed)
    local x, y, z = getElementPosition(actor)
    local x1, y1, z1, x2, y2, z2, offset = unpack(task, 2, 8)
    local length = getDistanceBetweenPoints3D(x1, y1, z1, x2, y2, z2)
    local progress = getPercentageInLine(x, y, x1, y1, x2, y2)
    local target = math.min(1, math.max(0, progress + math.max(offset, 0.01) / length))
    stepToPoint(actor, x1 + (x2 - x1) * target, y1 + (y2 - y1) * target, z1 + (z2 - z1) * target,
        elapsed, driveSpeed, x, y, z)
end

function stepNPCAroundBend(actor, task, elapsed, driveSpeed)
    local x, y, z = getElementPosition(actor)
    local cx, cy, x1, y1, z1, x2, y2, z2, offset = unpack(task, 2, 10)
    local length = getDistanceBetweenPoints2D(x1, y1, x2, y2)
    local angle = getAngleInBend(x, y, cx, cy, x1, y1, x2, y2)
    local target = math.min(math.pi * 0.5, math.max(0, angle + math.max(offset, 0.01) / length))
    local tx, ty = getPosFromBend(target, cx, cy, x1, y1, x2, y2)
    stepToPoint(actor, tx, ty, z1 + (z2 - z1) * target / (math.pi * 0.5), elapsed, driveSpeed, x, y, z)
end
