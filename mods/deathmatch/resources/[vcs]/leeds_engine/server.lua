local mapResources = { "vcs", "eagleLoader" }
local excludedResources = { vcs = true, eagleloader = true, leeds_engine = true }
local reloadKey = "leeds_engine:reloading"
local reloading = false

local function finishReload()
    if reloading then
        setElementData(root, reloadKey, false, "broadcast", "deny")
        reloading = false
    end
end

local function log(message, level)
    outputDebugString("[leeds_engine] " .. message, level or 3)
end

local function mapIsRunning()
    for _, name in ipairs(mapResources) do
        local resource = getResourceFromName(name)
        if not resource or getResourceState(resource) ~= "running" then
            log("Expected " .. name .. " to be running before loading the VCS scripts.", 1)
            return false
        end
    end
    return true
end

local function loadScripts()
    if not mapIsRunning() then return end

    local engine = getThisResource()
    if not hasObjectPermissionTo(engine, "function.startResource", false)
        or not hasObjectPermissionTo(engine, "function.stopResource", false) then
        log("Grant leeds_engine the startResource and stopResource rights in acl.xml.", 1)
        return
    end

    local selected = {}
    local expected = 0
    local hasRunningResources = false
    for _, entry in ipairs(vcsResources) do
        local name = entry[1]
        if excludedResources[name:lower()] then
            log("The reload list cannot contain " .. name .. ".", 1)
            return
        end

        local resource = getResourceFromName(name)
        local state = resource and getResourceState(resource)
        if state == "running" or (not entry.optional and not entry.ifInstalled) or (entry.ifInstalled and resource) then
            expected = expected + 1
            if state == "running" or state == "loaded" then
                selected[#selected + 1] = { name = name, resource = resource, running = state == "running" }
                hasRunningResources = hasRunningResources or state == "running"
            else
                log(("Cannot load %s (%s)."):format(name, state or "missing"), 1)
            end
        end
    end

    -- Publish the handoff before MTA sends the managed resource stop packets.
    if hasRunningResources then
        if not setElementData(root, reloadKey, true, "broadcast", "deny") then
            log("Could not announce the reload to clients.", 1)
            return
        end
        reloading = true
    end

    for index = #selected, 1, -1 do
        local entry = selected[index]
        if entry.running and not stopResource(entry.resource) then
            log("Could not stop " .. entry.name .. ".", 1)
        end
    end

    -- stopResource queues stops until the Lua callback exits.
    setTimer(function()
        if not mapIsRunning() then
            finishReload()
            return
        end

        local started = 0
        for _, entry in ipairs(selected) do
            local resource = getResourceFromName(entry.name)
            local state = resource and getResourceState(resource)
            if state == "running" or (state == "loaded" and startResource(resource, true)) then
                started = started + 1
            else
                log("Could not start " .. entry.name .. " after the stop phase.", 1)
            end
        end

        local message = ("Started %d/%d VCS script resources."):format(started, expected)
        finishReload()
        log(message, started < expected and 2 or 3)
    end, 50, 1)
end

addEventHandler("onResourceStart", resourceRoot, loadScripts, false)
addEventHandler("onResourceStop", resourceRoot, finishReload, false)
