-- Shared material state for the original VCS world-marker meshes.
-- Geometry and marker placement remain with frontend and marker respectively.
local materials = {}

function createVcsMarkerMaterial(texture, additive)
    if not isElement(texture) or getElementType(texture) ~= "texture"
            or (additive ~= nil and type(additive) ~= "boolean") then
        return false
    end
    local shader = dxCreateShader("shader/vcsMarker.fx", additive and {VCS_MARKER_ADDITIVE="1"} or {})
    if not shader then return false end
    if not dxSetShaderValue(shader, "MarkerTexture", texture) then
        destroyElement(shader)
        return false
    end
    local owner = sourceResource or getThisResource()
    local ownerRoot = getResourceDynamicElementRoot(owner)
    if not ownerRoot or not setElementParent(shader, ownerRoot) then
        destroyElement(shader)
        return false
    end
    materials[shader] = getResourceRootElement(owner)
    return shader
end

function getVcsMarkerLighting()
    -- 0016bc58 -> 001a6df0 uses constant ambient .6 and brightens each
    -- timecycle directional channel by 40% of its remaining distance to white.
    local values = VCSWeather and VCSWeather.data and VCSWeather.data.values
    local red, green, blue
    if values then
        red, green, blue = values[13], values[14], values[15]
    else
        red, green, blue = getWorldProperty("DirectionalColor")
    end
    local function channel(value)
        value = math.max(0, math.min(1, (tonumber(value) or 0) / 255))
        return value + (1 - value) * .4
    end

    -- Match the recovered VCS timecycle sun arc used by pipeline/vcsSun.lua.
    -- The returned unit vector points toward the light, for dot(normal, direction).
    local hour, minute = getTime()
    local clock = hour * 60 + minute
    if clock >= 360 and clock < 720 then
        clock = 360 + 360 * (1 - math.cos((clock - 360) * math.pi / 720))
    elseif clock >= 720 and clock < 1080 then
        clock = 720 + 360 * math.sin((clock - 720) * math.pi / 720)
    end
    local angle = clock * math.pi / 720
    local x, y, z = math.sin(angle), 1, .4 - math.cos(angle)
    local length = math.sqrt(x*x + y*y + z*z)
    return {ambient={.6,.6,.6}, directional={channel(red),channel(green),channel(blue)},
            direction={x/length,y/length,z/length}}
end

addEventHandler("onClientElementDestroy", root, function()
    materials[source] = nil
end)

addEventHandler("onClientResourceStop", root, function()
    for shader, ownerRoot in pairs(materials) do
        if source == resourceRoot or source == ownerRoot then
            materials[shader] = nil
            if isElement(shader) then destroyElement(shader) end
        end
    end
end)
