TrafficPoliceFlight = {}
TrafficPoliceFlight.ropeLifetimeMs = 255 * (1000 / 30)
TrafficPoliceFlight.ropeSpan = 31 * (20 / 32)
TrafficPoliceFlight.ropeProgressPerMs = 0.003 / 20

local function clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function angleDifference(target, current)
    return (target - current + math.pi) % (2 * math.pi) - math.pi
end

-- SLUS_215.90 0x002EA060 and 0x00196778. Nil terrain means the vertical ray
-- executed and missed. An unavailable terrain sample must be handled by the caller.
function TrafficPoliceFlight.spawnPoint(route, x, y, angleByte)
    local angle = angleByte * route.spawnAngleStep
    local dx, dy = math.cos(angle) * route.spawnRadius, math.sin(angle) * route.spawnRadius
    local bounds = route.spawnBounds
    if x + dx < bounds.minX or x + dx > bounds.maxX or y + dy < bounds.minY or y + dy > bounds.maxY then
        return x - dx, y - dy
    end
    return x + dx, y + dy
end

function TrafficPoliceFlight.spawnAltitude(route, targetZ, terrainZ)
    return math.max(targetZ + route.heightAboveTarget, (terrainZ or 20) + route.heightAboveTerrain)
end

-- Missions 0x1B and 0x1E in 0x00438420 dispatch to 0x0043C968 and 0x0043D8F8.
function TrafficPoliceFlight.intent(x, y, targetX, targetY, targetZ, airborneVehicle, retiring)
    local dx, dy = targetX - x, targetY - y
    local heading = math.atan2(dy, dx)
    if retiring then return heading + math.pi, 1000, 100 end
    local distance = math.sqrt(dx * dx + dy * dy)
    local altitude = airborneVehicle and targetZ + 3 or math.max(9, targetZ)
    if distance > 50 then altitude = math.max(25, altitude) end
    return heading, distance, altitude
end

-- 0x0043CB10, from the post-ray control calculation at 0x0043D318 onward.
-- Velocity uses original engine units; the caller supplies the results of the
-- original 500 ms obstruction checks, with lateral ±0.5 when obstructed.
function TrafficPoliceFlight.controls(state, heading, distance, clearanceAltitude, randomNibble, retiring, lateral)
    local delta = angleDifference(heading, state.heading)
    local altitudeError = clearanceAltitude - (state.z + state.vz * 100)
    local rawCollective = altitudeError * (altitudeError > 0 and 0.2 or 0.5) + (randomNibble - 7) * 0.002
    local pitch = state.previousPitch
    if distance > 60 or retiring then
        pitch = -0.8
    else
        local dx = state.x + state.vx * 50 - state.targetX
        local dy = state.y + state.vy * 50 - state.targetY
        local difference = math.sqrt(dx * dx + dy * dy) - 10
        if difference >= 0 then pitch = difference * -0.8 / 20 end
    end
    if pitch < 0 then
        pitch = pitch * math.max(0, 1 - math.abs(delta) * 2.1220658)
        if math.abs(delta) > math.pi * 0.5 and state.forwardSpeed > 0 then pitch = 0.3 end
    end
    pitch = pitch * (1 - clamp(rawCollective - 0.5, 0, 1))
    if pitch < 0 then
        pitch = math.max(pitch, -clamp((70 - state.forwardSpeed * 60) * 0.1, 0, 1))
    end
    if lateral ~= 0 then pitch = state.horizontalForwardSpeed * 2 end
    return clamp(-delta * 2, -1, 1), clamp(pitch, -1, 1), lateral, clamp(rawCollective, -0.3, 1)
end

local firingDelay = {[3] = 10000, [4] = 5000, [5] = 3500, [6] = 2000}
function TrafficPoliceFlight.acquisitionDelay(level, occupied)
    return occupied and 5000 or firingDelay[level] or 999999
end

-- The beam interpolates between older one-second prediction samples.
function TrafficPoliceFlight.track(state, target, x, y, vx, vy, now)
    if not state or state.target ~= target then
        state = {target=target, samples={}, at=now, x=x, y=y}
    end
    local elapsed = (now-state.at)%4294967296
    if elapsed >= 1000 then
        table.insert(state.samples,1,{x+vx*100, y+vy*100})
        state.samples[7] = nil
        state.at, elapsed = now, 0
    end
    local a,b = state.samples[2],state.samples[3]
    if a and b then
        local t = elapsed/1000
        state.x,state.y = b[1]+(a[1]-b[1])*t,b[2]+(a[2]-b[2])*t
    end
    return state
end

local boatCruise = {[0] = 8, 10, 15, 20, 25, 30, 40}
function TrafficPoliceFlight.boatPaused(state, targetKind, now)
    -- 00428C48 sets temporary maneuver 1 against a pedestrian or land vehicle.
    if targetKind ~= "Boat" and targetKind ~= "Plane" and targetKind ~= "Helicopter" then
        state.brakedAt = now
    end
    return state.brakedAt and (now-state.brakedAt)%4294967296 <= 1000
end

function TrafficPoliceFlight.boatIntent(level, x, y, z, tx, ty, tz, tvx, tvy, heading, speed)
    local dx, dy, dz = tx - x, ty - y, tz - z
    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
    local lead = 60 * math.min(2, distance * 0.05)
    local bearing = math.atan2(dy + tvy * lead, dx + tvx * lead)
    local error = angleDifference(bearing, heading)
    local cruise = boatCruise[level] or 8
    local deficit = cruise - speed * 60
    local throttle = deficit > 0 and math.min(1, 4 * deficit / cruise) or deficit < -5 and -0.2 or -0.1
    return bearing, throttle, distance < 40 and error < 0.15
end
