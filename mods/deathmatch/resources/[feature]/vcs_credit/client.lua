local elapsed, ending, scroll, fraction, tune, chatVisible
local hudVisibility = {}
local restored = true
local introMs, nominalHz = 3000, 30

function isCreditsRunning()
    return elapsed ~= nil
end

local function restoreScene()
    if restored then return end
    restored = true
    VCSCreditScene.stop()
    local frontend = getResourceFromName("frontend")
    if frontend and getResourceState(frontend) == "running" then
        exports.frontend:setGameplayUiVisible(true)
    end
    for component, visible in pairs(hudVisibility) do
        setPlayerHudComponentVisible(component, visible)
    end
    showChat(chatVisible)
end

local function stopTune()
    if isElement(tune) then destroyElement(tune) end
    tune = nil
end

local function finish()
    if ending then return end
    ending = 0
    stopTune()
end

local function update(dt)
    if isMainMenuActive() then return end
    if ending then
        ending = ending+dt
        if ending >= 1000 then restoreScene() end
        if ending >= 2000 then stopCredits() end
        return
    end
    local before = elapsed
    elapsed = elapsed+dt
    VCSCreditScene.update(elapsed)
    if elapsed < introMs then return end
    if before < introMs then
        tune = playSound("audio/theme.ogg", true)
        dt = elapsed-introMs
    end
    if isElement(tune) and before < introMs+3000 then
        local ticks = math.floor((elapsed-introMs)*nominalHz/4000)
        setSoundVolume(tune, math.min(1, math.max(0, ticks-3)*0.06))
    end
    fraction = fraction+dt*nominalHz/1000
    local frames = math.floor(fraction)
    fraction = fraction-frames
    scroll = scroll+frames*(getKeyState("space") and 20 or 1)
end

local function draw()
    if isMainMenuActive() then return end
    local w,h = guiGetScreenSize()
    if not restored then
        local alpha = VCSCreditScene.fadeAlpha(elapsed)
        if alpha and alpha > 0 then
            dxDrawRectangle(0,0,w,h,tocolor(0,0,0,math.min(255,alpha)))
        end
        if elapsed >= introMs and VCSCreditRoll.draw(scroll) and not ending then finish() end
    end
    if ending then
        local alpha = 255*(1-math.abs(1000-ending)/1000)
        dxDrawRectangle(0,0,w,h,tocolor(0,0,0,alpha))
    end
end

local function key(button, pressed)
    if isMainMenuActive() or isChatBoxInputActive() or isConsoleActive() then return end
    local skip = button == "enter" or button == "num_enter" or button == "backspace"
    if button == "space" or skip then
        cancelEvent()
        if pressed and skip then finish() end
    end
end

function startCredits()
    if isCreditsRunning() or not VCSCreditRoll.load() then return false end
    if VCSCreditScene.start() == false then return false end
    elapsed, ending, scroll, fraction, restored = 0,nil,48,0,false
    chatVisible = isChatVisible()
    for _, component in ipairs({"area_name", "vehicle_name"}) do
        hudVisibility[component] = isPlayerHudComponentVisible(component)
        setPlayerHudComponentVisible(component, false)
    end
    exports.frontend:setGameplayUiVisible(false)
    showChat(false)
    addEventHandler("onClientPreRender",root,update)
    addEventHandler("onClientRender",root,draw,false,"low-5")
    addEventHandler("onClientKey",root,key)
    return true
end

function stopCredits()
    if not isCreditsRunning() then return false end
    removeEventHandler("onClientKey",root,key)
    removeEventHandler("onClientRender",root,draw)
    removeEventHandler("onClientPreRender",root,update)
    stopTune()
    restoreScene()
    elapsed,ending = nil,nil
    return true
end

local function creditsCommand(_, action)
    if action == "stop" then stopCredits()
    elseif not action then startCredits() end
end
addCommandHandler("credit", creditsCommand)
addCommandHandler("vcscredits", creditsCommand)
addEventHandler("onClientResourceStop", resourceRoot, stopCredits, false)
addEventHandler("onClientPlayerWasted", localPlayer, stopCredits, false)
