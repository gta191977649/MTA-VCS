-- Task 729 chooses a vehicle pursuit. The progress, reachability and native
-- exit gates below are the multiplayer adapter for a driver circling a target.
TrafficVehiclePursuit = {}
TrafficVehiclePursuit.__index = TrafficVehiclePursuit

local function age(now, before)
    return (now - before) % 4294967296
end

local function resetProgress(self, distance, now)
    self.best, self.improvedAt, self.misses, self.passDistance = distance, now, 0, nil
end

function TrafficVehiclePursuit.new(target, now)
    local actor = getPedOccupiedVehicle(target) or target
    local x, y, z = getElementPosition(actor)
    return setmetatable({target = target, actor = actor, anchorX = x, anchorY = y, anchorZ = z,
        stillSince = now, improvedAt = now, misses = 0, phase = "chase"}, TrafficVehiclePursuit)
end

function TrafficVehiclePursuit:reroute(distance, now)
    if self.replanned then return "end" end
    self.replanned, self.phase, self.routeAt = true, "route", now
    resetProgress(self, distance, now)
    return "route"
end

function TrafficVehiclePursuit:update(vehicle, owner, now)
    local actor = getPedOccupiedVehicle(self.target) or self.target
    local tx, ty, tz = getElementPosition(actor)
    local x, y, z = getElementPosition(vehicle)
    local dx, dy = tx - x, ty - y
    local distance = math.sqrt(dx*dx + dy*dy + (tz - z)^2)
    local exitDistance = self.committed and 14 or 10
    local vx, vy, vz = getElementVelocity(actor)
    if self.committed and actor == self.target then
        self.actor, self.anchorX, self.anchorY, self.anchorZ = actor, tx, ty, tz
        if self.phase ~= "brake" and self.phase ~= "exit" then
            self.phase, self.brakeAt = "brake", now
            return "brake"
        end
        if age(now, self.brakeAt) >= 20000 then return "end" end
        if self.requestedAt and age(now, self.requestedAt) < 1200 then return end
        local xSpeed, ySpeed, zSpeed = getElementVelocity(vehicle)
        if xSpeed^2 + ySpeed^2 + zSpeed^2 <= 0.05^2 and TrafficWorld.pursuitExit(owner, vehicle, self.target, "foot", true) then
            self.phase, self.requestedAt = "exit", now
            return "exit"
        end
        return
    end
    local moved = actor ~= self.actor or (tx-self.anchorX)^2 + (ty-self.anchorY)^2 + (tz-self.anchorZ)^2 > 1
        or vx*vx + vy*vy + vz*vz > 0.02^2
    if moved then
        self.actor, self.anchorX, self.anchorY, self.anchorZ = actor, tx, ty, tz
        self.stillSince = now
        self.blockedAt = nil
        if self.phase ~= "chase" then
            self.phase, self.probeAt = "chase", nil
            resetProgress(self, distance, now)
            return "chase"
        end
    end
    if not self.best or distance < self.best - 1 then
        self.best, self.improvedAt = distance, now
    end
    if self.phase == "route" then
        if age(now, self.routeAt) >= 8000 then return "end" end
        if age(now, self.routeAt) < 1500 then return end
    end
    if self.phase == "chase" then
        local matrix = getElementMatrix(vehicle)
        local facing = matrix and (dx * matrix[2][1] + dy * matrix[2][2]) / math.max(distance, 0.01) or 0
        local a, b = getElementVelocity(vehicle)
        if distance <= 12 and facing > 0.6 and a*a + b*b > 0.02^2 then
            self.passDistance = math.min(self.passDistance or distance, distance)
        elseif self.passDistance and facing < 0 and distance > self.passDistance + 1 then
            self.misses, self.passDistance = self.misses + 1, nil
        end
        local closeRetaliation = self.committed and distance <= exitDistance and age(now, self.stillSince) >= 300
        if not closeRetaliation and self.misses < 2 and age(now, self.improvedAt) < 4000 then return end
    end

    local still = age(now, self.stillSince) >= (self.committed and 300 or 2000)
    if distance > exitDistance or not still then
        if self.phase == "brake" or self.phase == "exit" then
            self.phase, self.probeAt = "chase", nil
            resetProgress(self, distance, now)
            return "chase"
        end
        if age(now, self.improvedAt) >= 4000 then
            local a, b = getElementVelocity(vehicle)
            if not still and a*a + b*b > 0.05^2 then return end
            return self:reroute(distance, now)
        end
        return
    end
    -- Obtain a fresh probe after braking and again on each exit retry. The
    -- request is bound to the current vehicle syncer, target and stage.
    if self.phase == "exit" then
        if age(now, self.brakeAt) >= 8000 then return self:reroute(distance, now) end
        if age(now, self.requestedAt) < 1200 then return end
    end
    local cx, cy, cz = getElementVelocity(vehicle)
    if self.phase == "brake" and cx*cx + cy*cy + cz*cz > 0.05^2 then
        if age(now, self.brakeAt) >= 4000 then return self:reroute(distance, now) end
        return
    end
    if self.owner ~= owner then self.owner, self.probeAt = owner, nil end
    self.probeAt = self.probeAt or now
    local safe = TrafficWorld.pursuitExit(owner, vehicle, self.target, self.phase, false, self.committed)
    if safe == nil and age(now, self.probeAt) < 1200 then return end
    self.probeAt = nil
    if not safe then
        if self.committed and distance <= exitDistance and still then
            self.blockedAt = self.blockedAt or now
            if age(now, self.blockedAt) < 4000 then return end
        end
        if self.phase == "route" and age(now, self.improvedAt) < 4000 then return end
        return self:reroute(distance, now)
    end
    self.blockedAt = nil
    if self.phase ~= "brake" and self.phase ~= "exit" then
        self.phase, self.brakeAt = "brake", now
        return "brake"
    end
    if cx*cx + cy*cy + cz*cz > 0.05^2 then return end
    self.phase, self.requestedAt = "exit", now
    return "exit"
end
