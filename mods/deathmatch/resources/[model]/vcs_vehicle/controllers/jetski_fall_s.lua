local active = {}
local motion = setmetatable({}, {__mode="k"})
local clips = {"KO_skid_back","BIKE_fall_off","KO_skid_front","BIKE_fall_off"}

local function finite(n)
    return type(n) == "number" and n == n and math.abs(n) < math.huge
end

local function isSki(vehicle)
    return isElement(vehicle) and getElementType(vehicle) == "vehicle"
        and getVehicleType(vehicle) == "Boat" and getElementModel(vehicle) == CJetSki.baseModel
        and CVehicle.resolve(vehicle) == CJetSki
end

local function watch(vehicle)
    if isSki(vehicle) then
        local driver = getVehicleOccupant(vehicle,0)
        if driver and not isPedDead(driver) then
            active[vehicle] = active[vehicle] or {}
            return
        end
    end
    active[vehicle] = nil
end

addEventHandler("onVehicleEnter",root,function(_,seat) if seat == 0 then watch(source) end end)
addEventHandler("onVehicleExit",root,function(_,seat) if seat == 0 then active[source] = nil end end)
addEventHandler("onElementDestroy",root,function() active[source],motion[source] = nil,nil end)
addEventHandler("onElementDataChange",root,function(key)
    if key == CVehicle.modelKey or key == "npchlc_traffic:originalModel" or key == "mod.model" then watch(source) end
end)
addEventHandler("onResourceStart",resourceRoot,function()
    for _,vehicle in ipairs(getElementsByType("vehicle")) do watch(vehicle) end
end,false)

local function unseat(vehicle, contact, dx,dy, riderFall)
    local driver = getVehicleOccupant(vehicle,0)
    if not driver or isPedDead(driver) then return end
    local passenger = getVehicleOccupant(vehicle,1)
    local px,py,pz = getElementPosition(vehicle)
    local nearby = getElementsWithinRange(px,py,pz,200,"player",getElementInterior(vehicle),getElementDimension(vehicle))
    local vx,vy,vz = getElementVelocity(vehicle)
    local matrix = getElementMatrix(vehicle)
    local exitHeading = math.deg(math.atan2(-matrix[2][1],matrix[2][2]))
    if matrix[3][3] < 0 then exitHeading = exitHeading + 180 end
    -- 001FBAF8 quantizes the negative contact normal (negative hull
    -- velocity on overturn) relative to the rider's heading.
    local _,_,heading = getElementRotation(driver)
    local bearing = (dx == 0 and dy == 0) and 0 or math.atan2(-dx,dy)
    local direction = math.floor(((bearing-math.rad(heading)+math.pi/4)%(2*math.pi))/(math.pi/2))
    local kick = contact and -0.6*contact.impulse/contact.mass or 0
    local nx,ny = contact and contact.nx or 0,contact and contact.ny or 0
    for _,rider in ipairs({driver,passenger}) do
        if isElement(rider) and not isPedDead(rider) and getPedOccupiedVehicle(rider) == vehicle
            and removePedFromVehicle(rider) then
            triggerClientEvent(nearby,"vcs_vehicle:jetSkiFell",vehicle,rider)
            setElementRotation(rider,0,0,exitHeading%360,"default",true)
            setPedAnimation(rider,"PED",riderFall and "BIKE_fallR" or clips[direction+1],-1,false,false,false,false)
            -- 003F0EF8 copies hull velocity; contact pushes horizontally,
            -- while the world-Z force is selected independently for each ped.
            local upward = riderFall and (3+4*math.random()) or (8+7*math.random())
            setElementVelocity(rider,vx+nx*kick,vy+ny*kick,vz+upward/70)
            if contact and contact.damaging and not riderFall then
                -- 001D7940 applies 0.33 to player damage and spends armour
                -- first for reason 0x2A. Population peds already represent
                -- their original stat multiplier in their starting health.
                local damage = contact.score*0.05*(getElementType(rider) == "player" and 0.33 or 1)
                local absorbed = math.min(getPedArmor(rider),damage)
                if absorbed > 0 then setPedArmor(rider,getPedArmor(rider)-absorbed) end
                if damage > absorbed then
                    local health = getElementHealth(rider)-(damage-absorbed)
                    if health > 0 then setElementHealth(rider,health) else killPed(rider,nil,49) end
                end
            end
        end
    end
end

local function recentContact(vehicle)
    local state = active[vehicle]
    local contact = state and state.contact
    if contact and (getTickCount()-contact.tick)%4294967296 <= 150 then return contact end
end

local function authoritativeReporter(vehicle)
    return client and isSki(vehicle) and getElementSyncer(vehicle) == client
        and not isVehicleBlown(vehicle) and getElementInterior(client) == getElementInterior(vehicle)
        and getElementDimension(client) == getElementDimension(vehicle)
end

addEvent("vcs_vehicle:jetSkiRiderSpin",true)
addEventHandler("vcs_vehicle:jetSkiRiderSpin",resourceRoot,function(vehicle,driver,wx,wy,wz)
    if source ~= resourceRoot or not authoritativeReporter(vehicle) or not isElement(driver)
        or getVehicleOccupant(vehicle,0) ~= driver or isPedDead(driver)
        or (driver ~= client and (getElementType(driver) ~= "ped" or getElementSyncer(driver) ~= client))
        or not finite(wx) or not finite(wy) or not finite(wz)
        or math.max(math.abs(wx),math.abs(wy),math.abs(wz)) > 4 or wx*wx+wy*wy+wz*wz <= 0.09 then return end
    -- The current rider and passenger are looked up again by unseat. Whichever
    -- physical/animation cause removes the driver first consumes this ride.
    unseat(vehicle,recentContact(vehicle),0,0,true)
end,false)

local function sampleMotion(element, now)
    local history = motion[element] or {}
    motion[element] = history
    if history[1] and history[1].tick == now then return end
    local vx,vy,vz = getElementVelocity(element)
    table.insert(history,1,{vx,vy,vz,tick=now})
    history[8] = nil
end

-- Sampling both hulls preserves their approach velocities after native
-- physics has stopped or deflected them and before the contact packet lands.
setTimer(function()
    local now = getTickCount()
    for vehicle,state in pairs(active) do
        local driver = getVehicleOccupant(vehicle,0)
        if not driver or isPedDead(driver) or not isSki(vehicle) then
            active[vehicle] = nil
        elseif not isVehicleBlown(vehicle) then
            local matrix = getElementMatrix(vehicle)
            local vx,vy,vz = getElementVelocity(vehicle)
            local forward = matrix and (vx*matrix[2][1]+vy*matrix[2][2]+vz*matrix[2][3])
            -- 001DC64C: 3.5 times JETSKI handling +0x58 (-0.2),
            -- tipped beyond up.z -0.5. This branch also applies in air.
            if forward and forward < -0.7 and matrix[3][3] < -0.5 then
                unseat(vehicle,recentContact(vehicle),0,0,true)
            elseif matrix and matrix[3][3] < -0.6 and isElementInWater(vehicle) then
                -- The syncer owns the streamed water surface and the nine
                -- hull samples used by the 001A0808 buoyancy test.
                local owner = getElementSyncer(vehicle)
                if state.owner ~= owner or state.driver ~= driver then
                    state.owner,state.driver,state.episode,state.probed = owner,driver,now,nil
                end
                if owner and (not state.probed
                    or (now-state.probed)%4294967296 >= 250) then
                    state.probed = now
                    triggerClientEvent(owner,"vcs_vehicle:testJetSkiOverturn",resourceRoot,vehicle,state.episode)
                end
            else
                state.owner,state.probed,state.driver = nil,nil,nil
                sampleMotion(vehicle,now)
                local x,y,z = getElementPosition(vehicle)
                for _,other in ipairs(getElementsWithinRange(x,y,z,24,"vehicle",getElementInterior(vehicle),getElementDimension(vehicle))) do
                    sampleMotion(other,now)
                end
            end
        end
    end
end,100,0)

addEvent("vcs_vehicle:jetSkiOverturned",true)
addEventHandler("vcs_vehicle:jetSkiOverturned",resourceRoot,function(vehicle,episode)
    local state = active[vehicle]
    if source ~= resourceRoot or not client or not state or state.owner ~= client
        or state.episode ~= episode or not state.probed or (getTickCount()-state.probed)%4294967296 > 750
        or not isSki(vehicle) or getElementSyncer(vehicle) ~= client
        or getVehicleOccupant(vehicle,0) ~= state.driver or isVehicleBlown(vehicle)
        or getElementInterior(client) ~= getElementInterior(vehicle)
        or getElementDimension(client) ~= getElementDimension(vehicle) then return end
    local matrix = getElementMatrix(vehicle)
    if matrix and matrix[3][3] < -0.6 and isElementInWater(vehicle) then
        state.probed = nil
        local vx,vy = getElementVelocity(vehicle)
        unseat(vehicle,recentContact(vehicle),-vx,-vy)
    end
end,false)

local function relativeSpeed(vehicle,other,now)
    local vx,vy,vz = getElementVelocity(vehicle)
    local ox,oy,oz = 0,0,0
    if other then ox,oy,oz = getElementVelocity(other) end
    local best = (vx-ox)^2+(vy-oy)^2+(vz-oz)^2
    local otherHistory = motion[other] or {}
    for i,sample in ipairs(motion[vehicle] or {}) do
        if (now-sample.tick)%4294967296 <= 600 then
            local previous = otherHistory[i]
            local x,y,z = ox,oy,oz
            if previous and previous.tick == sample.tick then x,y,z = previous[1],previous[2],previous[3] end
            best = math.max(best,(sample[1]-x)^2+(sample[2]-y)^2+(sample[3]-z)^2)
        end
    end
    return math.sqrt(best)
end

-- The sender cannot specify riders, damage or launch velocity. Only the
-- current syncer of this occupied physical hull can report its native contact.
addEvent("vcs_vehicle:jetSkiImpact",true)
addEventHandler("vcs_vehicle:jetSkiImpact",resourceRoot,function(vehicle,other,impulse,x,y,z,nx,ny,nz)
    if source ~= resourceRoot or not authoritativeReporter(vehicle) or isVehicleDamageProof(vehicle) then return end
    local driver = getVehicleOccupant(vehicle,0)
    if not driver or isPedDead(driver) or getElementType(driver) == "player" and driver ~= client then return end
    if not finite(impulse) or impulse <= 0 or not finite(nx) or not finite(ny)
        or not finite(nz) or not finite(x) or not finite(y) or not finite(z) then return end
    local matrix = getElementMatrix(vehicle)
    if not matrix then return end
    local position = matrix[4]
    if getDistanceBetweenPoints3D(x,y,z,position[1],position[2],position[3]) > 8 then return end
    local length = math.sqrt(nx*nx+ny*ny+nz*nz)
    if length < 0.95 or length > 1.05 then return end
    nx,ny,nz = nx/length,ny/length,nz/length
    local collider = isElement(other) and getElementType(other) == "vehicle" and other
    if collider then
        if collider == vehicle or getElementDimension(collider) ~= getElementDimension(vehicle)
            or getElementInterior(collider) ~= getElementInterior(vehicle) then return end
        local cx,cy,cz = getElementPosition(collider)
        if getDistanceBetweenPoints3D(cx,cy,cz,x,y,z) > 12 then return end
    end
    local mass = getVehicleHandling(vehicle).mass
    local now = getTickCount()
    impulse = math.min(impulse,2*mass*relativeSpeed(vehicle,collider,now))
    -- Status PLAYER uses 0.65, RANDOM 1; mission-created nonplayer hulls
    -- have CreatedBy == 2 and use 0.4 at 001A4CB8. The population supplies
    -- the original model tag when it creates an ambient hull.
    local factor = getElementType(driver) == "player" and 0.65
        or getElementData(vehicle,"npchlc_traffic:originalModel",false) and 1 or 0.4
    local score = CJetSki.ImpactScore(impulse,mass,matrix,nx,ny,nz,factor)
    local contact = {tick=now,score=score,impulse=impulse,mass=mass,nx=nx,ny=ny,damaging=score>100}
    if active[vehicle] then active[vehicle].contact = contact end
    if score > 100 then
        unseat(vehicle,contact,-nx,-ny)
    end
end,false)
