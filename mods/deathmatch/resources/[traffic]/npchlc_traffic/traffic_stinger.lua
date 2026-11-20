TrafficStinger = {}

-- 0039CF70 builds 60 offsets. 0039D340 advances once per pair of slats.
function TrafficStinger.geometry(ageMs)
    local progress = math.max(0, math.min(1, ageMs / 2500))
    local index = math.min(59, math.floor(progress * 60))
    return 1.8 * math.sin(math.rad(index)), progress * 60
end
