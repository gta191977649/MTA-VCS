local CAEAudioEnvironment = {}
local listenerMatrix, listenerOffset

function CAEAudioEnvironment.GetDistanceAttenuation(dist)
    if dist >= SoundAttenuationTable.maxDistance then return -100 end
    return SoundAttenuationTable.decibels[1 + math.floor(dist / SoundAttenuationTable.resolution)]
end

function CAEAudioEnvironment.GetDirectionalMikeAttenuation(pos)
    return -6 * math.max(0, math.min(1, (0.70710678-pos.y)/1.41421356))
end

function CAEAudioEnvironment.GetPositionRelativeToCamera(pos)
    local camera = listenerMatrix
    local delta = pos - (camera.position + camera.forward*listenerOffset)
    return Vector3(-delta:dot(camera.right), delta:dot(camera.forward), delta:dot(camera.up))
end

local CAESound = {}
CAESound.__index = CAESound

function CAESound:CalculateVolume()
    local relativePos = CAEAudioEnvironment.GetPositionRelativeToCamera(self.m_CurrPos)
    self.m_ListenerVolume = self.m_Volume - self.m_Headroom
        + CAEAudioEnvironment.GetDistanceAttenuation(relativePos.length/self.m_RollOffFactor)
        + CAEAudioEnvironment.GetDirectionalMikeAttenuation(relativePos)
    self.outOfRange = relativePos.length >= SoundAttenuationTable.maxDistance*self.m_RollOffFactor
end

local AESoundManager = {}
local voices, entities = {}, {}

function AESoundManager.PlaySound(params)
    local bank = params.AudioEntity.banks[params.BankSlotID]
    local sample = bank and bank.samples[params.SoundID]
    if not sample then return false end
    local vehicle = params.AudioEntity.m_Entity
    if not isElementStreamedIn(vehicle) then return false end
    local pos = params.Pos
    local handle = playSound3D(sample.Path,pos.x,pos.y,pos.z,true)
    if not handle then return false end
    setSoundVolume(handle,0)
    -- SA disables the DirectSound listener roll-off. Keep BASS spatialization
    -- and supply the attenuation from CalculateVolume only once.
    local radius = SoundAttenuationTable.maxDistance * params.RollOffFactor
    setSoundMaxDistance(handle,radius+1)
    setSoundMinDistance(handle,radius)
    setElementDimension(handle,getElementDimension(vehicle))
    setElementInterior(handle,getElementInterior(vehicle))
    setSoundSpeed(handle,params.Speed)
    attachElements(handle,vehicle)
    local sound = setmetatable({
        handle=handle, m_AudioEntity=params.AudioEntity, m_RollOffFactor=params.RollOffFactor,
        m_Volume=params.Volume, m_Headroom=sample.Headroom or 0, bank=bank
    },CAESound)
    voices[handle] = sound
    return sound
end

local CAEVehicleAudioEntity = {}
CAEVehicleAudioEntity.__index = CAEVehicleAudioEntity
local boatRollOff = {[2]=3.5,[3]=5,[6]=2.5} -- ENGINE, DISTANT, WATER_SKIM

function CAEVehicleAudioEntity:UpdateVehicleEngineSoundRawVolume(st,speed,volume)
    local sound = self.m_EngineSounds[st]
    if not sound or not isElement(sound.handle) then return false end
    sound.m_Volume = volume
    setSoundSpeed(sound.handle,speed)
    return true
end

function CAEVehicleAudioEntity:UpdateGenericVehicleSound(st,bankSlot,bank,sfx,speed,volume,rollOff)
    local binding = self.banks[bankSlot]
    if not binding or binding.id ~= bank or not binding.samples[sfx] then return false end
    volume = volume + self.m_EventVolume
    if not self:UpdateVehicleEngineSoundRawVolume(st,speed,volume) then
        self.m_EngineSounds[st] = AESoundManager.PlaySound({
            BankSlotID=bankSlot,SoundID=sfx,AudioEntity=self,Pos=Vector3(getElementPosition(self.m_Entity)),
            Volume=volume,RollOffFactor=rollOff,Speed=speed
        })
    end
    local sound = self.m_EngineSounds[st]
    return sound and sound.handle
end

function CAEVehicleAudioEntity:UpdateBoatSound(st,bankSlot,sfx,speed,volume)
    local binding = self.banks[bankSlot]
    if not binding or not boatRollOff[st] then return false end
    return self:UpdateGenericVehicleSound(st,bankSlot,binding.id,sfx,speed,volume,boatRollOff[st])
end

function CAEVehicleAudioEntity:StopGenericEngineSound(st)
    local sound = self.m_EngineSounds[st]
    if sound and isElement(sound.handle) then stopSound(sound.handle) end
    self.m_EngineSounds[st] = nil
end

-- MTA resources provide sample paths in place of the native bank loader.
-- Exported methods take the vehicle in place of the C++ implicit this pointer.
function BindVehicleSoundBank(vehicle,slot,bank,samples)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle"
        or type(slot) ~= "number" or type(bank) ~= "number" or type(samples) ~= "table" then return false end
    for _,sample in pairs(samples) do
        if type(sample) ~= "table" or type(sample.Path) ~= "string"
            or (sample.Headroom ~= nil and type(sample.Headroom) ~= "number") then return false end
    end
    local entity = entities[vehicle]
    if not entity then
        entity = setmetatable({m_Entity=vehicle,m_EventVolume=-3,m_EngineSounds={},banks={}},CAEVehicleAudioEntity)
        entities[vehicle] = entity
    end
    local previous = entity.banks[slot]
    if previous then
        for st,sound in pairs(entity.m_EngineSounds) do
            if sound and sound.bank == previous then entity:StopGenericEngineSound(st) end
        end
    end
    entity.banks[slot] = {id=bank,samples=samples,owner=sourceResource or getThisResource()}
    return true
end

function UpdateGenericVehicleSound(vehicle,st,bankSlot,bank,sfx,speed,volume,rollOff)
    local entity = entities[vehicle]
    if not entity or type(st)~="number" or type(speed)~="number" or type(volume)~="number"
        or type(rollOff)~="number" or rollOff<=0 then return false end
    return entity:UpdateGenericVehicleSound(st,bankSlot,bank,sfx,speed,volume,rollOff)
end

function UpdateBoatSound(vehicle,st,bankSlot,sfx,speed,volume)
    local entity = entities[vehicle]
    if not entity or type(speed)~="number" or type(volume)~="number" then return false end
    return entity:UpdateBoatSound(st,bankSlot,sfx,speed,volume)
end

function StopGenericEngineSound(vehicle,st)
    if entities[vehicle] then entities[vehicle]:StopGenericEngineSound(st) end
end

addEventHandler("onClientPreRender",root,function()
    if not next(voices) then return end
    local x,y,z,lx,ly,lz = getCameraMatrix()
    local forward = Vector3(lx-x,ly-y,lz-z):getNormalized()
    local axis = math.abs(forward.z)<0.9999 and Vector3(0,0,1) or Vector3(0,1,0)
    local right = forward:cross(axis):getNormalized()
    listenerMatrix = {position=Vector3(x,y,z),forward=forward,right=right,up=right:cross(forward)}
    listenerOffset = math.max(0,math.min(0.5,(listenerMatrix.position-Vector3(getElementPosition(localPlayer))).length-0.5))
    local dim,interior = getElementDimension(localPlayer),getCameraInterior()
    for handle,sound in pairs(voices) do
        local vehicle = sound.m_AudioEntity.m_Entity
        if not isElement(vehicle) or not isElementStreamedIn(vehicle) then
            stopSound(handle)
        else
            local vd,vi = getElementDimension(vehicle),getElementInterior(vehicle)
            if vd ~= getElementDimension(handle) then setElementDimension(handle,vd) end
            if vi ~= getElementInterior(handle) then setElementInterior(handle,vi) end
            sound.m_CurrPos = Vector3(getElementPosition(vehicle))
            sound:CalculateVolume()
            local audible = dim==vd and interior==vi and not sound.outOfRange
            setSoundVolume(handle,audible and 10^(sound.m_ListenerVolume/20) or 0)
        end
    end
end,true,"low")

addEventHandler("onClientElementDestroy",root,function()
    voices[source] = nil
    local entity = entities[source]
    if entity then
        for st in pairs(entity.m_EngineSounds) do entity:StopGenericEngineSound(st) end
        entities[source] = nil
    end
end)

addEventHandler("onClientResourceStop",root,function(stopped)
    for vehicle,entity in pairs(entities) do
        for st,sound in pairs(entity.m_EngineSounds) do
            if sound and sound.bank.owner==stopped then entity:StopGenericEngineSound(st) end
        end
        for slot,bank in pairs(entity.banks) do
            if bank.owner==stopped then entity.banks[slot]=nil end
        end
        if not next(entity.banks) then entities[vehicle]=nil end
    end
end)
