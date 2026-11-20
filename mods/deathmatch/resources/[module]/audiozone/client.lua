local zonesByScope = {}
local mapResource
local activeZone, activeScope, trackIndex, entry
local sound, soundPath, soundVolume

local function scope(interior, dimension)
    return interior * 65536 + dimension
end

local function stopSound()
    if isElement(sound) then destroyElement(sound) end
    sound, soundPath, soundVolume = nil, nil, nil
end

local function bindZone(key, zone)
    local zones = zonesByScope[key] or {}
    zones[#zones + 1] = zone
    zonesByScope[key] = zones
end

local function readBox(node)
    local box = {}
    for index, attribute in ipairs({ "minX", "minY", "minZ", "maxX", "maxY", "maxZ" }) do
        box[index] = tonumber(xmlNodeGetAttribute(node, attribute))
        if not box[index] then return nil end
    end
    if box[1] > box[4] or box[2] > box[5] or box[3] > box[6] then return nil end
    return box
end

local function loadZones(mapStopping)
    zonesByScope = {}
    local config = xmlLoadFile("zones.xml", true)
    if not config then return end
    local portalPath = xmlNodeGetAttribute(config, "portals") or ""
    mapResource = portalPath:match("^:([^/]+)/")
    local portals = not mapStopping and portalPath ~= "" and xmlLoadFile(portalPath, true)

    local playlists = {}
    local nodes = xmlNodeGetChildren(config)
    for _, node in ipairs(nodes) do
        if xmlNodeGetName(node) == "playlist" then
            local id = xmlNodeGetAttribute(node, "id")
            local gain = tonumber(xmlNodeGetAttribute(node, "gain"))
            local tracks = {}
            for _, child in ipairs(xmlNodeGetChildren(node)) do
                local path = xmlNodeGetAttribute(child, "file")
                if path and fileExists(path) then tracks[#tracks + 1] = path end
            end
            if id and gain and gain >= 0 and gain <= 127 and #tracks > 0 then
                playlists[id] = { gain = gain, tracks = tracks }
            end
        end
    end

    local endpoints = {}
    if portals then
        for _, pair in ipairs(xmlNodeGetChildren(portals)) do
            local id = xmlNodeGetAttribute(pair, "id")
            for _, portal in ipairs(xmlNodeGetChildren(pair)) do
                local interior = tonumber(xmlNodeGetAttribute(portal, "interior"))
                local dimension = tonumber(xmlNodeGetAttribute(portal, "dimension"))
                if id and interior and dimension and (interior ~= 0 or dimension ~= 0) then
                    endpoints[#endpoints + 1] = { id = id, scope = scope(interior, dimension) }
                end
            end
        end
        xmlUnloadFile(portals)
    end

    for _, node in ipairs(nodes) do
        if xmlNodeGetName(node) == "zone" then
            local playlist = playlists[xmlNodeGetAttribute(node, "playlist")]
            if playlist then
                local radius = tonumber(xmlNodeGetAttribute(node, "radius"))
                local zone = {
                    playlist = playlist,
                    fallback = playlists[xmlNodeGetAttribute(node, "fallback")],
                    radius = radius and radius > 0 and radius or nil,
                }
                local scopes = {}
                for _, child in ipairs(xmlNodeGetChildren(node)) do
                    local kind = xmlNodeGetName(child)
                    if kind == "box" then
                        zone.box = readBox(child)
                    elseif kind == "scope" then
                        local interior = tonumber(xmlNodeGetAttribute(child, "interior"))
                        local dimension = tonumber(xmlNodeGetAttribute(child, "dimension"))
                        if interior and dimension then
                            scopes[scope(interior, dimension)] = true
                        end
                    elseif kind == "portal" then
                        local id = xmlNodeGetAttribute(child, "id")
                        local prefix = xmlNodeGetAttribute(child, "prefix")
                        for _, endpoint in ipairs(endpoints) do
                            if endpoint.id == id or prefix and endpoint.id:sub(1, #prefix) == prefix then
                                scopes[endpoint.scope] = true
                            end
                        end
                    end
                end
                for key in pairs(scopes) do bindZone(key, zone) end
            end
        end
    end
    xmlUnloadFile(config)
end

local function refresh()
    local playerScope = scope(getElementInterior(localPlayer), getElementDimension(localPlayer))
    local zones = zonesByScope[playerScope]
    local zone
    local x, y, z
    if zones and not isPedDead(localPlayer) then
        x, y, z = getElementPosition(localPlayer)
        for _, candidate in ipairs(zones) do
            local box = candidate.box
            if not box or x >= box[1] and y >= box[2] and z >= box[3]
                and x <= box[4] and y <= box[5] and z <= box[6] then
                zone = candidate
                break
            end
        end
    end
    if zone ~= activeZone or playerScope ~= activeScope then
        activeZone, activeScope = zone, playerScope
        trackIndex, entry = nil, nil
        if zone then
            local tracks = zone.playlist.tracks
            trackIndex = math.random(#tracks)
            entry = { x, y, z }
        end
    end
    if not zone then
        stopSound()
        return
    end

    local path, gain = zone.playlist.tracks[trackIndex], zone.playlist.gain
    local cameraX, cameraY, cameraZ = getCameraMatrix()
    local ambient = not zone.radius
    if zone.radius then
        local distance = getDistanceBetweenPoints3D(cameraX, cameraY, cameraZ, unpack(entry))
        if distance < zone.radius then
            gain = gain * (1 - distance / zone.radius)
        elseif zone.fallback then
            path, gain = zone.fallback.tracks[1], zone.fallback.gain
            ambient = true
        else
            gain = 0
        end
    end

    if ambient then
        gain = gain * math.max(0, math.min(1, (90 - cameraZ) / 70))
    end

    local volume = math.floor(gain) / 127
    if path ~= soundPath then
        stopSound()
        soundPath = path
        local looped = path ~= zone.playlist.tracks[trackIndex] or #zone.playlist.tracks == 1
        sound = playSound(path, looped)
        if not sound then outputDebugString("Audio zones: could not play " .. path, 2) end
    end
    if isElement(sound) and volume ~= soundVolume then
        setSoundVolume(sound, volume)
        soundVolume = volume
    end
end

addEventHandler("onClientSoundStopped", root, function(reason)
    if source ~= sound or reason ~= "finished" or not activeZone then return end
    local tracks = activeZone.playlist.tracks
    if #tracks <= 1 or soundPath ~= tracks[trackIndex] then return end
    trackIndex = trackIndex % #tracks + 1
    stopSound()
    refresh()
end)

addEventHandler("onClientInteriorChanged", localPlayer, refresh, false)
addEventHandler("onClientPlayerWasted", localPlayer, refresh, false)
addEventHandler("onClientResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == mapResource then
        loadZones()
        refresh()
    end
end)
addEventHandler("onClientResourceStop", root, function(resource)
    if resource == getThisResource() then
        stopSound()
    elseif getResourceName(resource) == mapResource then
        loadZones(true)
        refresh()
    end
end)
setTimer(refresh, 150, 0)
