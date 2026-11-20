CBoat = CVehicle.derive("CBoat", CVehicle)
CBoat.nativeType = "Boat"

CBoat.baseModels = {[214]=453, [215]=452, [219]=430, [225]=595, [247]=473, [248]=484,
    [249]=484, [250]=454, [257]=446, [258]=493, [264]=446}
for originalId in pairs(CBoat.baseModels) do
    CVehicle.register(originalId, CBoat)
end

-- 0019F728. Track the effective PS2 pad values for subtype-specific forces
-- and moving components. The native boat applies its own equivalent thrust.
function CBoat:ProcessControlInputs(accelerate, reverse, steer, handbrake, step)
    local brake = (self.brake or 0) + (reverse-(self.brake or 0))*(1-0.9^step)
    self.brake = (handbrake or brake<0.05) and 0 or brake
    self.throttle = self.brake>0 and -0.3*self.brake or accelerate
    if accelerate>0 and reverse>0 and not handbrake then
        self.throttle, self.brake = 0, 0
    end
    self.steer = (self.steer or 0) + (steer-(self.steer or 0))*(1-0.8^step)
end

function CBoat.SteerTraffic(vehicle, dx, dy, speed, vz, elapsed)
    if speed > 0.1 then
        local pitch, roll, heading = getElementRotation(vehicle, "ZXY")
        local target = math.deg(math.atan2(-dx, dy))
        local error = (target - heading + 180) % 360 - 180
        local limit = math.min(elapsed or 20, 150) * 0.09
        setElementRotation(vehicle, pitch, roll, heading + math.max(-limit, math.min(limit, error)), "ZXY")
    end
    setElementVelocity(vehicle, dx*speed/50, dy*speed/50, vz)
end

-- Keep the existing controller export usable by older rail clients.
function steerBoatTraffic(vehicle, dx, dy, tangentX, tangentY, futureX, futureY, look, speed, vz, elapsed)
    local class = CVehicle.resolve(vehicle) or CBoat
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
        or class.nativeType ~= "Boat" or getVehicleType(vehicle) ~= "Boat" then return false end
    local driver = getVehicleOccupant(vehicle, 0)
    if driver and getElementType(driver) == "player" then return false end
    class.SteerTraffic(vehicle, dx, dy, speed, vz, elapsed)
    return true
end

-- 00434F20 clips each moving corner against both slabs of the other hull.
local function clip(position, velocity, low, high, enter, leave)
    if math.abs(velocity) < 0.000001 then
        if position < low or position > high then return 1, 0 end
        return enter, leave
    end
    local a, b = (low - position) / velocity, (high - position) / velocity
    return math.max(enter, math.min(a, b)), math.min(leave, math.max(a, b))
end

local function hull(vehicle)
    local matrix = getElementMatrix(vehicle)
    local _, stern, _, halfWidth, bow = getElementBoundingBox(vehicle)
    if not matrix or not halfWidth then return end
    local fx, fy = matrix[2][1], matrix[2][2]
    local length = math.sqrt(fx * fx + fy * fy)
    if length < 0.001 then return end
    return {x = matrix[4][1], y = matrix[4][2], fx = fx / length, fy = fy / length,
        halfWidth = halfWidth, stern = stern, bow = bow}
end

local function sweep(box, other, vx, vy)
    local best = 1
    local sideSpeed = vx * box.fy - vy * box.fx
    local foreSpeed = vx * box.fx + vy * box.fy
    for corner = 0, 3 do
        local side = corner % 2 == 0 and -other.halfWidth or other.halfWidth
        local fore = corner < 2 and other.bow or other.stern
        local x = other.x - box.x + fore * other.fx + side * other.fy
        local y = other.y - box.y + fore * other.fy - side * other.fx
        local enter, leave = clip(x * box.fy - y * box.fx, sideSpeed, -box.halfWidth, box.halfWidth, 0, 1)
        enter, leave = clip(x * box.fx + y * box.fy, foreSpeed, box.stern, box.bow, enter, leave)
        if enter < leave then best = math.min(best, enter) end
    end
    return best
end

function getBoatTrafficSpeedLimit(vehicle, cruise)
    local own = hull(vehicle)
    if not own then return cruise end
    local x, y, z = getElementPosition(vehicle)
    local limit = cruise
    -- The enclosing radius covers the original +/-16 XY square and 5 Z.
    local nearby = getElementsWithinRange(x, y, z, 24, "vehicle", getElementInterior(vehicle), getElementDimension(vehicle))
    for _, other in ipairs(nearby) do
        if other ~= vehicle and isElementStreamedIn(other) and getElementCollisionsEnabled(other) then
            local ox, oy, oz = getElementPosition(other)
            local rx, ry = ox - x, oy - y
            if math.abs(rx) < 16 and math.abs(ry) < 16 and math.abs(oz - z) < 5 and rx * own.fx + ry * own.fy >= 0 then
                local target = hull(other)
                if target then
                    local vx, vy = getElementVelocity(other)
                    -- Convert both native velocities to displacements over 60 steps.
                    vx = (vx - own.fx * cruise / 50) * 60
                    vy = (vy - own.fy * cruise / 50) * 60
                    local contact = math.min(sweep(own, target, vx, vy), sweep(target, own, -vx, -vy))
                    limit = math.min(limit, cruise * math.max(0, (contact - 0.2) / 1.3))
                end
            end
        end
    end
    return limit
end
