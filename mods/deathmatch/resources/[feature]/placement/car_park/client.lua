-- CCarGenerator::DoInternalProcessing resolves a surface before adding the
-- vehicle's height above it. Wait for both providers instead of dropping a
-- native hull through a map/model that has not streamed yet.
local submitted = setmetatable({}, {__mode = "k"})

local function DoInternalProcessing(vehicle)
    local parking = getElementData(vehicle, "placement:parking")
    if type(parking) ~= "table" or not isElementStreamedIn(vehicle)
        or getElementInterior(vehicle) ~= getElementInterior(localPlayer)
        or getElementDimension(vehicle) ~= getElementDimension(localPlayer) then return end
    local original = getElementData(vehicle, "vcs_vehicle:originalModel")
    if not exports.vcs_model:HasModelLoaded(original) then return end
    local x, y, z, serial = unpack(parking)
    local px, py, pz = getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x, y, z, px, py, pz) > 100 then return end
    local now = getTickCount()
    if submitted[vehicle] and now - submitted[vehicle] < 2000 then return end
    -- The authored Z selects the floor: never cast from the sky onto roofs or
    -- from street level into the below-map mall.
    local hit, _, _, ground = processLineOfSight(x, y, z + 3, x, y, z - 8,
        true, false, false, true, false, false, false, false, vehicle)
    local water = getWaterLevel(x, y, z + 3)
    local boat = getVehicleType(vehicle) == "Boat"
    if boat or not hit then
        -- Missing road collision is not permission to drop a land vehicle
        -- onto the sea underneath a bridge or coastal street.
        if not boat and original ~= 278 and original ~= 198 then return end
        if not water or math.abs(water - z) > 8 then return end
        ground = water
    end
    local _, _, bottom = getElementBoundingBox(vehicle)
    if type(bottom) ~= "number" then return end
    local clearance = math.max(0.05, -bottom)
    local axles = exports.vcs_model:getVcsVehicleGroundGeometry(vehicle)
    if axles and axles[1][3] and axles[2][3] then
        clearance = math.max(axles[1][3] - axles[1][2], axles[2][3] - axles[2][2])
    end
    -- Hull buoyancy, rather than its keel, determines a boat's rest height.
    if boat then clearance = 0.05 end
    if clearance > 8 then return end
    submitted[vehicle] = now
    triggerServerEvent("placement:placeOnRoad", resourceRoot, vehicle, serial, ground, clearance)
end

setTimer(function()
    -- The factory creates these elements in vcs_vehicle. Server reparenting
    -- does not move them into placement's client resource tree.
    for _, vehicle in ipairs(getElementsByType("vehicle", root, true)) do
        DoInternalProcessing(vehicle)
    end
end, 500, 0)
