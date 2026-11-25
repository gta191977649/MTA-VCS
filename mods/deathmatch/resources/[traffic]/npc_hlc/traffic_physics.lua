local corridor = 14
local verticalTolerance = 7
local laneTolerance = 2.5
local headingTolerance = 0.35

function getNPCTrafficPhysicsMotion(actor)
    local matrix = getElementMatrix(actor)
    if not matrix then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.1 then return end
    fx, fy = fx / length, fy / length
    local vx, vy, vz = getElementVelocity(actor)
    vx, vy = vx * 50, vy * 50
    local forward, lateral = vx * fx + vy * fy, vx * fy - vy * fx
    return {x = matrix[4][1], y = matrix[4][2], z = matrix[4][3], fx = fx, fy = fy,
        grade = matrix[2][3] / length, vx = vx, vy = vy, vz = vz*50, forward = forward, lateral = lateral,
        unstable = matrix[3][3] < 0.35 or forward < -0.8 or math.abs(lateral) > math.max(1.5, forward * 0.45)}
end

-- Traffic physics task: first sequence, base speed, previous lane centre,
-- then up to eight records with link, lane, centre, unit heading, class and signal.
function normalizeNPCTrafficPhysics(task)
    local first, speed, anchor, segments = task[2], task[3], task[4], task[5]
    local function finite(value)
        return type(value) == "number" and value > -math.huge and value < math.huge
    end
    if (#task ~= 5 and not (#task == 6 and isNPCTrafficDrivingStyle(task[6]))) or not finite(first) or first < 1 or first % 1 ~= 0
        or not finite(speed) or speed <= 0 or type(anchor) ~= "table" or #anchor ~= 3
        or type(segments) ~= "table" or #segments < 1 or #segments > 8 then return false end
    for i = 1, 3 do if not finite(anchor[i]) then return false end end
    local copy = {}
    for i = 1, #segments do
        local segment = segments[i]
        if type(segment) ~= "table" or #segment ~= 9 then return false end
        for j = 1, 9 do if not finite(segment[j]) then return false end end
        local link, lane, _, _, _, dx, dy, class, signal = unpack(segment)
        if link < 0 or link % 1 ~= 0 or lane < 0 or lane > 6 or lane % 1 ~= 0
            or math.abs(dx * dx + dy * dy - 1) > 0.01
            or class < 0 or class > 3 or class % 1 ~= 0
            or signal < 0 or signal > 2 or signal % 1 ~= 0 then return false end
        copy[i] = {unpack(segment)}
        if task.race and segment.carriageway then
            local road=segment.carriageway
            if type(road)~="table" or #road~=7 then return false end
            for j=1,7 do if not finite(road[j]) then return false end end
            if road[5]>=road[6] or road[7]<0 then return false end
            copy[i].carriageway={unpack(road)}
        end
    end
    local normalized={task[1], first, speed, {unpack(anchor)}, copy, task[6]}
    if task.mission==true then normalized.mission=true end
    if task.race==true then normalized.race=true end
    if normalized.race and task.raceExit then
        local exit=task.raceExit
        if type(exit)~="table" or #exit~=4 and #exit~=5 then return false end
        for i=1,4 do if not finite(exit[i]) then return false end end
        if exit[5]~=nil and (not finite(exit[5]) or exit[5]<=0 or exit[5]>32) then return false end
        normalized.raceExit={unpack(exit)}
    end
    return normalized
end

local function distanceToSegment(x, y, z, ax, ay, az, segment)
    local dx, dy = segment[3] - ax, segment[4] - ay
    local squared = dx * dx + dy * dy
    local t = squared > 0 and math.max(0, math.min(1, ((x - ax) * dx + (y - ay) * dy) / squared)) or 0
    if math.abs(z - (az + (segment[5] - az) * t)) > verticalTolerance then return math.huge end
    return (x - ax - dx * t) ^ 2 + (y - ay - dy * t) ^ 2
end

-- 0x00438A80 advances near the lane centre or upon passing it towards the
-- next link. Bound the forward test to the route corridor after an MTA impact.
function getNPCTrafficPhysicsIndex(task, index, motion)
    if not motion or motion.unstable or motion.forward < -0.1 then return index end
    local x, y, z, fx, fy = motion.x, motion.y, motion.z, motion.fx, motion.fy
    local segments = task[5]
    while index <= #segments do
        local current, following = segments[index], segments[index + 1]
        local px, py = x - current[3], y - current[4]
        local squared = px * px + py * py
        local past = px * current[6] + py * current[7]
        if isNPCTrafficSignalClosed(current[9], task[6]) and past <= 0 then break end
        local aligned = fx * current[6] + fy * current[7] > headingTolerance
            and math.abs(px * current[7] - py * current[6]) <= laneTolerance
        local passed = squared < 25 and aligned
        if following then
            local dx, dy = following[3] - current[3], following[4] - current[4]
            local ahead = px * dx + py * dy
            local nextDistance = distanceToSegment(x, y, z, current[3], current[4], current[5], following)
            passed = passed or ahead > 0 and nextDistance <= laneTolerance ^ 2
                and (squared < 64 or ahead * ahead > 0.49 * squared * (dx * dx + dy * dy))
                and fx * following[6] + fy * following[7] > headingTolerance
        else
            passed = passed or past > 0 and squared < 64 and aligned
        end
        if task.race then
            -- 00438A80 advances a race link after passing it in the direction
            -- of the next link, even with a lateral offset from passing traffic.
            local dx,dy=current[6],current[7]
            if following then dx,dy=following[3]-current[3],following[4]-current[4] end
            local ahead=px*dx+py*dy
            passed=squared<25 or ahead>0 and (squared<64 or ahead*ahead>0.49*squared*(dx*dx+dy*dy))
        end
        if not passed or math.abs(z - current[5]) > verticalTolerance then break end
        index = index + 1
    end
    return index
end

local function routeDistance(task, index, x, y, z)
    local previous = task[5][index - 1]
    local ax, ay, az
    if previous then ax, ay, az = previous[3], previous[4], previous[5]
    else ax, ay, az = unpack(task[4]) end
    return distanceToSegment(x, y, z, ax, ay, az, task[5][index])
end

function isNPCTrafficPhysicsOnRoute(task, index, x, y, z)
    return routeDistance(task, index, x, y, z) <= corridor ^ 2
end

function isNPCRacePassingLane(task,x,y,fx,fy,length,width)
    if not task or not task[5][1].carriageway then return true end
    local initial,previous
    for step=0,math.ceil(length/5) do
        local d=math.min(length,step*5)
        local px,py=x+fx*d,y+fy*d
        local error
        for i,lane in ipairs(task[5]) do
            local road=lane.carriageway
            if road then
                local dx,dy=px-road[1],py-road[2]
                local along=dx*lane[6]+dy*lane[7]
                local span=(road[3]-road[1])*lane[6]+(road[4]-road[2])*lane[7]
                -- The streamed window can start on the next road link.
                if along<=span+1 and (along>=-1 or i==1 and along>=-24) then
                    local side=dx*lane[7]-dy*lane[6]
                    local boundary=math.max(0,road[5]+width-side,side+width-road[6])
                    if road[7]>.5 then boundary=math.max(boundary,road[7]+width-math.abs(side)) end
                    error=math.min(error or math.huge,boundary)
                end
            end
        end
        -- Wheel-track probes verify pavement between links. A racer starting
        -- outside the bounds must also be able to steer back onto the road.
        if error then
            initial=initial or error
            if error>(previous or 0)+.001 and step>0 then return false end
            previous=error
        end
    end
    return not initial or initial==0 or previous<initial
end

function canNPCTrafficPhysicsAvoid(task, index, x, y, z, dx, dy, distance, halfWidth, passing)
    local margin = ((passing or doesNPCTrafficAvoidCars(task[6])) and 2 * laneTolerance or laneTolerance) - halfWidth
    if margin <= 0 then return false end
    return routeDistance(task, index, x, y, z) <= margin ^ 2
        and routeDistance(task, index, x + dx * distance, y + dy * distance, z) <= margin ^ 2
end

function getNPCTrafficWindowProgress(task,vehicle)
    local motion=getNPCTrafficPhysicsMotion(vehicle)
    if not motion or motion.unstable then return 1 end
    local index=getNPCTrafficPhysicsIndex(task,1,motion)
    if index==1 then
        local rejoin=findNPCTrafficPhysicsRejoin(task,1,motion.x,motion.y,motion.z,motion.fx,motion.fy)
        if rejoin then index=getNPCTrafficPhysicsIndex(task,rejoin,motion) end
    end
    return index
end

function findNPCTrafficPhysicsRejoin(task, index, x, y, z, fx, fy)
    local best, distance = nil, laneTolerance ^ 2
    for nextIndex = index + 1, #task[5] do
        local previous, candidate = task[5][nextIndex - 1], task[5][nextIndex]
        if isNPCTrafficSignalClosed(previous[9], task[6])
            and (x - previous[3]) * previous[6] + (y - previous[4]) * previous[7] <= 0 then break end
        if fx * candidate[6] + fy * candidate[7] > headingTolerance
            and (candidate[3] - x) * candidate[6] + (candidate[4] - y) * candidate[7] >= 0 then
            local error = routeDistance(task, nextIndex, x, y, z)
            if error < distance then best, distance = nextIndex, error end
        end
    end
    return best
end

function getNPCTrafficPhysicsRejoin(task, actor)
    local motion = getNPCTrafficPhysicsMotion(actor)
    if not motion or motion.unstable or motion.forward < -0.1
        or isNPCTrafficPhysicsOnRoute(task, 1, motion.x, motion.y, motion.z) then return false end
    local nextLane = findNPCTrafficPhysicsRejoin(task, 1, motion.x, motion.y, motion.z, motion.fx, motion.fy)
    return nextLane or false, not nextLane and motion.vx^2 + motion.vy^2 < 1
end

-- Frozen rail traffic advances by position; sample its velocity like other moving traffic.
local railMotionSamples = setmetatable({}, {__mode = "k"})

function getNPCTrafficVelocity(vehicle, now, x, y)
    if not isElementFrozen(vehicle) then
        local vx, vy = getElementVelocity(vehicle)
        return vx * 50, vy * 50
    end
    local sample = railMotionSamples[vehicle]
    if not sample then
        railMotionSamples[vehicle] = {x = x, y = y, tick = now, vx = 0, vy = 0}
        return 0, 0
    end
    local elapsed = (now - sample.tick) % 4294967296
    if elapsed >= 50 then
        local dx, dy = x - sample.x, y - sample.y
        if elapsed >= 250 or dx * dx + dy * dy > 0.0004 then
            local scale = math.min(1000 / elapsed, 50 / math.max(0.01, math.sqrt(dx * dx + dy * dy)))
            sample.vx, sample.vy = elapsed < 400 and dx * scale or 0, elapsed < 400 and dy * scale or 0
            sample.x, sample.y, sample.tick = x, y, now
        end
    end
    return sample.vx, sample.vy
end

-- Bounds are relative to the model origin. Use their centre so long hoods
-- and rear overhangs have the same footprint on the client and server.
function getNPCTrafficModelFootprint(vehicle, left, rear, _, right, front)
    local matrix = getElementMatrix(vehicle)
    if not matrix then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local norm = math.sqrt(fx*fx + fy*fy)
    if norm < 0.01 then return end
    fx, fy = fx/norm, fy/norm
    if not (left and rear and right and front) then left, rear, right, front = -1, -2, 1, 2 end
    local x, y, z = matrix[4][1], matrix[4][2], matrix[4][3]
    local side, along = (left+right)/2, (rear+front)/2
    return {vehicle=vehicle, originX=x, originY=y, x=x+fy*side+fx*along, y=y-fx*side+fy*along, z=z, fx=fx, fy=fy,
        width=(right-left)/2, length=(front-rear)/2, offsetX=side, offsetY=along}
end

local function contactInterval(p, v, radius, first, last)
    if math.abs(v) < 0.00001 then
        if math.abs(p) <= radius then return first, last end
        return
    end
    local a, b = (-radius-p)/v, (radius-p)/v
    first, last = math.max(first, math.min(a,b)), math.min(last, math.max(a,b))
    if first <= last then return first, last end
end

-- Swept separating-axis test. Both rectangles must overlap along all four
-- axes at the same instant within the supplied interval.
function getNPCTrafficFootprintContact(rx, ry, vx, vy, fx, fy, width, length, other, horizon)
    local ox, oy = other.fx, other.fy
    local dot, cross = math.abs(fx*ox + fy*oy), math.abs(fx*oy - fy*ox)
    local first, last = contactInterval(rx*fy-ry*fx, vx*fy-vy*fx,
        width + dot*other.width + cross*other.length, 0, horizon)
    if not first then return end
    first, last = contactInterval(rx*fx+ry*fy, vx*fx+vy*fy,
        length + dot*other.length + cross*other.width, first, last)
    if not first then return end
    first, last = contactInterval(rx*oy-ry*ox, vx*oy-vy*ox,
        other.width + dot*width + cross*length, first, last)
    if not first then return end
    return contactInterval(rx*ox+ry*oy, vx*ox+vy*oy,
        other.length + dot*length + cross*width, first, last)
end

-- CCarCtrl::FindAngleToWeaveThroughTraffic scans 12 to 24 world units.
function getNPCRaceLeadRange(speed)
    return 12*math.min(2,1+speed/20)
end

local function angleDifference(a,b)
    return math.atan2(math.sin(a-b),math.cos(a-b))
end

-- reVC CCarCtrl::WeaveForOtherCar. Positions are in world units and
-- velocities in metres per second (50 times the engine's native velocity).
local function weaveForOtherCar(own,other,speed,left,right)
    local dx=(other.originX or other.x)-(own.originX or own.x)
    local dy=(other.originY or other.y)-(own.originY or own.y)
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<1 then return left,right end
    local vx,vy=own.vx or 0,own.vy or 0
    if speed>math.sqrt(vx*vx+vy*vy)+.01 then vx,vy=speed*own.fx,speed*own.fy end
    local closing=((vx-other.vx)*dx+(vy-other.vy)*dy)*110/50
    local radii=math.sqrt(own.width^2+own.length^2)+math.sqrt(other.width^2+other.length^2)
    if closing-radii<distance then return left,right end
    local bearing=math.atan2(dy,dx)
    local relative=bearing-math.atan2(own.fy,own.fx)
    local width=other.width+(other.offsetX or 0)
    local length=other.length+(other.offsetY or 0)
    local clearance=math.abs(length*math.sin(relative))+math.abs(width*math.cos(relative))
        +1.2*(own.width+(own.offsetX or 0))
    local spread=clearance/distance
    if math.abs(angleDifference(bearing,left))<spread then left=bearing-spread end
    if math.abs(angleDifference(bearing,right))<spread then right=bearing+spread end
    return left,right
end

function findAngleToWeaveThroughTraffic(own,others,speed,route)
    local left,right=route,route
    local reach=getNPCRaceLeadRange(speed)
    local ordered={}
    local x,y=own.originX or own.x,own.originY or own.y
    for index,other in ipairs(others) do
        if math.abs(own.z-other.z)<4 and math.abs(x-other.x)<=reach and math.abs(y-other.y)<=reach then
            local ox,oy=other.originX or other.x,other.originY or other.y
            ordered[#ordered+1]={body=other,sector=120*math.floor(oy/50+60)+math.floor(ox/50+60),index=index}
        end
    end
    -- CWorld visits sectors row by row. Keep enumeration order within a cell.
    if #ordered>1 then
        table.sort(ordered,function(a,b)
            if a.sector~=b.sector then return a.sector<b.sector end
            return a.index<b.index
        end)
    end
    for _,item in ipairs(ordered) do
        left,right=weaveForOtherCar(own,item.body,speed,left,right)
    end
    if left==route and right==route then return end
    local bias=route+0.5*angleDifference(math.atan2(own.fy,own.fx),route)
    local dl,dr=math.abs(angleDifference(left,bias)),math.abs(angleDifference(right,bias))
    if dl>math.pi/2 and dr>math.pi/2 then return bias end
    if math.abs(dl-dr)>=0.08 and dl<dr then return left,right end
    return right,left
end

-- CCarCtrl::ClitargetOrientationToLink (0x422760) clips a bearing between
-- the two road-edge bearings. SA leaves 0.3 lane widths at either edge.
local function clipTargetOrientationToLink(own,lane,angle)
    local road=lane.carriageway
    if not road then return angle end
    local fx,fy=lane[6],lane[7]
    local x,y=lane[3]-own.x,lane[4]-own.y
    if x*fx+y*fy<=own.length then return angle end
    local offset=(lane[3]-road[1])*fy-(lane[4]-road[2])*fx
    local low,high=road[5]+1.5-offset,road[6]-1.5-offset
    local left=angleDifference(math.atan2(y-low*fx,x+low*fy),angle)
    local right=angleDifference(math.atan2(y-high*fx,x+high*fy),angle)
    if left*right>0 then return angle+(math.abs(left)<math.abs(right) and left or right) end
    return angle
end

function getNPCRaceOvertake(own,others,routeX,routeY,speed,cruise,clear,corridorTraffic,road,index)
    if not own or #others==0 then return end
    local waypoint=math.atan2(routeY,routeX)
    local route=waypoint
    local first=index or 1
    local lane=road and road[5][first]
    if lane and lane.carriageway and own.fx*lane[6]+own.fy*lane[7]>.35 then
        -- A waypoint is a whole cross section during a pass. Pulling back
        -- to its lane centre cuts across the car the racer is overtaking.
        for _,other in ipairs(others) do
            local x,y=other.x-own.x,other.y-own.y
            local ahead=x*lane[6]+y*lane[7]
            if ahead>=-own.length-other.length and ahead<getNPCRaceLeadRange(speed)
                and math.abs(x*lane[7]-y*lane[6])<5+other.width and math.abs(other.z-own.z)<3 then
                route=math.atan2(own.fy,own.fx)
                for i=math.min(#road[5],first+4),first,-1 do
                    route=clipTargetOrientationToLink(own,road[5][i],route)
                end
                break
            end
        end
    end
    local preferred,alternate=findAngleToWeaveThroughTraffic(own,others,speed,route)
    if not preferred and speed<8 and cruise>speed then
        preferred,alternate=findAngleToWeaveThroughTraffic(own,others,math.min(cruise,8),route)
    end
    if not preferred and cruise>speed then
        -- reVC's avoid-cars style keeps accelerating towards cruise. Once
        -- an MTA racer matches a leader, the measured closing speed alone
        -- cannot produce a weave angle. Probe the pull-away on the same lane.
        for _,other in ipairs(others) do
            local x,y=other.x-own.x,other.y-own.y
            local ahead=x*own.fx+y*own.fy
            local pace=other.vx*own.fx+other.vy*own.fy
            if ahead>0 and ahead<=getNPCRaceLeadRange(speed) and math.abs(other.z-own.z)<3
                and math.abs(x*own.fy-y*own.fx)<own.width+other.width+.35
                and other.fx*own.fx+other.fy*own.fy>.7 and pace<cruise then
                preferred,alternate=findAngleToWeaveThroughTraffic(own,others,math.min(cruise,speed+8),route)
                break
            end
        end
    end
    if not preferred then
        if math.abs(angleDifference(route,waypoint))<.01 then return end
        preferred=route
    end
    routeX,routeY=math.cos(route),math.sin(route)
    -- The MTA road graph and streamed collision supply the drivable surface.
    -- Keep the native choice unless that bearing leaves the road or is blocked.
    local length=math.max(14,math.min(24,speed))
    local pace=math.max(6,speed)
    local traffic=corridorTraffic and corridorTraffic(length+65*length/pace+8) or others
    local alongX,alongY=lane and lane[6] or routeX,lane and lane[7] or routeY
    local function blocked(x,y,fx,fy,distance,elapsed)
        for _,other in ipairs(traffic) do
            if math.abs(own.z-other.z)<3 then
                local rx,ry=other.x+other.vx*elapsed-x,other.y+other.vy*elapsed-y
                local vx,vy=other.vx-fx*pace,other.vy-fy*pace
                local hit=getNPCTrafficFootprintContact(rx,ry,vx,vy,fx,fy,own.width+.35,own.length+.25,other,distance/pace)
                if hit and not (hit==0 and rx*fx+ry*fy<0 and vx*fx+vy*fy<0) then return true end
            end
        end
    end
    local function admissible(angle)
        local dx,dy=math.cos(angle),math.sin(angle)
        local dot=own.fx*dx+own.fy*dy
        if dot<=0 then return end
        local norm=math.sqrt(2+2*dot)
        local tx,ty=(own.fx+dx)/norm,(own.fy+dy)/norm
        local turn=math.min(length,2.5*own.length*math.acos(math.min(1,dot)))
        if turn>0 and blocked(own.x,own.y,tx,ty,turn,0) then return end
        local x,y=own.x+tx*turn,own.y+ty*turn
        local across=math.abs(dx*alongY-dy*alongX)
        -- The weave angle turns the vehicle onto an open strip of pavement.
        -- A narrow opening can require only half a lane of lateral travel.
        -- Test straightening inside it as well as the approach to it.
        for width=1.5,6,.75 do
            local span=math.min(length-turn,width/math.max(.01,across))
            local ex,ey=x+dx*span,y+dy*span
            local rest=length-turn-span
            if not blocked(x,y,dx,dy,span,turn/pace)
                and (rest<.01 or not blocked(ex,ey,alongX,alongY,rest,(turn+span)/pace))
                and (turn<.01 or clear(own.x,own.y,tx,ty,turn))
                and clear(x,y,dx,dy,span)
                and (rest<.01 or clear(ex,ey,alongX,alongY,rest)) then
                return dx,dy,math.huge
            end
            if rest<.01 then break end
        end
    end
    local dx,dy,cap=admissible(preferred)
    if dx then return dx,dy,cap end
    if alternate and alternate~=preferred then
        dx,dy,cap=admissible(alternate)
        if dx then return dx,dy,cap end
    end
    -- A native edge can clear the vehicle and overshoot the far curb.
    -- Search between the route and that edge for a road-width opening.
    local step=math.rad(6)
    local firstSide=angleDifference(preferred,route)<0 and -1 or 1
    for i=1,(speed<8 and 14 or 8) do
        for side=firstSide,-firstSide,-2*firstSide do
            dx,dy,cap=admissible(route+step*i*side)
            if dx then return dx,dy,cap end
        end
    end
    -- Both openings are blocked. Let a moving queue advance while preserving
    -- enough space to steer again on the next traffic scan.
    cap=cruise
    for _,other in ipairs(others) do
        local rx,ry=other.x-own.x,other.y-own.y
        local ahead=rx*routeX+ry*routeY
        if ahead>0 and math.abs(own.z-other.z)<3 and math.abs(rx*routeY-ry*routeX)<own.width+other.width+0.4 then
            local leader=math.max(0,other.vx*routeX+other.vy*routeY)
            local gap=ahead-own.length-other.length-4-.5*speed
            cap=math.min(cap,math.max(0,leader+.65*gap),math.sqrt(leader^2+12*math.max(0,gap)))
        end
    end
    return routeX,routeY,cap
end

-- Validate a stopped sync owner's reported blocker against the server route.
-- The two stationary cars have no relative velocity until the first advances.
function isNPCTrafficHeadOnBlocked(task, vehicle, blocker, ownBounds, otherBounds)
    local own = getNPCTrafficModelFootprint(vehicle, unpack(ownBounds))
    local other = getNPCTrafficModelFootprint(blocker, unpack(otherBounds))
    if not own or not other then return false end
    local x, y, z = getElementPosition(vehicle)
    local rail = task[1] == "driveTrafficRail"
    local segment, t, steerX, steerY
    local lengths = {}
    if rail then
        segment, t = getNPCTrafficRailSegment(task, x, y)
    else
        local lane = task[5][getNPCTrafficWindowProgress(task, vehicle)]
        if not lane then return false end
        local dx, dy = lane[3]-x, lane[4]-y
        local remaining = math.sqrt(dx*dx+dy*dy)
        if remaining <= 40 then dx,dy = dx-0.4*remaining*lane[6],dy-0.4*remaining*lane[7] end
        local norm = math.sqrt(dx*dx+dy*dy)
        if norm < 0.01 then return false end
        steerX, steerY = dx/norm, dy/norm
    end
    local startX, startY = x, y
    for distance = 2, 14, 2 do
        local px, py, pz
        if rail then
            px, py, pz = getNPCTrafficRailPreview(task, segment, t, lengths, distance)
        else
            px, py, pz = x+steerX*distance, y+steerY*distance, z
        end
        local dx, dy = px-startX, py-startY
        local span = math.sqrt(dx*dx+dy*dy)
        if span < 0.001 then break end
        local fx, fy = dx/span, dy/span
        local cx = startX + fy*own.offsetX + fx*own.offsetY
        local cy = startY - fx*own.offsetX + fy*own.offsetY
        if math.abs(other.z-pz) < 2.8 and getNPCTrafficFootprintContact(other.x-cx, other.y-cy,
            -fx,-fy,fx,fy,own.width,own.length,other,span) then return true end
        startX, startY = px, py
    end
    return false
end

-- VCS 00438A80 blends the next bend's speed factor over its last 40m.
-- 00438060 starts reducing at 0.1 radians and reaches 40% at 1.2 radians.
function getNPCRaceCornerSpeed(cruise, distance, incoming, outgoing)
    if cruise<12 or distance>=40 then return cruise end
    local bend=math.abs(math.atan2(math.sin(outgoing-incoming),math.cos(outgoing-incoming)))
    local turn=math.max(0,math.min(1,(bend-0.1)/1.1))
    return cruise*(1-0.6*turn*(1-math.max(0,distance)/40))
end

-- CarCtrl writes a wheel angle directly. The car and bike pad handlers
-- square the signed input before applying the handling steering lock.
function getNPCRaceSteeringInput(angle,limit,lock)
    local magnitude=math.sqrt(math.min(math.abs(angle),limit,lock)/lock)
    return angle<0 and -magnitude or magnitude
end

local raceCornerAcceleration=15

-- Bound the turning radius by the available tangent distance before the
-- waypoint. The SCM speed is native velocity * 60, MTA world speed is * 50.
function getNPCRaceApproachSpeed(cruise,distance,incoming,outgoing,radius)
    local requested=getNPCRaceCornerSpeed(cruise,distance,incoming,outgoing)
    local bend=math.abs(angleDifference(outgoing,incoming))
    if bend<0.4 then return requested end
    local tangent=math.min(radius or 8,8)
    local turnRadius=math.max(2,tangent/math.tan(bend*.5))
    local worldSpeed=math.sqrt(raceCornerAcceleration*turnRadius+2*8*math.max(0,distance-tangent))
    return math.min(requested,worldSpeed*60/50)
end

-- Radius of the circle from the current tangent to a steering target.
-- Re-evaluate on the outbound link while the chassis is still turning.
function getNPCRaceSteeringSpeed(cruise,distance,angle)
    local bend=math.abs(angleDifference(angle,0))
    if bend<.25 then return cruise end
    local radius=math.max(2,math.min(distance,18)/(2*math.sin(math.min(bend,math.pi/2))))
    return math.min(cruise,math.sqrt(raceCornerAcceleration*radius)*60/50)
end

-- Apply the bend at the current link's exit. MTA can insert an extra
-- approach point on that same link before the next road link starts.
function getNPCRaceWindowSpeed(task,index,remaining,cruise)
    local entry=cruise
    local exit=task.raceExit
    if exit and exit[5] and (exit[1]~=exit[3] or exit[2]~=exit[4]) then
        local x,y,nx,ny,radius=unpack(exit)
        local total,ax,ay=remaining,nil,nil
        local lane=task[5][index]
        local incoming=math.atan2(lane[7],lane[6])
        for i=index,#task[5] do
            local p=task[5][i]
            if i>index then total=total+math.sqrt((p[3]-ax)^2+(p[4]-ay)^2) end
            if (x-p[3])^2+(y-p[4])^2>25^2 then
                incoming=math.atan2(y-p[4],x-p[3])
            end
            ax,ay=p[3],p[4]
        end
        total=total+math.sqrt((x-ax)^2+(y-ay)^2)
        entry=getNPCRaceApproachSpeed(cruise,total,incoming,math.atan2(ny-y,nx-x),radius)
    end
    for i=index,#task[5] do
        local lane,after=task[5][i],task[5][i+1]
        local incoming=math.atan2(lane[7],lane[6])
        if after then
            local outgoing=math.atan2(after[7],after[6])
            entry=math.min(entry,getNPCRaceApproachSpeed(cruise,remaining,incoming,outgoing))
            -- A rounded street corner can span several short links. Their
            -- change of tangent per metre gives the radius even when each
            -- individual change is too small to count as a junction.
            local chord=math.sqrt((after[3]-lane[3])^2+(after[4]-lane[4])^2)
            local sine=math.abs(math.sin(.5*(outgoing-incoming)))
            if sine>.025 and chord>1 then
                local radius=chord/(2*sine)
                local corner=math.sqrt(raceCornerAcceleration*radius+16*math.max(0,remaining-8))*60/50
                entry=math.min(entry,corner)
            end
            remaining=remaining+chord
        elseif exit and (exit[1]~=exit[3] or exit[2]~=exit[4]) then
            remaining=remaining+math.sqrt((exit[1]-lane[3])^2+(exit[2]-lane[4])^2)
            entry=math.min(entry,getNPCRaceApproachSpeed(cruise,remaining,incoming,
                math.atan2(exit[4]-exit[2],exit[3]-exit[1]),exit[5]))
        end
    end
    return entry
end
