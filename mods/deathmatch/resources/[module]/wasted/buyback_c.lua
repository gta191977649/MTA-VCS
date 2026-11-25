local sites = {}
local model, dictionary, geometry
local offer, offerSite, helpVisible
local disabled = {}
local controls = {"forwards", "backwards", "left", "right", "jump", "sprint", "crouch",
    "fire", "aim_weapon", "enter_exit", "accelerate", "brake_reverse", "vehicle_fire"}

local function clearHelp()
    offer, offerSite = nil, nil
    for _, control in ipairs(disabled) do toggleControl(control, true) end
    disabled = {}
    if helpVisible then
        exports.frontend:showTextBox(false)
        helpVisible = false
    end
end

local function answer(buy)
    if not offer then return end
    triggerServerEvent("wasted:answer", resourceRoot, offer, buy)
    clearHelp()
end

addEvent("wasted:help", true)
addEventHandler("wasted:help", resourceRoot, function(key, token, index)
    clearHelp()
    if not key then return end
    local site = sites[index]
    if site then
        if getElementDimension(localPlayer) ~= site.dimension or getElementInterior(localPlayer) ~= 0 or
            not isElementWithinColShape(localPlayer, site.area) then
            if token then triggerServerEvent("wasted:answer", resourceRoot, token, false) end
            return
        end
        if isElement(site.pickup) then destroyElement(site.pickup) end
        site.pickup = nil
    end
    local text = exports.frontend:getVcsText(key)
    if not text then return end
    if token then
        text = text:gsub("~k~%s*~AMBUY~", "Enter"):gsub("~k~%s*~AMEXI~", "Backspace")
        offer, offerSite = token, site
        for _, control in ipairs(controls) do
            if isControlEnabled(control) then
                toggleControl(control, false)
                disabled[#disabled + 1] = control
            end
        end
    end
    local duration = token and 0 or (key == "H_WBBW1" and 8500 or 3000)
    helpVisible = exports.frontend:showTextBox(text, duration)
end, false)

addEventHandler("onClientKey", root, function(key, pressed)
    if not offer or not pressed then return end
    if key == "enter" or key == "num_enter" or key == "backspace" then
        cancelEvent()
        answer(key ~= "backspace")
    end
end)

local function clearPickups()
    local previous = sites
    sites = {}
    for _, site in ipairs(previous) do
        if isElement(site.pickup) then destroyElement(site.pickup) end
        destroyElement(site.area)
    end
end

local function releaseModel()
    if model then engineFreeModel(model) end
    if isElement(geometry) then destroyElement(geometry) end
    if isElement(dictionary) then destroyElement(dictionary) end
    model, geometry, dictionary = nil, nil, nil
end

local function loadModel()
    if model then return true end
    model = engineRequestModel("object", 1274)
    if model then
        dictionary = engineLoadTXD("assets/unlockableicon.txd")
        geometry = engineLoadDFF("assets/unlockableicon.dff")
        if dictionary and geometry and engineImportTXD(dictionary, model) and
            engineReplaceModel(geometry, model, true) then return true end
    end
    releaseModel()
    outputDebugString("Could not load the VCS weapon buyback pickup.", 1)
    return false
end

local function createIcon(site)
    local pickup = createPickup(site.x, site.y, site.z, 3, model)
    if not pickup then return end
    site.pickup = pickup
    setElementDimension(pickup, site.dimension)
    addEventHandler("onClientPickupHit", pickup, function(player, matching)
        if player == localPlayer and matching and getElementInterior(player) == 0 then
            triggerServerEvent("wasted:collect", resourceRoot, site.index)
        end
    end, false)
end

addEvent("wasted:sites", true)
addEventHandler("wasted:sites", resourceRoot, function(points, dimension)
    clearPickups()
    if not loadModel() then return end
    for index, point in ipairs(points) do
        local site = {index = index, x = point[1], y = point[2], z = point[3], dimension = dimension}
        sites[index] = site
        -- A collected pickup disappears. RADIA waits for the player to step
        -- out before another icon can be collected at this position.
        site.area = createColSphere(site.x, site.y, site.z, 2)
        setElementDimension(site.area, dimension)
        addEventHandler("onClientColShapeLeave", site.area, function(player)
            if player ~= localPlayer or sites[site.index] ~= site then return end
            if offerSite == site then answer(false) end
            if not site.pickup then createIcon(site) end
        end, false)
        createIcon(site)
    end
end, false)
addEventHandler("onClientPlayerWasted", localPlayer, clearHelp, false)
addEventHandler("onClientResourceStop", resourceRoot, function()
    clearHelp()
    clearPickups()
    releaseModel()
end, false)
