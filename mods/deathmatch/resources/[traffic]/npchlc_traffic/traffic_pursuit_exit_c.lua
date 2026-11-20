-- Probe the actual streamed terrain from the driver's door to the target.
-- Each strip needs floor support, headroom and an unobstructed walking line.
local function floorAt(x, y, z)
    local hit, _, _, floor, _, _, _, nz = processLineOfSight(x,y,z+0.9,x,y,z-2.3,true,false,false,true,false)
    if not hit or not nz or nz < 0.65 then return end
    local water = getWaterLevel(x, y, floor, true)
    if water and water > floor + 0.05 then return end
    if isLineOfSightClear(x,y,floor+0.2,x,y,floor+1.75,true,false,false,true,false) then return floor end
end

local function walkStrip(sx, sy, ground, tx, ty)
    local steps = math.max(1, math.ceil(math.sqrt((tx-sx)^2 + (ty-sy)^2) / 1.25))
    local lastX, lastY = sx, sy
    for i = 1, steps do
        local x, y = sx+(tx-sx)*i/steps, sy+(ty-sy)*i/steps
        local nextGround = floorAt(x, y, ground+0.3)
        if not nextGround or math.abs(nextGround-ground) > 0.65
            or not isLineOfSightClear(lastX,lastY,ground+0.75,x,y,nextGround+0.75,true,true,false,true,false) then return end
        lastX, lastY, ground = x, y, nextGround
    end
    return ground
end

local function hasWheelContact(vehicle)
    for wheel = 0, 3 do
        if isVehicleWheelOnGround(vehicle, wheel) then return true end
    end
    return false
end

function canTrafficPursuerExit(car, target)
    if not isElement(car) or not isElement(target) or not isElementStreamedIn(car)
        or not isElementStreamedIn(target) or isElementInWater(car) or isElementInWater(target)
        or not hasWheelContact(car) then return false end
    local actor = getPedOccupiedVehicle(target) or target
    if actor ~= target and (not isElementStreamedIn(actor) or not hasWheelContact(actor))
        or actor == target and not isPedOnGround(target) then return false end
    local m = getElementMatrix(car)
    local xmin, ymin, _, _, ymax = getElementBoundingBox(car)
    if not m or not xmin or m[3][3] < 0.8 then return false end
    local cx, cy, cz = unpack(m[4])
    local side, along = xmin - 0.7, (ymax-ymin)*0.1
    local sx, sy = cx + side*m[1][1]+along*m[2][1], cy + side*m[1][2]+along*m[2][2]
    local tx, ty, tz = getElementPosition(actor)
    if (cx-tx)^2 + (cy-ty)^2 + (cz-tz)^2 > 10^2 or math.abs(cz-tz) > 2 then return false end
    local ground = floorAt(sx, sy, cz)
    if not ground or not isLineOfSightClear(cx,cy,cz+0.3,sx,sy,ground+0.8,true,true,false,true,false,false,false,car) then
        return false
    end
    if actor ~= target then
        -- Stop outside the occupied vehicle, on the side facing the pursuer.
        local v = getElementMatrix(actor)
        local a, b, _, c, d = getElementBoundingBox(actor)
        if not v or not a then return false end
        local dx, dy = sx-tx, sy-ty
        local u, w = dx*v[1][1]+dy*v[1][2], dx*v[2][1]+dy*v[2][2]
        local scale = math.max(u/(u >= 0 and c+0.5 or a-0.5), w/(w >= 0 and d+0.5 or b-0.5))
        if scale > 1 then tx, ty = tx + dx/scale, ty + dy/scale end
    end
    local finish = walkStrip(sx, sy, ground, tx, ty)
    if finish and math.abs(finish-tz) <= 1.8 then return true end
    -- A parked car can lie between the driver's door and the target.
    for _, alongEnd in ipairs({ymax+0.9, ymin-0.9}) do
        local bx = cx + side*m[1][1] + alongEnd*m[2][1]
        local by = cy + side*m[1][2] + alongEnd*m[2][2]
        local corner = walkStrip(sx, sy, ground, bx, by)
        if corner then
            local ex, ey = bx - 2*side*m[1][1], by - 2*side*m[1][2]
            local endGround = walkStrip(bx, by, corner, ex, ey)
            finish = endGround and walkStrip(ex, ey, endGround, tx, ty)
            if finish and math.abs(finish-tz) <= 1.8 then return true end
        end
    end
    return false
end
