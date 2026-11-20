local setFire = setElementOnFire or setPedOnFire
local onFire = isElementOnFire or isPedOnFire
-- Gunpoint is a wait layered on top of the objective. Keep the gunman's
-- aim slot separate from the particular victim holding their hands up.
PedSpecial = {}
local aiming, holding, burning, drops, pending = {}, {}, {}, {}, {}
local responded = setmetatable({}, {__mode="k"})
local poseKey = "npchlc_traffic:threatPose"
local sequence = 0
local function age(now, tick) return (now - tick) % 4294967296 end
local function sameWorld(a,b)
    return isElement(a) and isElement(b) and getElementDimension(a) == getElementDimension(b)
        and getElementInterior(a) == getElementInterior(b)
end

function PedSpecial.active(ped) return holding[ped] ~= nil or burning[ped] ~= nil end

local function clearPose(ped)
    if isElement(ped) then removeElementData(ped, poseKey) end
end

local function release(ped, react)
    local wait, brain = holding[ped], PedAI.brain(ped)
    if not wait then return end
    holding[ped] = nil
    clearPose(ped)
    if not brain then return end
    brain.wait = nil
    if not react or not sameWorld(wait.source,ped) or isPedDead(wait.source) or isPedDead(ped) then return end
    if brain.event and (brain.event.intent == "fight" or brain.event.intent == "flee") then return end
    local attacker = PedAI.profile(wait.source) or PedAIRules.profile(0)
    local intent = PedAIRules.gunpointRelease(brain.profile, attacker, PedAIRules.ranged(getPedWeapon(ped)), wait.id)
    if intent == "flee" then
        brain:react("gunpoint",wait.source,0,"flee","run",10000)
        PedVoice.emit(ped,"reclaim")
    elseif intent == "fight" then
        brain:react("gunpoint",wait.source,0,"fight","run",20000)
    else
        brain.objectives:clear()
        brain.event = nil
        TrafficAmbient.resumeWander(ped, math.random(0,7))
    end
end

function PedSpecial.interrupt(ped)
    release(ped,false)
    if burning[ped] and burning[ped].recovered then
        burning[ped] = nil
        local brain = PedAI.brain(ped)
        if brain then brain.wait = nil end
        clearPose(ped)
    end
end

addEvent("npchlc_traffic:threatPoseEnded",true)
addEventHandler("npchlc_traffic:threatPoseEnded",resourceRoot,function(ped,revision)
    local wait = holding[ped]
    if wait and revision == wait.revision and sameWorld(client,ped) and getElementSyncer(ped)==client
        and age(getTickCount(),wait.tick)>200 then release(ped,true) end
end,false)

local function dropCash(brain)
    if not brain.dropCash then return end
    brain.dropCash = false
    local ped = brain.ped
    local peer = getElementSyncer(ped)
    if not sameWorld(ped,peer) then return end
    local x,y,z = getElementPosition(ped)
    local total = math.random(100,299)
    local count = math.floor(total/40)+1
    local points = {}
    for i=1,count do
        points[i] = {x+1.5*math.sin(math.random(0,255)*math.pi/128),
            y+1.5*math.cos(math.random(0,255)*math.pi/128),z}
    end
    sequence = sequence + 1
    pending[ped] = {peer=peer,id=sequence,tick=getTickCount(),points=points,amount=math.floor(total/count)}
    triggerClientEvent(peer,"npchlc_traffic:cashGround",resourceRoot,ped,sequence,points)
end

addEvent("npchlc_traffic:cashGroundReply",true)
addEventHandler("npchlc_traffic:cashGroundReply",resourceRoot,function(ped,id,heights)
    local request = pending[ped]
    if not request or request.peer ~= client or request.id ~= id or not sameWorld(client,ped)
        or getElementSyncer(ped) ~= client or type(heights) ~= "table" then return end
    pending[ped] = nil
    if age(getTickCount(),request.tick) > 1500 then return end
    for i, point in ipairs(request.points) do
        local z = heights[i]
        if type(z) == "number" and math.abs(z-point[3]) <= 2 then
            local pickup = createPickup(point[1],point[2],z+0.5,3,1212)
            if pickup then
                setElementInterior(pickup,getElementInterior(ped))
                setElementDimension(pickup,getElementDimension(ped))
                drops[pickup] = {amount=request.amount+math.random(0,7), tick=getTickCount()}
            end
        end
    end
end,false)
addEventHandler("onPickupHit",resourceRoot,function(player,matching)
    local drop = drops[source]
    if not drop or matching == false or not sameWorld(player,source) or isPedDead(player) then return end
    drops[source] = nil
    givePlayerMoney(player,drop.amount)
    destroyElement(source)
end)

local function threaten(sourcePed,ped)
    local brain = PedAI.brain(ped)
    if responded[sourcePed]==ped or not brain or not sameWorld(sourcePed,ped) or brain.scriptOwner or PedSpecial.active(ped)
        or isPedInVehicle(ped) or isPedDead(ped) or isPedDead(sourcePed) or not PedAIRules.ranged(getPedWeapon(sourcePed))
        or brain.leader == sourcePed or brain.leader and isElement(brain.leader) and getElementType(brain.leader) == "player"
        or PedVehicleEvasion.active(ped) then return end
    local player = getElementType(sourcePed) == "player"
    local x,y = getElementPosition(ped)
    local sx,sy = getElementPosition(sourcePed)
    local dx,dy = sx-x,sy-y
    local length = math.sqrt(dx*dx+dy*dy)
    local yaw = math.rad(getPedRotation(ped))
    if length > 15 or length > 0 and (-math.sin(yaw)*dx+math.cos(yaw)*dy)/length <= -0.5 then return end
    local old = brain.event
    local sourceProfile = PedAI.profile(sourcePed) or PedAIRules.profile(0)
    local pose, remember = PedAIRules.gunpointWait(brain.profile, sourceProfile, player, old, sourcePed)
    if remember then PedAI.rememberHostility(ped,sourcePed) end
    if not pose then return end
    if pose == "police" then
        if player then exports.wanted:raisePlayerWanted(sourcePed,2,"gunpoint") end
        return
    end
    local special = pose == "handscower"
    local id = special and 0x12 or 0x11
    TrafficAmbient.suspend(ped)
    responded[sourcePed]=ped
    brain.tasks:clear()
    if old then old.task = nil end
    sequence = sequence + 1
    holding[ped] = {id=id, source=sourcePed, tick=getTickCount(), duration=math.random(3000,5999), revision=sequence}
    brain.wait = id
    setElementData(ped,poseKey,{pose,sequence,holding[ped].duration},"broadcast","deny")
    PedVoice.emit(ped,"gunpoint",special and 1500 or nil)
    if player and not special then dropCash(brain) end
end

function PedSpecial.sampleAim(ped)
    local target = getPedTarget(ped)
    if aiming[ped]~=target then responded[ped]=nil end
    if isElement(target) and target ~= ped then
        aiming[ped] = target
        threaten(ped,target)
    else aiming[ped] = nil end
end

addEventHandler("onPlayerTarget",root,function(target)
    if aiming[source]~=target then responded[source]=nil end
    aiming[source] = isElement(target) and target or nil
    if aiming[source] then threaten(source,target) end
end)
addEventHandler("onPlayerQuit",root,function() aiming[source]=nil end)

function PedSpecial.observeFire(brain, persistent, attacker)
    local ped = brain.ped
    if burning[ped] or brain.scriptOwner and not persistent or isPedDead(ped) or isPedInVehicle(ped)
        or not onFire(ped) then return end
    release(ped,false)
    PedVehicleEvasion.cancel(ped)
    PedActivity.cancel(ped)
    brain.tasks:clear()
    brain.objectives:clear()
    brain.objectives.body, brain.event, brain.burning = 0x20,nil,true
    local fire = {tick=getTickCount(),persistent=persistent,pace="sprint"}
    if sameWorld(ped,attacker) then fire.target = attacker else fire.origin = {getElementPosition(ped)} end
    burning[ped] = fire
end

function PedSpecial.reportIgnition(brain, player)
    local fire = burning[brain.ped]
    if fire and not fire.reported and onFire(brain.ped) then
        fire.reported = true
        exports.wanted:reportWantedEvent(player, brain.profile.pedType == 6 and 15 or 14, brain.ped)
    end
end

function PedSpecial.update(ped,graph)
    local fire,brain = burning[ped],PedAI.brain(ped)
    if not fire then return holding[ped] ~= nil end
    if not brain then burning[ped]=nil return false end
    local now = getTickCount()
    if fire.recovered then
        if age(now,fire.recovered) <= fire.duration then return true end
        if brain.wait == 0x14 then
            brain.wait, fire.recovered, fire.duration = 3, now, 2000
            sequence = sequence + 1
            setElementData(ped,poseKey,{"roadcross",sequence},"broadcast","deny")
            return true
        end
        clearPose(ped)
        brain.wait, burning[ped] = nil,nil
        return false
    end
    if not onFire(ped) then
        brain.tasks:clear(true)
        brain.burning,brain.objectives.body,brain.wait = nil,1,0x14
        fire.recovered, fire.duration = now, 2500
        sequence = sequence + 1
        setElementData(ped,poseKey,{"idle_tired",sequence},"broadcast","deny")
    elseif not fire.persistent and age(now,fire.tick) > 10000 then
        setFire(ped,false)
    else
        if not fire.origin and not sameWorld(fire.target,ped) then fire.origin = {getElementPosition(ped)} end
        exports.npc_hlc:setNPCWalkSpeed(ped,"sprint")
        brain.tasks:flee(graph,fire,now)
    end
    return true
end

function PedSpecial.cancel(ped)
    release(ped,false)
    if burning[ped] then clearPose(ped) end
    burning[ped],pending[ped] = nil,nil
end

setTimer(function()
    local now = getTickCount()
    for ped, wait in pairs(holding) do
        if not sameWorld(ped,wait.source) or isPedDead(ped) or isPedDead(wait.source)
            or not aiming[wait.source] or not PedAIRules.ranged(getPedWeapon(wait.source)) or age(now,wait.tick)>wait.duration then release(ped,true) end
    end
    for sourcePed,target in pairs(aiming) do
        if not isElement(target) or not isElement(sourcePed) or isPedDead(sourcePed) or not PedAIRules.ranged(getPedWeapon(sourcePed)) then aiming[sourcePed],responded[sourcePed]=nil,nil
        elseif getElementType(sourcePed)=="ped" then PedSpecial.sampleAim(sourcePed)
        else threaten(sourcePed,target) end
    end
    for pickup, drop in pairs(drops) do
        if age(now,drop.tick)>120000 then destroyElement(pickup) end
    end
end,250,0)

addEventHandler("onElementDestroy",root,function()
    PedSpecial.cancel(source)
    drops[source],aiming[source]=nil,nil
end)
