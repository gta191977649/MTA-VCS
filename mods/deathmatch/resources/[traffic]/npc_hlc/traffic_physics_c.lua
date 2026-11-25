local samples = setmetatable({}, {__mode = "k"})
local diagnostics = setmetatable({}, {__mode = "k"})
local debugging = false
local sensorBudget = 12
local deferred = setmetatable({}, {__mode="k"})
local frame, reserved, missed = 0,0,0
local SAMPLE_MS = 75
local BRAKING = 3 -- Conservative MTA braking envelope, in world units/s².
local STALL_MS = 1000
local REVERSE_MS = 700 -- VCS PC 0x0041FC57, ordinary cruise traffic.
local AVOID_DISTANCE = 4
local AVOID_ANGLE = math.rad(15)
local RECOVERY_SPEED = 2.5
addEvent("npc_hlc:onCruiseStuck", false)
addEvent("npc_hlc:onRouteLow",false)

function beginNPCTrafficPhysicsFrame()
    sensorBudget = 12
    frame,reserved,missed=frame+1,math.min(6,missed),0
end

function resetNPCTrafficPhysicsSensor(vehicle)
    samples[vehicle], diagnostics[vehicle] = nil, nil
end

addEventHandler("onClientVehicleCollision", root, function()
    if samples[source] then resetNPCTrafficPhysicsSensor(source) end
end)

local function stopSpeed(gap, leader, speed)
    local available = math.max(0, gap - 2 - math.max(0, speed - leader) * 0.15)
    return math.sqrt(leader * leader + 2 * BRAKING * available)
end

local function vehicleExtents(vehicle)
    local a, b, _, c, d = getElementBoundingBox(vehicle)
    return a and c and math.max(-a, c) or 1, b and d and math.max(-b, d) or 2
end

-- Raycasts cover the environment and pedestrians. Vehicles use moving
-- rectangles over the same braking path, including its curved segments.
local function movingVehicles(vehicle,motion,range,now,exempt)
    local others = {}
    local nearby = getElementsWithinRange(motion.x, motion.y, motion.z, range + 16,
        "vehicle", getElementInterior(vehicle), getElementDimension(vehicle)) or {}
    for _, other in ipairs(nearby) do
        if other ~= vehicle and other ~= exempt and isElementStreamedIn(other) then
            local bounds = getNPCTrafficFootprint(other, now)
            if bounds then others[#others + 1] = bounds end
        end
    end
    return others
end

local function vehicleScan(vehicle, motion, range, speed, now, exempt, stopForPeds)
    local body = getNPCTrafficFootprint(vehicle, now)
    local others=movingVehicles(vehicle,motion,range,now,exempt)
    local pedestrians
    if stopForPeds then
        pedestrians = {}
        for _, kind in ipairs({"ped", "player"}) do
            local actors = getElementsWithinRange(motion.x, motion.y, motion.z, range + 6,
                kind, getElementInterior(vehicle), getElementDimension(vehicle)) or {}
            for _, actor in ipairs(actors) do
                if getElementType(actor) == kind and isElementStreamedIn(actor)
                    and not getPedOccupiedVehicle(actor) and not isPedDead(actor) then
                    local x,y,z = getElementPosition(actor)
                    local vx,vy = getElementVelocity(actor)
                    pedestrians[#pedestrians+1] = {x=x, y=y, z=z, vx=vx*50, vy=vy*50}
                end
            end
        end
    end
    return {body = body, others = others, pedestrians = pedestrians, speed = math.max(4, speed), motion = motion}
end

local function sweptVehicleLimit(scan, x, y, z, dx, dy, sweep, travelled, grade, speed)
    local body = scan.body
    local limit, nearest, cause, blocker = math.huge, math.huge, "clear"
    if not body then return limit, cause, nearest end
    local distance = math.max(0, travelled + 0.35)
    local arrival, duration = distance / scan.speed, sweep / scan.speed
    for _, other in ipairs(scan.others) do
        local rx = other.x + other.vx * arrival - x
        local ry = other.y + other.vy * arrival - y
        local hit = getNPCTrafficFootprintContact(rx, ry, other.vx - dx * scan.speed, other.vy - dy * scan.speed,
            dx, dy, body.width + (scan.turnMargin or 0), body.length, other, duration)
        -- A touching follower must not hold the lead car at a green light.
        -- Keep future contact from behind (such as a faster merge) eligible.
        local initialX, initialY = other.x - body.x, other.y - body.y
        local leavingFollower = hit == 0 and initialX*body.fx + initialY*body.fy < 0
            and rx*dx + ry*dy < 0 and other.vx*dx + other.vy*dy <= scan.speed
        if hit and other.vehicle ~= scan.exempt and not leavingFollower and math.abs(other.z - (z + grade * hit * scan.speed)) < 3 then
            local gap = distance + hit * scan.speed
            local alignment = other.fx * dx + other.fy * dy
            local following = alignment > 0.9 and initialX * body.fx + initialY * body.fy > 0
                and math.abs(initialX * body.fy - initialY * body.fx) < body.width + other.width
            local leader = following and math.max(0, other.vx * dx + other.vy * dy) or 0
            -- Keep turning room before a stopped queue starts its bypass.
            local ahead = initialX * body.fx + initialY * body.fy > 0
            local reserve = ahead and (alignment < -0.5 or other.parked) and other.vehicle ~= scan.passing and 4 or 0
            local cap = stopSpeed(gap - reserve, leader, speed)
            if scan.committed == other.vehicle then
                -- The awarded driver's side maneuver keeps the physical
                -- braking clearance after its one-second cruise floor expires.
                local available = math.max(0, gap - 0.35 - speed * 0.15)
                local safe = math.sqrt(2 * BRAKING * available)
                cap = scan.floor and math.min(safe, math.max(cap, scan.floor)) or safe
            end
            nearest = math.min(nearest, gap)
            if cap < limit then
                limit, cause, blocker = cap, (following or alignment < -0.5) and "following" or "crossing", other.vehicle
            end
        end
    end
    return limit, cause, nearest, blocker
end

local function roadSurface(element, normalZ)
    local kind=isElement(element) and getElementType(element)
    return normalZ and normalZ>=0.85 and (not kind or kind=="object" or kind=="building")
end

local function scanStrip(vehicle, x0, y0, z, dx, dy, halfWidth, sweep, grade, travelled, speed, scan)
    local limit, nearest, cause, blocker = math.huge, math.huge, "clear"
    if scan and scan.body then
        local body, motion = scan.body, scan.motion
        -- The existing ray path starts at the bumper. Translate its initial
        -- point back to the chassis origin and rotate the local box centre.
        local x = x0 - motion.fx * scan.bumper + dx * body.offsetY + dy * body.offsetX
        local y = y0 - motion.fy * scan.bumper + dy * body.offsetY - dx * body.offsetX
        limit, cause, nearest, blocker = sweptVehicleLimit(scan, x, y, z - motion.grade * scan.bumper,
            dx, dy, sweep, travelled, grade, speed)
    end
    -- A narrow pedestrian can fit between the three chassis rays. Style 6
    -- must brake across the full bumper width, including for a crossing ped.
    if scan and scan.pedestrians then
        for _, ped in ipairs(scan.pedestrians) do
            local rx, ry = ped.x-x0, ped.y-y0
            local arrival = math.max(0, math.min(1.5, (travelled+rx*dx+ry*dy)/scan.speed))
            rx, ry = rx+ped.vx*arrival, ry+ped.vy*arrival
            local ahead = rx*dx + ry*dy
            if ahead >= -0.5 and ahead <= sweep+0.35 and math.abs(rx*dy-ry*dx) <= halfWidth+0.35
                and math.abs(ped.z-z-grade*ahead) < 2 then
                local gap = math.max(0, travelled+ahead-0.35)
                local cap = stopSpeed(gap, 0, speed)
                nearest = math.min(nearest, gap)
                if cap <= limit then limit, cause, blocker = cap, "pedestrian", nil end
            end
        end
    end
    for offset = -1, 1 do
        local side = offset * halfWidth * 0.85
        local x = x0 + dy * side
        local y = y0 - dx * side
        local ex,ey=x+dx*sweep,y+dy*sweep
        local hit, hx, hy, hz, element, nx, ny, nz = processLineOfSight(x, y, z, ex, ey, z + grade * sweep,
            true, not (scan and scan.body), true, true, false, false, false, false, vehicle)
        if hit and scan and scan.race and roadSurface(element,nz) then
            -- A bumper ray meets the pavement where the road climbs faster
            -- than the chassis pitch. Continue above that face to catch a
            -- fence, traffic or a wall beyond the change in grade.
            local endZ=hz-((ex-hx)*nx+(ey-hy)*ny)/nz
            hit,hx,hy,hz,element,nx,ny,nz=processLineOfSight(hx,hy,hz+0.4,ex,ey,endZ+0.4,
                true,not scan.body,true,true,false,false,false,false,vehicle)
            if hit and roadSurface(element,nz) then hit=false end
        end
        if hit and not (scan and scan.exempt and element == scan.exempt) then
            local leader = 0
            local kind = isElement(element) and getElementType(element)
            if kind == "vehicle" and not isElementFrozen(element) then
                local vx, vy = getElementVelocity(element)
                leader = math.max(0, (vx * dx + vy * dy) * 50)
            end
            local gap = math.max(0, travelled + (hx - x) * dx + (hy - y) * dy)
            local candidate = stopSpeed(gap, leader, speed)
            local hitCause = kind == "vehicle" and "following"
                or (kind == "ped" or kind == "player") and "pedestrian" or "obstacle"
            nearest = math.min(nearest, gap)
            if candidate < limit or candidate == limit and (blocker or cause == "obstacle" and hitCause ~= "obstacle") then
                limit, cause, blocker = candidate, hitCause, nil
            end
        end
    end
    return limit, cause, nearest, blocker
end

local function scanBumper(vehicle, motion, dx, dy, width, length, range, speed, scan)
    local sign = dx * motion.fx + dy * motion.fy < 0 and -1 or 1
    local offset = sign * (length - 0.35)
    local grade = math.max(-0.3, math.min(0.3, motion.grade))
    if scan then scan.bumper = offset end
    return scanStrip(vehicle, motion.x + motion.fx * offset, motion.y + motion.fy * offset,
        motion.z + grade * offset, dx, dy, width, range + 0.35, grade * sign, -0.35, speed, scan)
end

-- 00435348 picks a free bearing for style 2, scanning 12–24 world units.
-- Close ram excludes its vehicle target. Block approach considers all cars.
local policeBearings = {0.32, -0.32, 0.65, -0.65}
local raceEscapeBearings = {0.32,-0.32,0.65,-0.65,0.95,-0.95,1.25,-1.25,math.pi/2,-math.pi/2}
function getNPCPoliceAvoidance(vehicle, exempt, dx, dy, progress, stopForPeds, raceCruise, road, index)
    local distance = math.sqrt(dx*dx+dy*dy)
    if distance < 0.1 then return 0 end
    local now = getTickCount()
    local age = progress.avoidAt and (now-progress.avoidAt)%4294967296 or math.huge
    if age < 100 then return progress.avoidAngle, progress.avoidSpeed end
    if sensorBudget <= reserved then
        if age<200 then return progress.avoidAngle,progress.avoidSpeed end
        return 0
    end
    local motion = getNPCTrafficPhysicsMotion(vehicle)
    if not motion then return 0 end
    sensorBudget = sensorBudget-1
    local speed = math.sqrt(motion.vx^2 + motion.vy^2)
    local reach = math.min(distance, 12*math.min(2, 1+speed/20))
    local width, length = vehicleExtents(vehicle)
    local scan = vehicleScan(vehicle, motion, raceCruise and math.sqrt(2)*getNPCRaceLeadRange(speed) or reach, speed, now, exempt, stopForPeds)
    scan.exempt = exempt
    scan.race = raceCruise~=nil and raceCruise~=false
    dx, dy = dx/distance, dy/distance
    if type(raceCruise)=="number" and scan.body then
        local function clear(x,y,fx,fy,span)
            if not isNPCRacePassingLane(road,x,y,fx,fy,span,width) then return false end
            -- Vehicle motion is checked by the shared swept-box predictor.
            -- The bumper rays also reject a wall or pedestrians in either
            -- half of the proposed lane change, including beside the leader.
            local saved=scan.others
            scan.others={}
            scan.bumper=0
            local _,_,gap=scanStrip(vehicle,x,y,motion.z,fx,fy,width,span,motion.grade,0,speed,scan)
            scan.others=saved
            if gap<span then return false end
            -- A horizontal ray can look clear over the edge of the apron.
            -- Verify both wheel tracks before committing to the open flank.
            for i=1,math.ceil(span/7) do
                local d=math.min(span,7*i)
                for side=-1,1,2 do
                    local px=x+fx*d+fy*width*side
                    local py=y+fy*d-fx*width*side
                    local h=motion.z+motion.grade*((px-motion.x)*motion.fx+(py-motion.y)*motion.fy)
                    local hit,_,_,_,object,_,_,nz=processLineOfSight(px,py,h+1.8,px,py,h-3,
                        true,false,false,true,false,false,false,false,vehicle)
                    if not hit or not roadSurface(object,nz) then return false end
                end
            end
            return true
        end
        local function corridorTraffic(range)
            return movingVehicles(vehicle,motion,range,now,exempt)
        end
        local fx,fy,limit=getNPCRaceOvertake(scan.body,scan.others,dx,dy,speed,raceCruise,clear,corridorTraffic,road,index)
        if fx then
            progress.raceFollowing=limit<math.huge
            -- Steering changes the wheel angle immediately. The chassis still
            -- travels along its current velocity while the motorcycle leans.
            if speed>4 then
                local along=math.min(reach,speed*0.8)
                local braking=scanBumper(vehicle,motion,motion.vx/speed,motion.vy/speed,width,length,along,speed,scan)
                limit=math.min(limit,braking)
            end
            if progress.raceFollowing then
                local obstruction=scanBumper(vehicle,motion,fx,fy,width,length,reach,speed,scan)
                limit=math.min(limit,obstruction)
            end
            local angle=math.atan2(fx*dy-fy*dx,fx*dx+fy*dy)
            progress.avoidAt,progress.avoidAngle,progress.avoidSpeed=now,angle,limit
            return angle,limit
        end
    end
    progress.raceFollowing=nil
    local cap, cause, best = scanBumper(vehicle,motion,dx,dy,width,length,reach,speed,scan)
    local angle = 0
    local vehicleAhead = scan.race and (cause == "following" or cause == "crossing")
    if best < reach and not vehicleAhead and not (stopForPeds and cause == "pedestrian") then
        local bearing = math.atan2(dy, dx)
        -- A race car can be deflected into an alley at the lap line. After
        -- a blocked reverse, scan to the side for the road opening. The
        -- native sector search (00435348) compares bearings out to pi/2.
        local escaping=progress.raceReverseAt and (now-progress.raceReverseAt)%4294967296<10000
        for _, offset in ipairs(escaping and raceEscapeBearings or policeBearings) do
            local x, y = math.cos(bearing-offset), math.sin(bearing-offset)
            local limit, _, gap = scanBumper(vehicle,motion,x,y,width,length,reach,speed,scan)
            -- A longer open ray behind a vehicle may require a U-turn that
            -- cannot fit between the walls. Prefer a drivable forward exit.
            if escaping and gap>=math.min(reach,2*length+2) and x*motion.fx+y*motion.fy>0.7 then
                angle,cap=offset,limit
                break
            end
            if gap > best then
                best, angle, cap = gap, offset, limit
                if gap >= reach and not escaping then break end
            end
        end
    end
    if math.abs(angle)>0.65 then cap=math.min(cap,7) end
    progress.avoidAt, progress.avoidAngle, progress.avoidSpeed = now, angle, cap
    return angle, cap
end

-- Near a turn the steering target can already point across the junction while
-- the bumper is still facing into it. Sweep from the actual bumper, rounding
-- toward the steering target before extending the braking sightline.
local function scanRoute(vehicle, motion, dx, dy, width, length, range, speed, lane, nextLane, scan)
    local dot = dx * motion.fx + dy * motion.fy
    local radius = math.max(3, length * 1.5)
    local straight = 0
    if dot > 0.985 then
        local nextDot = nextLane and dx*nextLane[6]+dy*nextLane[7]
        if not nextDot or nextDot > 0.985 then return scanBumper(vehicle,motion,dx,dy,width,length,range,speed,scan) end
        local bendAngle = math.acos(math.max(-1, math.min(1, nextDot)))
        local remaining = (lane[3]-motion.x)*dx + (lane[4]-motion.y)*dy - length
        straight = math.max(0, remaining - radius * math.tan(math.min(bendAngle, math.pi/2)/2))
        if straight >= range then return scanBumper(vehicle,motion,dx,dy,width,length,range,speed,scan) end
        dx,dy = nextLane[6],nextLane[7]
        dot = dx * motion.fx + dy * motion.fy
    end
    local angle = math.atan2(motion.fx * dy - motion.fy * dx, dot)
    local bend = math.min(radius * math.abs(angle), range-straight)
    local steps = math.max(1, math.ceil(bend / radius / math.rad(25)))
    local heading = math.atan2(motion.fy, motion.fx)
    local grade = math.max(-0.3, math.min(0.3, motion.grade))
    local x,y = motion.x + motion.fx*(length-0.35), motion.y + motion.fy*(length-0.35)
    local z = motion.z + grade*(length-0.35)
    scan.bumper = length - 0.35
    local limit,cause,gap,blocker = math.huge,"clear",math.huge
    local travelled = -0.35
    if straight > 0 then
        limit,cause,gap,blocker = scanStrip(vehicle,x,y,z,motion.fx,motion.fy,width,straight,grade,travelled,speed,scan)
        x,y,z=x+motion.fx*straight,y+motion.fy*straight,z+grade*straight
        travelled=travelled+straight
    end
    for i=1,steps+1 do
        local turn = math.min(i-0.5,steps) * bend / (steps*radius)
        local yaw = heading + (angle<0 and -turn or turn)
        local ux,uy = math.cos(yaw),math.sin(yaw)
        local distance = i<=steps and 2*radius*math.sin(bend/(2*radius*steps)) or range-straight-bend+0.35
        local slope = grade*(motion.fx*ux+motion.fy*uy)
        local cap,reason,clearance,other = scanStrip(vehicle,x,y,z,ux,uy,width,distance,slope,travelled,speed,scan)
        if cap<limit or cap==limit and not other then limit,cause,blocker=cap,reason,other end
        gap=math.min(gap,clearance)
        x,y,z=x+ux*distance,y+uy*distance,z+slope*distance
        travelled=travelled+distance
    end
    return limit,cause,gap,blocker
end

local function canPassOnRoute(task, index, motion, dx, dy, reach, width, passing)
    if canNPCTrafficPhysicsAvoid(task,index,motion.x,motion.y,motion.z,dx,dy,reach,width,passing) then return true end
    if not task[5][index+1] then return false end
    local half = reach / 2
    return canNPCTrafficPhysicsAvoid(task,index,motion.x,motion.y,motion.z,dx,dy,half,width,passing)
        and canNPCTrafficPhysicsAvoid(task,index+1,motion.x+dx*half,motion.y+dy*half,motion.z,dx,dy,half,width,passing)
        or canNPCTrafficPhysicsAvoid(task,index+1,motion.x,motion.y,motion.z,dx,dy,reach,width,passing)
end

-- Remember the chosen side until the whole vehicle is past the opposing
-- car. Steering straight back to the lane centre while alongside it closes
-- the very gap the maneuver needs.
local function passingOpponent(previous, award, scan)
    local pass = previous and previous.pass
    if award and (not pass or pass.vehicle ~= award) then
        pass = {vehicle = award, fx = scan.motion.fx, fy = scan.motion.fy}
    end
    if not pass or not scan.body then return end
    for _, other in ipairs(scan.others) do
        if other.vehicle == pass.vehicle then
            local x, y = other.x-scan.body.x, other.y-scan.body.y
            local ahead = x*pass.fx + y*pass.fy
            if x*x+y*y < 25^2 and ahead > -(scan.body.length+other.length+0.5) then
                return pass, other, ahead, x*pass.fy-y*pass.fx
            end
        end
    end
end

local function passOpponent(vehicle, motion, task, index, scan, pass, other, ahead, sideGap, width, length, speed, routeX, routeY)
    local firstSide = pass.side or (sideGap > 0 and 1 or -1)
    local lastSide = pass.side or -firstSide
    local best, angle, chosenSide, cause, blocker = -1, 0, nil, "route"
    scan.passing, scan.committed, scan.turnMargin = other.vehicle, other.vehicle, 0.2
    local parallel = math.abs(other.fx*pass.fx + other.fy*pass.fy)
    local across = math.abs(other.fx*pass.fy - other.fy*pass.fx)
    local halfWidth = other.width*parallel + other.length*across
    local halfLength = other.length*parallel + other.width*across
    for side = firstSide, lastSide, -2*firstSide do
        -- Aim outside the nearer corner of the blocker. Then follow its
        -- flank until the rear bumper clears, even if the straight ray opens.
        local lateral = sideGap - side*(scan.body.width + halfWidth + 0.7)
        local along = math.max(2.5, ahead - scan.body.length - halfLength)
        local reach = math.sqrt(lateral*lateral + along*along)
        local ax = (pass.fx*along + pass.fy*lateral)/reach
        local ay = (pass.fy*along - pass.fx*lateral)/reach
        if canPassOnRoute(task,index,motion,ax,ay,reach,width,true) then
            local cap, hazard, _, limitedBy = scanRoute(vehicle,motion,ax,ay,width,length,math.max(7,reach),speed,nil,nil,scan)
            if cap > best then
                best, chosenSide = cap, side
                angle = math.atan2(routeX*ay-routeY*ax, routeX*ax+routeY*ay)
                cause, blocker = hazard, limitedBy
            end
        end
    end
    scan.turnMargin = nil
    if best <= 0 then return 0, angle, cause, blocker end
    pass.side = chosenSide
    return math.min(best, task[3]*0.4), angle, "avoiding"
end

-- The VCS PC follow-path routine (0x00434900) calls the traffic speed
-- routine (0x00434400). Measure clearance with streamed MTA collision data.
local function trafficLimit(vehicle, motion, routeX, routeY, task, index, allowAvoid, abandoned)
    local style = task[6]
    if style == 3 then return math.huge, "clear", 0 end
    local avoidsCars = doesNPCTrafficAvoidCars(style)
    local speed = math.sqrt(motion.vx ^ 2 + motion.vy ^ 2)
    local dx, dy = routeX, routeY
    if speed > 0.5 then dx, dy = motion.vx / speed, motion.vy / speed end
    local sequence = task[2] + index - 1
    local previous, now = samples[vehicle], getTickCount()
    if previous and (previous.style ~= style or previous.abandoned ~= abandoned) then previous = nil end
    local award = abandoned or getElementData(vehicle, "npchlc_traffic:headOnBlocker", false)
    if previous and previous.award == award and previous.sequence == sequence and (now - previous.tick) % 4294967296 < SAMPLE_MS
        and previous.dx * dx + previous.dy * dy > 0.94
        and previous.fx * motion.fx + previous.fy * motion.fy > 0.94
        and previous.routeX * routeX + previous.routeY * routeY > 0.94
        and previous.allowAvoid == allowAvoid and math.abs(previous.speed - speed) < 2
        and (motion.x - previous.x) ^ 2 + (motion.y - previous.y) ^ 2 < 1 then
        return previous.limit, previous.cause, previous.avoidAngle
    end
    local priority=deferred[vehicle]==frame-1
    if sensorBudget==0 or not priority and sensorBudget<=reserved then
        if deferred[vehicle]~=frame then missed=missed+1 end
        deferred[vehicle]=frame
        if previous and previous.sequence==sequence and previous.cause=="clear"
            and (now-previous.tick)%4294967296<=150 and previous.dx*dx+previous.dy*dy>0.995
            and previous.routeX*routeX+previous.routeY*routeY>0.995 and previous.fx*motion.fx+previous.fy*motion.fy>0.995
            and previous.nextLink==(task[5][index+1] and task[5][index+1][1]) and math.abs(motion.z-previous.z)<0.5 then
            local shift=math.sqrt((motion.x-previous.x)^2+(motion.y-previous.y)^2)
            if shift<=2 and previous.range-shift>=speed^2/(2*BRAKING)+speed*0.15+2 then
                return math.huge,"clear",0
            end
        end
        return 0,"Sensor budget",0
    end
    if priority then reserved=math.max(0,reserved-1) end
    deferred[vehicle]=nil
    sensorBudget = sensorBudget - 1
    local width, length = vehicleExtents(vehicle)
    local range = math.min(120, math.max(8, speed ^ 2 / (2 * BRAKING) + speed * 0.15 + 4))
    local scan = vehicleScan(vehicle, motion, range, speed, now, nil, style == 6 or abandoned)
    local limit, cause, gap, blocker = scanRoute(vehicle, motion, routeX, routeY, width, length, range, speed,
        task[5][index],task[5][index+1],scan)
    local avoidAngle = 0
    local pass, opposing, ahead, sideGap
    if avoidsCars or abandoned then pass, opposing, ahead, sideGap = passingOpponent(previous, award, scan) end
    if pass and allowAvoid then
        scan.floor = award == opposing.vehicle and task[3]*0.2 or nil
        local sideLimit, angle, hazard, sideBlocker = passOpponent(vehicle,motion,task,index,scan,pass,opposing,ahead,sideGap,
            width,length,speed,routeX,routeY)
        if blocker == opposing.vehicle or cause == "clear" or sideLimit < limit then
            if sideLimit <= 0 and abandoned and blocker == abandoned then
                -- Both side paths are closed. Creep against this one empty
                -- vehicle, keeping the full sweep for buildings, peds and cars.
                scan.exempt = abandoned
                local clearance
                sideLimit, hazard, clearance, sideBlocker = scanRoute(vehicle,motion,routeX,routeY,width,length,range,speed,
                    task[5][index],task[5][index+1],scan)
                if sideLimit > task[3]*0.2 then sideLimit,hazard = task[3]*0.2,"clearing abandoned car" end
                angle = 0
            end
            limit, cause, avoidAngle, blocker = sideLimit, hazard, angle, sideBlocker
        end
    elseif avoidsCars and allowAvoid and (blocker or cause == "pedestrian" and style ~= 6) and limit < task[3] then
        scan.passing = blocker
        scan.turnMargin = 0.2 -- Allow for steering response while passing a stopped car.
        local angle = math.atan2(routeY,routeX)
        local reach = math.min(range,math.max(7,speed*1.4))
        local firstSide = 1
        if blocker then
            local bx, by = getElementPosition(blocker)
            firstSide = (bx-motion.x)*routeY - (by-motion.y)*routeX > 0 and 1 or -1
        end
        local lane = task[5][index]
        local endOffset = (motion.x + routeX*reach - lane[3])*lane[7] - (motion.y + routeY*reach - lane[4])*lane[6]
        for side = firstSide, -firstSide, -2*firstSide do
            local room = math.max(0, 4.9-width + side*endOffset)
            local offset = side * math.asin(math.min(0.55,room/reach))
            local ax, ay = math.cos(angle+offset), math.sin(angle+offset)
            if room > 0 and canPassOnRoute(task,index,motion,ax,ay,reach,width) then
                local sideLimit = scanRoute(vehicle,motion,ax,ay,width,length,reach,speed,nil,nil,scan)
                if math.min(sideLimit,task[3]) > limit then
                    limit, cause, avoidAngle, blocker = math.min(sideLimit,task[3]), "avoiding", offset, nil
                end
            end
        end
        scan.turnMargin = nil
        scan.passing = nil
    end
    if allowAvoid and cause == "obstacle" and gap <= AVOID_DISTANCE and speed <= RECOVERY_SPEED then
        local angle = math.atan2(routeY, routeX)
        for side = -1, 1, 2 do
            local offset = side * AVOID_ANGLE
            local ax, ay = math.cos(angle + offset), math.sin(angle + offset)
            if ax * motion.fx + ay * motion.fy > 0
                and canNPCTrafficPhysicsAvoid(task, index, motion.x, motion.y, motion.z, ax, ay, AVOID_DISTANCE, width) then
                local _, _, clearance = scanBumper(vehicle, motion, ax, ay, width, length, AVOID_DISTANCE, speed, scan)
                if clearance == math.huge then
                    limit, cause, avoidAngle = RECOVERY_SPEED, "avoiding", offset
                    break
                end
            end
        end
    end
    if speed > 0.6 and dx * routeX + dy * routeY < 0.999 then
        -- The tangent checks immediate drift during steering. Longer range
        -- braking is already covered along the turning path above.
        local emergencyRange = math.max(2, speed * 0.35)
        if cause ~= "avoiding" then scan.committed, scan.passing = nil, nil end
        local emergency, hazard, _, other = scanBumper(vehicle, motion, dx, dy, width, length, math.min(range, emergencyRange), speed, scan)
        if emergency < limit then limit, cause, blocker = emergency, hazard, other end
    end
    reportNPCTrafficBlocker(vehicle, blocker, limit, task[3], now)
    samples[vehicle] = {style = style, emptyBlocker = blocker and not getVehicleOccupant(blocker,0),
        abandoned = abandoned, award = award, pass = pass, tick = now, sequence = sequence, dx = dx, dy = dy, fx = motion.fx, fy = motion.fy,
        routeX = routeX, routeY = routeY, limit = limit, speed = speed, cause = cause, avoidAngle = avoidAngle,
        allowAvoid = allowAvoid, x = motion.x, y = motion.y,z=motion.z,range=range,
        nextLink=task[5][index+1] and task[5][index+1][1]}
    return limit, cause, avoidAngle
end

local function applyInputs(npc, vehicle, motion, progress, steer, speed, reason, avoidAngle, rear, elapsed)
    local reversing = reason == "reverse"
    local error = speed - motion.forward
    local gain = motion.forward < 2 and 0.25 or 0.125
    local throttle = speed > 0 and math.max(0, math.min(1, error * gain)) or 0
    if reason == "cruise" and elapsed then
        -- Keep enough throttle to hold the rail target against drag or grade.
        -- Limit the integral so a stationary or slow vehicle cannot wind it up.
        local trim = progress.cruiseThrottle or 0
        if throttle + trim < 1 or error < 0 then
            trim = math.max(0, math.min(1, trim + error * elapsed * 0.00022))
        end
        progress.cruiseThrottle = trim
        throttle = error >= -0.25 and math.max(0, math.min(1, error * gain + trim)) or 0
    else
        progress.cruiseThrottle = nil
    end
    local moving = motion.forward > 0.5
    local urgent = reason == "obstacle" or reason == "following" or reason == "crossing"
        or reason == "pedestrian" or reason == "signal" or reason == "Sensor budget"
    local brake = moving and (speed == 0 and 1
        or math.max(0, math.min(urgent and 1 or 0.5, -error * (urgent and 0.25 or 0.05)))) or 0
    if throttle > 0 then brake = 0 end
    if reversing then
        brake=progress.raceReverseAt and 0.5 or math.max(0,math.min(1,(1.5+motion.forward)*0.6))
    end
    local handbrake = speed == 0 and not moving and not reversing and reason ~= "sliding"
    setNPCVehicleInputs(npc, steer, throttle - brake, handbrake)
    recordNPCDebugDriving(reason=="cruise" and progress.usingPreview and "Route preview" or reason, speed > 0)
    if debugging then
        local action = reversing and "reverse" or progress.reverseAt and "rear check"
            or progress.rejoinAt and "rejoin" or "follow"
        diagnostics[vehicle] = {progress.sequence, motion.lateral, progress.cruiseSpeed or 0, motion.forward,
            speed, reason, brake, action,
            math.deg(avoidAngle or 0), rear or "-"}
    end
end

local function elapsedSince(now, started)
    return (now - started) % 4294967296
end

local function runReverse(npc, vehicle, motion, progress, now, signalClosed, reversingSteer)
    local reason, rear
    if signalClosed then
        reason = "signal"
    elseif elapsedSince(now, progress.reverseAt) >= (progress.reverseDuration or REVERSE_MS) then
        reason = "reverse complete"
    elseif sensorBudget == 0 then
        reason = "Sensor budget"
    else
        sensorBudget = sensorBudget - 1
        local width, length = vehicleExtents(vehicle)
        local speed = math.max(0, -motion.forward)
        local clearance = 2.5 + speed ^ 2 / (2 * BRAKING)
        local scan = progress.abandonedReverse and vehicleScan(vehicle,motion,clearance,speed,now,nil,true) or nil
        local _, _, gap = scanBumper(vehicle, motion, -motion.fx, -motion.fy, width, length, clearance, speed,scan)
        rear = gap == math.huge and "clear" or ("%.2f"):format(gap)
        reason = gap == math.huge and "reverse" or "rear blocked"
    end
    applyInputs(npc, vehicle, motion, progress, reversingSteer or 0, 0, reason, 0, rear)
    if reason ~= "reverse" then
        progress.reverseAt, progress.stalledAt = nil, nil
        progress.rejoinAt = now
        samples[vehicle] = nil
    end
end

-- Mission cars retry a blocked approach with temporary reversing actions.
-- Keep checking the rear bumper during the action, including against other racers.
function recoverNPCRaceApproach(npc, vehicle, motion, progress, now, dx, dy)
    if not progress.reverseAt then
        if motion.unstable or dx^2+dy^2<1 then
            progress.raceStoppedAt=nil
            return false
        end
        if not progress.raceStoppedAt or (motion.x-progress.raceX)^2+(motion.y-progress.raceY)^2>2^2 then
            progress.raceX,progress.raceY,progress.raceStoppedAt=motion.x,motion.y,now
            return false
        end
        if elapsedSince(now,progress.raceStoppedAt)<1500 then return false end
        local repeated=progress.raceReverseAt and elapsedSince(now,progress.raceReverseAt)<10000
        progress.reverseAt,progress.raceReverseAt,progress.raceStoppedAt=now,now,nil
        progress.rejoinAt=nil
        progress.reverseDuration=repeated and 2500 or 1500
    end
    -- VCS temporary action 2 (004380E0) negates mission steering and
    -- requests half braking/reverse while the normal driving action waits.
    local angle=math.atan2(dx*motion.fy-dy*motion.fx,dx*motion.fx+dy*motion.fy)
    local steer=-math.max(-1,math.min(1,angle/0.5))
    runReverse(npc,vehicle,motion,progress,now,false,steer)
    return true
end

local function speedForAngle(cruise, angle, start, finish, cornerSpeed)
    angle = math.abs(math.atan2(math.sin(angle), math.cos(angle)))
    local fraction = math.max(0, math.min(1, (angle - start) / (finish - start)))
    local minimum=math.min(0.4*cruise,cornerSpeed or cruise)
    return cruise+(minimum-cruise)*fraction
end

local function steeringLock(vehicle, progress)
    if not progress.steeringLock then
        local handling = getVehicleHandling(vehicle)
        progress.steeringLock = handling and handling.steeringLock and math.rad(handling.steeringLock) or 0.5
    end
    return math.max(0.01, progress.steeringLock)
end

local function sirenPathLimit(vehicle,motion,progress,task,action,dx,dy,look)
    local now = getTickCount()
    local previous = progress.sirenProbe
    if previous and previous.start == action[4] and (now-previous.tick)%4294967296 < 100 then return previous.cap end
    local width,length = vehicleExtents(vehicle)
    local speed = math.sqrt(motion.vx^2+motion.vy^2)
    local index = getNPCTrafficPhysicsIndex(task,math.max(1,(progress.sequence or task[2])-task[2]+1),motion)
    local lane = task[5][index]
    local cap = 0
    if lane and not motion.unstable and canPassOnRoute(task,index,motion,dx,dy,look,width,true) then
        local range = math.max(5,speed^2/(2*BRAKING)+speed*0.3+2)
        local source = action[1]
        if isElement(source) then
            -- An emitter catching up from behind is the reason to pull aside.
            -- Retain it in the sweep once alongside or ahead of the civilian.
            local x,y = getElementPosition(source)
            if (x-motion.x)*motion.fx+(y-motion.y)*motion.fy >= -2*length-1 then source=nil end
        end
        local scan = vehicleScan(vehicle,motion,range,speed,now,source,true)
        cap = scanRoute(vehicle,motion,dx,dy,width,length,range,speed,nil,nil,scan)
        if isNPCTrafficSignalClosed(lane[9],task[6]) then
            local remaining=(lane[3]-motion.x)*lane[6]+(lane[4]-motion.y)*lane[7]
            if remaining >= 0 then cap=math.min(cap,stopSpeed(remaining-length,0,speed)) end
        end
    end
    progress.sirenProbe = {start=action[4],tick=now,cap=cap}
    return cap
end

local function applySirenYield(npc, vehicle, motion, progress,task)
    local action = getElementData(vehicle, "npchlc_traffic:sirenYield", false)
    if type(action) ~= "table" then progress.sirenProbe=nil; return false end
    local mode = action[2]
    local moving = motion.forward > 0.5
    if mode == "right" or mode == "left" then
        local fx,fy,target = action[6],action[7],action[8]
        if type(target)~="number" then
            -- An action from a server running the original two-phase controller.
            local steer=(mode=="right" and 0.15 or -0.15)/steeringLock(vehicle,progress)
            setNPCVehicleInputs(npc,action[5] and -steer or steer,moving and -0.001 or 0,false)
        else
            -- Steer out, then countersteer until parallel to the protected path.
            -- Reconstruct both errors from world coordinates on syncer handoff.
            local offset=target-(motion.x*fy-motion.y*fx)
            local heading=math.atan2(motion.fx*fy-motion.fy*fx,motion.fx*fx+motion.fy*fy)
            local side=mode=="right" and 1 or -1
            local desired=math.max(-0.62,math.min(0.62,math.atan2(side*math.max(0,side*offset),math.max(2.5,motion.forward*0.46))))
            local dx=fx*math.cos(desired)+fy*math.sin(desired)
            local dy=fy*math.cos(desired)-fx*math.sin(desired)
            local look=math.max(2.5,math.min(6,math.abs(offset)/math.max(0.1,math.abs(math.sin(desired)))))
            local cap=sirenPathLimit(vehicle,motion,progress,task,action,dx,dy,look)
            local steer=math.max(-1,math.min(1,(desired-heading)/steeringLock(vehicle,progress)))
            local speed=math.min(cap, math.max(5.5,math.min(11,motion.forward)))
            if side*offset <= 0.12 and math.abs(heading)<0.16 then speed=0 end
            applyInputs(npc,vehicle,motion,progress,steer,speed,speed==0 and "obstacle" or "Siren "..mode)
        end
    elseif mode == "wait" then
        setNPCVehicleInputs(npc,0,moving and -0.2 or 0,not moving)
    else
        return false
    end
    progress.reverseAt, progress.rejoinAt, progress.stalledAt, progress.cruiseThrottle = nil, nil, nil, nil
    recordNPCDebugDriving("Siren " .. mode, false)
    return true
end

local function canMoveAbandonedBlocker(car)
    if not isElement(car) or getVehicleOccupant(car,0) then return false end
    for _, occupant in pairs(getVehicleOccupants(car) or {}) do
        if getElementType(occupant) == "player" then return false end
    end
    return true
end

function performTask.driveTrafficPhysics(npc, task, elapsed, progress)
    local vehicle = getPedOccupiedVehicle(npc)
    if isElementFrozen(vehicle) then setNPCVehicleInputs(npc, 0, 0, false) return end
    local motion = getNPCTrafficPhysicsMotion(vehicle)
    if not motion then stopAllNPCActions(npc) return end
    if applySirenYield(npc, vehicle, motion, progress,task) then return end
    local now = getTickCount()
    local x, y, z, fx, fy = motion.x, motion.y, motion.z, motion.fx, motion.fy
    if task.mission and not task.race and not motion.unstable then
        -- An off-road impact can leave a scripted driver pointing into a
        -- building. A short, rear-obstacle-checked reverse frees the nose.
        if not progress.missionMoveAt or (x-progress.missionX)^2+(y-progress.missionY)^2>2^2 then
            progress.missionX,progress.missionY,progress.missionMoveAt=x,y,now
        elseif not progress.reverseAt and elapsedSince(now,progress.missionMoveAt)>8000 then
            progress.reverseAt,progress.reverseDuration,progress.missionMoveAt=now,1200,now
        end
    end
    local start = math.max(1, (progress.sequence or task[2]) - task[2] + 1)
    local abandoned = getElementData(vehicle, "npchlc_traffic:abandonedBlocker", false)
    if not canMoveAbandonedBlocker(abandoned) then abandoned = nil end
    if abandoned and getElementData(vehicle,"npchlc_traffic:abandonedReverse",false) then
        -- The server owns this 400 ms window, including across syncer changes.
        progress.reverseAt, progress.abandonedReverse = now, true
        runReverse(npc, vehicle, motion, progress, now, false)
        progress.reverseAt = nil
        return
    elseif progress.abandonedReverse then
        progress.abandonedReverse, progress.rejoinAt = nil, now
    end
    if progress.reverseAt then
        local lane = task[5][start]
        if task.race and lane then
            -- A commanded reverse naturally has negative forward velocity.
            -- Run its rear-checked action before the forward lane controller
            -- classifies that velocity as sliding or tries to settle it.
            recoverNPCRaceApproach(npc,vehicle,motion,progress,now,lane[3]-x,lane[4]-y)
            return
        end
        local signalClosed = lane and isNPCTrafficSignalClosed(lane[9], task[6])
            and (lane[3] - x) * lane[6] + (lane[4] - y) * lane[7] >= 0
        runReverse(npc, vehicle, motion, progress, now, signalClosed)
        return
    end
    if progress.rejoinAt and motion.forward < -0.1 then
        applyInputs(npc, vehicle, motion, progress, 0, 0, "settling")
        return
    end
    local index = getNPCTrafficPhysicsIndex(task, start, motion)
    local lane = task[5][index]
    local onRoute = lane and isNPCTrafficPhysicsOnRoute(task, index, x, y, z)
    if lane and not motion.unstable and not onRoute then
        local rejoin = findNPCTrafficPhysicsRejoin(task, index, x, y, z, fx, fy)
        if rejoin then index, lane, onRoute = rejoin, task[5][rejoin], true end
    end
    local sequence = task[2] + index - 1
    if progress.sequence ~= sequence then progress.stalledAt = nil end
    progress.sequence = sequence
    progress.usingPreview = index>1 and lane~=nil
    if not lane and task.raceExit and not motion.unstable then
        -- The owner can pass the final road link before the server sees
        -- that sample. Mode 8 hands straight to mode 9 in the same frame.
        local exit=task.raceExit
        if progress.raceDirectExit~=exit then
            progress.raceDirectExit=exit
            progress.raceDirect={"driveRaceToPoint",exit[1],exit[2],task[5][#task[5]][5],exit[3],exit[4],exit[5]}
        end
        performTask.driveRaceToPoint(npc,progress.raceDirect,elapsed,progress)
        return
    end
    if motion.unstable or not lane or not onRoute and not task.race then
        progress.stalledAt = nil
        applyInputs(npc, vehicle, motion, progress, 0, 0, motion.unstable and "sliding" or not lane and "Awaiting route" or "route")
        return
    end

    local dx, dy = lane[3] - x, lane[4] - y
    local distance = math.sqrt(dx * dx + dy * dy)
    local remainingPath=distance
    for i=index+1,#task[5] do
        local a,b=task[5][i-1],task[5][i]
        remainingPath=remainingPath+math.sqrt((a[3]-b[3])^2+(a[4]-b[4])^2)
    end
    local last=task[2]+#task[5]-1
    if remainingPath<math.max(task[3],motion.forward) and (progress.hintedFirst~=task[2] or progress.hintedLast~=last) then
        progress.hintedFirst,progress.hintedLast=task[2],last
        triggerEvent("npc_hlc:onRouteLow",vehicle,task[2],last)
    end
    local forward = math.atan2(fy, fx)
    local direct = distance > 0.01 and math.atan2(dy, dx) - forward or 0
    -- CCarCtrl::SteerAICarWithPhysicsFollowPath projects the steering
    -- point back along the lane tangent. Speed uses the unprojected bearing.
    if distance<=40 then
        dx,dy=dx-.4*distance*lane[6],dy-.4*distance*lane[7]
    end
    recordNPCDebugTarget(npc, x + dx, y + dy, lane[5])
    local length = math.sqrt(dx * dx + dy * dy)
    local routeX, routeY = lane[6], lane[7]
    if length > 0.01 then routeX, routeY = dx / length, dy / length end
    local limit = getElementData(vehicle, "npchlc_traffic:steeringLimit", false)
    if type(limit) ~= "number" or not (limit > 0 and limit <= 1) then limit = 0.5 end
    if motion.vx ^ 2 + motion.vy ^ 2 + motion.vz ^ 2 > (0.45 * 50) ^ 2 then limit = 0.2 end
    if task.race then
        -- Mode 8, style 2 (00438A80). Use the free bearing, the next bend,
        -- and forward speed in PS2 units. The two traffic-light waiting
        -- styles take a separate speed-limit branch in the original.
        if recoverNPCRaceApproach(npc,vehicle,motion,progress,now,dx,dy) then return end
        local cruise=getNPCDriveSpeed(npc)*50
        local avoid,clearSpeed=getNPCPoliceAvoidance(vehicle,nil,dx,dy,progress,false,cruise*50/60,task,index)
        local angle=forward-math.atan2(routeY,routeX)+avoid
        angle=math.atan2(math.sin(angle),math.cos(angle))
        local steer=getNPCRaceSteeringInput(angle,limit,steeringLock(vehicle,progress))
        local requested=speedForAngle(cruise,direct,0.4,1.2)
        requested=math.min(requested,getNPCRaceWindowSpeed(task,index,distance,cruise),
            getNPCRaceSteeringSpeed(cruise,distance,direct))
        local actual=motion.forward*(60/50)
        if clearSpeed then requested=math.min(requested,clearSpeed*(60/50)) end
        local error=requested-actual
        local pedal=error>0 and math.min(1,error*(actual<2 and 0.25 or 0.125)) or math.max(-0.5,error*0.05)
        if progress.raceFollowing and clearSpeed and actual>clearSpeed*1.2 then
            pedal=math.min(pedal,math.max(-1,(clearSpeed*1.2-actual)*.12))
        end
        if requested<0.05 and error<0.03 then pedal=-1 end
        setNPCVehicleInputs(npc,steer,pedal,false)
        return
    end
    local step = math.min(elapsed or 16, 100) * getGameSpeed()
    local multiplier = getNPCTrafficDriveMultiplier(vehicle, lane[8], step)
    progress.cruiseSpeed = task[3] * multiplier
    -- A pursuit cruise request can exceed 40 units/s. At the ambient
    -- 40-percent turn floor that sends even a bike across the far curb.
    local cornerSpeed
    if task[6]==2 and getVehicleSirensOn(vehicle) then
        cornerSpeed=getElementData(vehicle,"npchlc_traffic:originalModel",false)==191 and 3.5 or 4.5
    end
    local speed, reason = speedForAngle(progress.cruiseSpeed,direct,0.4,1.2,cornerSpeed), "cruise"
    if cornerSpeed then
        -- On a short outbound link the waypoint can be nearly straight ahead
        -- while the car is still crossing the junction sideways to that link.
        local headingError=math.atan2(lane[7],lane[6])-forward
        local aligning=speedForAngle(progress.cruiseSpeed,headingError,0.1,1.2,cornerSpeed)
        if aligning<speed then speed,reason=aligning,"bend" end
    end
    local nextLane = task[5][index + 1]
    local bendDistance = distance
    local lastBend = cornerSpeed and #task[5]-1 or math.min(index,#task[5]-1)
    for i=index,lastBend do
        if not cornerSpeed and bendDistance > 40 then break end
        local before, after = task[5][i], task[5][i+1]
        local bend = math.atan2(after[7],after[6]) - math.atan2(before[7],before[6])
        local bendSpeed = speedForAngle(progress.cruiseSpeed,bend,0.1,1.2,cornerSpeed)
        local approachSpeed = math.sqrt(bendSpeed^2 + 2*BRAKING*math.max(0,bendDistance-5))
        if approachSpeed < speed then speed, reason = approachSpeed, "bend" end
        bendDistance = bendDistance + math.sqrt((before[3]-after[3])^2 + (before[4]-after[4])^2)
    end
    local remaining = (lane[3] - x) * lane[6] + (lane[4] - y) * lane[7]
    local signalClosed = remaining >= 0 and isNPCTrafficSignalClosed(lane[9], task[6])
    if signalClosed then
        local signalSpeed = stopSpeed(remaining - 6, 0, motion.forward)
        if signalSpeed < speed then speed, reason = signalSpeed, "signal" end
    end
    local allowAvoid = not signalClosed and (remaining > AVOID_DISTANCE or doesNPCTrafficAvoidCars(task[6]) and nextLane ~= nil)
    if signalClosed and remaining <= 12 then abandoned = nil end
    local obstacle, cause, avoidAngle = trafficLimit(vehicle, motion, routeX, routeY, task, index, allowAvoid or abandoned ~= nil, abandoned)
    if not abandoned and task[6] == 1 and (cause == "following" or cause == "crossing" or cause == "pedestrian") then
        obstacle = (math.min(obstacle, progress.cruiseSpeed) + progress.cruiseSpeed) * 0.5
    end
    if obstacle < speed then speed, reason = obstacle, cause end
    if not nextLane then
        local terminalSpeed=math.sqrt(2*BRAKING*remainingPath)
        if terminalSpeed<speed then speed,reason=terminalSpeed,"Awaiting route" end
    end
    -- Random-created VCS cruise cars are excluded from the short reverse
    -- used by other missions. 0x0042A364 permits a 400 ms reverse after a
    -- thirty-second stall for one fixed seed class. Keep queued cars at red.
    local ambientReverse = getElementData(vehicle, "npchlc_traffic:stuckReverse", false)
    local ps2Cruise = type(ambientReverse) == "number"
    local waiting = reason == "obstacle" or ps2Cruise and reason == "following"
    local sensor = samples[vehicle]
    if not signalClosed and waiting and speed == 0 and ambientReverse ~= 0 and not (ps2Cruise and sensor and sensor.emptyBlocker)
        and motion.vx ^ 2 + motion.vy ^ 2 < (ps2Cruise and 0.9^2 or 0.6^2) then
        if not progress.stalledAt or (x - progress.stalledX) ^ 2 + (y - progress.stalledY) ^ 2 > 0.5 ^ 2 then
            progress.stalledAt, progress.stalledX, progress.stalledY = now, x, y
        elseif elapsedSince(now, progress.stalledAt) >= (ps2Cruise and 30000 or STALL_MS) then
            progress.reverseDuration = ps2Cruise and ambientReverse or REVERSE_MS
            progress.reverseAt = now
            if ps2Cruise then triggerEvent("npc_hlc:onCruiseStuck", vehicle) end
            runReverse(npc, vehicle, motion, progress, now, false)
            return
        end
    else
        progress.stalledAt = nil
    end
    if progress.rejoinAt then
        if elapsedSince(now, progress.rejoinAt) < 2000 then
            if speed > RECOVERY_SPEED then speed, reason = RECOVERY_SPEED, "rejoin" end
        else
            progress.rejoinAt = nil
        end
    end
    local angle = forward - math.atan2(routeY, routeX) - avoidAngle
    angle = math.atan2(math.sin(angle), math.cos(angle))
    local steer = math.max(-1, math.min(1, math.max(-limit, math.min(limit, angle)) / steeringLock(vehicle, progress)))
    applyInputs(npc, vehicle, motion, progress, steer, speed, reason, avoidAngle, nil, step)
end

addCommandHandler("trafficphysicsdebug", function()
    debugging = not debugging
    if not debugging then diagnostics = setmetatable({}, {__mode = "k"}) end
    outputChatBox("Traffic physics debug " .. (debugging and "on" or "off"))
end)

setTimer(function()
    if not debugging then return end
    local x, y, z = getElementPosition(localPlayer)
    local closest, distance
    for vehicle, sample in pairs(diagnostics) do
        if isElement(vehicle) and isElementSyncer(vehicle) then
            local px, py, pz = getElementPosition(vehicle)
            local squared = (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2
            if squared < (distance or 30 ^ 2) then closest, distance = sample, squared end
        end
    end
    if closest then
        outputDebugString(("Traffic physics owner=%s segment=%d lateral=%.2f cruise=%.2f actual=%.2f target=%.2f reason=%s brake=%.2f action=%s avoid=%.0f rear=%s")
            :format(getPlayerName(localPlayer), unpack(closest)))
    end
end, 500, 0)
