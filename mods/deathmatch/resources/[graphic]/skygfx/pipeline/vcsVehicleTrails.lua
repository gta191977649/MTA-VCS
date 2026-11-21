-- PS2 VCS corona streaks: SLUS-21590 0027C418, 0027DD80, 00145998..001465DC.
VCSVehicleTrails = {}

local active = false
local material
local vehicles = {}
local lastView
local stats = {lamps=0, samples=0, segments=0, failures=0}
local sampleCount = 6

local function bind(vehicle)
    if not active or not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
            or not isElementStreamedIn(vehicle) then return end
    local lamps = {}
    for _, group in ipairs({{"light_front_main", true, 1, 0}, {"light_rear_main", false, 2, 3}}) do
        local x, y, z = getVehicleDummyPosition(vehicle, group[1])
        if type(x) == "number" and type(y) == "number" and type(z) == "number"
                and x*x+y*y+z*z > 0 then
            -- MTA's dummy is on the right (+X); the other lamp is mirrored.
            lamps[#lamps+1] = {x=math.abs(x), y=y, z=z, front=group[2], index=group[3], history={}}
            if math.abs(x) > 0.001 then
                lamps[#lamps+1] = {x=-math.abs(x), y=y, z=z, front=group[2], index=group[4], history={}}
            end
        end
    end
    local handling = getVehicleHandling(vehicle)
    vehicles[vehicle] = {model=getElementModel(vehicle), lamps=lamps,
        halogen=handling and bitAnd(handling.modelFlags, 0x400000) ~= 0}
end

local function streamIn() bind(source) end
local function removed() vehicles[source] = nil end
local function modelChanged()
    if getElementType(source) == "vehicle" then bind(source) end
end
local function assetsChanged(resource)
    local name = getResourceName(resource)
    if name ~= "vcs_model" and name ~= "npchlc_traffic" then return end
    VCSVehicleTrails.reset()
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do bind(vehicle) end
end

function VCSVehicleTrails.reset()
    for _, state in pairs(vehicles) do
        for _, lamp in ipairs(state.lamps) do lamp.history = {} end
    end
    lastView = nil
    stats.lamps, stats.samples, stats.segments = 0, 0, 0
end

local function sceneChanged(w, h, now, cx, cy, cz, lx, ly, lz, roll, fov)
    local interior, dimension = getCameraInterior(), getElementDimension(localPlayer)
    local dx, dy, dz = lx-cx, ly-cy, lz-cz
    local length = math.max(math.sqrt(dx*dx+dy*dy+dz*dz), 0.0001)
    dx, dy, dz = dx/length, dy/length, dz/length
    local prev = lastView
    if prev and (prev.w ~= w or prev.h ~= h or prev.interior ~= interior or prev.dimension ~= dimension
            or now-prev.tick > 150 or (cx-prev.x)^2+(cy-prev.y)^2+(cz-prev.z)^2 > 35^2
            or dx*prev.dx+dy*prev.dy+dz*prev.dz < 0.5 or math.abs(fov-prev.fov) > 5
            or math.abs(roll-prev.roll) > 30) then
        VCSVehicleTrails.reset()
    end
    lastView = {w=w, h=h, tick=now, interior=interior, dimension=dimension,
        x=cx, y=cy, z=cz, dx=dx, dy=dy, dz=dz, roll=roll, fov=fov}
    return interior, dimension
end

local function lampSample(vehicle, lamp, matrix, cx, cy, cz, dot, lights, braking, reversing, halogen, w, h)
    if getVehicleLightState(vehicle, lamp.index) ~= 0 then return false end
    local intensity, r, g, b, distance
    if lamp.front then
        if not lights or dot >= 0 then return false end
        intensity = 0.3-dot*0.5
        r, g, b, distance = 210, 210, 195, 200
        if halogen then r, g, b = 190, 190, 255 end
    else
        if dot <= 0 or not (lights or braking or reversing) then return false end
        intensity = 0.4+dot*0.4
        if braking or reversing then intensity = intensity+0.4 end
        r, g, b, distance = 128, 0, 0, 50
        if reversing then g, b = 128, 128 end
        -- 001472C0 / 00147540: daytime brake/reverse lamps use fixed RGB 120.
        if not lights then
            intensity, r = 1, 120
            if reversing then g, b = 120, 120 end
        end
    end
    local x = lamp.x*matrix[1][1]+lamp.y*matrix[2][1]+lamp.z*matrix[3][1]+matrix[4][1]
    local y = lamp.x*matrix[1][2]+lamp.y*matrix[2][2]+lamp.z*matrix[3][2]+matrix[4][2]
    local z = lamp.x*matrix[1][3]+lamp.y*matrix[2][3]+lamp.z*matrix[3][3]+matrix[4][3]
    local facing = (x-cx)*matrix[2][1]+(y-cy)*matrix[2][2]+(z-cz)*matrix[2][3]
    if lamp.front and facing >= 0 or not lamp.front and facing <= 0 then return false end
    if (x-cx)^2+(y-cy)^2 > distance*distance then return false end
    local sx, sy = getScreenFromWorldPosition(x, y, z, 0, false)
    if not sx or sx < 0 or sy < 0 or sx > w or sy > h then return false end
    -- Ignore the emitting vehicle and peds, and test the actual lamp, not all four together.
    if not isLineOfSightClear(cx, cy, cz, x, y, z, true, false, false, true, false, false, false, vehicle) then
        return false
    end
    return {math.floor(sx), math.floor(sy), math.floor(r*intensity), math.floor(g*intensity), math.floor(b*intensity)}
end

local function vertex(sample, age)
    -- 0027CE10: trunc((6-age)*21.333334) * historical RGB >> 8; alpha stays 255.
    local weight = math.floor((6-age)*21.333334)
    return {sample[1], sample[2], tocolor(math.floor(sample[3]*weight/256),
        math.floor(sample[4]*weight/256), math.floor(sample[5]*weight/256), 255), 0, 0}
end

function VCSVehicleTrails.render()
    stats.lamps, stats.samples, stats.segments = 0, 0, 0
    if not active then return end
    if not SKYGFX.vehicleLightTrails or isMainMenuActive() then
        VCSVehicleTrails.reset()
        return
    end
    local w, h = guiGetScreenSize()
    local now = getTickCount()
    local cx, cy, cz, lx, ly, lz, roll, fov = getCameraMatrix()
    local interior, dimension = sceneChanged(w, h, now, cx, cy, cz, lx, ly, lz, roll, fov)
    local vertices = {}
    for vehicle, state in pairs(vehicles) do
        if not isElement(vehicle) or not isElementStreamedIn(vehicle) then
            vehicles[vehicle] = nil
        else
            if state.model ~= getElementModel(vehicle) then bind(vehicle); state = vehicles[vehicle] end
            local matrix = getElementMatrix(vehicle)
            local eligible = matrix and getElementInterior(vehicle) == interior
                and getElementDimension(vehicle) == dimension and getElementAlpha(vehicle) > 0
            if getElementInterior(vehicle) ~= interior or getElementDimension(vehicle) ~= dimension
                    or getElementAlpha(vehicle) == 0 then
                for _, lamp in ipairs(state.lamps) do lamp.history = {} end
            end
            local dot, lights, braking, reversing
            if eligible then
                local dx, dy, dz = matrix[4][1]-cx, matrix[4][2]-cy, matrix[4][3]-cz
                local length = math.max(math.sqrt(dx*dx+dy*dy+dz*dz), 0.0001)
                eligible = dx*dx+dy*dy <= 200^2
                dot = math.max(-1, math.min(1, (dx*matrix[2][1]+dy*matrix[2][2]+dz*matrix[2][3])/length))
                lights = areVehicleLightsOn(vehicle)
                local vx, vy, vz = getElementVelocity(vehicle)
                local speed = vx*matrix[2][1]+vy*matrix[2][2]+vz*matrix[2][3]
                local driver = getVehicleController(vehicle)
                local brake = driver and getPedControlState(driver, "brake_reverse")
                reversing = getVehicleCurrentGear(vehicle) == 0 and speed < -0.001
                braking = brake and speed >= -0.001
            end
            for _, lamp in ipairs(state.lamps) do
                stats.lamps = stats.lamps+1
                local history = lamp.history
                for i = sampleCount, 2, -1 do history[i] = history[i-1] or false end
                local sample = eligible and lampSample(vehicle, lamp, matrix, cx, cy, cz, dot,
                    lights, braking, reversing, state.halogen, w, h) or false
                -- Do not join across a camera cut, teleport, failed projection or occlusion gap.
                local previous = history[2]
                if sample and previous and (math.abs(sample[1]-previous[1]) > 50
                        or math.abs(sample[2]-previous[2]) > 50) then sample = false end
                history[1] = sample
                if sample then stats.samples = stats.samples+1 end
                for i = 1, sampleCount-1 do
                    local a, b = history[i], history[i+1]
                    if a and b then
                        vertices[#vertices+1] = vertex(a, i-1)
                        vertices[#vertices+1] = vertex(b, i)
                    end
                end
            end
        end
    end
    if #vertices == 0 then return end
    local previousBlend = dxGetBlendMode()
    dxSetBlendMode("add")
    -- Bounded batches keep unpack below Lua's argument/stack limit in dense traffic.
    for first = 1, #vertices, 240 do
        local last = math.min(first+239, #vertices)
        if dxDrawMaterialPrimitive("linelist", material, false, unpack(vertices, first, last)) then
            stats.segments = stats.segments+(last-first+1)/2
        else
            stats.failures = stats.failures+1
        end
    end
    dxSetBlendMode(previousBlend)
end

function VCSVehicleTrails.getStats()
    return {active=active and SKYGFX.vehicleLightTrails, lamps=stats.lamps, samples=stats.samples,
        segments=stats.segments, failures=stats.failures}
end

function VCSVehicleTrails.start()
    if active then return end
    material = dxCreateShader("shader/vcsVehicleTrails.fx")
    if not material then
        stats.failures = stats.failures+1
        outputDebugString("SkyGfx VCS: vehicle trail material unavailable", 1)
        return
    end
    active = true
    stats.failures = 0
    addEventHandler("onClientElementStreamIn", root, streamIn)
    addEventHandler("onClientElementStreamOut", root, removed)
    addEventHandler("onClientElementDestroy", root, removed)
    addEventHandler("onClientElementModelChange", root, modelChanged)
    addEventHandler("npc_hlc:onVehicleGroundGeometry", root, modelChanged)
    addEventHandler("onClientResourceStart", root, assetsChanged)
    addEventHandler("onClientResourceStop", root, assetsChanged)
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do bind(vehicle) end
end

function VCSVehicleTrails.stop()
    if not active then return end
    removeEventHandler("onClientElementStreamIn", root, streamIn)
    removeEventHandler("onClientElementStreamOut", root, removed)
    removeEventHandler("onClientElementDestroy", root, removed)
    removeEventHandler("onClientElementModelChange", root, modelChanged)
    removeEventHandler("npc_hlc:onVehicleGroundGeometry", root, modelChanged)
    removeEventHandler("onClientResourceStart", root, assetsChanged)
    removeEventHandler("onClientResourceStop", root, assetsChanged)
    vehicles = {}
    if isElement(material) then destroyElement(material) end
    material = nil
    active = false
    VCSVehicleTrails.reset()
end
