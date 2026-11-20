VCSWater = {}

local surface, wake
local waveGrid, waveShader
local lastWaveUpdate
local updatesPerMillisecond = 30 / 1000
local waterWind, waterScroll = 0, 0
local textures = {}
local waterValues, lastOpacity, lastOpacityUpdate

local function loadTexture(name, mipmaps)
    local texture = dxCreateTexture("txd/vcs-" .. name .. ".png", "argb", mipmaps ~= false, "wrap")
    if texture then textures[#textures+1] = texture end
    return texture
end

function VCSWater.start()
    local base = loadTexture("waterclear256")
    local reflection = loadTexture("waterreflection2", false)
    local noise = loadTexture("water-noise", false)
    if base and reflection and noise then
        waveGrid = dxCreateRenderTarget(16, 16, true)
        waveShader = dxCreateShader("shader/vcsWater.fx", {VCS_WAVE_GRID="1"})
        if waveGrid and waveShader and dxSetShaderValue(waveShader, "WaveNoiseTexture", noise) then
            surface = dxCreateShader("shader/vcsWater.fx", 12, 0, false, "world,other")
        end
        if surface and not (dxSetShaderValue(surface, "SurfaceTexture", base)
                and dxSetShaderValue(surface, "ReflectionTexture", reflection)
                and dxSetShaderValue(surface, "WaveGridTexture", waveGrid)
                and engineApplyShaderToWorldTexture(surface, "waterclear256", nil, false)) then
            destroyElement(surface)
            surface = nil
        end
    end
    if not surface then
        outputDebugString("SkyGfx VCS: water surface shader unavailable", 2)
    end

    local wakeTexture = loadTexture("waterwake")
    VCSBoatWake.start(wakeTexture, surface)
    if wakeTexture then
        wake = dxCreateShader("shader/vcsWater.fx", {VCS_WAKE="1"}, 12, 0, false, "world,other")
        if wake and not engineApplyShaderToWorldTexture(wake, "waterwake", nil, false) then
            destroyElement(wake)
            wake = nil
        end
    end
    if not wake then outputDebugString("SkyGfx VCS: wake texture shader unavailable", 2) end
end

function VCSWater.update(values, wind)
    if not surface then return end
    waterValues, lastOpacity, lastOpacityUpdate = values, nil, nil
    waterWind = wind
    dxSetShaderValue(surface, "WaterColor", values[51]/255, values[52]/255, values[53]/255)
    dxSetShaderValue(waveShader, "WaterWind", waterWind)
    dxSetShaderValue(surface, "FogColor", (values[16]+2*values[19])/765,
        (values[17]+2*values[20])/765, (values[18]+2*values[21])/765)
    dxSetShaderValue(surface, "FogRange", getFogDistance(), getFarClipDistance())
    VCSWater.prepare()
end

function VCSWater.prepare()
    if not waterValues then return end
    local now = getTickCount()
    if not lastWaveUpdate
            or math.floor(now * updatesPerMillisecond) ~= math.floor(lastWaveUpdate * updatesPerMillisecond) then
        if dxSetRenderTarget(waveGrid) then
            local dt = lastWaveUpdate and math.max(now - lastWaveUpdate, 0) or 0
            -- 0x26f358 scrolls both texture axes with the current wind.
            waterScroll = (waterScroll + dt * updatesPerMillisecond * (0.0006 + waterWind * 0.0005)) % 1
            dxSetShaderValue(surface, "WaterScroll", waterScroll)
            dxSetShaderValue(waveShader, "WavePhase", (now % 4096) * (2 * math.pi / 4096))
            -- 0x11a918 advances the noise by 0.02 time steps in a 0.8-unit interval.
            dxSetShaderValue(waveShader, "NoiseFrame", (now * updatesPerMillisecond * (0.02 / 0.8)) % 64)
            local previousBlend = dxGetBlendMode()
            dxSetBlendMode("overwrite")
            local drawn = dxDrawImage(0, 0, 16, 16, waveShader)
            dxSetBlendMode(previousBlend)
            dxSetRenderTarget()
            if drawn then lastWaveUpdate = now end
        end
    end
    if lastOpacityUpdate and now >= lastOpacityUpdate and now - lastOpacityUpdate < 100 then return end
    lastOpacityUpdate = now

    -- SLUS-21590 0x2705c8 clamps water alpha to 200 and fades it to 255
    -- between camera altitudes 15 and 35. SA distributes the tint across its layers.
    local _, _, cameraZ = getCameraMatrix()
    local base = math.max(200, math.floor(waterValues[54]))
    local heightBlend = math.max(0, math.min(1, (cameraZ - 15) / 20))
    local opacity = base + math.floor((255 - base) * heightBlend)
    if opacity == lastOpacity then return end
    setWaterColor(waterValues[51], waterValues[52], waterValues[53], opacity)
    dxSetShaderValue(surface, "InverseWaterOpacity", 255 / opacity)
    lastOpacity = opacity
end

function VCSWater.restoreGraphics()
    lastWaveUpdate = nil
end

function VCSWater.stop()
    VCSBoatWake.stop()
    if waterValues then
        setWaterColor(waterValues[51], waterValues[52], waterValues[53], waterValues[54])
    end
    if surface then destroyElement(surface) end
    if wake then destroyElement(wake) end
    if waveShader then destroyElement(waveShader) end
    if waveGrid then destroyElement(waveGrid) end
    for _, texture in ipairs(textures) do destroyElement(texture) end
    surface, wake, textures = nil, nil, {}
    waveGrid, waveShader, lastWaveUpdate = nil, nil, nil
    waterWind, waterScroll = 0, 0
    waterValues, lastOpacity, lastOpacityUpdate = nil, nil, nil
end

function VCSWater.getStats()
    return {surface=isElement(surface), wake=isElement(wake), waveGrid=lastWaveUpdate ~= nil,
        boatWake=VCSBoatWake.getStats()}
end
