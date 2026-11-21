-- =========================
-- Water Config
-- =========================
local WORLD_MIN = -3000
local WORLD_MAX = 3000
local Z_MIN = -1000
local Z_MAX = 1000
local waterDebug = false
local activeWaterMaps = {}

-- ==============================
-- Water Loader Core
-- ==============================

local function clamp(val, min, max)
    return math.max(min, math.min(max, val))
end

function parseWaterDat(filePath, resourceName, offsetX, offsetY, offsetZ)
    local shiftX = tonumber(offsetX) or 0
    local shiftY = tonumber(offsetY) or 0
    local shiftZ = tonumber(offsetZ) or 0
    local waterData = {}
    local oceanLevel
    if fileExists(filePath) then
        local file = fileOpen(filePath)
        if not file then
            outputDebugString("Failed to open: " .. tostring(filePath), 1)
            return {}
        end

        local content = fileRead(file, fileGetSize(file))
        fileClose(file)

        local cLine = 0

        for line in string.gmatch(content, "[^\r\n]+") do
            cLine = cLine + 1
            local ocean = line:match("^%s*#oceanLevel%s+(%S+)%s*$")
            if ocean then
                oceanLevel = tonumber(ocean)
            elseif not line:match("^%s*[#;]") and line:match("%S")
                and not line:lower():match("^%s*processed%s*$") then
                local coords = {}
                for num in line:gmatch("%S+") do
                    local value = tonumber(num)
                    if not value then break end
                    coords[#coords + 1] = value
                end

                -- A 4-vertex water quad needs at least 29 numeric values
                -- (4 corners * 7 values + 1 type flag). Some exports include
                -- trailing values, so accept >= 29 rather than requiring exactly 29.
                if #coords >= 29 then
                    local function getClamped(i)
                        local x = clamp(coords[i] + shiftX, WORLD_MIN, WORLD_MAX)
                        local y = clamp(coords[i+1] + shiftY, WORLD_MIN, WORLD_MAX)
                        local z = clamp(coords[i+2] + shiftZ, Z_MIN, Z_MAX)
                        return x, y, z
                    end

                    local x1, y1, z1 = getClamped(1)
                    local x2, y2, z2 = getClamped(8)
                    local x3, y3, z3 = getClamped(15)
                    local x4, y4, z4 = getClamped(22)

                    table.insert(waterData, {
                        x1 = x1, y1 = y1, z1 = z1,
                        x2 = x2, y2 = y2, z2 = z2,
                        x3 = x3, y3 = y3, z3 = z3,
                        x4 = x4, y4 = y4, z4 = z4,
                        type = coords[29], name = cLine
                    })
                else
                    print("MALFORMED WATER - "..line)
                end
            end
        end

        local isVcsPS2 = resourceName == "vcs" and fileExists(":vcs/portals.xml")
        if isVcsPS2 and not oceanLevel and shiftX == 0 and shiftY == 0 then
            -- Eagle Editor keeps the polygons when writing water.dat and
            -- regenerates its header. Recover the ocean from both edge strips.
            local west, east
            for _, w in ipairs(waterData) do
                if w.y1 == WORLD_MIN and w.y2 == WORLD_MIN
                    and w.y3 == WORLD_MAX and w.y4 == WORLD_MAX
                    and w.z1 == w.z2 and w.z1 == w.z3 and w.z1 == w.z4 then
                    if w.x1 == WORLD_MIN and w.x2 == -2448 then west = w.z1 end
                    if w.x1 == 1648 and w.x2 == WORLD_MAX then east = w.z1 end
                end
            end
            if west and east == west then oceanLevel = west - shiftZ end
        end
        outputDebugString("Parsed " .. tostring(#waterData) .. " water quads from " .. filePath)
        createWaterPlanes(waterData, resourceName, oceanLevel ~= nil or isVcsPS2)
        if removeDefaultMap and oceanLevel then
            setWaterLevel(clamp(oceanLevel + shiftZ, Z_MIN, Z_MAX), false, false, false, true)
        end
    else
        outputDebugString2("Error: No water.dat file present.")
    end
end


function createWater2(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,name)
    -- Return the created water element so createWaterPlanes can track it for
    -- cleanup on unload; otherwise water planes leak across map switches.
    local water = createWater(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4)
    if water and z1 == z2 and z1 == z3 and z1 == z4 then
        -- GTA can reuse its original ocean vertices at the world edges.
        -- Apply the level to the native quad as well as the MTA element.
        if not setWaterLevel(water, z1) then
            destroyElement(water)
            return false
        end
    end

    if waterDebug then
        createRadarFromWaterZone(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,name)
    end

    return water
end


local function instantiateWater(w)
    return createWater2(w.x1, w.y1, w.z1, w.x2, w.y2, w.z2,
        w.x3, w.y3, w.z3, w.x4, w.y4, w.z4, w.name)
end

local function distanceToQuad(w, x, y)
    local dx = math.max(w.minX - x, 0, x - w.maxX)
    local dy = math.max(w.minY - y, 0, y - w.maxY)
    return math.sqrt(dx*dx + dy*dy)
end

local function moveWaterSlot(slot, w)
    local element = slot.element
    setWaterVertexPosition(element, 1, w.x1, w.y1, w.z1)
    setWaterVertexPosition(element, 2, w.x2, w.y2, w.z2)
    setWaterVertexPosition(element, 3, w.x3, w.y3, w.z3)
    setWaterVertexPosition(element, 4, w.x4, w.y4, w.z4)
end

local function parkWaterSlots(state, dimension)
    local changed
    for _, slot in ipairs(state.slots) do
        if slot.index then
            if dimension then setElementDimension(slot.element, dimension) end
            moveWaterSlot(slot, slot.parked)
            changed = slot.element
            slot.index = nil
        end
    end
    if changed then setElementPosition(changed, getElementPosition(changed)) end
    if dimension then
        for _, slot in ipairs(state.slots) do setElementDimension(slot.element, 0) end
    end
    state.active, state.px = {}, nil
end

addEventHandler("onClientElementDimensionChange", localPlayer, function(old, new)
    if old ~= 0 or new == 0 then return end
    -- MTA switches the native water manager and camera together. The player
    -- event comes before that switch for spawnPlayer and after it for a
    -- dimension RPC. Reclaim vertices in the dimension where GTA has them.
    local managerDimension = getElementDimension(getCamera())
    for _, state in pairs(activeWaterMaps) do
        parkWaterSlots(state, managerDimension ~= 0 and managerDimension or nil)
    end
end, false)

function stopStreamedWater(resourceName)
    local state = activeWaterMaps[resourceName]
    if not state then return end
    if isTimer(state.timer) then killTimer(state.timer) end
    parkWaterSlots(state)
    for _, slot in ipairs(state.slots) do
        if isElement(slot.element) then destroyElement(slot.element) end
    end
    activeWaterMaps[resourceName] = nil
end

local function startIndexedWater(waterData, resourceName)
    stopStreamedWater(resourceName)
    local state = {slots = {}, active = {}}
    activeWaterMaps[resourceName] = state
    -- Deleting a water polygon does not reclaim its native vertices.
    -- Give each slot four private vertices and move them as the view travels.
    for index = 0, math.min(#waterData, 80) - 1 do
        local x = -2950 + (index % 12) * 500
        local y = -2950 + math.floor(index / 12) * 500
        local parked = {x1=x, y1=y, z1=-900, x2=x+4, y2=y, z2=-900,
            x3=x, y3=y+4, z3=-900, x4=x+4, y4=y+4, z4=-900}
        local element = instantiateWater(parked)
        if not element then break end
        state.slots[#state.slots + 1] = {element=element, parked=parked}
    end
    for _, w in ipairs(waterData) do
        w.minX, w.maxX = math.min(w.x1,w.x2,w.x3,w.x4), math.max(w.x1,w.x2,w.x3,w.x4)
        w.minY, w.maxY = math.min(w.y1,w.y2,w.y3,w.y4), math.max(w.y1,w.y2,w.y3,w.y4)
        w.zones = {}
        for column = 0, 11 do
            local left = WORLD_MIN + column * 500
            if w.minX < left + 500 and w.maxX >= left then
                for row = 0, 11 do
                    local bottom = WORLD_MIN + row * 500
                    if w.minY < bottom + 500 and w.maxY >= bottom then
                        w.zones[#w.zones + 1] = column * 12 + row
                    end
                end
            end
        end
    end
    local function refresh()
        if getElementDimension(localPlayer) ~= 0 then return end
        local px, py = getElementPosition(localPlayer)
        local cx, cy = getCameraMatrix()
        if state.px and (px-state.px)^2 + (py-state.py)^2 < 32^2
            and (cx-state.cx)^2 + (cy-state.cy)^2 < 32^2 then return end
        state.px, state.py, state.cx, state.cy = px, py, cx, cy
        local nearby = {}
        for index, w in ipairs(waterData) do
            local distance = math.min(distanceToQuad(w, px, py), distanceToQuad(w, cx, cy))
            -- Large ocean strips cover more of the view than one shoreline
            -- tile. Give them priority before the last few index slots fill.
            local score = distance / (1 + 0.025 * (#w.zones - 1))
            if state.active[index] then score = score - math.min(24, score * 0.1) end
            nearby[index] = {index = index, distance = score}
        end
        table.sort(nearby, function(a, b)
            if a.distance == b.distance then return a.index < b.index end
            return a.distance < b.distance
        end)
        local function selectWater(parkedWeight)
            local keep, zones = {}, {}
            local entries, count = 0, 0
            for _, item in ipairs(nearby) do
                local water = waterData[item.index]
                -- MTA has 1024 index entries. Stock water can use 700 of
                -- them, and a zone's first list can take two extra slots.
                local cost = #water.zones
                for _, zone in ipairs(water.zones) do
                    if not zones[zone] then cost = cost + 2 end
                end
                local parkedCost = (#state.slots - count - 1) * parkedWeight
                if entries + cost + parkedCost <= 320 and count < #state.slots then
                    keep[item.index] = true
                    entries, count = entries + cost, count + 1
                    for _, zone in ipairs(water.zones) do zones[zone] = true end
                end
            end
            return keep, entries + (#state.slots - count) * 3
        end
        -- Avoid rejecting a broad nearby quad based on slots that are
        -- expected to move out of their parking zones in the same update.
        local keep, cost = selectWater(1)
        if cost > 320 then keep = selectWater(3) end
        local pending = {}
        for _, item in ipairs(nearby) do
            if keep[item.index] and not state.active[item.index] then
                pending[#pending + 1] = item.index
            end
        end
        local nextWater, changed = 1, nil
        for _, slot in ipairs(state.slots) do
            local old = slot.index
            if not keep[old] then
                local index = pending[nextWater]
                if index then
                    nextWater = nextWater + 1
                    state.active[index] = true
                end
                if old then state.active[old] = nil end
                if index ~= old then
                    moveWaterSlot(slot, waterData[index] or slot.parked)
                    slot.index, changed = index, slot.element
                end
            end
        end
        if changed then
            -- Updating individual vertices leaves the native spatial index
            -- untouched. One position update rebuilds it for the whole batch.
            setElementPosition(changed, getElementPosition(changed))
        end
    end
    refresh()
    state.timer = setTimer(refresh, 100, 0)
end

function createWaterPlanes(waterData, resourceName, indexedOcean)
    if indexedOcean then
        startIndexedWater(waterData, resourceName)
        return
    end
    local rejected = 0
    for _, w in ipairs(waterData) do
        local water = instantiateWater(w)
        if water and resourceElements[resourceName] then
            table.insert(resourceElements[resourceName], water)
        elseif not water then
            rejected = rejected + 1
        end
    end
    if rejected > 0 then
        outputDebugString(("Eagle: MTA rejected %d/%d water quads for %s."):format(
            rejected, #waterData, resourceName), 2)
    end
end

-- ==============================
-- Debug system
-- ==============================

local radarAreas = {}

function createRadarFromWaterZone(x1, y1, z1, x2, y2, z2, x3, y3, z3, x4, y4, z4,rName)
    -- Find min/max XY from all corners
    local minX = math.min(x1, x2, x3, x4)
    local maxX = math.max(x1, x2, x3, x4)
    local minY = math.min(y1, y2, y3, y4)
    local maxY = math.max(y1, y2, y3, y4)
    
    local width = maxX - minX
    local height = maxY - minY
    
    
    local rArea = createRadarArea(minX, minY, width, height, math.random(0,255), math.random(0,255), math.random(0,255), 200) -- blue

    table.insert(radarAreas,{area = rArea,name = rName})

    return rArea
end


function isPlayerInRadarArea(area)
    local x, y = getElementPosition(localPlayer)

    local ax, ay = getElementPosition(area)
    local aw, ah = getRadarAreaSize (area)        

    return x >= ax and x <= ax + aw and y >= ay and y <= ay + ah
end

addCommandHandler("currentZone", function()
    local zoneName = "Unknown"
    for _, info in ipairs(radarAreas) do
        if isPlayerInRadarArea(info.area) then
            zoneName = info.name
            break
        end
    end
    outputChatBox("You are in zone: " .. zoneName, 255, 255, 0)
end)
