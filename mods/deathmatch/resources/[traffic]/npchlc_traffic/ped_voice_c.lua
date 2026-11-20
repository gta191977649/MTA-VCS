local playing = {}

local function stopVoice(ped)
    local voice = playing[ped]
    playing[ped] = nil
    if voice and isElement(voice.sound) then stopSound(voice.sound) end
end

local function updateGain(ped,voice,cx,cy,cz)
    local x,y,z=getElementPosition(ped)
    z=z+0.65
    local distance=getDistanceBetweenPoints3D(cx,cy,cz,x,y,z)
    local gain=math.max(0,math.min(1,(voice.range-distance)/(voice.range*0.8)))^2
    if gain>0 and not isLineOfSightClear(cx,cy,cz,x,y,z,true,false,false,false,false) then
        gain=gain*31/127
    end
    setSoundVolume(voice.sound,gain)
end

addEvent("npchlc_traffic:pedVoice",true)
addEventHandler("npchlc_traffic:pedVoice",resourceRoot,function(ped, clip, range)
    if not isElement(ped) or not isElementStreamedIn(ped)
        or getElementInterior(ped) ~= getElementInterior(localPlayer)
        or getElementDimension(ped) ~= getElementDimension(localPlayer) then return end
    stopVoice(ped)
    local x,y,z = getElementPosition(ped)
    local cx,cy,cz = getCameraMatrix()
    local distance = getDistanceBetweenPoints3D(cx,cy,cz,x,y,z+0.65)
    if distance >= range then return end
    local sound = playSound3D(clip,x,y,z+0.65,false)
    if not sound then return end
    setElementInterior(sound,getElementInterior(ped))
    setElementDimension(sound,getElementDimension(ped))
    -- playSound3D supplies panning. Apply the PS2 distance curve exactly once.
    setSoundMaxDistance(sound,range)
    setSoundMinDistance(sound,range)
    if not attachElements(sound,ped,0,0,0.65) then
        stopSound(sound)
        return
    end
    local voice={sound=sound,range=range}
    playing[ped]=voice
    updateGain(ped,voice,cx,cy,cz)
    addEventHandler("onClientElementDestroy",sound,function()
        if playing[ped] == voice then playing[ped] = nil end
    end,false)
end,false)

setTimer(function()
    if not next(playing) then return end
    local cx,cy,cz=getCameraMatrix()
    for ped,voice in pairs(playing) do
        if not isElement(ped) or not isElement(voice.sound)
            or getElementDimension(ped)~=getElementDimension(localPlayer)
            or getElementInterior(ped)~=getElementInterior(localPlayer) then
            stopVoice(ped)
        else
            updateGain(ped,voice,cx,cy,cz)
        end
    end
end,100,0)

addEventHandler("onClientElementStreamOut",root,function()
    if playing[source] then stopVoice(source) end
end)
addEventHandler("onClientElementDestroy",root,function()
    if playing[source] then stopVoice(source) end
end)
