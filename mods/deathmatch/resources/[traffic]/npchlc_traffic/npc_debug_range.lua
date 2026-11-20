TrafficNPCDebugRange = {}

local fullDistance, limit = 12, 35

function TrafficNPCDebugRange.alpha(ped, viewer, x, y, z)
    if getElementInterior(ped) ~= getElementInterior(viewer)
        or getElementDimension(ped) ~= getElementDimension(viewer) then return 0 end
    local px, py, pz = getElementPosition(ped)
    local squared = (px-x)^2 + (py-y)^2 + (pz-z)^2
    if squared >= limit^2 then return 0 end
    if squared <= fullDistance^2 then return 255 end
    return math.ceil(255 * (limit - math.sqrt(squared)) / (limit - fullDistance))
end
