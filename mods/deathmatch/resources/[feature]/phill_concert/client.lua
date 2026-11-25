local audioPath = "assets/concert.ogg"
-- SCM cue differences agree with the original animation resyncs at 44.1 kHz.
local scriptRate = 44100
local session
local offer = false
local sx, sy = guiGetScreenSize()

local function skygfxRunning()
    local resource = getResourceFromName("skygfx")
    return resource and getResourceState(resource) == "running"
end

local function send(event, ...)
    triggerServerEvent("phillConcert:" .. event, resourceRoot, ...)
end

local function restore()
    local previous = session
    session = nil
    if not previous then return end
    if isElement(previous.sound) then destroyElement(previous.sound) end
    if isTimer(previous.stageTimer) then killTimer(previous.stageTimer) end
    if isTimer(previous.exitTimer) then killTimer(previous.exitTimer) end
    destroyConcertLights(previous)
    destroyConcertCast(previous)
    if previous.hud then
        local frontend = getResourceFromName("frontend")
        if frontend and getResourceState(frontend) == "running" then exports.frontend:setGameplayUiVisible(true) end
        for component, visible in pairs(previous.hud) do setPlayerHudComponentVisible(component, visible) end
        showChat(previous.chat)
        setTime(unpack(previous.worldTime))
        if previous.vcsWeather and skygfxRunning() then
            exports.skygfx:setVcsWeather(previous.vcsWeather)
        else
            exports.interior:setOutdoorWeather(unpack(previous.weather))
        end
        setElementData(localPlayer, "phill_concert:weatherOverride", false, false)
    end
    if previous.controls then
        for control, enabled in pairs(previous.controls) do toggleControl(control, enabled) end
        setCameraInterior(getElementInterior(localPlayer))
        setCameraTarget(localPlayer)
        fadeCamera(true, 0.5)
    end
end

local function finish()
    if not session or session.finishing then return end
    session.finishing = true
    send("finish", session.id)
end

local function skip()
    if not session or not session.started or session.finishing or session.exitTimer then return end
    session.faded = true
    fadeCamera(false, 0.5)
    session.exitTimer = setTimer(finish, 550, 1)
end

local function presentationTime(scene, audioTime, dt)
    local previous = scene.seconds or scene.start
    if not scene.audioAdvanced then
        scene.audioAdvanced = audioTime > scene.start
        return math.max(scene.start, audioTime)
    end
    if audioTime > previous + 0.2 then return audioTime end
    -- Audio position can repeat across render frames. Advance with render
    -- time between samples, steering gently back toward the audio clock.
    local predicted = previous + dt
    local correction = math.max(-0.1, math.min(0.1, (audioTime - predicted) * 4))
    return math.max(previous, math.min(audioTime + 0.05, predicted + dt * correction))
end

local function cameraAt(scene, seconds)
    local camera = scene.camera
    if not camera then return end
    if not camera.from then return camera.to end
    local factor = math.max(0, math.min(1, (seconds - camera.time) / camera.duration))
    local matrix = {}
    for i = 1, 6 do
        matrix[i] = camera.from[i] + (camera.to[i] - camera.from[i]) * factor
    end
    return matrix
end

local function renderTimeline(scene, seconds)
    local cursor = seconds * scriptRate
    local event = ConcertTimeline[scene.next]
    while event and event[1] <= cursor do
        local time = event[1] / scriptRate
        if event[2] == "camera" then
            local duration = event[9] / 1000
            scene.camera = {
                from = duration > 0 and cameraAt(scene, time) or nil,
                to = {unpack(event, 3, 8)}, time = time, duration = duration
            }
        elseif event[2] == "fadeAudio" then
            scene.fadeTime = time
        elseif event[2] == "lights" then
            scene.ensembleLights = time
        elseif event[2] == "holdLights" then
            scene.lightCycleStop = time
        elseif event[2] == "spot" then
            scene.spot = event[3] == 1
        elseif scene.actors and not applyConcertActorEvent(scene, event, time) then
            outputDebugString("[phill_concert] Could not apply " .. event[2] .. " at " .. time, 2)
        end
        scene.next = scene.next + 1
        event = ConcertTimeline[scene.next]
    end
    local matrix = cameraAt(scene, seconds)
    if matrix then setCameraMatrix(unpack(matrix)) end
    local remaining = ConcertEnd / scriptRate - seconds
    if scene.fadeTime and isElement(scene.sound) then
        setSoundVolume(scene.sound, math.min(1, math.max(0, remaining / 1.0)))
    end
    if scene.actors then updateConcertCast(scene, seconds) end
    if scene.started then
        updateConcertLights(scene, seconds)
        if remaining <= 0.5 and not scene.faded then
            scene.faded = true
            fadeCamera(false, math.max(0, remaining))
        end
        if remaining <= 0 and not scene.exitTimer then finish() end
    end
end

local function onEvent(name, callback)
    addEvent("phillConcert:" .. name, true)
    addEventHandler("phillConcert:" .. name, resourceRoot, callback)
end

local function closeTicketOffer()
    offer = false
    local frontend = getResourceFromName("frontend")
    if frontend and getResourceState(frontend) == "running" then exports.frontend:showTextBox(false) end
end

local function ticketPrice(price)
    -- RE_PHI and RE_PHIN use ~h~ for the price in VCS PS2.
    return ("#1EFFFF$%d#FFFFFF"):format(price)
end

onEvent("offer", function(show, price)
    if not show then
        closeTicketOffer()
    elseif not session and not offer then
        offer = exports.frontend:showTextBox("Pay " .. ticketPrice(price)
            .. " to buy access to\nthe Phil Collins concert?\nEnter to buy.\nBackspace to exit.", 0)
    end
end)

onEvent("ticketDenied", function(price)
    offer = false
    exports.frontend:showTextBox("You need " .. ticketPrice(price)
        .. " to buy access to\nthe Phil Collins concert.", 3000)
end)

onEvent("prepare", function(id, debugStart)
    restore()
    closeTicketOffer()
    session = {id = id, start = debugStart or 0, debug = debugStart ~= nil, next = 1}
    session.sound = playSound(audioPath, false)
    if not isElement(session.sound) then
        outputChatBox("The concert audio could not load.", 255, 205, 225)
        send("finish", id)
        return
    end
    setSoundPaused(session.sound, true)
    setSoundPosition(session.sound, session.start)
    session.controls = {}
    for _, control in ipairs({"forwards", "backwards", "left", "right", "jump", "sprint",
        "fire", "aim_weapon", "enter_exit", "action", "crouch", "next_weapon", "previous_weapon"}) do
        session.controls[control] = isControlEnabled(control)
        toggleControl(control, false)
    end
    fadeCamera(false, 0.35)
    session.stageTimer = setTimer(send, 400, 1, "ready", id)
end)

onEvent("inside", function(id)
    if not session or session.id ~= id then return end
    setCameraInterior(ConcertStadium.interior)
    setCameraMatrix(-1548.17, 1335.58, -221.78, -1549.13, 1335.53, -222.05)
    local scene = session
    local attempts = 0
    session.stageTimer = setTimer(function()
        if session ~= scene or scene.finishing then return end
        attempts = attempts + 1
        local hit, _, _, _, floor = processLineOfSight(-1574.58, 1337.27, -227,
            -1574.58, 1337.27, -234, true, false, false, true, false)
        local ready = hit and isElement(floor)
            and getElementInterior(floor) == ConcertStadium.interior
            and getElementDimension(floor) == ConcertStadium.dimension
            and getElementInterior(localPlayer) == ConcertStadium.interior
            and getElementDimension(localPlayer) == ConcertStadium.dimension
        if ready then
            killTimer(scene.stageTimer)
            local loaded, asset = makeConcertCast(session)
            if not loaded then
                outputChatBox("Concert could not load " .. asset .. ".", 255, 205, 225)
                finish()
                return
            end
            renderTimeline(session, session.start)
            send("stageReady", id)
        elseif attempts >= 100 then
            killTimer(scene.stageTimer)
            outputDebugString("[phill_concert] Stadium collision did not stream in interior "
                .. ConcertStadium.interior .. ", dimension " .. ConcertStadium.dimension, 2)
            exports.frontend:showTextBox("The concert stadium could not load. Please try again.", 3000)
            finish()
        end
    end, 100, 100)
end)

onEvent("play", function(id)
    if not session or session.id ~= id then return end
    session.hud, session.chat = {}, isChatVisible()
    exports.frontend:setGameplayUiVisible(false)
    for _, component in ipairs({"ammo", "area_name", "armour", "breath", "clock", "health",
        "money", "radar", "vehicle_name", "weapon", "radio", "wanted", "crosshair"}) do
        session.hud[component] = isPlayerHudComponentVisible(component)
        setPlayerHudComponentVisible(component, false)
    end
    if not session.debug then showChat(false) end
    setElementData(localPlayer, "phill_concert:weatherOverride", true, false)
    session.worldTime = {getTime()}
    session.weather = {exports.interior:getOutdoorWeather()}
    if skygfxRunning() then
        session.vcsWeather = exports.skygfx:getOutdoorWeather()
    end
    if not session.vcsWeather or not exports.skygfx:setVcsWeather(3) then
        exports.interior:setOutdoorWeather(3)
    end
    setTime(0, 0)
    session.started = getTickCount()
    setSoundPaused(session.sound, false)
    fadeCamera(true, 0.5)
end)

onEvent("exit", function(id)
    if session and id == session.id then restore() end
end)

bindKey("enter", "down", function()
    if session and session.started then
        skip()
    elseif offer and not session then
        closeTicketOffer()
        send("buy")
    end
end)
bindKey("backspace", "down", function()
    if not session then closeTicketOffer() end
end)

addEventHandler("onClientPreRender", root, function(timeSlice)
    if not session or not session.started or session.finishing or session.exitTimer then return end
    local audioTime = getSoundPosition(session.sound)
    if not audioTime then finish() return end
    local seconds = presentationTime(session, audioTime, timeSlice / 1000)
    session.seconds = seconds
    setTime(0, 0)
    renderTimeline(session, seconds)
end)

addEventHandler("onClientPedsProcessed", root, function()
    if session and session.seconds and not session.finishing then
        updateConcertBones(session)
    end
end)

addEventHandler("onClientRestore", root, function()
    if not session or not session.started then return end
    for _, actor in pairs(session.actors) do
        if actor.clip then actor.seekPending = true end
    end
end)

addEventHandler("onClientRender", root, function()
    if session and session.started then
        if session.seconds then drawConcertCrowdFlashes(session, session.seconds) end
        local height = math.max(0, (sy - sx / 2.35) / 2)
        dxDrawRectangle(0, 0, sx, height, tocolor(0, 0, 0))
        dxDrawRectangle(0, sy - height, sx, height, tocolor(0, 0, 0))
        if session.debug then
            local status = ("Phil Collins Concert  |  %.1fs  |  Enter: Skip"):format(session.seconds or session.start)
            dxDrawText(status, 0, sy - 25, sx, sy, tocolor(255, 255, 255, 230), 1, "default-bold", "center", "top")
        end
    end
end)

addEventHandler("onClientResourceStop", resourceRoot, function()
    closeTicketOffer()
    restore()
end)
