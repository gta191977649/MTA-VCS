local sampledRoad = setmetatable({}, {__mode = "k"})
local chassis = setmetatable({}, {__mode = "k"})
local SAMPLE_MS = 75
local groundDebug = false

local function finite(value)
    return type(value) == "number" and value > -math.huge and value < math.huge
end

function resetNPCTrafficRailGround(vehicle)
    sampledRoad[vehicle], chassis[vehicle] = nil, nil
end

addEvent("npc_hlc:onVehicleGroundGeometry", false)
addEventHandler("npc_hlc:onVehicleGroundGeometry", root, function() resetNPCTrafficRailGround(source) end)
addEventHandler("onClientElementStreamIn", root, function() resetNPCTrafficRailGround(source) end)
addEventHandler("onClientElementStreamOut", root, function() resetNPCTrafficRailGround(source) end)

local function chassisFor(vehicle)
    local model = getElementModel(vehicle)
    local provider = getElementData(vehicle, "npchlc_traffic:modelProvider", false)
    local cached = chassis[vehicle]
    if cached and cached.model == model and cached.provider == provider then return cached end
    local resource = type(provider) == "string" and getResourceFromName(provider)
    local metadata
    if resource and getResourceState(resource) == "running" then
        for _, name in ipairs(getResourceExportedFunctions(resource) or {}) do
            if name == "getTrafficVehicleGroundGeometry" then
                metadata = call(resource, name, vehicle)
                break
            end
        end
    end
    cached = {model = model, provider = provider, metadata = metadata}
    chassis[vehicle] = cached
    return cached
end

local function readAxle(vehicle, components, names, geometry, diameter, wheelScale, suspension, defaultY, fallback, defaultX)
    local radius = finite(diameter) and diameter > 0 and diameter * 0.5 * wheelScale or nil
    for _, name in ipairs(names) do
        if components[name] ~= nil then
            local x, y, z = getVehicleComponentPosition(vehicle, name, "root")
            if finite(y) and finite(z) then
                local visibleRadius
                if geometry and geometry[3] then
                    local _, _, scaleZ = getVehicleComponentScale(vehicle, name, "root")
                    if finite(scaleZ) and scaleZ > 0 then visibleRadius = geometry[3] * scaleZ end
                end
                local size = visibleRadius or radius
                if size then return {y, z, size, "component", finite(x) and x or defaultX} end
            end
        end
    end
    if geometry and (geometry[3] or radius) then
        return {geometry[1], geometry[2] + (suspension or 0), geometry[3] and geometry[3] * wheelScale or radius, "suspension", defaultX}
    end
    return {geometry and geometry[1] or defaultY, -fallback, 0, "collision", defaultX}
end

local function readContacts(vehicle, body, fallback)
    local components = getVehicleComponents(vehicle) or {}
    local wheels = getVehicleModelWheelSize(body.model) or {}
    local wheelScale = getVehicleWheelScale(vehicle)
    if not finite(wheelScale) or wheelScale <= 0 then wheelScale = 1 end
    local kind = getVehicleType(vehicle)
    local suspension
    if body.metadata and kind == "Automobile" then
        local handling = getVehicleHandling(vehicle)
        local upper = handling and handling.suspensionUpperLimit
        local lower = handling and handling.suspensionLowerLimit
        local force = handling and handling.suspensionForceLevel
        if finite(upper) and finite(lower) and finite(force) and upper > lower and force > 0 then
            -- SA CAutomobile::SetupSuspensionLines, expressed as the static wheel centre.
            suspension = upper - (1 - 1 / (4 * force)) * (upper - lower)
        end
    end
    local frontGeometry, rearGeometry = body.metadata and body.metadata[1], body.metadata and body.metadata[2]
    local left, _, bottom, right = getElementBoundingBox(vehicle)
    if finite(bottom) and bottom < 0 then fallback = -bottom end
    local halfTrack = finite(left) and finite(right) and math.max(0, (right - left) * 0.37) or 0.8
    local bike = kind == "Bike" or kind == "Bicycle"
    local front = readAxle(vehicle, components, {"wheel_lf_dummy", "wheel_front"}, frontGeometry,
        wheels.front_axle, wheelScale, suspension, 1.5, fallback, bike and 0 or -halfTrack)
    local rear = readAxle(vehicle, components, {"wheel_lb_dummy", "wheel_rear"}, rearGeometry,
        wheels.rear_axle, wheelScale, suspension, -1.5, fallback, bike and 0 or -halfTrack)
    if not bike then
        local frontRight = readAxle(vehicle, components, {"wheel_rf_dummy"}, frontGeometry,
            wheels.front_axle, wheelScale, suspension, front[1], fallback, halfTrack)
        local rearRight = readAxle(vehicle, components, {"wheel_rb_dummy"}, rearGeometry,
            wheels.rear_axle, wheelScale, suspension, rear[1], fallback, halfTrack)
        -- On models with a single usable dummy per axle, mirror that wheel's
        -- installed geometry. A missing right wheel must not change ride height.
        local function pair(leftWheel, rightWheel)
            if rightWheel[4] == "component" and leftWheel[4] ~= "component" then
                leftWheel = {rightWheel[1], rightWheel[2], rightWheel[3], rightWheel[4], -rightWheel[5]}
            elseif rightWheel[4] ~= "component" then
                rightWheel = {leftWheel[1], leftWheel[2], leftWheel[3], leftWheel[4], -leftWheel[5]}
            end
            return leftWheel, rightWheel
        end
        front, frontRight = pair(front, frontRight)
        rear, rearRight = pair(rear, rearRight)
        local contacts = {front, rear, frontRight, rearRight}
        for _, name in ipairs({"wheel_lm_dummy", "wheel_rm_dummy"}) do
            if components[name] ~= nil then
                local wheel = readAxle(vehicle, components, {name}, rearGeometry, wheels.rear_axle,
                    wheelScale, suspension, 0, fallback, name == "wheel_lm_dummy" and -halfTrack or halfTrack)
                if wheel[4] == "component" then contacts[#contacts + 1] = wheel end
            end
        end
        return contacts
    end
    return {front, rear}
end

local function surfaceAt(vehicle, x, y, z, upper, lower, upward)
    local startZ, endZ = z + upper, z - lower
    if upward then startZ, endZ = endZ, startZ end
    local hit, _, _, height, _, nx, ny, nz = processLineOfSight(x, y, startZ, x, y, endZ,
        true, false, false, true, false, false, false, false, vehicle)
    if not hit then return false end
    if finite(nz) and nz < 0.7 then return false end
    local water = getWaterLevel(x, y, height, true)
    if type(water) == "number" and height <= water then return false, nil, nil, nil, "water" end
    return height, nx, ny, nz
end

local function wheelGround(vehicle, x, y, dx, dy, wheel, height, grade, cross, tolerance)
    local side, along = wheel[5], wheel[1]
    local expected = height + along * grade + side * cross
    local wx, wy = x + dx * along + dy * side, y + dy * along - dx * side
    local ground, _, _, _, reason = surfaceAt(vehicle, wx, wy, expected, 0.08, 0.08)
    if not ground and reason ~= "water" then
        ground = surfaceAt(vehicle, wx, wy, expected, tolerance, tolerance)
    end
    if ground and math.abs(ground - expected) <= tolerance then return ground end
    return false
end

local function mean(a, b)
    if a and b then return (a + b) * 0.5 end
    return a or b
end

local function fitGround(vehicle, body, x, y, reference, dx, dy, clearance, pathGrade, previous, now)
    local expected = reference
    if previous and previous.height and (now - previous.tick) % 4294967296 <= 200 then
        local px, py = x - previous.x, y - previous.y
        local predicted = previous.road + (px * previous.dx + py * previous.dy) * previous.grade
            + (px * previous.dy - py * previous.dx) * previous.cross
        -- Follow the confirmed deck while the route moves through adjacent
        -- samples. Packed route Z can change by metres on a flat street.
        if px * px + py * py <= 9 and math.abs(predicted - reference) <= 7 then expected = predicted end
    end
    local road, nx, ny, nz, reason = surfaceAt(vehicle, x, y, expected, 0.30, 0.55)
    if not road and reason ~= "water" then
        -- The packed PS2 path Z can be below the converted road collision.
        -- Try the lower surface first to avoid selecting an overhead deck.
        road, nx, ny, nz, reason = surfaceAt(vehicle, x, y, expected, 0, 3)
        if not road and reason ~= "water" then
            road, nx, ny, nz, reason = surfaceAt(vehicle, x, y, expected, 1.75, 0, true)
            if not road and reason ~= "water" then
                -- Converted collision may only be visible to a downward ray.
                road, nx, ny, nz, reason = surfaceAt(vehicle, x, y, expected, 1.75, 0)
            end
        end
    end
    if not road then return false, reason end
    local grade, cross = pathGrade or 0, 0
    local hasNormal = finite(nx) and finite(ny) and finite(nz)
    if hasNormal then grade, cross = -(nx * dx + ny * dy) / nz, -(nx * dy - ny * dx) / nz end
    local wheels = readContacts(vehicle, body, clearance)
    local front, rear, frontRight, rearRight = unpack(wheels)
    local tolerance = 0.55
    local fg = wheelGround(vehicle, x, y, dx, dy, front, road, grade, cross, tolerance)
    local rg = wheelGround(vehicle, x, y, dx, dy, rear, road, grade, cross, tolerance)
    local frg, rrg
    if frontRight and frontRight[5] ~= front[5] then
        frg = wheelGround(vehicle, x, y, dx, dy, frontRight, road, grade, cross, tolerance)
    end
    if rearRight and rearRight[5] ~= rear[5] then
        rrg = wheelGround(vehicle, x, y, dx, dy, rearRight, road, grade, cross, tolerance)
    end
    local frontGround, rearGround = mean(fg, frg), mean(rg, rrg)
    local frontSide = fg and frg and (frg - fg) / (frontRight[5] - front[5])
    local rearSide = rg and rrg and (rrg - rg) / (rearRight[5] - rear[5])
    cross = mean(frontSide, rearSide) or cross
    local frontX = mean(fg and front[5], frg and frontRight[5]) or front[5]
    local rearX = mean(rg and rear[5], rrg and rearRight[5]) or rear[5]
    if frontGround and rearGround and front[1] - rear[1] > 0.1 then
        grade = (frontGround - rearGround - (frontX - rearX) * cross) / (front[1] - rear[1])
    end
    local frontZ = mean(front[2], frontRight and frontRight[2])
    local rearZ = mean(rear[2], rearRight and rearRight[2])
    local radiusDelta = mean(front[3], frontRight and frontRight[3]) - mean(rear[3], rearRight and rearRight[3])
    local wheelbase, difference = front[1] - rear[1], frontZ - rearZ
    local span = math.sqrt(wheelbase ^ 2 + difference ^ 2)
    local pitch = math.atan(grade)
    if wheelbase > 0.1 then
        pitch = pitch + math.asin(math.max(-1, math.min(1, radiusDelta / span))) - math.atan2(difference, wheelbase)
    end
    local roll = -math.atan(cross)
    local cy, sy, cr, sr = math.cos(pitch), math.sin(pitch), math.cos(roll), math.sin(roll)
    local normalScale = math.sqrt(1 + grade * grade + cross * cross)
    local supportedZ = -math.huge
    local hits = {fg, rg, frg, rrg}
    local debugContacts = groundDebug and {} or nil
    for index, wheel in ipairs(wheels) do
        local along = wheel[1] * cy - wheel[2] * sy
        local up = wheel[1] * sy + wheel[2] * cy
        local side = wheel[5] * cr + up * sr
        local height = up * cr - wheel[5] * sr
        local hit = hits[index]
        if index > 4 then hit = wheelGround(vehicle, x, y, dx, dy, wheel, road, grade, cross, tolerance) end
        local surface = hit or (road + wheel[1] * grade + wheel[5] * cross)
        local requiredZ = surface + (along - wheel[1]) * grade + (side - wheel[5]) * cross
            + wheel[3] * normalScale - height
        supportedZ = math.max(supportedZ, requiredZ)
        if debugContacts then
            debugContacts[index] = {wheel[1], wheel[5], hit, -requiredZ}
        end
    end
    return {x = x, y = y, dx = dx, dy = dy, tick = now, body = body, front = front, rear = rear,
        frontGround = fg, rearGround = rg, frontRightGround = frg, rearRightGround = rrg,
        height = supportedZ, road = road, grade = grade, cross = cross, pitch = pitch, roll = roll,
        contacts = debugContacts}
end

function groundNPCTrafficRail(vehicle, x, y, pathZ, dx, dy, clearance, pathGrade)
    local now = getTickCount()
    local sample = sampledRoad[vehicle]
    local body = chassisFor(vehicle)
    if not sample or sample.body ~= body or (now - sample.tick) % 4294967296 >= SAMPLE_MS
        or sample.dx * dx + sample.dy * dy < 0.94
        or (sample.x - x) ^ 2 + (sample.y - y) ^ 2 >= 1 then
        local nextSample, reason = fitGround(vehicle, body, x, y, pathZ - clearance, dx, dy, clearance, pathGrade, sample, now)
        if nextSample then
            sample = nextSample
            sampledRoad[vehicle] = sample
        elseif reason == "water" or not sample or sample.body ~= body or (now - sample.tick) % 4294967296 > 125
            or (x - sample.x) ^ 2 + (y - sample.y) ^ 2 > 2.25 then
            sampledRoad[vehicle] = nil
            return false
        end
    end
    local px, py = x - sample.x, y - sample.y
    return sample.height + (px * sample.dx + py * sample.dy) * sample.grade
        + (px * sample.dy - py * sample.dx) * sample.cross, math.deg(sample.pitch), math.deg(sample.roll)
end

-- One wheel fit when native physics acquires a server-driven road vehicle.
-- Subsequent frames leave suspension, jumps, pitch and roll to the client.
local function fitHandoff(vehicle, pending, roadPose)
    if not (getElementData(vehicle,"vcs_vehicle:originalModel",false)
        or getElementData(vehicle,"npchlc_traffic:originalModel",false)) then return true end
    local kind=getVehicleType(vehicle)
    if kind~="Automobile" and kind~="Bike" and kind~="Quad" and kind~="Monster Truck" then return true end
    local x,y,z=getElementPosition(vehicle)
    local now=getTickCount()
    local vx,vy,vz=getElementVelocity(vehicle)
    local frame=getElementMatrix(vehicle)
    if not frame or frame[3][3]<0.75 then return true end
    if vz>0.12 and not (pending and pending.onDeck) then return true end
    if not pending then pending={x=x,y=y,z=z,at=now} end
    if (now-pending.at)%4294967296>2000 or (x-pending.x)^2+(y-pending.y)^2>100 then return true end
    if pending.sampleAt and (now-pending.sampleAt)%4294967296<25 then return pending end
    pending.sampleAt=now
    local _,_,bottom=getElementBoundingBox(vehicle)
    if not finite(bottom) or bottom>=0 then return pending end
    local dx,dy=frame[2][1],frame[2][2]
    local length=math.sqrt(dx*dx+dy*dy)
    if length<0.5 then return true end
    local expected=pending.z+bottom
    local predicted
    if roadPose then
        local ox,oy=x-roadPose[1],y-roadPose[2]
        if ox*ox+oy*oy<=100 then
            local yaw=math.rad(roadPose[7])
            local along=-ox*math.sin(yaw)+oy*math.cos(yaw)
            local across=ox*math.cos(yaw)+oy*math.sin(yaw)
            predicted=roadPose[3]+along*math.tan(math.rad(roadPose[4]))-across*math.tan(math.rad(roadPose[5]))
            expected=predicted-roadPose[6]
        end
    end
    local lower=surfaceAt(vehicle,x,y,expected,0.04,2)
    local upper=surfaceAt(vehicle,x,y,expected,2,0,true)
    if not upper then upper=surfaceAt(vehicle,x,y,expected,2,0) end
    local road=lower
    if upper and (not road or math.abs(upper-expected)<math.abs(road-expected)) then road=upper end
    if not road or (predicted and math.abs(road-expected)>1) then
        -- Map collision can arrive later than the car. Support it on the
        -- verified server deck during this short acquisition window.
        if predicted and vz<=0 and z<predicted-0.04 then
            setElementPosition(vehicle,x,y,predicted,false)
            setElementVelocity(vehicle,vx,vy,0)
        end
        return pending
    end
    -- The visible wheel dummies acquire their suspension positions over the
    -- first physics frames, including on long trucks and vans.
    sampledRoad[vehicle]=nil
    local support,pitch,roll=groundNPCTrafficRail(vehicle,x,y,road-bottom,dx/length,dy/length,-bottom)
    if not support then return pending end
    -- A vehicle already airborne above the deck keeps its flight path.
    if not pending.onDeck and support<z-0.3 and (vx*vx+vy*vy>0.02 or math.abs(vz)>0.06)
        and not isVehicleOnGround(vehicle) then return true end
    pending.onDeck=true
    local rx,ry,yaw=getElementRotation(vehicle,"ZXY")
    local pitchError=(rx-pitch+180)%360-180
    local rollError=(ry-roll+180)%360-180
    if math.abs(support-z)>0.035 or math.abs(pitchError)>2 or math.abs(rollError)>2 then
        setElementPosition(vehicle,x,y,support,false)
        setElementRotation(vehicle,pitch,roll,yaw,"ZXY")
    end
    -- Remove the suspension impulse left by the old chassis placement while
    -- preserving speed along both the grade and the bank.
    local deckVZ=((vx*dx+vy*dy)*math.tan(math.rad(pitch))
        -(vx*dy-vy*dx)*math.tan(math.rad(roll)))/length
    if math.abs(vz-deckVZ)>0.003 then setElementVelocity(vehicle,vx,vy,deckVZ) end
    if (now-pending.at)%4294967296<350 then return pending end
    return true
end

local earlyContacts={}

function settleNPCRoadHandoff(vehicle,pending,roadPose)
    pending=pending or earlyContacts[vehicle]
    earlyContacts[vehicle]=nil
    return fitHandoff(vehicle,pending,roadPose)
end

local function beginRoadContact()
    if getElementType(source)~="vehicle" or not isElementStreamedIn(source) or not isElementSyncer(source)
        or not (getElementData(source,"npchlc_traffic:rail",false)
            or getElementData(source,"mission:turismoRival",false)) then return end
    local pending=fitHandoff(source,nil)
    earlyContacts[source]=pending~=true and pending or nil
end

addEventHandler("onClientElementStreamIn",root,beginRoadContact)
addEventHandler("npc_hlc:onVehicleGroundGeometry",root,beginRoadContact)
addEventHandler("onClientElementDataChange",root,function(key)
    if key=="npchlc_traffic:rail" or key=="mission:turismoRival" then beginRoadContact() end
end)
addEventHandler("onClientPreRender",root,function()
    for vehicle,pending in pairs(earlyContacts) do
        if not isElement(vehicle) or not isElementStreamedIn(vehicle) or not isElementSyncer(vehicle)
            or fitHandoff(vehicle,pending)==true then earlyContacts[vehicle]=nil end
    end
end,true,"high")

local function closestGroundSample()
    local x, y, z = getElementPosition(localPlayer)
    local closest, distance = nil, 25 ^ 2
    for vehicle, sample in pairs(sampledRoad) do
        if isElement(vehicle) and getElementData(vehicle, "npchlc_traffic:rail", false) then
            local px, py, pz = getElementPosition(vehicle)
            local squared = (px - x) ^ 2 + (py - y) ^ 2 + (pz - z) ^ 2
            if squared < distance then closest, distance = {vehicle, sample}, squared end
        end
    end
    return closest
end

addCommandHandler("trafficgrounddebug", function()
    groundDebug = not groundDebug
    outputChatBox("Traffic ground debug " .. (groundDebug and "on" or "off"))
    if not groundDebug then return end
    local closest = closestGroundSample()
    if not closest then return end
    local vehicle, sample = closest[1], closest[2]
    local function describe(axle, ground)
        return ("Y %.3f, Z %.3f, radius %.3f, road %s (%s)"):format(axle[1], axle[2], axle[3],
            ground and ("%.3f"):format(ground) or "missing", axle[4])
    end
    outputChatBox(("Traffic ground: model %s (base %d), front %s, rear %s, Z %.3f, pitch %.2f, roll %.2f"):format(
        tostring(getElementData(vehicle, "npchlc_traffic:originalModel", false)), sample.body.model,
        describe(sample.front, sample.frontGround), describe(sample.rear, sample.rearGround),
        sample.height, math.deg(sample.pitch), math.deg(sample.roll)))
end)

addEventHandler("onClientRender", root, function()
    if not groundDebug then return end
    local x, y, z = getElementPosition(localPlayer)
    for _, vehicle in ipairs(getElementsWithinRange(x, y, z, 25, "vehicle")) do
        if isElementStreamedIn(vehicle) and getElementData(vehicle, "npchlc_traffic:rail", false) then
            local px, py, pz = getElementPosition(vehicle)
            local _, _, yaw = getElementRotation(vehicle)
            local _, _, bottom = getElementBoundingBox(vehicle)
            groundNPCTrafficRail(vehicle, px, py, pz, -math.sin(math.rad(yaw)), math.cos(math.rad(yaw)), -(bottom or 0))
        end
    end
    local closest = closestGroundSample()
    local sample = closest and closest[2]
    if not sample or not sample.contacts then return end
    local names = {"FL", "RL", "FR", "RR"}
    local labels = {}
    for index, contact in ipairs(sample.contacts) do
        local x = sample.x + sample.dx * contact[1] + sample.dy * contact[2]
        local y = sample.y + sample.dy * contact[1] - sample.dx * contact[2]
        local z = contact[3] or sample.road
        local color = contact[3] and tocolor(70, 240, 100) or tocolor(250, 80, 70)
        dxDrawLine3D(x, y, z - 0.2, x, y, z + 0.6, color, 2)
        local sx, sy = getScreenFromWorldPosition(x, y, z + 0.55)
        if sx then
            local name = names[index] or (contact[2] < 0 and "ML" or "MR")
            local _, _, actualZ = getElementPosition(closest[1])
            local label = contact[3] and ("%s fit %+.2f m"):format(name, actualZ + contact[4])
                or name .. " surface rejected"
            labels[#labels+1] = {label,sx,sy-dxGetFontHeight(1,"default-bold")/2,color,"center",1}
        end
    end
    if #labels>0 then exports.frontend:drawDebugLabels(labels) end
end)
