TrafficVehicleCollision = {}

-- The PS2 Automobile::VehicleDamage branch at 0x0013771C tests calculated
-- collision damage before the separate health multiplier is applied.
function TrafficVehicleCollision.damage(impulse, coefficient, kind)
    -- CBike::VehicleDamage at 0x00336590 omits the automobile's 0.6 factor.
    return math.max(0, impulse - 25) * coefficient * (kind == "Bike" and 1 or 0.6)
end

local function speedSquared(x, y, z)
    return x*x + y*y + z*z
end

function TrafficVehicleCollision.chooseResponse(profile, roll)
    local choices = profile and TrafficCrashDecisions[profile.name]
    if not choices then return 200 end
    local total = 0
    for _, item in ipairs(choices) do total = total + item[2] end
    local selection = roll * total
    for _, item in ipairs(choices) do
        if selection < item[2] then return item[1] end
        selection = selection - item[2]
    end
    return 200
end

local function projectedSpeed(x, y, z, nx, ny, nz)
    return x * nx + y * ny + z * nz
end

-- The contact normal points towards the traffic vehicle. Distinguish a player
-- driving into the NPC from an NPC driving into the player's stationary car.
function TrafficVehicleCollision.struckByDriver(state, other, observer, now, nx, ny, nz)
    local x, y, z = getElementVelocity(other)
    local approach = projectedSpeed(x, y, z, nx, ny, nz)
    if observer and observer.impactVehicle == other then
        for _, sample in ipairs(observer.impactSamples) do
            if (now - sample.tick) % 4294967296 <= 180 then
                approach = math.max(approach, projectedSpeed(sample.x, sample.y, sample.z, nx, ny, nz))
            end
        end
    end
    x, y, z = getElementVelocity(state.vehicle)
    local before = state.railMotion
    if before and (now - before.tick) % 4294967296 <= 180 then x, y, z = before.vx, before.vy, before.vz end
    return approach > 0 and approach >= math.abs(projectedSpeed(x, y, z, nx, ny, nz))
end

-- 0x00136FA0 uses the collision source's driver and both 3D speeds.
local function checkLawEnforcer(state, other, driver, now, observer)
    if not state.lawEnforcer or getElementType(driver) ~= "player"
        or getPlayerWantedLevel(driver) >= 1 then return end
    local otherSpeed = speedSquared(getElementVelocity(other))
    if observer and observer.impactVehicle == other then
        for _, sample in ipairs(observer.impactSamples) do
            if (now - sample.tick) % 4294967296 <= 180 then
                otherSpeed = math.max(otherSpeed, speedSquared(sample.x, sample.y, sample.z))
            end
        end
    end
    local ownSpeed = speedSquared(getElementVelocity(state.vehicle))
    local sample = state.railMotion
    if sample and (now - sample.tick) % 4294967296 <= 180 then
        ownSpeed = speedSquared(sample.vx, sample.vy, sample.vz)
    end
    if otherSpeed > 0.1^2 and otherSpeed >= ownSpeed then
        setPlayerWanted(driver, 1, "policeCollision")
    end
end

function TrafficVehicleCollision.driverReaction(state, other, impulse, now, observer, nx, ny, nz)
    local driver, kind = getVehicleOccupant(other, 0), getVehicleType(state.vehicle)
    if impulse <= 25 or kind ~= "Automobile" and kind ~= "Bike" or isVehicleBlown(state.vehicle)
        or getVehicleOccupant(state.vehicle, 0) ~= state.driver
        or not driver or isPedDead(state.driver) then return end
    if kind == "Automobile" then checkLawEnforcer(state, other, driver, now, observer) end
    local coefficient = TrafficCollisionHandling[state.originalVehicle]
    if not coefficient then
        -- User-supplied MTA graphs can use native model IDs.
        local handling = getVehicleHandling(state.vehicle)
        coefficient = handling.collisionDamageMultiplier * 2000 / handling.mass
    end
    if TrafficVehicleCollision.damage(impulse, coefficient, kind) <= 5 then return end
    -- The police bike checks its computed damage before this branch.
    if kind == "Bike" then checkLawEnforcer(state, other, driver, now, observer) end
    local sameImpact = state.crashOther == other and (now - state.crashAt) % 4294967296 < 600
    state.crashOther, state.crashAt = other, now
    if sameImpact then return end
    PedVoice.emit(state.driver, "crash")
    if not state.lawEnforcer and not state.panicDriving and not state.pursuit
        and getElementType(driver) == "player" and TrafficVehicleCollision.struckByDriver(state, other, observer, now, nx, ny, nz) then
        -- Keep the native damage and contact in either network arrival order.
        state.crashDecision = {at = now, target = driver, collider = other}
    end
    return true
end
