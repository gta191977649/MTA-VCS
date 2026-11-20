-- SLUS 003BB408 / 003BB450 implement two different save filters.
PedObjectives = {}
PedObjectives.__index = PedObjectives
local temporary = {[0x10]=true,[0x11]=true,[0x12]=true,[0x1D]=true,[0x26]=true}
local excluded = {}
for _, id in ipairs({3,8,9,10,11,12,13,14,15,16,17,18,24,25,39,40,43,44,45,49,53}) do excluded[id] = true end

function PedObjectives.new()
    return setmetatable({revision = 0, body = 1}, PedObjectives)
end

function PedObjectives:request(job)
    local old, nextId = self.current, job.id
    if self.body == 0x20 or self.body == 0x39 or self.body == 0x3A then return false end
    if self.saved and self.saved.id == nextId then return false end
    if old and old.id == nextId and old.target == job.target and old.origin == job.origin then return false end
    if old and old.id ~= nextId then
        if temporary[old.id] and not temporary[nextId] then
            self.saved = job
            self.revision = self.revision + 1
            return true
        end
        local save = not excluded[old.id]
        if temporary[nextId] then
            save = nextId ~= 0x11 and nextId ~= 0x12 or save or old.id == 9 or old.id == 15 or old.id == 16
        end
        if save then self.saved = old end
    end
    self.current = job
    self.revision = self.revision + 1
    return true
end

function PedObjectives:complete()
    if not self.current then return end
    if self.current.id == 7 then
        local car = self.current.vehicle
        self.current = nil
        self.revision = self.revision + 1
        if isElement(car) then self:request({id=0x10,order="exitVehicle",vehicle=car}) end
        return self.current
    end
    self.current, self.saved = self.saved, nil
    self.revision = self.revision + 1
    return self.current
end

function PedObjectives:clear()
    self.current, self.saved = nil, nil
    self.revision = self.revision + 1
end

function PedObjectives.flightExpired(event, now, duration, horizontalSquared)
    if duration == 0 or (now - event.lastSeen) % 4294967296 <= duration then return false end
    if not event.origin and horizontalSquared < 900 then
        event.lastSeen, event.duration = now, 5000
        return false
    end
    return true
end
