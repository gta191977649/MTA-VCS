-- Source effect records 642-646 from the USA PS2 GAME.DTZ.
local palette = {
    {0, 0, 230, 20}, {0, 0, 230, 4}, {0, 200, 200, 4},
    {255, 255, 255, 4}, {175, 193, 212, 1}
}
local lightZ = -226.72
local orbit = {
    {-1568.76, 1332.86, 3, 2, 4, 3}, {-1568.76, 1336.86, 3, -2, 4, -3},
    {-1571.4301, 1327.86, 3, -2, 5, -3}, {-1571.4301, 1341.86, 3, 2, 5, 3},
    {-1578.13, 1331.0601, 3, 2, 1.5, -2}, {-1578.13, 1338.66, 3, -2, 1.5, 2},
    {-1575.4301, 1323.88, 3, -2, 6, -2}, {-1575.4301, 1345.84, 3, 2, 6, 2},
    {-1572.46, 1319.64, 3, 2, 4, 1}, {-1572.46, 1350.08, 3, -2, 4, -1}
}
local spotPositions = {
    {-1573.77, 1334.87}, {-1567.8101, 1335.03}, {-1574.39, 1341.72}, {-1576.24, 1327.5601}
}

local function addLight(fixtures, kind, x, y, orbitRadius, speed)
    local r, g, b, radius = unpack(palette[kind])
    local element = createLight(0, x, y, lightZ, radius, r, g, b)
    if not element then return end
    setElementInterior(element, ConcertStadium.interior)
    setElementDimension(element, ConcertStadium.dimension)
    fixtures[#fixtures + 1] = {element = element, x = x, y = y, radius = orbitRadius, speed = speed}
    return element
end

local function clearFixtures(fixtures)
    for _, fixture in ipairs(fixtures or {}) do
        if isElement(fixture.element) then destroyElement(fixture.element) end
    end
end

function destroyConcertLights(scene)
    clearFixtures(scene.lights)
    clearFixtures(scene.spots)
    if isElement(scene.flashTexture) then destroyElement(scene.flashTexture) end
end

local function makeOpeningLights(fixtures)
    addLight(fixtures, 1, -1573.77, 1334.87)
    addLight(fixtures, 2, -1570.16, 1334.86)
    addLight(fixtures, 2, -1570.67, 1340.5601)
    addLight(fixtures, 2, -1571.59, 1329.16)
    for _, source in ipairs(orbit) do
        addLight(fixtures, 5, source[1], source[2], source[3], source[4])
        addLight(fixtures, 5, source[1], source[2], source[5], source[6])
    end
end

local function updateSpots(scene)
    local mode = scene.ensembleLights and "ensemble" or (scene.spot and "lead" or "off")
    if scene.spotMode ~= mode then
        clearFixtures(scene.spots)
        scene.spots = {}
        scene.spotMode = mode
        if mode == "ensemble" then
            for _, position in ipairs(spotPositions) do
                addLight(scene.spots, 4, position[1], position[2])
            end
        elseif mode == "lead" then
            addLight(scene.spots, 4, spotPositions[2][1], spotPositions[2][2])
        end
    end
    if mode == "ensemble" and scene.spots[1] and scene.actors and scene.actors.phcol then
        local x, y = getElementPosition(scene.actors.phcol.ped)
        setElementPosition(scene.spots[1].element, x, y, lightZ)
    end
end

function updateConcertLights(scene, time)
    local phase = false
    if scene.ensembleLights then
        phase = math.floor((math.min(time, scene.lightCycleStop or time) - scene.ensembleLights) / 0.25) % 3
    end
    if not scene.lights or scene.lightPhase ~= phase then
        if not scene.lights or phase == false or scene.lightPhase == false then
            clearFixtures(scene.lights)
            scene.lights = {}
            if phase == false then
                makeOpeningLights(scene.lights)
            else
                for i = 0, 5 do
                    local angle = math.rad(i * 60)
                    addLight(scene.lights, 4, -1574 + 5 * math.cos(angle), 1334.86 + 5 * math.sin(angle))
                end
            end
        end
        if phase ~= false then
            local colors = {4, 3, 2}
            for i, fixture in ipairs(scene.lights) do
                local r, g, b = unpack(palette[colors[(i - 1 + phase) % 3 + 1]])
                setLightColor(fixture.element, r, g, b)
            end
        end
        scene.lightPhase = phase
    end
    if phase == false then
        for _, fixture in ipairs(scene.lights) do
            if fixture.speed then
                local angle = math.rad(time * 30 * fixture.speed)
                setElementPosition(fixture.element, fixture.x + fixture.radius * math.cos(angle),
                    fixture.y + fixture.radius * math.sin(angle), lightZ)
            end
        end
    end
    updateSpots(scene)
end

local function nextFlashValue(seed)
    return (seed * 48271) % 2147483647
end

function drawConcertCrowdFlashes(scene, time)
    if scene.flashTexture == nil then
        scene.flashTexture = dxCreateTexture("assets/crowd_flash.png", "argb", false, "clamp")
    end
    if not scene.flashTexture then return end

    -- RENC7_11423 spawns flashes with a 30% chance per source frame. Use
    -- that cadence and the original world bounds at every client FPS.
    local cx, cy, cz = getCameraMatrix()
    local _, height = guiGetScreenSize()
    local frame = math.floor(time * 30)
    dxSetBlendMode("add")
    for tick = math.max(0, frame - 3), frame do
        local age = time - tick / 30
        local seed = nextFlashValue(nextFlashValue(tick + 1))
        if age < 0.105 and seed / 2147483647 < 0.30 then
            seed = nextFlashValue(seed)
            local x = -1517.23 + seed / 2147483647 * 134.97
            seed = nextFlashValue(seed)
            local y = 1257.17 + seed / 2147483647 * 161.07
            seed = nextFlashValue(seed)
            local z = -231 + seed / 2147483647 * 10
            local sx, sy = getScreenFromWorldPosition(x, y, z)
            if sx and isLineOfSightClear(cx, cy, cz, x, y, z, true, false, false, true, true) then
                local distance = getDistanceBetweenPoints3D(cx, cy, cz, x, y, z)
                local size = math.max(height * 0.018, math.min(height * 0.095, height * 3.2 / math.max(distance, 1)))
                local alpha = math.floor(255 * (1 - age / 0.105)^1.5)
                dxDrawImage(sx - size / 2, sy - size / 2, size, size, scene.flashTexture,
                    0, 0, 0, tocolor(235, 242, 255, alpha))
                if age < 0.045 then
                    local coreAlpha = math.floor(255 * (1 - age / 0.045))
                    local core = size * 0.32
                    local color = tocolor(255, 255, 255, coreAlpha)
                    dxDrawImage(sx - core / 2, sy - core / 2, core, core, scene.flashTexture,
                        0, 0, 0, color)
                    dxDrawRectangle(sx - 1, sy - 1, 2, 2, color)
                end
            end
        end
    end
    dxSetBlendMode("blend")
end
