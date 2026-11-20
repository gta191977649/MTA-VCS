addEventHandler("onResourceStart", resourceRoot, function()
    -- The mall's PS2 interior is below SA's underworld warp threshold.
    if isWorldSpecialPropertyEnabled("underworldwarp")
        and not setWorldSpecialPropertyEnabled("underworldwarp", false) then
        outputDebugString("ENEX: could not disable underworld warp for below-map interiors.", 1)
    end
end)

-- ENEX previews destination collision on the client. Authorize at the source
-- door, then publish the successful landing's world to server-side resources.
local routes
local pending={}

local function loadPassageRoutes()
    -- This copy of vcs/portals.xml is packaged with enex so authorization
    -- also works when the running map resource cannot reload.
    local document = xmlLoadFile("passage_routes.xml", true)
    if not document then
        outputDebugString("ENEX: could not read passage_routes.xml.", 1)
        return
    end

    local catalog = {}
    local attributes = {"x", "y", "z", "width", "depth", "dimension", "interior", "spawnX", "spawnY", "floorZ"}
    for _, pair in ipairs(xmlNodeGetChildren(document)) do
        local id = xmlNodeGetAttribute(pair, "id")
        local nodes = xmlNodeGetChildren(pair)
        if id and #nodes == 2 then
            local endpoints = {}
            for i, node in ipairs(nodes) do
                local endpoint = {}
                for _, key in ipairs(attributes) do
                    endpoint[key] = tonumber(xmlNodeGetAttribute(node, key))
                end
                endpoints[i] = endpoint
            end
            catalog[id] = endpoints
        end
    end
    xmlUnloadFile(document)
    return catalog
end

addEvent("enex:requestPassage",true)
addEventHandler("enex:requestPassage",resourceRoot,function(id,entering,serial)
    if not client or type(id)~="string" or type(entering)~="boolean" or type(serial)~="number" then return end
    local map=getResourceFromName("vcs")
    if not map or getResourceState(map)~="running" then return end
    if not routes then
        routes=loadPassageRoutes()
        if not routes then return end
    end
    local pair=routes[id]
    if not pair or isPedDead(client) or isPedInVehicle(client) then return end
    local door=pair[entering and 1 or 2]
    local x,y,z=getElementPosition(client)
    if door.dimension~=getElementDimension(client) or door.interior~=getElementInterior(client)
        or math.abs(z-door.z)>4 or (x-door.x)^2+(y-door.y)^2>(math.max(door.width,door.depth)+3)^2 then return end
    pending[client]={serial=serial,target=pair[entering and 2 or 1],started=getTickCount()}
    triggerClientEvent(client,"enex:passageReady",resourceRoot,serial)
end,false)

addEvent("enex:landed",true)
addEventHandler("enex:landed",resourceRoot,function(serial,x,y,z)
    local pass=pending[client]
    if not pass or pass.serial~=serial then return end
    pending[client]=nil
    if (getTickCount()-pass.started)%4294967296>15000 or isPedDead(client) or isPedInVehicle(client) then return end
    local target=pass.target
    if type(x)~="number" or type(y)~="number" or type(z)~="number"
        or not ((x-target.spawnX)^2+(y-target.spawnY)^2<=0.5^2 and math.abs(z-target.floorZ-0.85)<=0.65) then return end
    setElementInterior(client,target.interior)
    setElementDimension(client,target.dimension)
    setElementPosition(client,x,y,z)
end,false)
addEventHandler("onPlayerQuit",root,function() pending[source]=nil end)
addEventHandler("onPlayerWasted",root,function() pending[source]=nil end)

addEventHandler("onResourceStop",root,function(stopped)
    if getResourceName(stopped)=="vcs" then pending={} end
end)
