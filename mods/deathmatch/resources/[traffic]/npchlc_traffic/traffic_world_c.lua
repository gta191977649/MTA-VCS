local function visibleSpawn(x, y, z)
    return type(getScreenFromWorldPosition(x, y, z, 0.05, true)) == "number"
end

local function pedestrianLine(x, y, z, node, ignored)
    -- 0x00267308 raises both endpoints one unit for the static LOS test.
    return isLineOfSightClear(x, y, z + 1, node.x, node.y, node.z + 1,
        true, false, false, true, false, false, false, ignored)
end

local function spawnGround(x, y, z, endpoints)
    -- 0x00268048 / 0x001967F8 start two units above the node and
    -- reject hits more than three units from it.
    local hit, _, _, ground, groundElement = processLineOfSight(x, y, z + 2, x, y, z - 3.001,
        true, false, false, true, false)
    if not hit then return false end

    -- Reject occupied positions using MTA streamed elements. The original
    -- 0x00406E18 probe has radius 0.75 at the standing height.
    for _, kind in ipairs({"player", "ped", "vehicle", "object"}) do
        for _, element in ipairs(getElementsWithinRange(x, y, ground + 0.7, 0.75, kind,
            getElementInterior(localPlayer), getElementDimension(localPlayer))) do
            -- Map geometry hit by the ground ray is handled by the ray itself.
            if element ~= groundElement then return false end
        end
    end
    local visible = visibleSpawn(x, y, ground + 0.7)
    if not endpoints then return {ground, visible} end
    for _, node in ipairs(endpoints) do
        if getDistanceBetweenPoints2D(x, y, node.x, node.y) > 1
            and pedestrianLine(x, y, ground + 0.7, node) then
            return {ground, visible, node.id}
        end
    end
    return false
end

local function reachableNodes(ped, candidates, origin)
    if not isElement(ped) or not isElementStreamedIn(ped) then return false end
    local x, y, z = getElementPosition(ped)
    if origin then x, y, z = origin.x, origin.y, origin.z + 0.7 end
    local result = {}
    for _, node in ipairs(candidates) do
        if pedestrianLine(x, y, z, node, ped) then
            result[#result + 1] = node.id
        end
    end
    return result
end

local function roadGround(x, y, nominalZ)
    -- 0x00430290 casts both ways and keeps the hit closest to path Z + 1.5.
    -- Hits outside seven world units cannot be accepted by the original branch.
    local z = nominalZ + 1.5
    local up, _, _, upper = processLineOfSight(x, y, z, x, y, z + 7,
        true, false, false, true, false)
    local down, _, _, lower = processLineOfSight(x, y, z, x, y, z - 7,
        true, false, false, true, false)
    -- Some converted road faces only answer top-down casts. Search above the
    -- reference in short slabs, stopping once the lower hit is already nearer.
    if not up and (not down or z - lower > 0.1) then
        local reach = down and math.min(7, z - lower) or 7
        for base = 0, reach, 1.75 do
            local top = math.min(base + 1.75, reach)
            if top <= base then break end
            up, _, _, upper = processLineOfSight(x, y, z + top, x, y, z + base,
                true, false, false, true, false)
            if up then break end
        end
    end
    if not up and not down then return false end
    local ground = up and upper or lower
    if down and math.abs(lower - z) < math.abs(ground - z) then ground = lower end
    local water = getWaterLevel(x, y, ground, true)
    if type(water) == "number" and ground <= water then return false end
    -- MTA adapter for the original model-bound camera visibility check.
    return {ground, visibleSpawn(x, y, ground + 1.5)}
end

local function roadBatch(points)
    local probes = {}
    for index, point in ipairs(points) do
        probes[index] = roadGround(point[1], point[2], point[3])
    end
    local cameraX, cameraY, _, targetX, targetY = getCameraMatrix()
    if not cameraX then return {probes} end
    local dx, dy = targetX - cameraX, targetY - cameraY
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then return {probes, dx / length, dy / length} end
    return {probes}
end

addEvent("npchlc_traffic:worldProbe", true)
addEventHandler("npchlc_traffic:worldProbe", resourceRoot, function(id, kind, ...)
    local result
    if kind == "spawn" then result = spawnGround(...)
    elseif kind == "reach" then result = reachableNodes(...)
    elseif kind == "road" then result = roadBatch(...)
    else return end
    triggerServerEvent("npchlc_traffic:worldProbeResult", resourceRoot, id, result)
end, false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("npchlc_traffic:worldProbeReady", resourceRoot)
end, false)

local railTag = "npchlc_traffic:rail"
local reportedImpacts = setmetatable({}, {__mode = "k"})

addEventHandler("onClientVehicleCollision", root, function(other, impulse, _, x, y, z, nx, ny, nz)
    if impulse <= 0 then return end
    local rail, collider
    if getElementData(source, railTag, false) and isElementSyncer(source) then
        -- Static map collisions can identify a client-only building. The
        -- server already validates this report against the rail sync owner.
        rail = source
        collider = isElement(other) and getElementType(other) == "vehicle" and other or false
    elseif nx and ny and nz and source == getPedOccupiedVehicle(localPlayer) and getVehicleOccupant(source, 0) == localPlayer
        and isElement(other) and getElementData(other, railTag, false) then
        rail, collider = other, source
        nx, ny, nz = -nx, -ny, -nz
    end
    if not rail then return end
    -- Suspension/road contact is continuous during velocity cruise.
    if not collider and nz and math.abs(nz) > 0.7 then return end
    local now = getTickCount()
    local previous = reportedImpacts[rail]
    if previous and (now - previous) % 4294967296 < 200 then return end
    reportedImpacts[rail] = now
    if isElementSyncer(rail) then
        setElementData(rail, "npchlc_traffic:impactPending", true, false)
        setTimer(function()
            if isElement(rail) and reportedImpacts[rail] == now then
                setElementData(rail, "npchlc_traffic:impactPending", false, false)
            end
        end, math.max(350, math.min(1200, 2 * getPlayerPing(localPlayer) + 200)), 1)
    end
    triggerServerEvent("npchlc_traffic:railImpact", resourceRoot, rail, collider, x, y, z, nx, ny, nz)
end)
