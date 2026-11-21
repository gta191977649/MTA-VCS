local block = "phill_concert.pc_conc"
-- SCM positions are at the feet. All four PS2 models have a -1.0 collision
-- box minimum on Z. The MTA creation and movement APIs use the ped origin.
local pedOriginHeight = 1.0
local cast = {
    phcol = {-1584.08, 1330.6, -230.52, 270},
    gtr1 = {-1567.8101, 1335.03, -231.26, 0, 496},
    gtr2 = {-1574.39, 1341.72, -230.29, 0, 501},
    bmyst = {-1576.0601, 1327.45, -230.08, 10, 502}
}

local function own(scene, element)
    if isElement(element) then
        scene.elements[#scene.elements + 1] = element
        return element
    end
end

local function loadModel(scene, name, kind, txdName)
    local id = engineRequestModel(kind)
    if not id then return end
    scene.modelIDs[#scene.modelIDs + 1] = id
    local dff = own(scene, engineLoadDFF("assets/" .. name .. ".dff"))
    local txd = own(scene, engineLoadTXD("assets/" .. (txdName or name) .. ".txd"))
    if dff and txd and engineImportTXD(txd, id) and engineReplaceModel(dff, id, true) then
        return id
    end
end

function destroyConcertCast(scene)
    if not scene.elements then return end
    for i = #scene.elements, 1, -1 do
        if isElement(scene.elements[i]) then destroyElement(scene.elements[i]) end
    end
    for i = #scene.modelIDs, 1, -1 do engineFreeModel(scene.modelIDs[i]) end
end

local function place(element)
    setElementInterior(element, ConcertStadium.interior)
    setElementDimension(element, ConcertStadium.dimension)
    setElementCollisionsEnabled(element, false)
    return element
end

local function setClip(actor, id, time)
    local clip = ConcertClips[id]
    local loop = id ~= 415
    actor.clip, actor.clipStart, actor.loop = clip, time, loop
    actor.seekPending = true
    return setPedAnimation(actor.ped, block, clip[1], -1, loop, false, false, not loop, 0, false)
end

function makeConcertCast(scene)
    scene.elements, scene.modelIDs, scene.actors = {}, {}, {}
    if scene.debug then outputDebugString("[phill_concert] Loading pc_conc.ifp") end
    local ifp = own(scene, engineLoadIFP("assets/pc_conc.ifp", block))
    if not ifp then return false, "pc_conc.ifp" end
    if scene.debug then outputDebugString("[phill_concert] IFP loaded") end
    for name, def in pairs(cast) do
        if scene.debug then outputDebugString("[phill_concert] Loading " .. name) end
        local id = loadModel(scene, name, "ped")
        local ped = id and own(scene, createPed(id, def[1], def[2], def[3] + pedOriginHeight, def[4]))
        if not ped then return false, name end
        place(ped)
        local actor = {ped = ped, position = def}
        scene.actors[name] = actor
        if def[5] and not setClip(actor, def[5], 0) then return false, ConcertClips[def[5]][1] end
    end
    if scene.debug then outputDebugString("[phill_concert] Cast loaded") end
    setElementAlpha(scene.actors.phcol.ped, 0)
    local rig = loadModel(scene, "me_mainlightrig", "object")
    local stick = loadModel(scene, "ndc_philstick", "object", "stage_props")
    if not rig or not stick then return false, "stage props" end
    local lighting = own(scene, createObject(rig, -1568.91, 1334.8, -223))
    if not lighting then return false, "lighting rig" end
    place(lighting)
    scene.sticks = {}
    for i = 1, 2 do
        local object = own(scene, createObject(stick, -1584.08, 1330.6, -231))
        if not object then return false, "drumsticks" end
        place(object)
        setElementAlpha(object, 0)
        scene.sticks[i] = object
    end
    return true
end

local function sample(track, time)
    local lo, hi = 1, #track
    while hi - lo > 1 do
        local mid = math.floor((lo + hi) / 2)
        if track[mid][1] <= time then lo = mid else hi = mid end
    end
    local a, b = track[lo], track[hi]
    local span = b[1] - a[1]
    local t = span > 0 and math.max(0, math.min(1, (time - a[1]) / span)) or 0
    return a, b, t
end

local function rootPosition(time)
    local a, b, t = sample(ConcertPhilRoot, time)
    return a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, a[4] + (b[4] - a[4]) * t
end

local function setRoot(scene, time, offset, x, y, z)
    local dx, dy = rootPosition(offset)
    -- SCM resyncs use the same Z datum throughout the show. The clip's Z is
    -- relative to that datum and includes the stage steps and seated pose.
    scene.philBase = {x - dx, y - dy, z + pedOriginHeight}
    scene.philRootStart = time - offset
end

function applyConcertActorEvent(scene, event, time)
    local kind = event[2]
    if kind == "animation" then
        if event[3] ~= "phcol" then return setClip(scene.actors[event[3]], event[5], time) end
    elseif kind == "reveal" then
        local actor = scene.actors.phcol
        -- Match the SCM reveal heading. The IFP root already turns the pose
        -- from the model's +Y bind heading to the +X entrance path.
        setElementRotation(actor.ped, 0, 0, 0, "default", true)
        setRoot(scene, time, 0, -1583.2, 1330.1, -230.45)
        setElementAlpha(actor.ped, 255)
        return setClip(actor, 415, time)
    elseif kind == "root" then
        setRoot(scene, time, event[3], event[4], event[5], event[6])
    end
    return true
end

local function syncClip(actor, time)
    local name, duration = unpack(actor.clip)
    local elapsed = math.max(0, time - actor.clipStart)
    local target = actor.loop and elapsed % duration or math.min(elapsed, duration)
    if setPedAnimationProgress(actor.ped, name, math.min(target / duration, 0.9999)) then
        actor.seekPending = false
    end
end

function updateConcertCast(scene, time)
    for name, actor in pairs(scene.actors) do
        setElementVelocity(actor.ped, 0, 0, 0)
        if name ~= "phcol" or not scene.philBase then
            local position = actor.position
            setElementPosition(actor.ped, position[1], position[2], position[3] + pedOriginHeight, false)
        end
        if actor.seekPending and scene.started then syncClip(actor, time) end
    end
    if not scene.philBase then return end
    local actor = scene.actors.phcol
    local elapsed = time - scene.philRootStart
    local x, y, z = rootPosition(elapsed)
    local base = scene.philBase
    setElementPosition(actor.ped, base[1] + x, base[2] + y, base[3] + z, false)
    scene.sticksVisible = scene.sticksVisible or elapsed >= 159
end

local function attachStick(stick, ped, bone, roll)
    local m = getElementBoneMatrix(ped, bone)
    if not m then return end
    local dx, dy = -0.07, 0.03
    local cosX, sinX = 0.5, math.sqrt(3) * 0.5
    local sign = roll == 0 and 1 or -1
    local transform = {{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 1}}
    for i = 1, 3 do
        transform[1][i] = sign * m[1][i]
        transform[2][i] = cosX * m[2][i] + sinX * m[3][i]
        transform[3][i] = sign * (-sinX * m[2][i] + cosX * m[3][i])
        transform[4][i] = m[4][i] + dx * m[1][i] + dy * m[2][i]
    end
    setElementMatrix(stick, transform)
    setElementAlpha(stick, 255)
end

function updateConcertBones(scene)
    local actor = scene.actors.phcol
    if not scene.philBase then return end
    if scene.sticksVisible then
        attachStick(scene.sticks[1], actor.ped, 25, 0)
        attachStick(scene.sticks[2], actor.ped, 35, 180)
    end
end
