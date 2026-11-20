local routesByOwner = {}

-- Callers supply their fixed-wing route catalog once, independently of the
-- vehicles they own. Only small slot and clock arguments cross resources
-- during subsequent position updates.
function setPlaneRoutes(routes)
    if type(routes) ~= "table" then return false end
    for id, route in pairs(routes) do
        if not CPlane.IsValidRoute(route) or route.id ~= id then return false end
    end
    routesByOwner[sourceResource or getThisResource()] = routes
    return true
end

function samplePlaneRoute(routeId, clock, slot)
    local routes = routesByOwner[sourceResource or getThisResource()]
    return routes and CPlane.SampleFlight(routes[routeId], clock, slot) or false
end

function updatePlaneRouteVehicle(vehicle, routeId, clock, slot, initialize)
    if not isElement(vehicle) or getElementType(vehicle) ~= "vehicle" or getVehicleType(vehicle) ~= "Plane" then
        return false
    end
    local pose = samplePlaneRoute(routeId, clock, slot)
    if not pose then return false end
    if initialize and (not setVehicleLocked(vehicle, true) or not setElementSyncer(vehicle, false)
        or not setElementFrozen(vehicle, true)) then return false end
    return CPlane.ApplyPose(vehicle, pose)
end

addEventHandler("onResourceStop", root, function(resource)
    routesByOwner[resource] = nil
end)
