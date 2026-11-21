local MAP_NAME = "vcs"
local PORTAL_FILE = ":vcs/portals.xml"
local locationNames = {
    ARMYH = "Army Barracks", COMPO = "The Compound", DTNAMU = "Downtown Ammu-Nation",
    Fidl = "Fiddler's Bar", HOS = "Hospital", JERRY = "Army Quarters", JS = "Workshop",
    LANCE_HIDEOUT = "Hideout", SAFE_BEACH = "Beach Safehouse", SAFE_BEACH_ROOF = "Beach Rooftop",
    SFDOCK = "Docks", VCN = "News Station", VPSHOO = "Shooting Range", WSAMMN = "Ammu-Nation",
}
local portals = {}
local children = {}
local triggers = {}
local previousRoute
local transition
local passageSerial=0
local cooldown = 0
local blockedShape

local function cleanup()
    if transition then
        local current = transition
        transition = nil
        if current.timer and isTimer(current.timer) then killTimer(current.timer) end
        setElementDimension(localPlayer, current.dimension)
        setElementInterior(localPlayer, current.interior)
        setElementPosition(localPlayer, current.x, current.y, current.z)
        setElementRotation(localPlayer, 0, 0, current.heading)
        setElementFrozen(localPlayer, current.frozen)
        fadeCamera(true, 0.3)
    end
    for _, element in ipairs(children) do
        if isElement(element) then destroyElement(element) end
    end
    portals, children, triggers = {}, {}, {}
    previousRoute, blockedShape = nil, nil
end

local function findLanding(target)
    for _, offset in ipairs({{0, 0}, {0.4, 0}, {-0.4, 0}, {0, 0.4}, {0, -0.4}}) do
        local x, y = target.spawnX + offset[1], target.spawnY + offset[2]
        local hit, _, _, height, element, _, _, nz = processLineOfSight(
            x, y, target.floorZ + 1.1, x, y, target.floorZ - 1.1,
            true, false, false, true, true, false, false, false, localPlayer)
        local sameScope = isElement(element)
            and getElementInterior(element) == target.interior
            and (getElementDimension(element) or 0) == target.dimension
        if hit and sameScope and nz and nz > 0.5 and math.abs(height - target.floorZ) <= 0.6 then
            local function obstructed(x1, y1, z1, x2, y2, z2)
                return processLineOfSight(x1, y1, z1, x2, y2, z2,
                    true, false, false, true, true, false, false, false, localPlayer)
            end
            local clear = not obstructed(x, y, height + 0.25, x, y, height + 1.75)
            if clear then
                for _, direction in ipairs({{0.27, 0}, {-0.27, 0}, {0, 0.27}, {0, -0.27}}) do
                    local px, py = x + direction[1], y + direction[2]
                    if obstructed(x, y, height + 0.55, px, py, height + 0.55)
                        or obstructed(x, y, height + 1.45, px, py, height + 1.45) then
                        clear = false
                        break
                    end
                end
            end
            if clear then return x, y, height + 0.85 end
        end
    end
end

local function triggerKey(portal)
    return table.concat({portal.x, portal.y, portal.z, portal.interior, portal.dimension}, "|")
end

local function finish(target, success)
    local current = transition
    if not current then return end
    transition = nil
    if current.timer and isTimer(current.timer) then killTimer(current.timer) end
    if success then
        previousRoute = current.entering and current.routeId or nil
        if current.entering then exports.frontend:showGameText(target.label, "LOCATION_NAME", 3000) end
        blockedShape = nil
        local returnShape = triggers[triggerKey(target)]
        if returnShape and isElementWithinColShape(localPlayer, returnShape) then
            blockedShape = returnShape
        end
    else
        setElementDimension(localPlayer, current.dimension)
        setElementInterior(localPlayer, current.interior)
        setElementPosition(localPlayer, current.x, current.y, current.z)
        setElementRotation(localPlayer, 0, 0, current.heading)
        blockedShape = current.sourceShape
        local reason = current.authorized and "interior collision did not stream"
            or "server passage authorization timed out"
        outputDebugString("VCS: " .. reason .. " for " .. target.name, 2)
    end
    setElementFrozen(localPlayer, current.frozen)
    cooldown = getTickCount() + 1800
    fadeCamera(true, 0.35)
end

local function travel(target, routeId, entering, shape)
    local x, y, z = getElementPosition(localPlayer)
    local _, _, heading = getElementRotation(localPlayer)
    transition = {
        x = x, y = y, z = z, heading = heading,
        dimension = getElementDimension(localPlayer),
        interior = getElementInterior(localPlayer),
        frozen = isElementFrozen(localPlayer),
        routeId = routeId, entering = entering, sourceShape = shape,
    }
    setElementFrozen(localPlayer, true)
    fadeCamera(false, 0.3)
    passageSerial=passageSerial+1
    transition.serial,transition.target=passageSerial,target
    transition.timer=setTimer(function() finish(target,false) end,4000,1)
    triggerServerEvent("enex:requestPassage",resourceRoot,routeId,entering,passageSerial)
end

addEvent("enex:passageReady",true)
addEventHandler("enex:passageReady",resourceRoot,function(serial)
    if not transition or transition.serial~=serial or transition.authorized then return end
    transition.authorized=true
    local target=transition.target
    killTimer(transition.timer)
    transition.timer = setTimer(function()
        setElementDimension(localPlayer, target.dimension)
        setElementInterior(localPlayer, target.interior)
        setElementPosition(localPlayer, target.spawnX, target.spawnY, target.floorZ + 0.85)
        setElementRotation(localPlayer, 0, 0, target.heading)
        if enginePreloadWorldArea then
            enginePreloadWorldArea(target.spawnX, target.spawnY, target.floorZ, "collisions")
        end
        local attempts = 0
        transition.timer = setTimer(function()
            attempts = attempts + 1
            local landingX, landingY, landingZ = findLanding(target)
            if landingX then
                setElementPosition(localPlayer, landingX, landingY, landingZ)
                triggerServerEvent("enex:landed",resourceRoot,serial,landingX,landingY,landingZ)
                finish(target, true)
            elseif attempts >= 24 then
                finish(target, false)
            end
        end, 250, 24)
    end, 350, 1)
end,false)

local function parsePortal(xml, name, label)
    local result = {name = name, label = label}
    for _, key in ipairs({
        "x", "y", "z", "yaw", "width", "depth", "interior", "dimension",
        "spawnX", "spawnY", "floorZ", "heading",
    }) do
        result[key] = tonumber(xmlNodeGetAttribute(xml, key))
        if result[key] == nil then return nil end
    end
    if result.width <= 0 or result.depth <= 0 then return nil end
    return result
end

local function createPortal(from, to, routeId, entering)
    local key = triggerKey(from)
    local route = {from = from, to = to, id = routeId, entering = entering}
    if triggers[key] then
        local choices = portals[triggers[key]]
        choices[#choices + 1] = route
        return
    end
    local yaw = math.rad(from.yaw)
    local c, s = math.cos(yaw), math.sin(yaw)
    local points = {}
    for _, direction in ipairs({{-1,-1}, {1,-1}, {1,1}, {-1,1}}) do
        local x = direction[1] * from.width / 2
        local y = direction[2] * from.depth / 2
        points[#points + 1] = from.x + x*c - y*s
        points[#points + 1] = from.y + x*s + y*c
    end
    local shape = createColPolygon(from.x, from.y, unpack(points))
    if not shape then return end
    setColPolygonHeight(shape, from.z - 1.2, from.z + 2.2)
    setElementInterior(shape, from.interior)
    setElementDimension(shape, from.dimension)
    local marker = exports.marker:createMarker(from.x, from.y, from.z + 1.5, "arrow", 1.3, 0, 255, 255, 125)
    setElementInterior(marker, from.interior)
    setElementDimension(marker, from.dimension)
    children[#children + 1] = shape
    children[#children + 1] = marker
    triggers[key] = shape
    portals[shape] = {route}
end

local function loadPortals()
    cleanup()
    if not fileExists(PORTAL_FILE) then return end
    local document = xmlLoadFile(PORTAL_FILE, true)
    if not document then
        outputDebugString("VCS: could not read PS2 interior portals.", 1)
        return
    end
    for _, pair in ipairs(xmlNodeGetChildren(document)) do
        local name = xmlNodeGetAttribute(pair, "name")
        local id = xmlNodeGetAttribute(pair, "id")
        local nodes = xmlNodeGetChildren(pair)
        if #nodes == 2 then
            local label = xmlNodeGetAttribute(pair, "label") or locationNames[name]
                or (name:match("^MALL%d+$") and "Shopping Mall") or name
            local outside, inside = parsePortal(nodes[1], name, label), parsePortal(nodes[2], name, label)
            if outside and inside then
                createPortal(outside, inside, id, true)
                createPortal(inside, outside, id, false)
            end
        end
    end
    xmlUnloadFile(document)
end

addEventHandler("onClientColShapeHit", root, function(player, matchingDimension)
    local choices = portals[source]
    if not choices or source == blockedShape or player ~= localPlayer or not matchingDimension or transition
        or getTickCount() < cooldown or getPedOccupiedVehicle(localPlayer)
        or getElementInterior(localPlayer) ~= choices[1].from.interior then
        return
    end
    local route = choices[1]
    for _, candidate in ipairs(choices) do
        if candidate.id == previousRoute then
            route = candidate
            break
        end
    end
    travel(route.to, route.id, route.entering, source)
end)

addEventHandler("onClientColShapeLeave", root, function(player)
    if player == localPlayer and source == blockedShape and not transition then
        blockedShape = nil
    end
end)

addEventHandler("onClientResourceStart", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == MAP_NAME then
        loadPortals()
    end
end)

addEventHandler("onClientResourceStop", root, function(resource)
    if resource == getThisResource() or getResourceName(resource) == MAP_NAME then
        cleanup()
    end
end)
