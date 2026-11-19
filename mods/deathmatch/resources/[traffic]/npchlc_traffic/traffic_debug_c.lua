local mode, timer, nodes, links, connections, lastX, lastY, lastInterior, lastDimension, lastRequest
local colors = {
    pedestrian = tocolor(117, 233, 136, 230),
    vehicle = tocolor(255, 188, 64, 235),
    rail = tocolor(255, 237, 157, 255),
    boat = tocolor(78, 179, 255, 230),
}
local signalColor = tocolor(255, 87, 103, 250)
local connectionColor = tocolor(255, 188, 64, 175)
local background = tocolor(0, 0, 0, 180)
local foreground = tocolor(255, 255, 255, 240)
local modes = {all = true, road = true, ped = true, boat = true}
local cameraX, cameraY, cameraZ, forwardX, forwardY, forwardZ

local function drawProjectedLine(ax, ay, az, bx, by, bz, color, width)
    local near = 0.25
    local aDepth = (ax - cameraX) * forwardX + (ay - cameraY) * forwardY + (az - cameraZ) * forwardZ
    local bDepth = (bx - cameraX) * forwardX + (by - cameraY) * forwardY + (bz - cameraZ) * forwardZ
    if aDepth < near and bDepth < near then return end
    if aDepth < near then
        local at = (near - aDepth) / (bDepth - aDepth)
        ax, ay, az = ax + (bx - ax) * at, ay + (by - ay) * at, az + (bz - az) * at
    elseif bDepth < near then
        local at = (near - bDepth) / (aDepth - bDepth)
        bx, by, bz = bx + (ax - bx) * at, by + (ay - by) * at, bz + (az - bz) * at
    end
    -- project both endpoints even outside the viewport so dx clips long links
    -- that cross the screen; dxDrawLine does not read the world depth buffer.
    local sx, sy = getScreenFromWorldPosition(ax, ay, az, 10, true)
    local tx, ty = getScreenFromWorldPosition(bx, by, bz, 10, true)
    if sx and tx then dxDrawLine(sx, sy, tx, ty, color, width, true) end
end

local function update()
    local x, y = getElementPosition(localPlayer)
    local interior, dimension = getElementInterior(localPlayer), getElementDimension(localPlayer)
    local now = getTickCount()
    local refreshRail = (mode == "all" or mode == "road")
        and (not lastRequest or (now - lastRequest) % 4294967296 >= 1500)
    if nodes and lastX and (x - lastX) ^ 2 + (y - lastY) ^ 2 < 35 ^ 2
        and interior == lastInterior and dimension == lastDimension and not refreshRail then return end
    lastX, lastY, lastInterior, lastDimension = x, y, interior, dimension
    lastRequest = now
    triggerServerEvent("npchlc_traffic:debugRequest", resourceRoot, mode)
end

local function draw()
    local message = "Traffic debug / " .. mode .. "   Lane connections: orange   Active routes: light yellow   Ped: green   Boat: blue   Signal: red"
    dxDrawText(message, 19, 19, 0, 0, background, 1, "default-bold")
    dxDrawText(message, 18, 18, 0, 0, foreground, 1, "default-bold")
    if not nodes then return end
    local cx, cy, cz, tx, ty, tz = getCameraMatrix()
    if not cx then return end
    cameraX, cameraY, cameraZ = cx, cy, cz
    local dx, dy, dz = tx - cx, ty - cy, tz - cz
    local length = math.sqrt(dx * dx + dy * dy + dz * dz)
    if length == 0 then return end
    forwardX, forwardY, forwardZ = dx / length, dy / length, dz / length
    local x, y, z = getElementPosition(localPlayer)
    for _, points in ipairs(connections or {}) do
        for i = 2, #points do
            local a, b = points[i - 1], points[i]
            drawProjectedLine(a[1], a[2], a[3] + 0.35, b[1], b[2], b[3] + 0.35, connectionColor, 1.5)
        end
    end
    for _, link in ipairs(links) do
        local a, b, c, d, e, f, kind, directed, light = unpack(link)
        local color = colors[kind]
        c, f = c + 0.35, f + 0.35
        drawProjectedLine(a, b, c, d, e, f, color, (directed or kind == "rail") and 2.5 or 1.5)
        if directed then
            local dx, dy = d - a, e - b
            local length = math.sqrt(dx * dx + dy * dy)
            if length > 0.1 then
                local mx, my, mz = (a + d) * 0.5, (b + e) * 0.5, (c + f) * 0.5
                local vx, vy = dx / length, dy / length
                local arrowColor = light > 0 and signalColor or color
                drawProjectedLine(mx - vx + vy * 0.6, my - vy - vx * 0.6, mz, mx + vx, my + vy, mz, arrowColor, 3)
                drawProjectedLine(mx - vx - vy * 0.6, my - vy + vx * 0.6, mz, mx + vx, my + vy, mz, arrowColor, 3)
            end
        end
    end
    local labels = 0
    for _, node in ipairs(nodes) do
        local nx, ny, nz, kind, id = unpack(node)
        local color = colors[kind]
        drawProjectedLine(nx, ny, nz + 0.2, nx, ny, nz + 0.8, color, 2)
        if labels < 24 and (nx - x) ^ 2 + (ny - y) ^ 2 + (nz - z) ^ 2 <= 35 ^ 2 then
            local sx, sy = getScreenFromWorldPosition(nx, ny, nz + 0.9)
            if sx then
                dxDrawText(tostring(id), sx, sy, sx, sy, color, 0.9, "default-bold", "center")
                labels = labels + 1
            end
        end
    end
end

addEvent("npchlc_traffic:debugPaths", true)
addEventHandler("npchlc_traffic:debugPaths", resourceRoot, function(replyMode, replyNodes, replyLinks, replyConnections)
    if mode == replyMode then nodes, links, connections = replyNodes, replyLinks, replyConnections end
end, false)

addCommandHandler("trafficdebug", function(_, filter)
    filter = filter and filter:lower()
    if filter and not modes[filter] and filter ~= "off" then
        outputChatBox("/trafficdebug [all|road|ped|boat|off]", 255, 188, 64)
        return
    end
    if mode and (not filter or filter == "off") then
        removeEventHandler("onClientRender", root, draw)
        killTimer(timer)
        mode, timer, nodes, links, connections = nil, nil, nil, nil, nil
        return
    end
    if filter == "off" then return end
    if not mode then
        addEventHandler("onClientRender", root, draw)
        timer = setTimer(update, 750, 0)
    end
    mode, nodes, links, connections, lastX = filter or "all", nil, nil, nil, nil
    update()
end)
