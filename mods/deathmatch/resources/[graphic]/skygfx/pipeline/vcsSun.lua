VCSSun = {}

local texture, shader, opticsTexture, opticsShader
local active = false
local minute, minuteTick, lastFrame, lastRay, rayDimension, rayMinute
local rayX, rayY, rayZ, haloClear
local haloOpacity = 0
local lastColors, lastFogScale
local stats = {draws=0, rays=0}
local vertices = {{0,0,0,-1,0,0}, {0,0,0,-1,1,0}, {0,0,0,-1,0,1}, {0,0,0,-1,1,1}}

-- VCSPC Coronas.cpp patches the native registration distance and size operands.
-- The patch divides its coefficients by ten because VCSPC stores SunSize in tenths.
local coreScale, haloScale = 10.64, 20
local sunDistance, pullTowardCamera = 150, 1.5
local coreFraction = coreScale / haloScale
local rayInterval = 67  -- at most 15 queries per second
local fadeInMs, fadeOutMs = 220, 140

-- SLUS-21590 flare type 1 at 0x4878b8. VCSPC reads these fields from flaredef.dat.
local flares = {
    {-0.5, 15, 50, 50, 0}, {-1, 10, 50, 20, 0}, {-1.5, 15, 50, 0, 0},
    {-2.5, 25, 50, 0, 0}, {0.5, 12.5, 40, 40, 25}, {0.05, 20, 30, 22, 9},
    {1.3, 7.5, 50, 30, 9},
}
local flareCorners = {{0,0}, {1,0}, {0,1}, {0,1}, {1,0}, {1,1}}
local opticsVertices = {}
for i = 1, (#flares + 1) * 6 do opticsVertices[i] = {} end
-- Texel centers of the 64x64 star and 32x32 ring in the padded optics atlas.
local starUv = {1.5/128, 1.5/128, 64.5/128, 64.5/128}
local ringUv = {67.5/128, 1.5/128, 98.5/128, 32.5/128}

function VCSSun.resetVisibility()
    lastFrame, lastRay, rayDimension, rayMinute = nil, nil, nil, nil
    haloClear, haloOpacity = nil, 0
end

local function sunDirection(clock)
    -- SLUS-21590 timecycle, 0x1CD780. The daylight arc has two eased intervals.
    if clock >= 360 and clock < 720 then
        clock = 360 + 360 * (1 - math.cos((clock - 360) * math.pi / 720))
    elseif clock >= 720 and clock < 1080 then
        clock = 720 + 360 * math.sin((clock - 720) * math.pi / 720)
    end
    local angle = clock * math.pi / 720
    local x, z = math.sin(angle), 0.4 - math.cos(angle)
    local length = math.sqrt(x*x + 1 + z*z)
    return x/length, 1/length, z/length
end

function VCSSun.start()
    texture = dxCreateTexture("txd/vcs-coronastar.png", "argb", false, "clamp")
    shader = dxCreateShader("shader/vcsSun.fx")
    if texture and shader and dxSetShaderValue(shader, "Sprite", texture)
            and VCSWeather.setCustomSun(true) then
        active = true
        opticsTexture = dxCreateTexture("txd/vcs-sun-optics.png", "argb", false, "clamp")
        opticsShader = dxCreateShader("shader/vcsSun.fx", {VCS_SUN_OPTICS="1"})
        if not (opticsTexture and opticsShader and dxSetShaderValue(opticsShader, "Sprite", opticsTexture)) then
            if isElement(opticsShader) then destroyElement(opticsShader) end
            if isElement(opticsTexture) then destroyElement(opticsTexture) end
            opticsTexture, opticsShader = nil, nil
            outputDebugString("SkyGfx VCS: solar halo and flares unavailable", 2)
        end
        return
    end
    VCSSun.stop()
    outputDebugString("SkyGfx VCS: custom sun unavailable, using the native sun", 2)
end

function VCSSun.stop(reloading)
    if active and not reloading then VCSWeather.setCustomSun(false) end
    if isElement(shader) then destroyElement(shader) end
    if isElement(texture) then destroyElement(texture) end
    if isElement(opticsShader) then destroyElement(opticsShader) end
    if isElement(opticsTexture) then destroyElement(opticsTexture) end
    texture, shader = nil, nil
    opticsTexture, opticsShader = nil, nil
    active = false
    minute, minuteTick, lastRay = nil, nil, nil
    lastColors, lastFogScale = nil, nil
    stats.draws, stats.rays, stats.core, stats.halo = 0, 0, false, false
    stats.haloWidth, stats.haloHeight = 0, 0
    stats.flares = 0
    VCSSun.resetVisibility()
end

function VCSSun.getStats()
    local blocked
    if haloClear ~= nil then blocked = not haloClear end
    return {
        mode=active and "custom" or "native", draws=stats.draws, rays=stats.rays,
        core=stats.core, halo=stats.halo, blocked=blocked, opacity=haloOpacity,
        haloWidth=stats.haloWidth or 0, haloHeight=stats.haloHeight or 0, flares=stats.flares or 0,
    }
end

local function updateHalo(now, onScreen, x, y, z, sx, sy, sz, distance, clock)
    local dimension = getElementDimension(localPlayer)
    if haloClear ~= nil and (dimension ~= rayDimension
            or math.min(math.abs(clock-rayMinute), 1440-math.abs(clock-rayMinute)) > 2
            or (x-rayX)^2 + (y-rayY)^2 + (z-rayZ)^2 > 25^2) then
        VCSSun.resetVisibility()
    end

    if not onScreen then
        -- The corona fades out when its center leaves the viewport.
        lastRay = nil
    elseif not lastRay or now < lastRay or now-lastRay >= rayInterval then
        local clear = isLineOfSightClear(x, y, z, x+sx*distance, y+sy*distance, z+sz*distance,
            true, true, false, true, false, true, false, localPlayer)
        if haloClear == nil then haloOpacity = clear and 1 or 0 end
        haloClear = clear
        lastRay, rayDimension, rayMinute = now, dimension, clock
        rayX, rayY, rayZ = x, y, z
        stats.rays = stats.rays + 1
    end

    local elapsed = lastFrame and math.max(0, math.min(now-lastFrame, 50)) or 0
    lastFrame = now
    if onScreen and haloClear then
        haloOpacity = math.min(1, haloOpacity + elapsed/fadeInMs)
    else
        haloOpacity = math.max(0, haloOpacity - elapsed/fadeOutMs)
    end
end

local function overlapsScreen(x, y, width, height, halfWidth, halfHeight)
    return x and x >= -halfWidth and x <= width+halfWidth
        and y >= -halfHeight and y <= height+halfHeight
end

local function drawCore(x, y, z, halfWidth, halfHeight, values, fogScale, depth)
    if values ~= lastColors or fogScale ~= lastFogScale then
        local colorScale = 1 / (255 * fogScale)
        dxSetShaderValue(shader, "CoreColor", values[22]*colorScale, values[23]*colorScale, values[24]*colorScale)
        lastColors, lastFogScale = values, fogScale
    end
    dxSetShaderValue(shader, "HalfExtent", 2*halfWidth, 2*halfHeight)
    dxSetShaderValue(shader, "CoreDepth", depth)
    for _, vertex in ipairs(vertices) do
        vertex[1], vertex[2], vertex[3] = x, y, z
    end
    return dxDrawMaterialPrimitive3D("trianglestrip", shader, "prefx", unpack(vertices))
end

local function appendOpticsQuad(count, x, y, radius, width, height, color, uv)
    for _, corner in ipairs(flareCorners) do
        local u, v = corner[1], corner[2]
        count = count + 1
        local vertex = opticsVertices[count]
        vertex[1], vertex[2] = 2*(x+(2*u-1)*radius)/width-1, 1-2*(y+(2*v-1)*radius)/height
        vertex[3], vertex[4] = 0, color
        vertex[5], vertex[6] = uv[1]+u*(uv[3]-uv[1]), uv[2]+v*(uv[4]-uv[2])
    end
    return count
end

local function drawOptics(x, y, radius, width, height, values, fogScale)
    if not opticsShader or haloOpacity <= 0 then return false, 0 end
    -- The PS2 corona's LOS flag selects an always-pass depth test (0x27C800).
    -- Fade that screen-space glow separately from the depth-tested sun core.
    local r, g, b = values[25], values[26], values[27]
    local opacity = 255*haloOpacity
    local haloColor = tocolor(r/fogScale, g/fogScale, b/fogScale, opacity)
    local count = appendOpticsQuad(0, x, y, radius, width, height, haloColor, starUv)
    if overlapsScreen(x, y, width, height, 0, 0) then
        local cx, cy = width/2, height/2
        local sizeScale = 4*height/448
        -- Mean of VCSPC's flare flicker, in GS vertex color units.
        local intensity = 0.85 * 128 / (255 * 256)
        for _, flare in ipairs(flares) do
            local fx, fy = cx+(x-cx)*flare[1], cy+(y-cy)*flare[1]
            local flareRadius = flare[2]*sizeScale
            if overlapsScreen(fx, fy, width, height, flareRadius, flareRadius) then
                local color = tocolor(r*flare[3]*intensity, g*flare[4]*intensity, b*flare[5]*intensity, opacity)
                count = appendOpticsQuad(count, fx, fy, flareRadius, width, height, color, ringUv)
            end
        end
    end
    local submitted = dxDrawMaterialPrimitive3D("trianglelist", opticsShader, "prefx", unpack(opticsVertices, 1, count))
    return submitted, submitted and count/6-1 or 0
end

function VCSSun.prepare(values)
    stats.draws, stats.core, stats.halo = 0, false, false
    stats.haloWidth, stats.haloHeight = 0, 0
    stats.flares = 0
    if not active or not values or isMainMenuActive() or getCameraInterior() ~= 0 or values[28] <= 0 or values[29] <= 0 then
        VCSSun.resetVisibility()
        return
    end

    local now = getTickCount()
    local hour, min = getTime()
    local clock = hour * 60 + min
    if minute ~= clock or now < minuteTick then minute, minuteTick = clock, now end
    if not isTimeFrozen() then
        clock = clock + math.min((now-minuteTick) / math.max(getMinuteDuration(), 1), 1)
    end
    local sx, sy, sz = sunDirection(clock)
    -- SLUS-21590 registers the core at z > -0.2 and the halo at z > 0.
    if sz <= -0.2 then VCSSun.resetVisibility() return end

    local x, y, z, lx, ly, lz, _, fov = getCameraMatrix()
    local dx, dy, dz = lx-x, ly-y, lz-z
    local viewDot = (sx*dx + sy*dy + sz*dz) / math.max(math.sqrt(dx*dx + dy*dy + dz*dz), 0.001)
    if viewDot <= 0.01 then VCSSun.resetVisibility() return end

    -- The anchor supplies screen position only. The shader tests at sky depth.
    local px, py, pz = x+sx*sunDistance, y+sy*sunDistance, z+sz*sunDistance
    local width, height = guiGetScreenSize()
    -- Only cap the extreme off-axis perspective term, independently of SunSize.
    local depth = (sunDistance-pullTowardCamera)*math.max(viewDot, 0.5)
    local fogScale = 1 + math.min(depth, 40) * 0.025 * (getWorldProperty("Foggyness") or 0)
    -- Use viewport height for both axes. SunSize is in source Timecyc units
    -- and must remain proportional even when the halo is larger than the viewport.
    local pixelsPerUnit = height * (70 / math.max(fov or 70, 15)) / depth
    -- 0x27DD80 multiplies both registered sun radii by the Timecyc SpriteSize.
    local haloRadius = haloScale * values[28] * values[29] * pixelsPerUnit
    local coreRadius = haloRadius * coreFraction
    local visibleFraction = sz > 0 and 1 or coreFraction
    local tolerance = visibleFraction * haloRadius
    local screenX, screenY = getScreenFromWorldPosition(px, py, pz, tolerance, false)
    if not overlapsScreen(screenX, screenY, width, height,
            tolerance, tolerance) then
        VCSSun.resetVisibility()
        return
    end

    local coreVisible = overlapsScreen(screenX, screenY, width, height,
        coreRadius, coreRadius)
    local farClip = getFarClipDistance()
    if sz > 0 and opticsShader then
        stats.haloWidth, stats.haloHeight = 2*haloRadius, 2*haloRadius
        local onScreen = overlapsScreen(screenX, screenY, width, height, 0, 0)
        updateHalo(now, onScreen, x, y, z, sx, sy, sz, farClip/math.max(viewDot, 0.5), clock)
    else
        VCSSun.resetVisibility()
    end

    if coreVisible and drawCore(px, py, pz, coreRadius/width, coreRadius/height, values, fogScale, 0.95*farClip) then
        stats.draws, stats.core = 1, true
    end
    stats.halo, stats.flares = drawOptics(screenX, screenY, haloRadius, width, height, values, fogScale)
    if stats.halo then stats.draws = stats.draws + 1 end
end
