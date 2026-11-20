WantedRules = {}

-- SLUS_215.90 0x003AA918, 0x003AAB80 and the initial globals at 0x00489EE8.
local threshold = {[0] = 0, 40, 180, 550, 1200, 2400, 4800}
local scriptedPoints = {[0] = 0, 60, 200, 570, 1220, 2420, 4820}
local maximumPoints = 9600

-- Indexes are the crime IDs consumed by 0x003AB458, after event translation.
local crimePoints = {0, 5, 45, 30, 80, 15, 10, 5, 10, 18, 80, 400, 20, 80, 20, 500, 25, 35, 100}

-- Cops, vehicles and roadblock threshold come from 0x003AA918. The unit
-- requests follow 0x003C90E8 with the default (no script override) flags.
local response = {
    [0] = {0, 0, 0},
    {2, 1, 0}, {3, 2, 0}, {4, 3, 12}, {6, 3, 18}, {8, 4, 24}, {10, 4, 30},
}

function WantedRules.forLevel(level)
    return scriptedPoints[level]
end

function WantedRules.levelForPoints(points)
    for level = 6, 1, -1 do
        if points >= threshold[level] then return level end
    end
    return 0
end

function WantedRules.isCrimeType(crimeType)
    return type(crimeType) == "number" and crimePoints[crimeType] ~= nil
end

function WantedRules.addCrime(points, parolePoints, crimeType, reduced, multiplier)
    local amount = crimePoints[crimeType] * (multiplier or 1) * (reduced and 0.333 or 1)
    return math.min(maximumPoints, math.max(parolePoints, math.floor(points + amount)))
end

function WantedRules.getPoliceResponse(level)
    local counts = response[level]
    if not counts then return false end
    return {
        pursuitPedLimit = counts[1],
        pursuitVehicleLimit = counts[2],
        roadblockThreshold = counts[3],
        policeHelicopters = level >= 3 and 1 or 0,
        undercover = level >= 3,
        swat = level == 4,
        fbi = level == 5,
        army = level == 6,
    }
end
