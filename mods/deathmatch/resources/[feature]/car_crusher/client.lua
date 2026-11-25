local parts, models = {}, {}
local hook, hookMotion, lidMotion
local renderedRevision
local revision, clockOffset, desiredOffset, bestRTT = -1, nil, nil, math.huge

local function loadPart(name, position, dictionary)
    local id = engineRequestModel("object")
    if not id then return false end
    models[#models + 1] = id
    if not engineImportTXD(dictionary, id) then return false end
    local mesh = engineLoadDFF("models/" .. name .. ".dff")
    local collision = engineLoadCOL("models/" .. name .. ".col")
    if not mesh or not collision or not engineReplaceCOL(collision, id) or not engineReplaceModel(mesh, id) then return false end
    local part = createObject(id, unpack(position))
    if not part then return false end
    engineSetModelLODDistance(id, 180)
    setElementRotation(part, 0, 0, Crusher.rotation)
    setElementFrozen(part, true)
    setObjectBreakable(part, false)
    setElementID(part,"car_crusher:"..name)
    parts[name] = part
    return part
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local dictionary = engineLoadTXD("models/harwood.txd")
    if not dictionary then return end
    for name, pos in pairs(Crusher.parts) do
        if not loadPart(name, pos, dictionary) then outputDebugString("Cannot load crusher part " .. name, 1) end
    end
    local magnet = loadPart("magnet", Crusher.drop, dictionary)
    if magnet then setElementCollisionsEnabled(magnet, false) end
    local function requestMotion()
        triggerServerEvent("car_crusher:requestMotion",resourceRoot,getTickCount())
    end
    requestMotion()
    setTimer(requestMotion,15000,0)
end)

addEvent("car_crusher:motion",true)
addEventHandler("car_crusher:motion",resourceRoot,function(sequence,serverNow,crane,lid,sent)
    local now = getTickCount()
    if sent then
        local rtt = now-sent
        if rtt <= bestRTT+10 then
            bestRTT = rtt
            desiredOffset = serverNow + rtt/2 - now
        end
    end
    if not clockOffset then
        desiredOffset = desiredOffset or serverNow-now+getPlayerPing(localPlayer)/2
        clockOffset = desiredOffset
    end
    if sequence < revision then return end
    revision,hookMotion,lidMotion = sequence,crane,lid
end)

local sounds = {}

local function updateSound(name, position, volume, start, duration, looped, now)
    local sound = sounds[name]
    local elapsed = start and now-start
    if not elapsed or elapsed < 0 or elapsed >= duration then
        if isElement(sound) then destroyElement(sound) end
        sounds[name] = nil
        return
    end
    if isElement(sound) then return end
    sound = playSound3D("audio/" .. name .. ".wav", position[1], position[2], position[3], looped, false)
    if not sound then return end
    sounds[name] = sound
    setSoundVolume(sound, volume/127)
    setSoundMaxDistance(sound, 80)
    local length = getSoundLength(sound)
    if length > 0 then setSoundPosition(sound, looped and (now/1000)%length or elapsed/1000) end
end

local function processMachineAudio(now)
    local x,y,z = getCameraMatrix()
    local cab, lid = Crusher.parts.doc_crane_cab, Crusher.parts.crushertop
    -- Both emitters lie within 40 units of the lid.
    if getElementDimension(localPlayer) ~= 0 or getElementInterior(localPlayer) ~= 0
        or getDistanceBetweenPoints3D(x,y,z,lid[1],lid[2],lid[3]) > 120 then
        for name,sound in pairs(sounds) do
            if isElement(sound) then destroyElement(sound) end
            sounds[name] = nil
        end
        return
    end
    updateSound("magnet", cab, 100, hookMotion.start, hookMotion.duration, true, now)
    updateSound("pickup", cab, 100, hookMotion.pickup and hookMotion.start, 648, false, now)
    local moving = lidMotion.from ~= lidMotion.to
    updateSound("press", lid, 90, moving and lidMotion.start, lidMotion.duration, true, now)
    updateSound("crushing", lid, 90, lidMotion.shake and lidMotion.start, lidMotion.duration, false, now)
    local stopTime
    if lidMotion.shake then stopTime = lidMotion.start
    elseif moving and lidMotion.to == -90 then stopTime = lidMotion.start + lidMotion.duration end
    updateSound("lid_stop", lid, 60, stopTime, 574, false, now)
end

addEventHandler("onClientPreRender",root,function(frameTime)
    if not hookMotion or not lidMotion then return end
    clockOffset = clockOffset+(desiredOffset-clockOffset)*math.min(1,frameTime/300)
    local now = getTickCount()+clockOffset
    processMachineAudio(now)
    if renderedRevision == revision then return end
    local px,py = getCameraMatrix()
    if (px-Crusher.drop[1])^2+(py-Crusher.drop[2])^2 > 200^2 then return end
    if now >= math.max(hookMotion.start+hookMotion.duration,lidMotion.start+lidMotion.duration) and isElement(hook) then renderedRevision = revision end
    local x,y,z,yaw,angle = cranePose(hookMotion,now)
    if not isElement(hook) then hook = getElementByID("car_crusher:hook") end
    if hook then
        -- Local presentation of the replicated parent also interpolates its attached car.
        setElementPosition(hook,x,y,z,false)
        setElementRotation(hook,0,0,yaw)
    end
    if parts.magnet then setElementPosition(parts.magnet,x,y,z,false) end
    if parts.doc_crane_cab then setElementRotation(parts.doc_crane_cab,0,0,angle) end
    local tilt,dx,dy = crusherLidPose(lidMotion,now)
    for _, name in ipairs({"crushertop","crushercrush"}) do
        local part,rest = parts[name],Crusher.parts[name]
        if part then setElementPosition(part,rest[1]+dx,rest[2]+dy,rest[3],false) end
    end
    if parts.crushertop then setElementRotation(parts.crushertop,tilt,0,Crusher.rotation,"ZXY") end
end)

addEvent("car_crusher:message", true)
addEventHandler("car_crusher:message", resourceRoot, function(text)
    exports.frontend:showVcsGarageGameText(text, 5000)
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    for _, part in pairs(parts) do destroyElement(part) end
    for _, id in ipairs(models) do engineFreeModel(id) end
end)
