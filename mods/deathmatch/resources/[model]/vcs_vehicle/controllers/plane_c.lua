local presentations = {}

local function presentation()
    local owner = sourceResource or getThisResource()
    local group = presentations[owner]
    if not group then
        group = {slots={}, models={}, lastAttempt={}, state="loading"}
        presentations[owner] = group
    end
    return group
end

local function clearProxy(entry)
    if isElement(entry.proxy) then destroyElement(entry.proxy) end
    entry.proxy = nil
end

local function setNativeVisible(entry, visible)
    if entry.hidden == not visible then return end
    if isElement(entry.vehicle) then setElementAlpha(entry.vehicle, visible and 255 or 0) end
    entry.hidden = not visible
end

local function setNativeResident(entry, resident)
    local vehicle = entry.vehicle
    if not isElement(vehicle) then return end
    if resident then
        if not entry.pinned and isElementStreamable(vehicle) then
            entry.pinned = setElementStreamable(vehicle, false)
        end
    elseif entry.pinned then
        setElementStreamable(vehicle, true)
        entry.pinned = false
    end
end

function CPlane:ReleasePresentation()
    local entry = self
    clearProxy(entry)
    setNativeVisible(entry, true)
    setNativeResident(entry, false)
end

function setPlanePresentationSlot(slot, vehicle, provider)
    if type(slot) ~= "number" or slot < 0 or slot >= 32 or slot % 1 ~= 0 then return false end
    if vehicle ~= false and (not isElement(vehicle) or getElementType(vehicle) ~= "vehicle") then return false end
    local group = presentation()
    local old = group.slots[slot]
    if old and old.vehicle == vehicle and old.provider == provider then return true end
    if vehicle and group.route and slot >= group.route.instances then return false end
    if old then old:ReleasePresentation() end
    local entry = vehicle and CPlane:New(vehicle) or nil
    if entry then entry.provider = provider end
    group.slots[slot] = entry
    return true
end

local function presentationModel(group, provider, tier, farClip, now)
    if not provider then return false end
    local key = provider .. "/" .. group.route.originalModelId .. "/" .. tier
    local model = group.models[key]
    if not model then
        if group.lastAttempt[key] and (now - group.lastAttempt[key]) % 4294967296 < 1000 then return false end
        group.lastAttempt[key] = now
        local resource = getResourceFromName(provider)
        if not resource or getResourceState(resource) ~= "running" then return false end
        for _, name in ipairs(getResourceExportedFunctions(resource) or {}) do
            if name == "getTrafficFixedWingLOD" then
                local id = call(resource, name, group.route.originalModelId, tier)
                if id then model = {id=id, range=0, provider=provider} end
                break
            end
        end
        if not model then return false end
        group.models[key] = model
    end
    if farClip > model.range then
        model.range = math.ceil(farClip / 100) * 100
        engineSetModelLODDistance(model.id, model.range, true)
    end
    return model.id
end

local function showProxy(group, entry, pose, tier, farClip, now)
    local id = presentationModel(group, entry.provider, tier, farClip, now)
    if not id then clearProxy(entry) return false end
    if entry.tier ~= tier or not isElement(entry.proxy) then
        clearProxy(entry)
        entry.proxy = createObject(id, pose.x, pose.y, pose.z, 0, 0, 0, tier == "vlo")
        if not entry.proxy then return false end
        entry.tier = tier
        setElementCollisionsEnabled(entry.proxy, false)
        setElementStreamable(entry.proxy, false)
    end
    CPlane.ApplyPose(entry.proxy, pose)
    return true
end

-- SLUS-21590 0037AEE4..0037B068 stores 70/FOV, with an altitude
-- multiplier for aircraft and a final cap of 2. 0036EBF8 squares
-- this multiplier for the 60 and 150 unit type-5 atomic cutoffs.
local function cameraScale(z, fov)
    local scale = 70 / math.max(1, fov or 70)
    local vehicle = getPedOccupiedVehicle(localPlayer)
    local kind = vehicle and getVehicleType(vehicle)
    if z > 55 and (kind == "Plane" or kind == "Helicopter") then
        scale = scale * (1 + (z - 55) / 60)
    end
    return math.min(2, scale)
end

local function currentClock(group, now)
    return group.haltClock or (group.syncClock + (now - group.syncTick) % 4294967296) % 4294967296
end

function CPlane:Render(group, slot, clock, view, now)
    local cx, cy, cz = view.x, view.y, view.z
    local lodScale, farClip, nativeRange = view.lodScale, view.farClip, view.nativeRange
    local entry, route = self, group.route
    local vehicle = entry.vehicle
    local pose = CPlane.SampleFlight(route, clock, slot)
    local distance = getDistanceBetweenPoints3D(cx, cy, cz, pose.x, pose.y, pose.z)
    -- 0022D418 uses the forward path sample and a horizontal 300-unit
    -- radius to switch the entire clump to simple model 319. Its disc
    -- streaming entry has no sectors. Use 280's authored VLO for it.
    local simple = (pose.aheadX - cx)^2 + (pose.aheadY - cy)^2 >= 90000
    local drawRange = simple and math.min(farClip, 2000 * lodScale) or farClip
    local tier = "vlo"
    if not simple then
        if distance < 60 * lodScale then tier = "hi"
        elseif distance < 150 * lodScale then tier = "lo" end
    end
    entry.sourceModelId = simple and 319 or route.originalModelId
    local alive = isElement(vehicle) and not isVehicleBlown(vehicle)
    -- The remote camera can be near the route while the player's native
    -- vehicle streamer is elsewhere. Keep just the near slot resident.
    setNativeResident(entry, alive and view.exterior and tier == "hi" and distance <= math.min(nativeRange, farClip))
    local native = alive and isElementStreamedIn(vehicle)
    if native and view.exterior then CPlane.ApplyPose(vehicle, pose) end
    entry.representation = "none"
    if not alive or not view.exterior or distance > drawRange then
        clearProxy(entry)
        setNativeVisible(entry, not alive)
    elseif showProxy(group, entry, pose, tier, drawRange, now) then
        setNativeVisible(entry, false)
        entry.representation = tier == "hi" and "near-model" or tier == "lo" and "middle-model" or "distant"
    else
        setNativeVisible(entry, true)
        if native then entry.representation = "native" end
    end
end

local function render(group, now)
    local route = group.route
    if not route then return end
    local clock = currentClock(group, now)
    local cx, cy, cz, _, _, _, _, fov = getCameraMatrix()
    local lodScale = cameraScale(cz, fov)
    local exterior = getElementInterior(localPlayer) == 0 and getElementDimension(localPlayer) == 0
        and not group.haltClock
    local farClip = getFarClipDistance()
    local vehicles, planes = getVehiclesLODDistance()
    local view = {x=cx, y=cy, z=cz, lodScale=lodScale, exterior=exterior, farClip=farClip, nativeRange=planes or vehicles}
    for slot, entry in pairs(group.slots) do
        entry:Render(group, slot, clock, view, now)
    end
end

function getPlanePresentationStatus()
    local group = presentation()
    local route = group.route
    local clock = route and currentClock(group, getTickCount()) or 0
    local result = {state=group.state,
        active=0, expected=route and route.instances or 0, slots={}, phaseMs=route and clock % route.clockPeriodMs or 0}
    for slot=0,result.expected-1 do
        local pose = CPlane.SampleFlight(route, clock, slot)
        local entry = group.slots[slot]
        local alive = entry and isElement(entry.vehicle) and not isVehicleBlown(entry.vehicle)
        if alive then result.active = result.active + 1 end
        local representation = entry and entry.representation or "none"
        local display = entry and (representation == "native" and entry.vehicle or entry.proxy)
        result.slots[#result.slots+1] = {slot=slot, active=alive or false, x=pose.x, y=pose.y, z=pose.z,
            sourceModelId=entry and entry.sourceModelId, meshModelId=route.originalModelId,
            phaseMs=(clock + slot * route.phaseStepMs) % route.clockPeriodMs, representation=representation,
            streamed=alive and isElementStreamedIn(entry.vehicle) or false,
            rendered=representation ~= "none" and isElement(display) and isElementOnScreen(display)}
    end
    return result
end

function setPlanePresentationRoute(route, clock)
    if not CPlane.IsValidRoute(route) or type(clock) ~= "number" or not (clock>=0 and clock<math.huge) then return false end
    local group = presentation()
    for slot, entry in pairs(group.slots) do
        if slot >= route.instances then entry:ReleasePresentation() group.slots[slot] = nil end
    end
    group.route, group.syncClock, group.syncTick = route, clock, getTickCount()
    return true
end

function setPlanePresentationState(state, haltClock)
    if type(state) ~= "string" or (haltClock ~= false and type(haltClock) ~= "number") then return false end
    local group = presentation()
    group.state, group.haltClock = state, haltClock
    return true
end

addEventHandler("onClientElementDestroy", root, function()
    for _, group in pairs(presentations) do
        for slot, entry in pairs(group.slots) do
            if entry.vehicle == source then
                group.slots[slot] = nil
                clearProxy(entry)
            end
        end
    end
end)

addEventHandler("onClientResourceStop", root, function(resource)
    local name = getResourceName(resource)
    for owner, group in pairs(presentations) do
        if resource == getThisResource() or resource == owner then
            for _, entry in pairs(group.slots) do entry:ReleasePresentation() end
            presentations[owner] = nil
        else
            for _, entry in pairs(group.slots) do
                if entry.provider == name then entry:ReleasePresentation() end
            end
            for key, model in pairs(group.models) do
                if model.provider == name then
                    group.models[key], group.lastAttempt[key] = nil, nil
                end
            end
        end
    end
end)

addEventHandler("onClientPreRender", root, function()
    local now = getTickCount()
    for _, group in pairs(presentations) do render(group, now) end
end)
