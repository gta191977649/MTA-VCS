local bursts = {}
local smoke
local particleLifetime = 4000
local drawDistanceSquared = 10000

local function nearestWall(bay, cameraX, cameraY)
    local ax, ay, bx, by, cx, cy = unpack(bay)
    local ux, uy, vx, vy = bx - ax, by - ay, cx - ax, cy - ay
    local walls = {
        {ax, ay, ux, uy, vx, vy}, {cx, cy, ux, uy, -vx, -vy},
        {ax, ay, vx, vy, ux, uy}, {bx, by, vx, vy, -ux, -uy},
    }
    local nearest, distance = nil, math.huge
    for _, wall in ipairs(walls) do
        local dx, dy = cameraX - wall[1] - wall[3] / 2, cameraY - wall[2] - wall[4] / 2
        local squared = dx * dx + dy * dy
        if squared < distance then nearest, distance = wall, squared end
    end
    return nearest
end

addEvent("nspray:sprayEffect", true)
addEventHandler("nspray:sprayEffect", resourceRoot, function(driver, bay, floor, interior, dimension, paint)
    -- SLUS-21590 0x41EE14 uses front-end event 0x41 (SFX0 sample 209).
    if driver == localPlayer then playSound("effects/spray.wav") end
    if getElementInterior(localPlayer) ~= interior or getElementDimension(localPlayer) ~= dimension then return end

    local cameraX, cameraY, cameraZ = getCameraMatrix()
    local centerX, centerY = (bay[3] + bay[5]) / 2, (bay[4] + bay[6]) / 2
    if (cameraX - centerX)^2 + (cameraY - centerY)^2 + (cameraZ - floor)^2 > drawDistanceSquared then return end
    smoke = smoke or dxCreateTexture("effects/smoke.png", "argb", true, "clamp")
    if not smoke then return end

    -- The original burst places GARAGEPAINT_SPRAY particles across the bay from the camera-facing side.
    local x, y, alongX, alongY, inX, inY = unpack(nearestWall(bay, cameraX, cameraY))
    local depth = math.sqrt(inX * inX + inY * inY)
    local outwardX, outwardY = -inX / depth, -inY / depth
    local ground = math.max(floor, getGroundPosition(centerX, centerY, floor + 2) or floor)
    local particles = {}
    for index = 1, 200 do
        local along = math.random()
        local inward = 0.1 + math.random() * math.min(6.4, depth - 0.1)
        particles[index] = {
            x = x + alongX * along - outwardX * inward,
            y = y + alongY * along - outwardY * inward,
            z = ground + 0.2 + math.random() * 0.4,
        }
    end
    bursts[#bursts + 1] = {particles = particles, start = getTickCount(), paint = paint,
        vx = outwardX * 2, vy = outwardY * 2, interior = interior, dimension = dimension}
end, false)

addEventHandler("onClientPreRender", root, function()
    if #bursts == 0 then return end
    local now = getTickCount()
    local interior, dimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
    for index = #bursts, 1, -1 do
        local burst = bursts[index]
        local elapsed = now - burst.start
        if elapsed >= particleLifetime or burst.interior ~= interior or burst.dimension ~= dimension then
            table.remove(bursts, index)
        else
            local seconds = elapsed / 1000
            local size = 0.15 + 0.45 * seconds
            local r, g, b = unpack(burst.paint)
            local color = tocolor(r, g, b, math.floor(150 * (1 - elapsed / particleLifetime)))
            local dx, dy = burst.vx * seconds, burst.vy * seconds
            for _, particle in ipairs(burst.particles) do
                local x, y, z = particle.x + dx, particle.y + dy, particle.z + 0.3 * seconds
                dxDrawMaterialLine3D(x, y, z - size / 2, x, y, z + size / 2, smoke, size, color, "prefx")
            end
        end
    end
end)
