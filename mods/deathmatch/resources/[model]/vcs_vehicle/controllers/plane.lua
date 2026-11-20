CPlane = CVehicle.derive("CPlane", CAutomobile)
CPlane.nativeType = "Plane"
CPlane.baseModel = 577
CVehicle.register(280, CPlane)

local function finite(value)
    return type(value) == "number" and math.abs(value) < math.huge
end

function CPlane.IsValidRoute(route)
    if type(route) ~= "table" or route.kind ~= "fixedWing" or not finite(route.instances)
        or route.instances % 1 ~= 0 or route.instances < 1 or route.instances > 32
        or not finite(route.phaseStepMs) or not finite(route.clockPeriodMs) or route.clockPeriodMs <= 0
        or not finite(route.clockDuration) or route.clockDuration <= 0 or not finite(route.length)
        or not finite(route.takeoffDistance) or not finite(route.landingDistance)
        or type(route.points) ~= "table" or #route.points < 2
        or type(route.motionSegments) ~= "table" or #route.motionSegments == 0
        or type(route.motionEnd) ~= "table" or route.motionEnd.kind ~= 0
        or not finite(route.motionEnd.distance) then return false end
    local previous = -1
    for _, point in ipairs(route.points) do
        if type(point) ~= "table" or not finite(point.x) or not finite(point.y) or not finite(point.z)
            or not finite(point.distance) or point.distance <= previous or point.distance >= route.length
            or not finite(point.flags) then return false end
        previous = point.distance
    end
    previous = 0
    for _, segment in ipairs(route.motionSegments) do
        if type(segment) ~= "table" or (segment.kind ~= 1 and segment.kind ~= 2)
            or segment.start ~= previous or not finite(segment["end"]) or segment["end"] <= previous
            or not finite(segment.distance) or not finite(segment.velocity)
            or not finite(segment.acceleration) then return false end
        previous = segment["end"]
    end
    return route.points[1].distance == 0 and previous == route.clockDuration
end

function CPlane.ApplyPose(element, pose)
    return setElementMatrix(element, {
        {pose.rx, pose.ry, pose.rz, 0},
        {pose.fx, pose.fy, pose.fz, 0},
        {pose.ux, pose.uy, pose.uz, 0},
        {pose.x, pose.y, pose.z, 1},
    })
end

local function samplePoint(route, distance)
    local points = route.points
    local low, high = 2, #points + 1
    while low < high do
        local middle = math.floor((low + high) * 0.5)
        if distance <= points[middle].distance then
            high = middle
        else
            low = middle + 1
        end
    end
    local from, to = points[low - 1], points[low] or points[1]
    local finish = points[low] and to.distance or route.length
    local t = (distance - from.distance) / (finish - from.distance)
    local u = 1 - t
    return u * from.x + t * to.x, u * from.y + t * to.y, u * from.z + t * to.z,
        from.flags ~= 0 and to.flags ~= 0
end

local function normalize(x, y, z)
    local length = math.sqrt(x * x + y * y + z * z)
    if length <= 0 then return 1, 0, 0 end
    return x / length, y / length, z / length
end

local function pitchBoost(route, distance)
    local takeoff, landing = distance - route.takeoffDistance, distance - route.landingDistance
    if landing > -200 and landing <= 0 then return 1 + landing / 200 end
    if landing > 0 and landing < 70 then return 1 - landing / 70 end
    if takeoff > -70 and takeoff <= 0 then return 1 + takeoff / 70 end
    if takeoff > 0 and takeoff < 100 then return 1 - takeoff / 100 end
    return 0
end

local function motionAt(route, clockMs, slot)
    -- SLUS_215.90 0x0022D1F8 uses the low 19 bits of the shifted clock.
    local clockFactor = route.clockDuration / route.clockPeriodMs
    local phase = (math.floor(clockMs) + slot * route.phaseStepMs) % route.clockPeriodMs * clockFactor
    local segment = route.motionEnd
    for _, candidate in ipairs(route.motionSegments) do
        if phase <= candidate["end"] then
            segment = candidate
            break
        end
    end
    if segment.kind == 0 then return segment.distance, 0 end
    local dt = phase - segment.start
    local acceleration = segment.kind == 2 and segment.acceleration or 0
    return segment.distance + dt * (segment.velocity + dt * acceleration),
        (segment.velocity + 2 * dt * acceleration) * clockFactor * 1000
end

function CPlane.SampleFlight(route, clockMs, slot)
    if not route or route.kind ~= "fixedWing"
        or type(clockMs) ~= "number" or not (clockMs >= 0 and clockMs < math.huge)
        or type(slot) ~= "number" or slot < 0 or slot >= route.instances or slot % 1 ~= 0 then return false end

    -- SLUS_215.90 0x0022D418 constructs the vehicle matrix from three path samples.
    local distance, speed = motionAt(route, clockMs, slot)
    local behind = (distance - 30) % route.length
    local ahead, lead = (behind + 60) % route.length, (behind + 120) % route.length
    local bx, by, bz, ground = samplePoint(route, behind)
    local ax, ay, az = samplePoint(route, ahead)
    local lx, ly, lz = samplePoint(route, lead)
    local fx, fy, fz = normalize(ax - bx, ay - by, az - bz)
    local boost = pitchBoost(route, behind + 30)
    if boost ~= 0 then fx, fy, fz = normalize(fx, fy, fz + boost * 0.4) end

    local lx, ly = normalize(lx - bx, ly - by, lz - bz)
    local bank = ground and 0 or (fx * ly - fy * lx) * 3
    local rx, ry, rz = normalize(fy, -fx, bank)
    return {
        x = (bx + ax) * 0.5, y = (by + ay) * 0.5, z = (bz + az) * 0.5 + 4.3,
        aheadX = ax, aheadY = ay,
        fx = fx, fy = fy, fz = fz, rx = rx, ry = ry, rz = rz,
        ux = ry * fz - rz * fy, uy = rz * fx - rx * fz, uz = rx * fy - ry * fx,
        routeDistance = distance, speed = speed, groundSegment = ground,
    }
end
