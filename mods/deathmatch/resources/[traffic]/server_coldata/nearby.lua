local MAX_CANDIDATES = 32
local CANDIDATE_TYPES = {"vehicle", "ped", "player"}

local function modelBox(model, x, y, z, heading)
    if not bb_x1[model] then return false end
    local angle = math.rad(heading)
    local c, s = math.cos(angle), math.sin(angle)
    local midX, midY = (bb_x1[model] + bb_x2[model]) * 0.5, (bb_y1[model] + bb_y2[model]) * 0.5
    return {
        x = x + midX * c - midY * s, y = y + midX * s + midY * c,
        lower = z + bb_z1[model], upper = z + bb_z2[model],
        width = (bb_x2[model] - bb_x1[model]) * 0.5, length = (bb_y2[model] - bb_y1[model]) * 0.5,
        c = c, s = s,
    }
end

local function separated(a, b, dx, dy)
    local dot = a.c * b.c + a.s * b.s
    local cross = a.c * b.s - a.s * b.c
    local along = math.abs(dx * a.c + dy * a.s)
    local across = math.abs(-dx * a.s + dy * a.c)
    return along >= a.width + math.abs(dot) * b.width + math.abs(cross) * b.length
        or across >= a.length + math.abs(cross) * b.width + math.abs(dot) * b.length
end

local function overlaps(a, b)
    if a.lower >= b.upper or b.lower >= a.upper then return false end
    local dx, dy = b.x - a.x, b.y - a.y
    return not separated(a, b, dx, dy) and not separated(b, a, dx, dy)
end

function hasNearbyModelCollision(actor, x, y, z, heading)
    local model = getElementModel(actor)
    local proposed = modelBox(model, x, y, z, heading)
    if not proposed then return false end

    local px, py, pz = getElementPosition(actor)
    local _, _, previousHeading = getElementRotation(actor)
    local previous = modelBox(model, px, py, pz, previousHeading)
    local interior, dimension = getElementInterior(actor), getElementDimension(actor)
    local checked = 0
    -- Include the largest supported model radius in the broad phase, then use oriented model extents.
    for _, kind in ipairs(CANDIDATE_TYPES) do
        local range = bs_r[model] + (kind == "vehicle" and maxModelRadius or maxPedRadius)
        local candidates = getElementsWithinRange(x, y, z, range, kind, interior, dimension)
        for _, element in ipairs(candidates) do
            local otherModel = getElementModel(element)
            if element ~= actor and bs_r[otherModel] and (kind == "vehicle" or not isPedInVehicle(element)) then
                local ex, ey, ez = getElementPosition(element)
                local radius = bs_r[model] + bs_r[otherModel]
                if math.abs(x - ex) <= radius and math.abs(y - ey) <= radius then
                    checked = checked + 1
                    if checked > MAX_CANDIDATES then return true end
                    local _, _, rotation = getElementRotation(element)
                    local obstacle = modelBox(otherModel, ex, ey, ez, rotation)
                    if overlaps(proposed, obstacle) and not overlaps(previous, obstacle) then return true end
                end
            end
        end
    end
    return false
end
