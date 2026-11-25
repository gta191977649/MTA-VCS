TrafficCustody = {}

function getTrafficIslandAt(x, y, z)
    return exports.wasted:GetLevelFromPosition(x, y, z)
end

function TrafficCustody.restartPoint(x, y, z)
    return exports.wasted:FindClosestPoliceRestartPoint(x, y, z)
end
