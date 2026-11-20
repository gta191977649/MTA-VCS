TrafficPoliceResponse = {}

local descending = {}
local serial = 0
local function age(now, previous)
    return (now - previous) % 4294967296
end

local function targetFor(player)
    return getPedOccupiedVehicle(player) or player
end

local function callout(state, vehicle, now, first, last)
    if state.called and age(now, state.called) <= state.callDelay then return end
    state.called, state.callDelay = now, math.random(4500,8595)
    local x,y,z = getElementPosition(vehicle)
    local nearby = getElementsWithinRange(x,y,z,100,"player",getElementInterior(vehicle),getElementDimension(vehicle))
    if nearby and #nearby > 0 then
        triggerClientEvent(nearby,"traffic:policeCallout",resourceRoot,vehicle,math.random(first,last))
    end
end

local function muzzle(m, x, y, z)
    return {m[4][1] + m[1][1]*x + m[2][1]*y + m[3][1]*z,
        m[4][2] + m[1][2]*x + m[2][2]*y + m[3][2]*z,
        m[4][3] + m[1][3]*x + m[2][3]*y + m[3][3]*z}
end

local function shoot(state, gun, target, now)
    local boat = state.boat ~= nil
    local shots = {}
    local x, y, z = getElementPosition(target)
    local matrix = getElementMatrix(gun)
    local forwardScale = boat and 60 / math.max(0.1, math.sqrt(matrix[2][1]^2 + matrix[2][2]^2)) or 0
    for i = 1, boat and 2 or 1 do
        local start = boat and muzzle(matrix, i == 1 and 0.95 or -0.95, 9.3, 0.85) or muzzle(matrix, 0, 3.5, -1)
        local spread = boat and 0.015 or 0.02
        local ax = boat and start[1] + matrix[2][1]*forwardScale or x
        local ay = boat and start[2] + matrix[2][2]*forwardScale or y
        local az = boat and start[3] + math.random(-128,127)*0.02 or z
        if not boat then
            local dx,dy,dz=x-start[1],y-start[2],z-start[3]
            local norm=math.sqrt(dx*dx+dy*dy+dz*dz)
            if norm>0 then dx,dy,dz=dx/norm,dy/norm,dz/norm else dx=1 end
            start[1],start[2],start[3]=start[1]+3*dx,start[2]+3*dy,start[3]+3*dz
            ax,ay,az=ax+3*dx,ay+3*dy,az+3*dz
        end
        shots[i] = {start[1], start[2], start[3], ax + math.random(-128,127)*spread,
            ay + math.random(-128,127)*spread, az}
    end
    serial = serial + 1
    state.shots = state.shots or {}
    for id, shot in pairs(state.shots) do if age(now, shot.at) > 1000 then state.shots[id] = nil end end
    state.shots[serial] = {at = now, target = target, count = #shots}
    local gx, gy, gz = getElementPosition(gun)
    local nearby = getElementsWithinRange(gx, gy, gz, 135, "player", getElementInterior(gun), getElementDimension(gun))
    if nearby and #nearby > 0 then
        triggerClientEvent(nearby, "traffic:policeVolley", resourceRoot, gun, state.player, serial, shots)
    end
end

-- Only the target reports the collision result for its own issued volley.
-- The server owns timing, shooter, target selection, world and damage.
addEvent("traffic:policeImpacts", true)
addEventHandler("traffic:policeImpacts", resourceRoot, function(gun, id, hits)
    local state = TrafficPolice.assignment(client, gun)
    local shot = state and state.shots and state.shots[id]
    if not shot then return end
    state.shots[id] = nil
    if type(hits) ~= "number" or hits%1 ~= 0 or hits < 1 or hits > shot.count or age(getTickCount(),shot.at)>1000
        or not isElement(gun) or not isElement(state.pilot) or isPedDead(state.pilot)
        or getVehicleOccupant(gun,0) ~= state.pilot
        or isPedDead(client) or TrafficCustody.isActive(client) or state.retiring or targetFor(client) ~= shot.target
        or getElementInterior(client) ~= getElementInterior(gun) or getElementDimension(client) ~= getElementDimension(gun)
        or getPlayerWantedLevel(client) < (state.boat and 1 or 3) then return end
    local damage = hits * (state.boat and 15 or 20)
    local response = TrafficWanted.getPoliceResponse(getPlayerWantedLevel(client),client)
    if not response or response.suppressPolice or response.suppressGarage then return end
    if shot.target == client then
        local armour = getPedArmor(client)
        if armour > 0 then
            setPedArmor(client, math.max(0, armour - damage))
            damage = math.max(0, damage - armour)
        end
        if damage >= getElementHealth(client) then killPed(client, state.pilot, 31)
        elseif damage > 0 then setElementHealth(client, getElementHealth(client) - damage) end
    elseif not isVehicleDamageProof(shot.target) then
        setElementHealth(shot.target, math.max(0, getElementHealth(shot.target) - damage))
    end
end, false)

local function requestSurvey(state, now)
    if state.probed and age(now, state.probed) < 700 then return end
    serial = serial + 1
    state.probed, state.surveyId = now, serial
    triggerClientEvent(state.player, "traffic:policeSurvey", resourceRoot, state.heli, serial, state.remaining)
end

addEvent("traffic:policeSurveyResult", true)
addEventHandler("traffic:policeSurveyResult", resourceRoot, function(heli, id, clear, floor)
    local state = TrafficPolice.assignment(client, heli)
    if not state or state.heli ~= heli or not state.surveyId or state.surveyId ~= id or type(clear) ~= "boolean"
        or age(getTickCount(),state.probed) > 1500 or state.retiring then return end
    state.surveyId = nil
    state.visible, state.surveyAt = clear, getTickCount()
    local _, _, z = getElementPosition(client)
    state.floor = type(floor) == "number" and math.abs(floor - z) < 2.5 and floor or nil
end, false)

local function deploy(state, now)
    local model = TrafficAmbient.getPedestrianModel(9)
    if not model then return end
    local heli = state.heli
    local slot = state.remaining - 1
    local ox, oy = slot % 2 == 0 and -1.2 or 1.2, slot < 2 and -1 or 1
    local pos = muzzle(getElementMatrix(heli), ox, oy, -0.5)
    if pos[3] <= state.floor + 2 then return end
    local ped = createPed(model, unpack(pos))
    if not ped then return end
    setElementDimension(ped, state.dimension)
    TrafficModelBindings.tag(ped, 9)
    TrafficVisibility.track(ped, "pedestrian")
    setTrafficPolicePed(ped, true)
    PedAI.attach(ped,9)
    setElementFrozen(ped, true)
    setElementCollisionsEnabled(ped,false)
    setPedAnimation(ped, "ped", "abseil", -1, true, false, false)
    setElementData(ped, "traffic:policeRope", {heli,pos[1],pos[2],pos[3]}, "broadcast", "deny")
    descending[ped] = {heli = heli, player = state.player, floor = state.floor, started = now,
        ox = ox, oy = oy, x = pos[1], y = pos[2]}
    state.remaining = slot
    -- Each survey ray is cast under one particular door.
    state.floor, state.surveyId = nil, nil
end

local function swatResident(state, response, x, y, z)
    if response.swat then return true end
    -- The PS2 deployment check also passes when an existing SWAT unit loaded
    -- model 9 for another suspect. Search only on a successful random draw.
    local nearby = getElementsWithinRange(x,y,z,150,"ped",getElementInterior(state.heli),state.dimension)
    for _,ped in ipairs(nearby) do
        if getElementData(ped,"npchlc_traffic:originalModel",false) == 9 then return true end
    end
    return false
end

function TrafficPoliceResponse.air(state, now)
    if TrafficCustody.isActive(state.player) then
        state.lockAt, state.acquired, state.shots = now, nil, nil
        return
    end
    if state.retiring or not isElement(state.heli) or not isElement(state.pilot) or isPedDead(state.pilot)
        or isPedDead(state.player) or getElementDimension(state.player) ~= state.dimension
        or getElementInterior(state.player) ~= getElementInterior(state.heli) then return end
    local level = getPlayerWantedLevel(state.player)
    local response = TrafficWanted.getPoliceResponse(level, state.player)
    if not response or response.policeHelicopters < 1 then
        state.lockAt, state.shots, state.acquired = now, nil, nil
        return
    end
    local target = targetFor(state.player)
    local kind = target ~= state.player and getVehicleType(target)
    local x,y,z = getElementPosition(state.heli)
    local tx,ty,tz = getElementPosition(target)
    local dx,dy = tx-x, ty-y
    if dx*dx + dy*dy > 70^2 or kind=="Helicopter" or kind=="Plane" then
        state.lockAt, state.track, state.floor, state.visible, state.acquired = nil, nil, nil, nil, nil
        return
    end
    requestSurvey(state, now)
    if not state.surveyAt or age(now, state.surveyAt) > 2000 then state.visible, state.floor = false, nil end
    local vx,vy,vz = getElementVelocity(state.heli)
    if state.remaining > 0 and state.floor and dx*dx + dy*dy + (tz-z)^2 <= 2500 and vx*vx+vy*vy+vz*vz <= 0.01
        and math.random(128) <= 3 and swatResident(state,response,x,y,z) then
        -- Three 30 Hz game frames per 100 ms scheduler visit.
        deploy(state, now)
    end

    if not state.track or state.track.target ~= target then state.lockAt, state.acquired = now, nil end
    local tvx,tvy = getElementVelocity(target)
    local track = TrafficPoliceFlight.track(state.track,target,tx,ty,tvx,tvy,now)
    state.track = track
    if (track.x-x)^2+(track.y-y)^2 > 42^2 or (track.x-tx)^2+(track.y-ty)^2 > 49 then
        state.lockAt, state.acquired = now, nil
        return
    end
    state.lockAt = state.lockAt or now
    callout(state,state.heli,now,30,81)
    if age(now,state.lockAt) <= TrafficPoliceFlight.acquisitionDelay(level,kind ~= false and kind ~= nil) then return end
    if not state.acquired and not state.visible then
        state.lockAt = now
        return
    end
    state.acquired = true
    if not state.lastShot or age(now,state.lastShot) > state.delay then
        shoot(state,state.heli,target,now)
        state.lastShot,state.delay = now,math.random() < 0.15 and 400 or 150
    end
end

function TrafficPoliceResponse.boat(state, now)
    if TrafficCustody.isActive(state.player) then
        state.shots = nil
        return
    end
    local target = targetFor(state.player)
    local kind = target ~= state.player and getVehicleType(target)
    if kind == "Boat" then callout(state,state.boat,now,0,29) end
    if TrafficPoliceFlight.boatPaused(state,kind,now) then return end
    local x,y,z = getElementPosition(state.boat)
    local tx,ty,tz = getElementPosition(target)
    local tvx,tvy = getElementVelocity(target)
    local vx,vy = getElementVelocity(state.boat)
    local matrix = getElementMatrix(state.boat)
    local _,_,fire = TrafficPoliceFlight.boatIntent(getPlayerWantedLevel(state.player), x,y,z, tx,ty,tz,tvx,tvy,
        math.atan2(matrix[2][2],matrix[2][1]),math.sqrt(vx*vx+vy*vy))
    if fire and (not state.lastShot or age(now,state.lastShot) > state.delay) then
        shoot(state,state.boat,target,now)
        state.burst = state.burst-1
        state.lastShot,state.delay = now,400
        if state.burst == 0 then state.burst,state.delay = 20,1800 end
    end
end

function TrafficPoliceResponse.descend(now)
    for ped, rope in pairs(descending) do
        if not isElement(ped) or isPedDead(ped) then
            if isElement(ped) then
                removeElementData(ped,"traffic:policeRope")
                setElementCollisionsEnabled(ped,true)
                setElementFrozen(ped,false)
            end
            descending[ped] = nil
        else
            local player = rope.player
            if not isElement(player) or getPlayerWantedLevel(player)==0 or isPedDead(player)
                or getElementDimension(player) ~= getElementDimension(ped)
                or getElementInterior(player) ~= getElementInterior(ped) then
                descending[ped] = nil
                destroyElement(ped)
            else
                local elapsed = age(now,rope.started)
                local linked = isElement(rope.heli) and elapsed < TrafficPoliceFlight.ropeLifetimeMs
                local landed = false
                if linked then
                    local head = muzzle(getElementMatrix(rope.heli),rope.ox,rope.oy,-0.5)
                    -- Approximate the 32-node strand with a taut line from the
                    -- moving door to its surveyed foot. Progress uses VCS time steps.
                    local dz = math.max(0,head[3]-rope.floor)
                    local dx,dy = rope.x-head[1],rope.y-head[2]
                    local length = math.sqrt(dx*dx+dy*dy+dz*dz)
                    local travel = math.min(0.999,elapsed*TrafficPoliceFlight.ropeProgressPerMs)*TrafficPoliceFlight.ropeSpan
                    local t = math.min(1,travel/math.max(0.01,length))
                    local x,y,z = head[1]+dx*t,head[2]+dy*t,head[3]-dz*t
                    landed = z-rope.floor < 2
                    setElementPosition(ped,x,y,landed and rope.floor+1 or z)
                end
                if landed or not linked then
                    descending[ped] = nil
                    removeElementData(ped,"traffic:policeRope")
                    setPedAnimation(ped)
                    setElementCollisionsEnabled(ped,true)
                    setElementFrozen(ped,false)
                    setElementVelocity(ped,0,0,0)
                    if exports.npc_hlc:enableHLCForNPC(ped,"walk") and TrafficAmbient.adoptDriver(ped,nil,nil,9) then
                        if not isPedDead(player) and not TrafficCustody.isActive(player) then
                            TrafficGroundPolice.enroll(ped,player)
                        end
                    else
                        destroyElement(ped)
                    end
                end
            end
        end
    end
end

function TrafficPoliceResponse.release(state)
    state.shots, state.surveyId = nil, nil
    if state.heli then
        for _,rope in pairs(descending) do
            if rope.heli==state.heli then rope.heli=nil end
        end
    end
end

function TrafficPoliceResponse.clear(player)
    for ped,rope in pairs(descending) do
        if not player or rope.player==player then
            descending[ped] = nil
            if isElement(ped) then destroyElement(ped) end
        end
    end
end
