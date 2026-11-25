-- USA PS2 cAudioManager::ProcessFires (001C3810), ProcessExplosions
-- (001C35A8), vehicle damage (001BB760) and ped weapon events (001BFBC0).
local samples = {
    ground = {file="fire", rate=16794, radius=80, volume=80, looped=true, pooled=true, releaseFrames=10},
    building = {file="fire", rate=16794, pitch=13435, radius=80, volume=100, looped=true, pooled=true, releaseFrames=10},
    ped = {file="ped_fire", rate=22041, radius=25, volume=60, looped=true, pooled=true, releaseFrames=10},
    vehicle = {file="fire", rate=16794, radius=30, volume=60, looped=true, releaseFrames=3},
    flamethrowerStart = {file="flamethrower_start", rate=28000, radius=60, volume=85, variation=1750},
    flamethrower = {file="flamethrower", rate=11025, radius=60, volume=105, looped=true, releaseFrames=6},
    explosion = {file="explosion", rate=20000, radius=200, volume=127, pitch=19500, variation=1000, burst=true},
    grenade = {file="explosion", rate=20000, radius=200, volume=127, pitch=19000, variation=1000, burst=true},
    heliExplosion = {file="explosion", rate=20000, radius=200, volume=127, pitch=19500, variation=1000, scale=0.8, burst=true},
    molotov = {file="molotov", rate=20000, radius=150, volume=127, pitch=19000, variation=1000, burst=true},
    mine = {file="mine", rate=23000, radius=200, volume=127, pitch=12347, variation=1000, burst=true},
}
-- MTA inserts "rocket weak" at 3. Confirm a corresponding original type
-- before mapping an SA-only event into the VCS selector at 001C35A8.
local explosionKinds = {
    [0]="grenade",[1]="molotov",[2]="grenade",[4]="explosion",[5]="explosion",
    [6]="explosion",[7]="heliExplosion",[8]="mine",[9]="grenade",[10]="grenade",
}

local voices, releasing, nextId = {}, {}, 0

local function release(voice,fade)
    local handle = voice.sound
    if isElement(handle) then
        local frames = fade and voice.sample.releaseFrames
        local level = math.floor((voice.volume or 0)*127+0.5)
        if frames and level>0 then
            -- 002A8218 keeps an unrequested loop at its last position and
            -- subtracts at least one volume unit per original audio frame.
            releasing[handle]={owner=voice.owner,interior=voice.interior,dimension=voice.dimension,
                start=getTickCount(),frames=frames,level=level,loss=math.max(1,math.floor(level/frames))}
        else stopSound(handle) end
    end
    voice.sound = nil
end

-- SLUS 001B56C0 scales the vertical separation before calculating distance.
-- 002A7120 keeps the first fifth at full volume, then squares the roll-off.
local function calculateVolume(voice, cx, cy, cz, interior, dimension)
    if voice.interior ~= interior or voice.dimension ~= dimension then return 0 end
    local dx, dy, dz = cx-voice.x, cy-voice.y, (cz-voice.z)*0.65
    local distance = math.sqrt(dx*dx + dy*dy + dz*dz)
    local sample = voice.sample
    local gain = math.min(1, math.max(0, (sample.radius-distance)/(sample.radius*0.8)))
    return math.min(127,math.floor((voice.level or sample.volume)*gain*gain)) / 127
end

local function startSound(voice, volume)
    local sample = voice.sample
    local sound = playSound3D("audio/"..sample.file..".wav",voice.x,voice.y,voice.z,sample.looped or false)
    if not sound then return false end
    voice.sound = sound
    setElementDimension(sound, voice.dimension)
    setElementInterior(sound, voice.interior)
    -- Retain BASS directional panning; the PS2 calculation supplies all roll-off.
    local maxDistance = sample.radius / 0.65 + 1
    setSoundMaxDistance(sound, maxDistance+1)
    setSoundMinDistance(sound, maxDistance)
    setSoundVolume(sound, volume)
    setSoundSpeed(sound, voice.speed)
    if sample.looped then
        local length = getSoundLength(sound)
        if length and length > 0 then
            local elapsed = (getTickCount()-voice.started) / 1000
            setSoundPosition(sound, (elapsed*voice.speed) % length)
        end
    end
    return true
end

function PlayFireSound(kind, x, y, z, interior, dimension, slot, ageMs)
    if type(kind)=="number" then kind=explosionKinds[kind] end
    local sample = samples[kind]
    if not sample or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number"
        or (slot ~= nil and type(slot) ~= "number") or (ageMs ~= nil and type(ageMs) ~= "number") then return false end
    nextId = nextId + 1
    local id = nextId
    local priority = slot or id
    local pitch = sample.pitch or sample.rate
    if sample.pooled then pitch = pitch + math.floor(pitch/256) * ((slot or 0) % 40) end
    if kind == "flamethrower" then pitch = pitch + ((slot or 0)*10) % 2048 end
    if sample.variation then pitch = pitch + math.random(1-sample.variation,sample.variation-1) end
    if sample.scale then pitch=math.floor(pitch*sample.scale) end
    local voice = {
        kind=kind, sample=sample, x=x, y=y, z=z, interior=interior or 0, dimension=dimension or 0,
        owner=sourceResource or getThisResource(), priority=priority, slot=slot or 0, speed=pitch/sample.rate,
        started=getTickCount()-math.max(0,ageMs or 0)
    }
    if not sample.looped then
        local cx, cy, cz = getCameraMatrix()
        local volume = calculateVolume(voice,cx,cy,cz,getCameraInterior(),getElementDimension(localPlayer))
        if volume <= 0 or not startSound(voice,volume) then return false end
    end
    voices[id] = voice
    return id
end

function MoveFireSound(id,x,y,z)
    local voice = voices[id]
    if not voice or voice.owner ~= (sourceResource or getThisResource())
        or type(x) ~= "number" or type(y) ~= "number" or type(z) ~= "number" then return false end
    voice.x, voice.y, voice.z = x, y, z
    if isElement(voice.sound) then setElementPosition(voice.sound,x,y,z) end
    local hiss = voices[voice.hiss]
    if hiss then
        hiss.x,hiss.y,hiss.z=x,y,z
        if isElement(hiss.sound) then setElementPosition(hiss.sound,x,y,z) end
    end
    return true
end

-- 001C3A80 tests CFire's water flag and queues bank 0 sample 188.
-- Each refresh reuses the slot. The release request has 20 frames to play.
local waterReleaseMs = 20*1000/30
function ReportWaterExtinguish(id,strength)
    local fire = voices[id]
    if not fire or fire.owner ~= (sourceResource or getThisResource()) or type(strength) ~= "number"
        or not (fire.sample.pooled or fire.kind=="vehicle") then return false end
    local hiss = voices[fire.hiss]
    if not hiss then
        nextId=nextId+1
        fire.hiss=nextId
        hiss={
            sample={file="extinguish",looped=true,radius=fire.sample.radius,volume=0},
            x=fire.x,y=fire.y,z=fire.z,dimension=fire.dimension,interior=fire.interior,
            owner=fire.owner,started=getTickCount(),speed=(23000+89*(fire.slot%40))/22050
        }
        voices[nextId]=hiss
    end
    hiss.waterLevel=math.floor(math.max(0,strength)*400)%256
    hiss.expires=getTickCount()+waterReleaseMs
    return true
end

function StopFireSound(id)
    local voice = voices[id]
    if not voice or voice.owner ~= (sourceResource or getThisResource()) then return false end
    release(voice,true)
    voices[id] = nil
    return true
end

addEventHandler("onClientPreRender", root, function()
    if not next(voices) and not next(releasing) then return end
    local cx, cy, cz = getCameraMatrix()
    local interior, dimension = getCameraInterior(), getElementDimension(localPlayer)
    local firstId
    local now=getTickCount()
    for handle,tail in pairs(releasing) do
        local frame=math.floor((now-tail.start)*30/1000)
        local level=tail.level-frame*tail.loss
        if not isElement(handle) or level<=0 or frame>=tail.frames
            or tail.interior~=interior or tail.dimension~=dimension then
            if isElement(handle) then stopSound(handle) end
            releasing[handle]=nil
        else setSoundVolume(handle,level/127) end
    end
    for id, voice in pairs(voices) do
        if voice.expires then
            voice.level=voice.waterLevel*math.max(0,(voice.expires-now)/waterReleaseMs)
        end
        voice.volume = calculateVolume(voice,cx,cy,cz,interior,dimension)
        if voice.sample.pooled and voice.volume > 0 and
            (not firstId or voice.priority < voices[firstId].priority or
            (voice.priority == voices[firstId].priority and id < firstId)) then firstId = id end
    end
    for id, voice in pairs(voices) do
        if voice.expires and now>=voice.expires then
            release(voice)
            voices[id]=nil
        elseif not voice.sample.looped and not isElement(voice.sound) then
            voices[id] = nil
        elseif voice.sample.looped and (voice.volume <= 0 or (voice.sample.pooled and id ~= firstId)) then
            release(voice,voice.volume>0)
        elseif isElement(voice.sound) then
            setSoundVolume(voice.sound,voice.volume)
        elseif not startSound(voice,voice.volume) then
            voices[id] = nil
        end
    end
end)

-- gta-reversed CAEFireAudioEntity::PlayFireSounds, CAEExplosionAudioEntity::
-- AddAudioEvent and CAEWeaponAudioEntity::PlayFlameThrowerSounds. Scope the
-- cancellation to a registered VCS source because these slots have other users.
addEventHandler("onClientWorldSound", root, function(group,index,x,y,z)
    if not next(voices) or not x then return end
    local fire = group == 4 and index == 0
    local explosion = group == 4 and index >= 2 and index <= 4
    local secondaryFire = group == 19 and index == 26
    local flameTrigger = group == 5 and index == 83
    if not (fire or explosion or secondaryFire or flameTrigger) then return end
    local entityType = getElementType(source)
    local flameWeapon = (entityType == "ped" or entityType == "player") and getPedWeapon(source) == 37
    local interior, dimension = getCameraInterior(), getElementDimension(localPlayer)
    for _,voice in pairs(voices) do
        local kind = voice.kind
        local burning = voice.sample.pooled or kind == "vehicle"
        local burst = voice.sample.burst
        local weapon = kind == "flamethrower" or kind == "flamethrowerStart"
        local match = (fire and burning) or (explosion and burst)
            or (secondaryFire and burning and source == root)
            or ((secondaryFire or flameTrigger) and weapon and flameWeapon)
        if match and voice.dimension == dimension and voice.interior == interior
            and getDistanceBetweenPoints3D(x,y,z,voice.x,voice.y,voice.z) < 1.5 then
            cancelEvent()
            return
        end
    end
end)

addEventHandler("onClientResourceStop", root, function(stopped)
    for handle,tail in pairs(releasing) do
        if tail.owner==stopped then
            if isElement(handle) then stopSound(handle) end
            releasing[handle]=nil
        end
    end
    for id, voice in pairs(voices) do
        if voice.owner == stopped then
            release(voice)
            voices[id] = nil
        end
    end
end)
