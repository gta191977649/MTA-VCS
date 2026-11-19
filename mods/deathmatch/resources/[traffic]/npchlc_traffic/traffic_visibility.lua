TrafficVisibility = {
    profileKey = "npchlc_traffic:visibility",
    retiringKey = "npchlc_traffic:retiring",
    roadRangeKey = "npchlc_traffic:roadRange",
    fadeInMs = 500,
    fadeOutMs = 350,
    roadRange = 160, -- SLUS_215.90 0x00433378, ordinary outward retention branch.
    pedestrianRange = 65, -- SLUS_215.90 0x002B0200, ordinary pedestrians.
    pedestrianMaxScale = 1.5,
}

function TrafficVisibility.pedestrianScale(observer)
    -- SLUS_215.90 0x002B44C8, also used by the pedestrian spawner.
    local vehicle = getPedOccupiedVehicle(observer)
    if not vehicle then return 1 end
    local vx, vy = getElementVelocity(vehicle)
    return math.min(TrafficVisibility.pedestrianMaxScale, math.max(1, math.sqrt(vx * vx + vy * vy) + 0.9))
end
