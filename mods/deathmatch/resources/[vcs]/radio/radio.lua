-- IDs 1–9 are the PS2 disc order. Preserve ID 10 for vehicles tuned to Smooth.
local stations = {
    "Flash FM", "V-Rock", "Paradise FM", "VCPR", "VCFL", "Wave 103",
    "Fresh 105 FM", "Radio Espantoso", "Emotion 98.3", "Smooth 95.3",
}
local onlineId = #stations
local onlineUrl = "https://23153.live.streamtheworld.com/SMOOTH953_AAC48.aac"
local volume, retuneDelay, prefetchSeconds = 0.7, 1000, 2
local pack, defaultHudVisible
local reloadSnapshot = "leeds_engine:radioHud"
local radioReady = false
local vehicle, selected, tuned = nil, 0, 0
local switchTimer, streamTimer, effect, effectIndex
local driving, cinema = {}, {}
-- Wave 103, Flash FM, Emotion 98.3 and V-Rock in disc station order IDs.
local rideStations = {6, 1, 9, 2}
local rideStation, lastRideStation
local online, cinemaMode
local envelope = 0

local function destroy(element)
    if isElement(element) then destroyElement(element) end
end

local function kill(timer)
    if isTimer(timer) then killTimer(timer) end
end

local function clearSegments(channel)
    for _,key in ipairs({"active","prepared","fading"}) do
        local segment=channel[key]
        channel[key]=nil
        destroy(segment and segment.sound)
    end
end

local function clearPlayback()
    kill(streamTimer)
    streamTimer = nil
    clearSegments(driving)
    local stream=online
    online=nil
    destroy(stream)
end

local function display(text, waiting, hide)
    exports.frontend:showGameText(text, waiting and "radioTuning" or "radio", hide and 2000 or 0)
end

local function stationLabel(id)
    if id == 0 then return exports.frontend:getVcsText("FEA_NON") or "Radio Off" end
    if id == onlineId then return stations[id] end
    return exports.frontend:getVcsText("FEA_FM" .. (id - 1)) or stations[id]
end

local function unavailable(reason)
    clearPlayback()
    display(stations[selected] .. " unavailable", false, true)
    outputDebugString("radio: " .. reason, 2)
end

local function playEffect(power)
    destroy(effect)
    local name = "radio_click"
    if not power then
        effectIndex = ((effectIndex or 0) + math.random(1, 2) - 1) % 3 + 1
        name = "radio_dial" .. effectIndex
    end
    effect = exports.frontend:playVcsFrontendSound(name)
    if isElement(effect) then
        setSoundVolume(effect, power and volume or volume * 103 / 127)
    end
end

local function loadSegment(channel, station, index)
    local segment = station.segments[index]
    local data = RadioPack.readSegment(pack, segment)
    if not data then return nil end
    local sound = playSound(data, false)
    if not isElement(sound) then return nil end
    setSoundVolume(sound, 0)
    setSoundPaused(sound, true)
    if channel == cinema then
        setSoundEffectEnabled(sound,"parameq",true)
        setSoundEffectParameter(sound,"parameq","center",300)
        setSoundEffectParameter(sound,"parameq","bandwidth",18)
        setSoundEffectParameter(sound,"parameq","gain",-4)
        setSoundEffectEnabled(sound,"reverb",true)
        setSoundEffectParameter(sound,"reverb","reverbMix",-19)
        setSoundEffectParameter(sound,"reverb","reverbTime",600)
    end
    return {sound = sound, station = station, index = index, seconds = segment.seconds}
end

local function nextSegment(current)
    return current.index % #current.station.segments + 1
end

local function advance(channel, elapsed, crossfade, gain)
    local previous = channel.active
    local incoming = channel.prepared or loadSegment(channel, previous.station, nextSegment(previous))
    channel.prepared = nil
    if not incoming then
        if channel==driving then unavailable("unable to decode next segment") else clearSegments(channel) end
        return
    end
    channel.active = incoming
    if elapsed > 0 then setSoundPosition(incoming.sound, elapsed) end
    if crossfade then
        channel.fading = previous
    else
        destroy(previous.sound)
        setSoundVolume(incoming.sound, gain)
    end
    setSoundPaused(incoming.sound, false)
end

local function updatePlayback(channel,gain)
    if not channel.active or not isElement(channel.active.sound) then return end
    local position = getSoundPosition(channel.active.sound)
    if not position then return end

    if channel.fading and not isElement(channel.fading.sound) then
        channel.fading = nil
        setSoundVolume(channel.active.sound, gain)
    end
    if channel==cinema and not channel.fading then setSoundVolume(channel.active.sound,gain) end
    if channel.fading then
        local fade = math.min(1, position / RadioPack.overlap)
        setSoundVolume(channel.active.sound, fade * gain)
        setSoundVolume(channel.fading.sound, (1 - fade) * gain)
        if fade == 1 then
            destroy(channel.fading.sound)
            channel.fading = nil
        end
    end

    local remaining = channel.active.seconds - position
    if not channel.fading and remaining <= 0 then
        local elapsed = -remaining
        advance(channel, elapsed, elapsed < RadioPack.overlap,gain)
    elseif not channel.prepared and not channel.active.prefetched and remaining <= prefetchSeconds then
        channel.active.prefetched = true
        channel.prepared = loadSegment(channel, channel.active.station, nextSegment(channel.active))
    end
end

local function startBroadcast(channel,id,gain)
    local station = pack and pack.stations[id]
    if not station then
        return false
    end
    local time = getRealTime()
    local seconds = time.hour * 3600 + time.minute * 60 + time.second
    local frame = (seconds * RadioPack.rate) % station.total
    local index = math.floor(frame / RadioPack.segmentFrames) + 1
    channel.active = loadSegment(channel, station, index)
    if not channel.active then
        return false
    end
    local position = (frame % RadioPack.segmentFrames) / RadioPack.rate
    setSoundPosition(channel.active.sound, position)
    setSoundVolume(channel.active.sound, gain)
    setSoundPaused(channel.active.sound, false)
    return true
end

function setCinematicRadio(mode)
    if mode~="playing" and mode~="paused" and mode~="off" then return false end
    cinemaMode=mode
    if mode=="playing" and not cinema.active then
        if not rideStation then
            local choices={}
            for _,id in ipairs(rideStations) do
                if id~=lastRideStation then choices[#choices+1]=id end
            end
            rideStation=choices[math.random(#choices)]
        end
        if not startBroadcast(cinema,rideStation,0) then return false end
        lastRideStation=rideStation
    elseif mode=="off" and not cinema.active then
        rideStation=nil
    end
    return true
end

local function startStation(id)
    if id == 0 then
        display(stationLabel(0), false, true)
        return
    end
    if id == onlineId then
        online = playSound(onlineUrl, false)
        if not isElement(online) then
            unavailable("unable to create Smooth 95.3 stream")
            return
        end
        setSoundVolume(online, volume)
        streamTimer = setTimer(function()
            unavailable("Smooth 95.3 connection timed out")
        end, 12000, 1)
        return
    end
    if not startBroadcast(driving,id,volume) then
        unavailable("unable to start " .. stations[id])
        return
    end
    display(stationLabel(id), false, true)
end

local function leaveVehicle()
    kill(switchTimer)
    switchTimer = nil
    clearPlayback()
    destroy(effect)
    effect, vehicle, selected, tuned = nil, nil, 0, 0
    local frontend = getResourceFromName("frontend")
    if frontend and getResourceState(frontend) == "running" then exports.frontend:hideGameText("radio") end
end

local function selectStation(id, retune)
    kill(switchTimer)
    switchTimer = nil
    selected = id
    setElementData(vehicle, "radio_station", id, false)
    clearPlayback()
    if retune then
        playEffect(false)
        display(stationLabel(id), true, false)
        local targetVehicle = vehicle
        switchTimer = setTimer(function()
            switchTimer = nil
            if not isElement(targetVehicle) or getPedOccupiedVehicle(localPlayer) ~= targetVehicle then return end
            if (id == 0) ~= (tuned == 0) then playEffect(true) end
            tuned = id
            startStation(id)
        end, retuneDelay, 1)
    else
        tuned = id
        if id == onlineId then display(stations[id], true, false) end
        startStation(id)
    end
end

local function enterVehicle(entered)
    leaveVehicle()
    vehicle = entered
    local id = getElementData(vehicle, "radio_station")
    if type(id) ~= "number" or id % 1 ~= 0 or id < 0 or id > onlineId then
        id = math.random(1, onlineId - 1)
    end
    selectStation(id, false)
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    local reason
    pack, reason = RadioPack.open()
    if not pack then outputDebugString("radio: " .. reason, 1) end
    local previous = getElementData(localPlayer, reloadSnapshot, false)
    if previous then
        defaultHudVisible = previous.visible
        setElementData(localPlayer, reloadSnapshot, nil, false)
    else
        defaultHudVisible = isPlayerHudComponentVisible("radio")
    end
    setPlayerHudComponentVisible("radio", false)
    setRadioChannel(0)
    radioReady = true
    local occupied = getPedOccupiedVehicle(localPlayer)
    if occupied then enterVehicle(occupied) end
end)

addEventHandler("onClientPlayerRadioSwitch", localPlayer, function(nativeId)
    if not radioReady then return end
    cancelEvent()
    if not vehicle or getPedOccupiedVehicle(localPlayer) ~= vehicle then return end
    local step
    if getKeyState("mouse_wheel_down") then
        step = 1
    elseif getKeyState("mouse_wheel_up") then
        step = -1
    elseif nativeId == 1 then
        step = 1
    elseif nativeId == 12 then
        step = -1
    end
    if step then selectStation((selected + step) % (onlineId + 1), true) end
end)

addEventHandler("onClientVehicleEnter", root, function(player)
    if player == localPlayer and radioReady then enterVehicle(source) end
end)

addEventHandler("onClientVehicleExit", root, function(player)
    if player == localPlayer and source == vehicle then leaveVehicle() end
end)

addEventHandler("onClientElementDestroy", root, function()
    if source == vehicle then leaveVehicle() end
end)

addEventHandler("onClientPlayerWasted", localPlayer, leaveVehicle)
addEventHandler("onClientPreRender", root, function(delta)
    updatePlayback(driving,volume)
    if not cinema.active then return end
    if cinemaMode=="playing" then envelope=math.min(1,envelope+delta/3000)
    else envelope=math.max(0,envelope-delta/2000) end
    if envelope==0 and cinemaMode~="playing" then
        clearSegments(cinema)
        if cinemaMode=="off" then rideStation=nil end
        return
    end
    updatePlayback(cinema,volume*.2*envelope*envelope*(3-2*envelope))
end)

addEventHandler("onClientSoundStopped", root, function(reason)
    if reason ~= "finished" then return end
    for _,channel in ipairs({driving,cinema}) do
        if channel.active and source == channel.active.sound then
            destroy(channel.fading and channel.fading.sound)
            channel.fading=nil
            advance(channel,0,false,channel==driving and volume or volume*.2*envelope*envelope*(3-2*envelope))
            return
        end
    end
    if source == online then
        unavailable("Smooth 95.3 disconnected")
    end
end)

addEventHandler("onClientSoundStream", root, function(success)
    if source ~= online then return end
    kill(streamTimer)
    streamTimer = nil
    if success then
        display(stations[onlineId], false, true)
    else
        unavailable("Smooth 95.3 connection failed")
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    radioReady = false
    clearSegments(cinema)
    leaveVehicle()
    if pack then
        fileClose(pack.file)
        pack = nil
    end
    if defaultHudVisible == nil then return end
    if getElementData(root, "leeds_engine:reloading", false) then
        setElementData(localPlayer, reloadSnapshot, {visible = defaultHudVisible}, false)
    else
        setPlayerHudComponentVisible("radio", defaultHudVisible)
    end
end)
