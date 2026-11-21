local function visibleSpawn(x, y, z)
    return type(getScreenFromWorldPosition(x, y, z, 0.05, true)) == "number"
end

local function pedestrianLine(x, y, z, node, ignored)
    -- 0x00267308 raises both endpoints one unit for the static LOS test.
    return isLineOfSightClear(x, y, z + 1, node.x, node.y, node.z + 1,
        true, false, false, true, false, false, false, ignored)
end

local function indoorFloor(x,y,z,interior,dimension)
    local hit,_,_,height,element=processLineOfSight(x,y,z+1.6,x,y,z-2.5,true,false,false,true,false)
    return hit and isElement(element) and getElementInterior(element)==interior
        and getElementDimension(element)==dimension and math.abs(height-z)<=2
end

local function spawnGround(x, y, z, endpoints)
    -- 0x00268048 / 0x001967F8 start two units above the node and
    -- reject hits more than three units from it.
    local hit, _, _, ground, groundElement, _, _, _, material = processLineOfSight(x, y, z + 2, x, y, z - 3.001,
        true, false, false, true, false)
    if not hit then return false end
    local interior,dimension=getElementInterior(localPlayer),getElementDimension(localPlayer)
    local indoors=interior~=0 or z < -50
    if indoors and (not isElement(groundElement) or getElementInterior(groundElement)~=interior
        or getElementDimension(groundElement)~=dimension) then return false end

    -- Reject occupied positions using MTA streamed elements. The original
    -- 0x00406E18 probe has radius 0.75 at the standing height.
    for _, kind in ipairs({"player", "ped", "vehicle", "object"}) do
        for _, element in ipairs(getElementsWithinRange(x, y, ground + 0.7, 0.75, kind,
            getElementInterior(localPlayer), getElementDimension(localPlayer))) do
            -- Map geometry hit by the ground ray is handled by the ray itself.
            if element ~= groundElement then return false end
        end
    end
    local visible = visibleSpawn(x, y, ground + 0.7)
    if not endpoints then return {ground, visible} end
    for _, node in ipairs(endpoints) do
        if getDistanceBetweenPoints2D(x, y, node.x, node.y) > 1
            and pedestrianLine(x, y, ground + 0.7, node)
            and (not indoors or indoorFloor(node.x,node.y,node.z,interior,dimension)) then
            local _,_,_,_,_,_,_,_,nodeMaterial = processLineOfSight(node.x,node.y,node.z+2,node.x,node.y,node.z-2,
                true,false,false,true,false)
            -- modeldata.SURFACES converts VCS pavement 1/5 to SA 1/89.
            return {ground, visible, node.id, (material == 1 or material == 89)
                and (nodeMaterial == 1 or nodeMaterial == 89)}
        end
    end
    return false
end

-- An off-graph escape must have walkable ground across the proposed step.
local function supportedEscape(x,y,z,node,ped)
    local previous
    for i=0,4 do
        local t=i/4
        local px,py=x+(node.x-x)*t,y+(node.y-y)*t
        local hit,_,_,height,_,_,_,normal=processLineOfSight(px,py,z+1.4,px,py,z-2.2,
            true,false,false,true,false,false,false,false,ped)
        if not hit or normal and normal<.7 or previous and math.abs(height-previous)>.65 then return false end
        previous=height
    end
    return true
end

local function reachableNodes(ped, candidates, origin)
    if not isElement(ped) or not isElementStreamedIn(ped) then return false end
    local x, y, z = getElementPosition(ped)
    if origin then x, y, z = origin.x, origin.y, origin.z + 0.7 end
    local result = {}
    local interior,dimension=getElementInterior(ped),getElementDimension(ped)
    local indoors=interior~=0 or z < -50
    local graphRoute=false
    for _, node in ipairs(candidates) do
        if (node.id>=0 or not graphRoute) and pedestrianLine(x, y, z, node, ped)
            and (node.id>=0 or supportedEscape(x,y,z,node,ped))
            and (not indoors or indoorFloor(node.x,node.y,node.z,interior,dimension)) then
            result[#result + 1] = node.id
            if node.id>=0 and (node.x-x)^2+(node.y-y)^2>1 then graphRoute=true end
        end
    end
    return result
end

local function roadGround(x, y, nominalZ)
    -- 0x00430290 casts both ways and keeps the hit closest to path Z + 1.5.
    -- Hits outside seven world units cannot be accepted by the original branch.
    local z = nominalZ + 1.5
    local up, _, _, upper = processLineOfSight(x, y, z, x, y, z + 7,
        true, false, false, true, false)
    local down, _, _, lower = processLineOfSight(x, y, z, x, y, z - 7,
        true, false, false, true, false)
    -- Some converted road faces only answer top-down casts. Search above the
    -- reference in short slabs, stopping once the lower hit is already nearer.
    if not up and (not down or z - lower > 0.1) then
        local reach = down and math.min(7, z - lower) or 7
        for base = 0, reach, 1.75 do
            local top = math.min(base + 1.75, reach)
            if top <= base then break end
            up, _, _, upper = processLineOfSight(x, y, z + top, x, y, z + base,
                true, false, false, true, false)
            if up then break end
        end
    end
    if not up and not down then return false end
    local ground = up and upper or lower
    if down and math.abs(lower - z) < math.abs(ground - z) then ground = lower end
    local water = getWaterLevel(x, y, ground, true)
    if type(water) == "number" and ground <= water then return false end
    -- MTA adapter for the original model-bound camera visibility check.
    return {ground, visibleSpawn(x, y, ground + 1.5)}
end

local function roadBatch(points)
    local probes = {}
    for index, point in ipairs(points) do
        if point[4] == "boat" then
            local water = getWaterLevel(point[1], point[2], point[3], true)
            probes[index] = type(water) == "number" and math.abs(water - point[3]) <= 7
                and {water, visibleSpawn(point[1], point[2], water)} or false
        else
            probes[index] = roadGround(point[1], point[2], point[3])
        end
    end
    local cameraX, cameraY, _, targetX, targetY = getCameraMatrix()
    if not cameraX then return {probes} end
    local dx, dy = targetX - cameraX, targetY - cameraY
    local length = math.sqrt(dx * dx + dy * dy)
    if length > 0 then return {probes, dx / length, dy / length} end
    return {probes}
end

addEvent("npchlc_traffic:worldProbe", true)
addEventHandler("npchlc_traffic:worldProbe", resourceRoot, function(id, kind, ...)
    local result
    if kind == "spawn" then result = spawnGround(...)
    elseif kind == "reach" then result = reachableNodes(...)
    elseif kind == "road" then result = roadBatch(...)
    elseif kind == "pursuitExit" then result = canTrafficPursuerExit(...)
    else return end
    triggerServerEvent("npchlc_traffic:worldProbeResult", resourceRoot, id, result)
end, false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("npchlc_traffic:worldProbeReady", resourceRoot)
end, false)

local railTag = "npchlc_traffic:rail"
local reportedImpacts = setmetatable({}, {__mode = "k"})
local pendingImpacts = setmetatable({}, {__mode = "k"})

local function roadVehicle(vehicle)
    return isElement(vehicle) and getElementType(vehicle) == "vehicle"
        and getVehicleType(vehicle) ~= "Boat"
        and getElementData(vehicle, TrafficVisibility.profileKey, false) == "road"
end

addEventHandler("npc_hlc:onHeadOnBlocker", root, function(blocker)
    if roadVehicle(source) and isElementSyncer(source) and roadVehicle(blocker) then
        triggerServerEvent("npchlc_traffic:headOnBlocker", resourceRoot, source, blocker)
    end
end)

addEventHandler("npc_hlc:onAbandonedBlocker", root, function(blocker)
    if roadVehicle(source) and isElementSyncer(source) and isElement(blocker) then
        triggerServerEvent("npchlc_traffic:abandonedBlocker", resourceRoot, source, blocker)
    end
end)

addEventHandler("npc_hlc:onCruiseStuck", root, function()
    if roadVehicle(source) and isElementSyncer(source) then
        triggerServerEvent("npchlc_traffic:cruiseStuck", resourceRoot, source)
    end
end)

local impactMotion=setmetatable({}, {__mode="k"})
addEventHandler("npc_hlc:onRouteLow",root,function(first,last)
    if roadVehicle(source) and isElementSyncer(source) then
        triggerServerEvent("npchlc_traffic:routeLow",resourceRoot,source,first,last)
    end
end)
local correction, blockedCorrectionCar
local sampledAt
local function approachVelocity(e,now)
    local s=impactMotion[e]
    if not s then return end
    local dt=(now-s.tick)%4294967296
    local x,y,z=getElementPosition(e)
    if dt<=120 and (x-s.x)^2+(y-s.y)^2+(z-s.z)^2<=(3+dt*.05*math.sqrt(s.vx^2+s.vy^2+s.vz^2))^2 then
        return s.vx,s.vy,s.vz
    end
end

local function reportPedImpact(ped,car,x,y,z,nx,ny,nz,physicalContact)
    if getElementData(ped,TrafficVisibility.profileKey,false)~="pedestrian" or isPedInVehicle(ped)
        or not (isElementSyncer(ped) or getVehicleOccupant(car,0)==localPlayer) then return end
    -- hitElementForce is zero for peds. Resolve the closing speed along
    -- the contact normal so a fast tangential pass stays a glancing hit.
    local vx, vy, vz = getElementVelocity(car)
    local px, py, pz = getElementVelocity(ped)
    local closing = (px-vx)*nx + (py-vy)*ny + (pz-vz)*nz
    local now=getTickCount()
    local ax,ay,az=approachVelocity(car,now)
    local bx,by,bz=approachVelocity(ped,now)
    if ax then
        local before=((bx or px)-ax)*nx+((by or py)-ay)*ny+((bz or pz)-az)*nz
        closing=math.max(closing,before)
    end
    -- The native collision callback can also be the first speed observation
    -- after stream-in. Keep its pre-reaction velocity when it is the faster one.
    if not ax or vx*vx+vy*vy+vz*vz>ax*ax+ay*ay+az*az then
        ax,ay,az=vx,vy,vz
        bx,by,bz=px,py,pz
    end
    if physicalContact and getVehicleType(car)=="Automobile" then
        local matrix=getElementMatrix(car)
        local left,rear,low,rightEdge,front,top=getElementBoundingBox(car)
        if matrix and left then
            local r,f,u=matrix[1],matrix[2],matrix[3]
            local dx,dy,dz=x-matrix[4][1],y-matrix[4][2],z-matrix[4][3]
            local along=dx*f[1]+dy*f[2]+dz*f[3]
            local side=dx*r[1]+dy*r[2]+dz*r[3]
            local height=dx*u[1]+dy*u[2]+dz*u[3]
            local speed=(ax-(bx or px))*f[1]+(ay-(by or py))*f[2]+(az-(bz or pz))*f[3]
            local sign=speed>0 and 1 or -1
            if side>=left and side<=rightEdge and height>=low-0.2 and height<=top+0.4
                and math.abs(along-(sign>0 and front or rear))<=0.5 and math.abs(speed)>closing then
                closing=math.abs(speed)
                nx,ny,nz=-sign*f[1],-sign*f[2],-sign*f[3]
            end
        end
    end
    if closing > 0 then
        local mass = getVehicleHandling(car).mass
        local contactImpulse = closing * 70 * mass / (70 + mass)
        if contactImpulse > 6 or (nz > 0.8 and contactImpulse > 3) then
            triggerServerEvent("npchlc_traffic:pedRoadContact", resourceRoot, ped, car, contactImpulse, -nz,x,y,z)
            if physicalContact and blockedCorrectionCar~=car and getVehicleOccupant(car,0)==localPlayer and getVehicleType(car)=="Automobile" then
                local speed=math.sqrt(ax*ax+ay*ay)
                if speed>0.1 and -(ax*nx+ay*ny)>0.7*speed then
                    local recoil=contactImpulse>12 and 100*math.min(1,mass/1400) or 60*math.min(1,mass/1000)
                    correction={car=car,at=now,speed=speed,fx=ax/speed,fy=ay/speed,allowed=(contactImpulse+recoil)/mass}
                end
            end
        end
    end
end

-- Check the volume actually crossed between samples. A bonnet contact can
-- have a vertical normal, and streamed peds can miss both native callbacks.
local function checkBumperTravel(car,now)
    local before=impactMotion[car]
    if not before or not approachVelocity(car,now) or before.dimension~=getElementDimension(car)
        or before.interior~=getElementInterior(car) then return end
    local matrix=getElementMatrix(car)
    if not matrix then return end
    local forward,right,up=matrix[2],matrix[1],matrix[3]
    local speed=before.vx*forward[1]+before.vy*forward[2]+before.vz*forward[3]
    if math.abs(speed)<0.2 then return end
    local x,y,z=getElementPosition(car)
    local dx,dy,dz=x-before.x,y-before.y,z-before.z
    local sign=speed>0 and 1 or -1
    local travel=sign*(dx*forward[1]+dy*forward[2]+dz*forward[3])
    if travel<=0.02 then return end
    local left,rear,low,rightEdge,front,top=getElementBoundingBox(car)
    if not left then return end
    local bumper=(sign>0 and front or -rear)+0.2
    local reach=bumper+travel+math.max(math.abs(left),rightEdge)+2
    for _,ped in ipairs(getElementsWithinRange(x,y,z,reach,"ped",before.interior,before.dimension) or {}) do
        local old=impactMotion[ped]
        if old and old.tick==before.tick and getElementData(ped,TrafficVisibility.profileKey,false)=="pedestrian"
            and not isPedDead(ped) and not isPedInVehicle(ped) then
            local px,py,pz=getElementPosition(ped)
            local ax,ay,az=old.x-before.x,old.y-before.y,old.z-before.z
            local bx,by,bz=px-x,py-y,pz-z
            local from=sign*(ax*forward[1]+ay*forward[2]+az*forward[3])
            local to=sign*(bx*forward[1]+by*forward[2]+bz*forward[3])
            if from>bumper and to<=bumper then
                local t=(from-bumper)/(from-to)
                local rx,ry,rz=ax+(bx-ax)*t,ay+(by-ay)*t,az+(bz-az)*t
                local side=rx*right[1]+ry*right[2]+rz*right[3]
                local height=rx*up[1]+ry*up[2]+rz*up[3]
                local hx,hy,hz=old.x+(px-old.x)*t,old.y+(py-old.y)*t,old.z+(pz-old.z)*t
                if side>=left and side<=rightEdge and height>=low-0.2 and height<=top+0.4
                    and isLineOfSightClear(before.x,before.y,before.z,hx,hy,hz,true,false,false,true,false,false,false,car) then
                    reportPedImpact(ped,car,hx,hy,hz,-sign*forward[1],-sign*forward[2],-sign*forward[3],true)
                end
            end
        end
    end
end

addEventHandler("onClientPreRender",root,function()
    local now=getTickCount()
    if correction then
        local c=correction
        correction=nil
        if isElement(c.car) and getVehicleOccupant(c.car,0)==localPlayer and (now-c.at)%4294967296<=100
            and not getPedControlState(localPlayer,"brake_reverse") and not getPedControlState(localPlayer,"handbrake") then
            local vx,vy,vz=getElementVelocity(c.car)
            local lost=c.speed-(vx*c.fx+vy*c.fy)
            if lost>c.allowed then
                local delta=lost-c.allowed
                setElementVelocity(c.car,vx+delta*c.fx,vy+delta*c.fy,vz)
            end
        end
    end
    if sampledAt and (now-sampledAt)%4294967296<50 then return end
    local car=getPedOccupiedVehicle(localPlayer)
    if isElement(car) and getVehicleOccupant(car,0)==localPlayer and getVehicleType(car)=="Automobile" then
        checkBumperTravel(car,now)
    end
    blockedCorrectionCar=nil
    sampledAt=now
    local x,y,z=getElementPosition(localPlayer)
    local interior,dimension=getElementInterior(localPlayer),getElementDimension(localPlayer)
    for _,kind in ipairs({"vehicle","ped"}) do
        for _,e in ipairs(getElementsWithinRange(x,y,z,100,kind,interior,dimension) or {}) do
            if isElementStreamedIn(e) then
                local s=impactMotion[e] or {}
                s.x,s.y,s.z=getElementPosition(e)
                s.vx,s.vy,s.vz=getElementVelocity(e)
                s.dimension,s.interior=dimension,interior
                s.tick=now
                impactMotion[e]=s
            end
        end
    end
end)
-- Native run-over damage can arrive without a vehicle collision callback.
-- Use the native attacker and victim position; never infer a hit from proximity.
addEventHandler("onClientPedDamage",root,function(attacker,weapon)
    if (weapon~=49 and weapon~=50) or not isElement(attacker) then return end
    local kind=getElementType(attacker)
    local car=kind=="vehicle" and attacker or (kind=="ped" or kind=="player") and getPedOccupiedVehicle(attacker)
    if not car or (kind~="vehicle" and getVehicleOccupant(car,0)~=attacker) then return end
    local x,y,z=getElementPosition(source)
    local s=impactMotion[car]
    local cx,cy=getElementPosition(car)
    local px,py=x,y
    if s and approachVelocity(car,getTickCount()) then
        cx,cy=s.x,s.y
        local previous=impactMotion[source]
        if previous and previous.tick==s.tick then px,py=previous.x,previous.y end
    end
    local dx,dy=cx-px,cy-py
    local length=math.sqrt(dx*dx+dy*dy)
    if length>.01 then reportPedImpact(source,car,x,y,z,dx/length,dy/length,0,true) end
end)

addEventHandler("onClientVehicleCollision", root, function(other, impulse, _, x, y, z, nx, ny, nz, otherImpulse)
    local pedestrian = isElement(other) and getElementType(other) == "ped"
    if source==getPedOccupiedVehicle(localPlayer) and impulse and impulse>0 and not pedestrian and nz and math.abs(nz)<0.8 then
        blockedCorrectionCar=source
        correction=nil
    end
    if pedestrian then
        if nx and ny and nz then reportPedImpact(other,source,x,y,z,nx,ny,nz,true) end
        -- Bikes still evaluate rider ejection from their own damage impulse.
        if getVehicleType(source) ~= "Bike" then return end
    end
    local vehicle, collider
    if roadVehicle(source) and isElementSyncer(source) then
        vehicle = source
        collider = isElement(other) and getElementType(other) == "vehicle" and other or false
    elseif nx and ny and nz and source == getPedOccupiedVehicle(localPlayer)
        and getVehicleOccupant(source, 0) == localPlayer and roadVehicle(other) then
        vehicle, collider = other, source
        -- MTA supplies an independent impulse for each vehicle in a contact.
        impulse = otherImpulse
        nx, ny, nz = -nx, -ny, -nz
    end
    if not vehicle or not impulse or impulse <= 0 then return end
    local rail = getElementData(vehicle, railTag, false)
    if getVehicleType(vehicle)~="Bike" then
        if not rail and (not collider or impulse <= 25) then return end
        if not collider and nz and math.abs(nz) > 0.7 then return end
    end
    local now = getTickCount()
    local previous = reportedImpacts[vehicle]
    if previous and previous.collider == collider and (now - previous.tick) % 4294967296 < 200
        and impulse <= previous.impulse then return end
    reportedImpacts[vehicle] = {tick = now, collider = collider, impulse = impulse}
    if rail and isElementSyncer(vehicle) then
        pendingImpacts[vehicle] = now
        setElementData(vehicle, "npchlc_traffic:impactPending", true, false)
        setTimer(function()
            if isElement(vehicle) and pendingImpacts[vehicle] == now then
                pendingImpacts[vehicle] = nil
                setElementData(vehicle, "npchlc_traffic:impactPending", false, false)
            end
        end, math.max(350, math.min(1200, 2 * getPlayerPing(localPlayer) + 200)), 1)
    end
    triggerServerEvent("npchlc_traffic:railImpact", resourceRoot, vehicle, collider, x, y, z, nx, ny, nz, impulse,getElementData(vehicle,"npchlc_traffic:ride",false))
end)
