TrafficPopulation = {}

local zoneCellSize = 256
local boxes = { "minX", "minY", "minZ", "maxX", "maxY", "maxZ" }

local function finite(value)
    return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function requireRecord(condition, label, index)
    if not condition then
        error(("invalid traffic population %s %d"):format(label, index), 0)
    end
end

local function indexZone(cells, zone)
    for x = math.floor(zone.minX / zoneCellSize), math.floor(zone.maxX / zoneCellSize) do
        local column = cells[x]
        if not column then
            column = {}
            cells[x] = column
        end
        for y = math.floor(zone.minY / zoneCellSize), math.floor(zone.maxY / zoneCellSize) do
            local bucket = column[y]
            if not bucket then
                bucket = {}
                column[y] = bucket
            end
            bucket[#bucket + 1] = zone
        end
    end
end

function TrafficPopulation.build(data, checkpoint)
    if not data then
        return
    end
    requireRecord(type(data) == "table" and type(data.zones) == "table" and #data.zones > 0
        and type(data.records) == "table" and type(data.pedGroups) == "table", "data", 0)
    local index = { cells = {}, fallback = data.zones[1], records = data.records, pedGroups = data.pedGroups }

    for slot, group in ipairs(data.pedGroups) do
        requireRecord(type(group) == "table" and #group == 16, "ped group", slot - 1)
        for _, model in ipairs(group) do
            requireRecord(finite(model) and model % 1 == 0 and model >= -1, "ped group model", slot - 1)
        end
        checkpoint()
    end

    for slot, record in ipairs(data.records) do
        requireRecord(type(record) == "table" and record.id == slot - 1
            and type(record.values) == "table" and #record.values == 36, "zone record", slot - 1)
        for _, value in ipairs(record.values) do
            requireRecord(finite(value) and value % 1 == 0 and value >= 0 and value <= 65535,
                "zone record value", slot - 1)
        end
        requireRecord(index.pedGroups[record.values[36] + 1], "zone record group", slot - 1)
        checkpoint()
    end

    for slot, zone in ipairs(data.zones) do
        requireRecord(type(zone) == "table" and zone.id == slot - 1 and finite(zone.day)
            and finite(zone.night) and index.records[zone.day + 1] and index.records[zone.night + 1],
                "zone", slot - 1)
        for _, name in ipairs(boxes) do
            requireRecord(finite(zone[name]) and math.abs(zone[name]) <= 16384, "zone bound", slot - 1)
        end
        requireRecord(zone.minX <= zone.maxX and zone.minY <= zone.maxY and zone.minZ <= zone.maxZ,
            "zone bounds", slot - 1)
        if slot > 1 then
            indexZone(index.cells, zone)
        end
        checkpoint()
    end
    return index
end

-- 0x00367BB0 uses the first matching 3-D zone; zone zero is the fallback.
local function findZone(index, x, y, z)
    local column = index.cells[math.floor(x / zoneCellSize)]
    local bucket = column and column[math.floor(y / zoneCellSize)]
    for _, zone in ipairs(bucket or {}) do
        if zone.minX <= x and x <= zone.maxX and zone.minY <= y and y <= zone.maxY
            and zone.minZ <= z and z <= zone.maxZ then
            return zone
        end
    end
    return index.fallback
end

-- 0x00368260 only interpolates field zero using different source records.
-- The pedestrian model group instead switches at 05:00 and 19:00.
function TrafficPopulation.sample(index, x, y, z, hour, modelSlot)
    if not index or not finite(x) or not finite(y) or not finite(z) or not finite(hour)
        or hour % 1 ~= 0 or hour < 0 or hour > 23
        or (modelSlot ~= nil and (not finite(modelSlot) or modelSlot % 1 ~= 0 or modelSlot < 0 or modelSlot > 15)) then
        return false
    end
    local zone = findZone(index, x, y, z)
    local day = index.records[zone.day + 1].values
    local night = index.records[zone.night + 1].values
    local current = night
    local vehicleDensity
    if hour >= 8 and hour < 19 then
        current = day
        vehicleDensity = day[1]
    elseif hour < 5 or hour >= 22 then
        vehicleDensity = night[1]
    else
        local daylightFraction = hour < 8 and (8 - hour) / 3 or (hour - 19) / 3
        vehicleDensity = math.floor(day[1] * daylightFraction + night[1] * (1 - daylightFraction))
    end
    local groupId = (hour >= 5 and hour < 19 and day or night)[36]
    local group = index.pedGroups[groupId + 1]
    local model = modelSlot and group[modelSlot + 1]
    return {
        zoneId = zone.id,
        dayProfileId = zone.day,
        nightProfileId = zone.night,
        vehicleDensity = vehicleDensity,
        pedestrianDensity = current[25],
        pedestrianGroupId = groupId,
        originalModelId = model and model >= 0 and model or nil,
    }
end
