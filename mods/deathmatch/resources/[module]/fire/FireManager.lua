-- US SLUS_215.90. CFireManager::GetNextFreeFire (002BD438) scans 40 records.
-- Each MTA dimension represents a separate game world.
local worlds, byHost, byOwner = {}, {}, {}
local lastSnapshot, lastShot, lastCannon = {}, {}, {}
local function sendFire(player, fire, now)
    triggerClientEvent(player, "fire:start", resourceRoot, fire.id, fire.kind, fire.host,
        fire.x, fire.y, fire.z, fire.size, now - fire.started, fire.strength,
        fire.interior, fire.dimension, fire.slot - 1)
end

local function extinguish(fire)
    if fire.kind=="ped" and isElement(fire.host) and isElementOnFire(fire.host) then
        setElementOnFire(fire.host,false)
    end
    local pool = worlds[fire.dimension]
    pool[fire.slot] = nil
    if not next(pool) then worlds[fire.dimension] = nil end
    if fire.host and byHost[fire.host] == fire then byHost[fire.host] = nil end
    if fire.owner then byOwner[fire.owner] = nil end
    if isElement(fire.viewer) then
        triggerClientEvent(fire.viewer, "fire:stop", resourceRoot, fire.id)
    end
end

local serial = 0
local function startFire(kind, host, owner, viewer, x, y, z, size, interior, dimension, duration)
    if host and byHost[host] then return byHost[host] end
    local pool = worlds[dimension] or {}
    for slot = 1, 40 do
        if not pool[slot] then
            serial = serial + 1
            local now = getTickCount()
            local fire = {id = serial, slot = slot, kind = kind, host = host or false,
                owner = owner, viewer = viewer or root, x = x, y = y, z = z, size = size,
                strength = 1, interior = interior, dimension = dimension, started = now,
                expires = duration and now + duration}
            worlds[dimension], pool[slot] = pool, fire
            if host then byHost[host] = fire end
            if owner then byOwner[owner] = fire end
            sendFire(fire.viewer, fire, now)
            return fire
        end
    end
end

-- Mission owns the lifetime. Destroying its marker also releases the slot.
function StartScriptFire(owner, host, viewer, size)
    if not isElement(owner) or not isElement(viewer) or getElementType(viewer) ~= "player" then return false end
    if host and not isElement(host) then return false end
    if byOwner[owner] then return byOwner[owner].id end
    if host and byHost[host] then return false end
    local x, y, z = getElementPosition(host or owner)
    local fire = startFire("script", host, owner, viewer, x, y, z, size or 0.8,
        getElementInterior(owner), getElementDimension(owner))
    return fire and fire.id or false
end

local function startEntityFire(host, kind, duration)
    local x, y, z = getElementPosition(host)
    return startFire(kind, host, nil, root, x, y, z, 0.8,
        getElementInterior(host), getElementDimension(host), duration)
end

-- Script command 0490 (003113E0) supplies the only positive value
-- written to CObject+1DE. Ordinary static map objects never enter this pool.
local objectHealth=setmetatable({}, {__mode="k"})
function SetObjectHealth(object,health,damageMultiplier)
    if not isElement(object) or getElementType(object)~="object" or type(health)~="number"
        or health~=math.floor(health) or health<0 or health>127 then return false end
    damageMultiplier=damageMultiplier or 1
    if type(damageMultiplier)~="number" or not (damageMultiplier>=0 and damageMultiplier<math.huge) then return false end
    objectHealth[object]=health>0 and {hp=health,multiplier=damageMultiplier} or nil
    if health==0 and byHost[object] then extinguish(byHost[object]) end
    return true
end
local function igniteObject(object)
    if objectHealth[object] and not byHost[object] then
        startEntityFire(object,"object",10000+math.random(0,999))
    end
end
local function damageObject(f,elapsed)
    local state=objectHealth[f.host]
    if not state then return extinguish(f) end
    -- Keep the integer truncation per original 30 Hz processing step.
    local period=1000/30
    local accumulated=(f.remainder or 0)+elapsed
    local steps=math.floor(accumulated/period)
    f.remainder=accumulated-steps*period
    state.hp=state.hp-steps*math.min(127,math.floor(2*50/30*state.multiplier))
    if state.hp<=0 then
        objectHealth[f.host]=nil
        extinguish(f)
        destroyElement(f.host)
    end
end

local function isFireproof(ped)
    if getElementData(ped,"mission:fireproof") then return true end
    if getElementType(ped)~="player" then return false end
    local debugResource=getResourceFromName("debug")
    return debugResource and getResourceState(debugResource)=="running" and exports.debug:isPlayerInGodMode(ped)
end

local function ignitePed(ped,creator)
    if byHost[ped] or isPedDead(ped) or isElementInWater(ped) or getPedOccupiedVehicle(ped)
        or getElementData(ped, "mission:fireVictim") or isFireproof(ped) then return end
    local duration = getElementType(ped) == "player" and 3333 or 10000 + math.random(0, 999)
    local fire = startEntityFire(ped, "ped", duration)
    if fire then
        -- Keep native ped reactions. The server accounts for the recovered
        -- damage rate; the syncer filters the native burn while managed.
        fire.creator,fire.lastDamage=creator,fire.started
        if not isElementOnFire(ped) then setElementOnFire(ped, true) end
    end
end

local function damage(attacker, weapon)
    if weapon == 37 then ignitePed(source,attacker) end
end
addEventHandler("onPlayerDamage", root, damage)
addEventHandler("onPedDamage", root, damage)

local function watchVehicle(vehicle)
    if isElement(vehicle) and not byHost[vehicle] and not isVehicleBlown(vehicle)
        and getElementHealth(vehicle) < 250 and isVehicleDamageProof(vehicle) == false then
        startEntityFire(vehicle, "engine", 5000)
    end
end
addEventHandler("onVehicleDamage", root, function(loss)
    if not byHost[source] and getElementHealth(source) - (loss or 0) < 250 then
        setTimer(watchVehicle, 50, 1, source)
    end
end)
addEventHandler("onVehicleExplode", root, function()
    if byHost[source] then extinguish(byHost[source]) end
    local kind=getVehicleType(source)
    if kind~="Plane" and kind~="Helicopter" then startEntityFire(source,"wreck",4250) end
end)

local function removeElement(element)
    if byHost[element] then extinguish(byHost[element]) end
    if byOwner[element] then extinguish(byOwner[element]) end
end
addEventHandler("onElementDestroy", root, function() removeElement(source) end)
addEventHandler("onVehicleRespawn", root, function() removeElement(source) end)
addEventHandler("onPlayerQuit", root, function()
    removeElement(source)
    lastSnapshot[source], lastShot[source], lastCannon[source] = nil,nil,nil
end)

addEvent("fire:ready", true)
addEventHandler("fire:ready", resourceRoot, function()
    if not client or source ~= resourceRoot then return end
    local now = getTickCount()
    if lastSnapshot[client] and now - lastSnapshot[client] < 1000 then return end
    lastSnapshot[client] = now
    for _, pool in pairs(worlds) do
        for _, fire in pairs(pool) do
            if fire.viewer == root or fire.viewer == client then sendFire(client, fire, now) end
        end
    end
end, false)

-- CExplosion::AddExplosion (002E16C0), molotov type 1. MTA supplies the
-- collision position. The three-second hot area and the ten-second fire
-- have independent clocks in the executable.
addEventHandler("onExplosion", root, function(x, y, z, explosionType)
    if explosionType ~= 1 or wasEventCancelled() then return end
    local dimension, interior = getElementDimension(source) or 0, getElementInterior(source) or 0
    local map=getResourceFromName("vcs")
    if interior==0 and map and getResourceState(map)=="running" then
        local water=exports.vcs:getVcsWaterQuadLevel(x,y)
        if water and z<water and z>water-6 then return end
    end
    for _, fire in pairs(worlds[dimension] or {}) do
        if fire.kind == "molotov" and fire.interior == interior and getTickCount() - fire.started < 200
            and getDistanceBetweenPoints3D(x,y,z,fire.x,fire.y,fire.z) < 0.5 then return end
    end
    local fire = startFire("molotov", nil, nil, root, x,y,z,0.7,interior,dimension,10000)
    if fire then fire.hotUntil,fire.creator = fire.started + 3000,source end
end, true, "low")

function ExtinguishPointWithWater(x,y,z,radius,interior,dimension,elapsedMs)
    for slot = 1, 40 do
        local fire = worlds[dimension] and worlds[dimension][slot]
        if fire and fire.kind ~= "script" and fire.kind ~= "wreck" and fire.interior == interior
            and getDistanceBetweenPoints3D(x,y,z,fire.x,fire.y,fire.z) < radius then
            -- 002BEAB8: the first matching slot loses step * 0.012.
            fire.strength = fire.strength - elapsedMs * 0.0006
            triggerClientEvent(fire.viewer, "fire:water", resourceRoot, fire.id, fire.strength)
            if fire.strength < 0 then
                if fire.kind == "engine" and not isVehicleBlown(fire.host) then
                    setElementHealth(fire.host, math.max(250, getElementHealth(fire.host)))
                end
                extinguish(fire)
            end
            return true
        end
    end
    return false
end

local function spread(fire, now)
    local hot = fire.hotUntil and now < fire.hotUntil
    local radius = hot and 10 or 1.415
    local kinds = hot and {"player", "ped", "vehicle", "object"} or {"player"}
    for _, kind in ipairs(kinds) do
        for _, entity in ipairs(getElementsWithinRange(fire.x,fire.y,fire.z,radius,kind,fire.interior,fire.dimension)) do
            local x,y,z = getElementPosition(entity)
            local dx,dy,dz = x-fire.x,y-fire.y,z-fire.z
            -- SetPedsOnFire and SetCarsOnFire test independent XY bounds.
            if not byHost[entity] and ((hot and math.abs(dx)<6 and math.abs(dy)<6 and math.abs(dz)<5)
                or dx*dx+dy*dy+dz*dz < 2) then
                if kind == "vehicle" then
                    if not isVehicleDamageProof(entity) and not isVehicleBlown(entity) then
                        startEntityFire(entity,"vehicle",4000+math.random(0,999))
                    end
                elseif kind=="object" then igniteObject(entity)
                else ignitePed(entity,fire.creator) end
            end
        end
    end
end

-- CShotInfo::AddShot / Update (00179708 / 00179B58), with the US PS2
-- weapon 33 record from GAME.DTZ (0x3D7530 + 33*0x70). Only the aim
-- direction comes from the shooter. The server determines the muzzle,
-- dimension, eligible entities, slot, time, speed and extent of the shot.
local shots={}
local function finite(value)
    return type(value)=="number" and value==value and math.abs(value)<math.huge
end
addEvent("fire:shot",true)
addEventHandler("fire:shot",resourceRoot,function(dx,dy,dz)
    if not client or source~=resourceRoot or not finite(dx) or not finite(dy) or not finite(dz)
        or getPedWeapon(client)~=37 or getPedTotalAmmo(client)<1 or isPedDead(client)
        or getPedOccupiedVehicle(client) then return end
    local norm=dx*dx+dy*dy+dz*dz
    if norm<0.999 or norm>1.001 then return end
    local now=getTickCount()
    if now-(lastShot[client] or -100)<95 then return end
    lastShot[client]=now
    for i=1,100 do
        if not shots[i] then
            local x,y,z=getElementPosition(client)
            shots[i]={x=x+dx*0.65,y=y+dy*0.65,z=z+0.5+dz*0.65,dx=dx*0.65,dy=dy*0.65,dz=dz*0.65,
                shooter=client,interior=getElementInterior(client),dimension=getElementDimension(client),
                size=1.2,expires=now+1000,frame=0,last=now}
            return
        end
    end
end,false)

local function updateShots(now)
    for i,s in pairs(shots) do
        if now>=s.expires or not isElement(s.shooter) then shots[i]=nil
        else
            while s.last+1000/30<=now do
                local step=50/30
                local damping=0.96^step
                s.last=s.last+1000/30
                s.frame=s.frame+1
                s.dx,s.dy,s.dz=s.dx*damping,s.dy*damping,s.dz*damping
                s.x,s.y,s.z=s.x+s.dx*step,s.y+s.dy*step,s.z+s.dz*step
                s.size=s.size+0.075*step
                for _,kind in ipairs({"player","ped"}) do
                    for _,ped in ipairs(getElementsWithinRange(s.x,s.y,s.z,math.sqrt(s.size),kind,s.interior,s.dimension)) do
                        if ped~=s.shooter and not byHost[ped] then
                            local x,y,z=getElementPosition(ped)
                            if (x-s.x)^2+(y-s.y)^2+(z-s.z)^2<s.size then ignitePed(ped,s.shooter) end
                        end
                    end
                end
                if (s.frame+i-1)%4==0 then
                    for _,o in ipairs(getElementsWithinRange(s.x,s.y,s.z,6,"object",s.interior,s.dimension)) do
                        if objectHealth[o] and not byHost[o] then
                            local x,y,z=getElementPosition(o)
                            if math.abs(x-s.x)<2 and math.abs(y-s.y)<2 and math.abs(z-s.z)<5 then igniteObject(o) end
                        end
                    end
                    for _,v in ipairs(getElementsWithinRange(s.x,s.y,s.z,6,"vehicle",s.interior,s.dimension)) do
                        local x,y,z=getElementPosition(v)
                        if not byHost[v] and not isVehicleDamageProof(v) and not isVehicleBlown(v)
                            and math.abs(x-s.x)<2 and math.abs(y-s.y)<2 and math.abs(z-s.z)<5 then
                            startEntityFire(v,"vehicle",4000+math.random(0,999))
                        end
                    end
                end
            end
        end
    end
end

-- 00186AA8 integrates a thrown water point at 50 m/s and decreases Z
-- velocity by .009 per 20 ms. Test the path from its current turret base.
addEvent("fire:cannon",true)
addEventHandler("fire:cannon",resourceRoot,function(yaw,pitch)
    if not client or source~=resourceRoot or not finite(yaw) or not finite(pitch) then return end
    local vehicle=getPedOccupiedVehicle(client)
    if not vehicle or getVehicleController(vehicle)~=client then return end
    local original=tonumber(getElementData(vehicle,"vcs_vehicle:originalModel"))
    if original~=194 and getElementModel(vehicle)~=407 then return end
    local now=getTickCount()
    if now-(lastCannon[client] or -100)<90 then return end
    local elapsed=math.min(200,now-(lastCannon[client] or now-100))
    lastCannon[client]=now
    local dimension,interior=getElementDimension(vehicle),getElementInterior(vehicle)
    if not worlds[dimension] then return end
    local m=getElementMatrix(vehicle)
    local right,forward,up=-math.sin(yaw)*math.cos(pitch),math.cos(yaw)*math.cos(pitch),math.sin(pitch)
    local x,y,z=m[4][1]+m[3][1]*1.8,m[4][2]+m[3][2]*1.8,m[4][3]+m[3][3]*1.8
    local dx=right*m[1][1]+forward*m[2][1]+up*m[3][1]
    local dy=right*m[1][2]+forward*m[2][2]+up*m[3][2]
    local dz=right*m[1][3]+forward*m[2][3]+up*m[3][3]
    for i=1,16 do
        dz=dz-0.009*50/30
        x,y,z=x+dx*50/30,y+dy*50/30,z+dz*50/30
        if ExtinguishPointWithWater(x,y,z,4,interior,dimension,elapsed) then break end
    end
end,false)

local function damagePed(f, now)
    local dt = math.min(now,f.expires) - f.lastDamage
    if dt<=0 or isPedDead(f.host) then return end
    f.lastDamage = math.min(now,f.expires)
    local damage = dt*0.06
    if getElementType(f.host)=="player" then damage=damage*0.33 end
    local armour=getPedArmor(f.host)
    local absorbed=math.min(armour,damage)
    if absorbed>0 then setPedArmor(f.host,armour-absorbed) end
    local lost=damage-absorbed
    if lost>0 then
        local health=getElementHealth(f.host)-lost
        if health>0 then setElementHealth(f.host,health)
        else killPed(f.host,isElement(f.creator) and f.creator~=root and f.creator or nil,37) end
    end
end

local previous = getTickCount()
setTimer(function()
    local now = getTickCount()
    local elapsed = now - previous
    previous = now
    updateShots(now)
    for _, pool in pairs(worlds) do
        for slot=1,40 do
            local f = pool[slot]
            if f then
                if f.host then f.x,f.y,f.z = getElementPosition(f.host) end
                if f.host and (getElementDimension(f.host) ~= f.dimension or getElementInterior(f.host) ~= f.interior) then
                    extinguish(f)
                elseif f.kind == "engine" and (getElementHealth(f.host) >= 250 or isVehicleBlown(f.host)) then
                    extinguish(f)
                elseif f.kind == "ped" and (isPedDead(f.host) or isElementInWater(f.host) or isFireproof(f.host) or not isElementOnFire(f.host)) then
                    extinguish(f)
                elseif f.expires and now >= f.expires then
                    if f.kind == "ped" then damagePed(f,now) end
                    extinguish(f)
                    if f.kind == "engine" and not isVehicleBlown(f.host) then blowVehicle(f.host) end
                elseif f.kind == "vehicle" and not isVehicleBlown(f.host) then
                    -- FUN_002BDDC8: 1.2 points per 20 ms while attached.
                    local health = getElementHealth(f.host)
                    if health >= 250 then setElementHealth(f.host, math.max(249,health - elapsed * 0.06)) end
                    if getElementHealth(f.host) < 250 then
                        extinguish(f)
                        watchVehicle(f.host)
                    end
                elseif f.kind == "object" then damageObject(f,elapsed)
                elseif f.kind == "ped" then damagePed(f,now)
                elseif f.kind == "molotov" then spread(f,now) end
                if pool[slot] == f then f.strength = math.min(1, f.strength + elapsed * 0.0001) end
            end
        end
    end
end,100,0)

-- Native damage events cover normal gameplay. Reconcile vehicles that a
-- gameplay script damaged directly or that were already burning at startup.
setTimer(function()
    for _,vehicle in ipairs(getElementsByType("vehicle")) do watchVehicle(vehicle) end
end,1000,0)


addEventHandler("onResourceStop",resourceRoot,function()
    for _,pool in pairs(worlds) do
        for _,f in pairs(pool) do
            if f.kind=="ped" and isElement(f.host) then setElementOnFire(f.host,false) end
        end
    end
end,false)
