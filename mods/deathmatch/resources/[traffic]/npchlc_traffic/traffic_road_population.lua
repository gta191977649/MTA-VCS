TrafficRoadPopulation = {}

local cellSize = 160

function TrafficRoadPopulation.resolveMode(graph, requested)
    if requested == "zone" then return "zone" end
    if requested == "scheduled" then
        if graph.roadPopulation then return "scheduled" end
        return "zone", "Scheduled road population is unavailable for this graph. Using zone density."
    end

    local mode = graph.edition ~= "SLUS-21590 USA v1.00" and graph.roadPopulation and "scheduled" or "zone"
    if requested and requested ~= "auto" then
        return mode, "Invalid roadPopulationMode. Using auto."
    end
    return mode
end

function TrafficRoadPopulation.zoneTarget(profile, multiplier)
    -- SLUS_215.90 0x00430290 truncates the scaled zone value before applying 0.7.
    return math.ceil(math.floor(profile.vehicleDensity * multiplier) * 0.7)
end

local function validateSchedule(schedule)
    assert(type(schedule) == "table" and #schedule == 24, "invalid scheduled road population schedule")
    for _, value in ipairs(schedule) do
        assert(type(value) == "number" and value >= 0 and value < math.huge, "invalid scheduled road density")
    end
    return schedule
end

function TrafficRoadPopulation.build(data, checkpoint)
    assert(data.cap == 12 and type(data.schedules) == "table" and type(data.zones) == "table",
        "invalid scheduled road population")
    local profile = {cap = data.cap, fallback = validateSchedule(data.fallback), cells = {}}
    for _, schedule in pairs(data.schedules) do validateSchedule(schedule) end
    for _, row in ipairs(data.zones) do
        local label, bounds = row[1], row[2]
        assert(data.schedules[label] and type(bounds) == "table" and #bounds == 6, "invalid scheduled road zone")
        for _, coordinate in ipairs(bounds) do
            assert(type(coordinate) == "number" and coordinate >= -32768 and coordinate <= 32767,
                "invalid scheduled road zone bounds")
        end
        local zone = {bounds = bounds, schedule = data.schedules[label],
            span = bounds[4] - bounds[1] + bounds[5] - bounds[2]}
        for x = math.floor(bounds[1] / cellSize), math.floor(bounds[4] / cellSize) do
            local column = profile.cells[x] or {}
            profile.cells[x] = column
            for y = math.floor(bounds[2] / cellSize), math.floor(bounds[5] / cellSize) do
                local cell = column[y] or {}
                column[y] = cell
                cell[#cell + 1] = zone
            end
            checkpoint()
        end
    end
    return profile
end

function TrafficRoadPopulation.cap(profile, x, y, z, hour, day, multiplier)
    local column = profile.cells[math.floor(x / cellSize)]
    local cell = column and column[math.floor(y / cellSize)]
    local schedule, smallest = profile.fallback, math.huge
    if cell then
        for _, zone in ipairs(cell) do
            local b = zone.bounds
            if zone.span < smallest and x >= b[1] and x <= b[4] and y >= b[2] and y <= b[5] and z >= b[3] and z <= b[6] then
                schedule, smallest = zone.schedule, zone.span
            end
        end
    end
    -- CPopCycle::Update switches to the weekend table on Saturday evening
    -- and returns to the weekday table on Monday evening.
    local weekend = day == 7 or day == 1 and hour < 20 or day == 6 and hour >= 20
    local target = schedule[math.floor(hour / 2) + (weekend and 13 or 1)]
    return math.ceil(math.min(profile.cap, target) * multiplier)
end
