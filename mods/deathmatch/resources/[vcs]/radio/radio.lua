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
local active, prepared, fading, online

local function destroy(element)
    if isElement(element) then destroyElement(element) end
end

local function kill(timer)
    if isTimer(timer) then killTimer(timer) end
end

local function clearPlayback()
    kill(streamTimer)
    streamTimer = nil
    local old, nextSound, tail, stream = active, prepared, fading, online
    active, prepared, fading, online = nil, nil, nil, nil
    destroy(old and old.sound)
    destroy(nextSound and nextSound.sound)
    destroy(tail and tail.sound)
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

local function loadSegment(station, index)
    local segment = station.segments[index]
    local data = RadioPack.readSegment(pack, segment)
    if not data then return nil end
    local sound = playSound(data, false)
    if not isElement(sound) then return nil end
    setSoundVolume(sound, 0)
    setSoundPaused(sound, true)
    return {sound = sound, station = station, index = index, seconds = segment.seconds}
end

local function nextSegment(current)
    return current.index % #current.station.segments + 1
end

local function advance(elapsed, crossfade)
    local previous = active
    local incoming = prepared or loadSegment(previous.station, nextSegment(previous))
    prepared = nil
    if not incoming then
        unavailable("unable to decode next segment")
        return
    end
    active = incoming
    if elapsed > 0 then setSoundPosition(incoming.sound, elapsed) end
    if crossfade then
        fading = previous
    else
        destroy(previous.sound)
        setSoundVolume(incoming.sound, volume)
    end
    setSoundPaused(incoming.sound, false)
end

local function updatePlayback()
    if not active or not isElement(active.sound) then return end
    local position = getSoundPosition(active.sound)
    if not position then return end

    if fading and not isElement(fading.sound) then
        fading = nil
        setSoundVolume(active.sound, volume)
    end
    if fading then
        local fade = math.min(1, position / RadioPack.overlap)
        setSoundVolume(active.sound, fade * volume)
        setSoundVolume(fading.sound, (1 - fade) * volume)
        if fade == 1 then
            destroy(fading.sound)
            fading = nil
        end
    end

    local remaining = active.seconds - position
    if not fading and remaining <= 0 then
        local elapsed = -remaining
        advance(elapsed, elapsed < RadioPack.overlap)
    elseif not prepared and not active.prefetched and remaining <= prefetchSeconds then
        active.prefetched = true
        prepared = loadSegment(active.station, nextSegment(active))
    end
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
    local station = pack and pack.stations[id]
    if not station then
        unavailable("PS2 audio pack is unavailable")
        return
    end
    local time = getRealTime()
    local seconds = time.hour * 3600 + time.minute * 60 + time.second
    local frame = (seconds * RadioPack.rate) % station.total
    local index = math.floor(frame / RadioPack.segmentFrames) + 1
    active = loadSegment(station, index)
    if not active then
        unavailable("unable to decode " .. stations[id])
        return
    end
    local position = (frame % RadioPack.segmentFrames) / RadioPack.rate
    setSoundPosition(active.sound, position)
    setSoundVolume(active.sound, volume)
    setSoundPaused(active.sound, false)
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
addEventHandler("onClientPreRender", root, updatePlayback)

addEventHandler("onClientSoundStopped", root, function(reason)
    if reason ~= "finished" then return end
    if active and source == active.sound then
        if fading then destroy(fading.sound) end
        fading = nil
        advance(0, false)
    elseif source == online then
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
