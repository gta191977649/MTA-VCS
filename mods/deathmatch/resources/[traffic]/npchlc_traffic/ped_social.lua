PedSocial = {}
local hlc = exports.npc_hlc
local motion = "npchlc_traffic:activityMotion"
local facingTarget = "npchlc_traffic:socialFacing"
local function modelSet(models)
    local result = {}
    for _, id in ipairs(models) do result[id] = true end
    return result
end

-- SLUS_215.90 0x002B3A08 / 0x002B3AD8. The ordinary zone pool also
-- contains actors (workers, gangs and others) that cannot form a couple.
local men = modelSet({17,18,19,20,21,31,32,35,36,39,40,43,44,45,47,48,49,50,51,55,57,59,60,62,64,65,70})
local women = modelSet({24,25,26,27,28,29,30,33,34,37,38,41,42,46,52,53,54,56,58,61,63,66,67,68,69,71})
function PedSocial.pickPair(group, available, draw)
    if not group then return end
    for _ = 1, 8 do
        local man = group[draw(1, 16)]
        local info = PedAIModels[man]
        if men[man] and info and info[1] == 4 then
            for _, woman in ipairs(group) do
                local other = PedAIModels[woman]
                if women[woman] and other and other[1] == 5 and ((info[2] == 39) == (other[2] == 39)) then
                    if available(man) and available(woman) then return man, woman end
                    return
                end
            end
            return
        end
    end
end

local function live(ped)
    return isElement(ped) and not isPedDead(ped)
end

-- Population dispatches police and emergency crews to their own update classes.
local function streetSocial(ped, walk)
    local model = walk and PedAIModels[walk.originalModelId]
    if not model then return false end
    local kind = model[1]
    return kind ~= 6 and kind ~= 16 and kind ~= 17
        and not (TrafficActors and TrafficActors.isPolicePed(ped))
end

function PedSocial.interrupt(ped, walk)
    if walk.facingTarget and isElement(ped) then removeElementData(ped,facingTarget) end
    walk.facingTarget = nil
    if walk.gesture and isElement(ped) then removeElementData(ped,motion) end
    walk.gesture,walk.gestureStarted,walk.spoke = nil,nil,nil
    walk.chatAnim, walk.partner, walk.followTask, walk.spoke, walk.gatherLeader, walk.gathering = nil, nil, nil, nil, nil, nil
end

local function stopWalking(ped, walk)
    hlc:clearNPCTasks(ped)
    walk.queued, walk.blockedSince, walk.anchor = 0, nil, nil
    walk.crossing, walk.nextCrossing = nil, nil
end

local function facePartner(ped,walk,partner)
    walk.facingTarget = partner
    setElementData(ped,facingTarget,partner,"broadcast","deny")
    if not getElementSyncer(ped) then
        local x,y = getElementPosition(ped)
        local tx,ty = getElementPosition(partner)
        if (tx-x)^2+(ty-y)^2 > 0.0001 then
            setElementRotation(ped,0,0,math.deg(math.atan2(x-tx,ty-y)),"default",true)
        end
    end
end

local function startChat(ped, walk, partner, duration, now)
    stopWalking(ped, walk)
    walk.followTask = nil
    walk.partner, walk.chatSince, walk.chatDuration = partner, now, duration
    facePartner(ped,walk,partner)
    walk.chatAnim = true
end

local function chatPair(ped,other,actors,duration,now)
    -- Both queues must be empty before either participant can start a gesture.
    startChat(ped,actors[ped],other,duration,now)
    startChat(other,actors[other],ped,duration,now)
end

-- 0040F810 formation slots in the leader's local basis. The civilian
-- pair uses slot 7. Ordinary gang followers start with slots 1 and 2.
function PedSocial.slotOffset(slot)
    local distance = 1.75*(1+0.25*math.random())
    if slot == 7 then return distance,0 end
    return slot == 2 and -distance or 0,-distance
end

function PedSocial.formationPoint(candidate,index)
    local kind = candidate.formation
    if kind == "chat" or kind == "cluster" then
        local step = 2*math.pi/candidate.total
        local radius = math.sqrt(0.5/(1-math.cos(step)))
        local angle = step*(index+0.4*math.random()-0.2)
        local jitter = kind == "cluster" and 0.2+0.2*math.random() or 0.4*math.random()-0.2
        radius = radius*(1+jitter)
        return candidate.centerX+radius*math.cos(angle),candidate.centerY+radius*math.sin(angle)
    end
    if index == 0 or not isElement(candidate.leader) then return candidate.centerX,candidate.centerY end
    local matrix = getElementMatrix(candidate.leader)
    if not matrix then return end
    local dx,dy = PedSocial.slotOffset(kind == "couple" and 7 or index)
    candidate.slotX,candidate.slotY = dx,dy
    return matrix[4][1]+dx*matrix[1][1]+dy*matrix[2][1],matrix[4][2]+dx*matrix[1][2]+dy*matrix[2][2]
end

function PedSocial.bind(leader, follower, actors, chat, slot, slotX, slotY)
    if not streetSocial(leader,actors[leader]) or not streetSocial(follower,actors[follower]) then return false end
    local walk = actors[follower]
    walk.leader = leader
    if slot then
        if not slotX then slotX,slotY = PedSocial.slotOffset(slot) end
        walk.slotX,walk.slotY = slotX,slotY
    end
    PedAI.setLeader(follower, leader)
    if chat then
        chatPair(leader,follower,actors,100000,getTickCount())
    end
    return true
end

function PedSocial.update(ped, walk, now, actors)
    local partner = walk.partner
    if partner then
        local other = actors[partner]
        if live(partner) and streetSocial(ped,walk) and streetSocial(partner,other)
            and other.partner == ped and not PedAI.busy(partner)
            and getElementInterior(ped)==getElementInterior(partner) and getElementDimension(ped)==getElementDimension(partner)
            and not isPedInVehicle(ped) and not isPedInVehicle(partner)
            and not (PedAI.isScriptControlled and PedAI.isScriptControlled(partner))
            and (now - walk.chatSince) % 4294967296 < walk.chatDuration then
            if walk.gesture and (now-walk.gestureStarted)%4294967296 >= PedActivityClips[walk.gesture] then
                removeElementData(ped,motion)
                walk.gesture = nil
                walk.spoke = true
                other.spoke = false
            elseif not walk.gesture and not other.gesture and not walk.spoke then
                walk.gesture = math.random(0,65535) < 20 and "xpressscratch" or "idle_chat"
                walk.gestureStarted = now
                setElementData(ped,motion,{walk.gesture,false,now,PedActivityClips[walk.gesture],now,"PED"},"broadcast","deny")
                if PedVoice and walk.gesture == "idle_chat" then PedVoice.emit(ped,"chat") end
            end
            return true
        end
        walk.chatEnded = now
        PedSocial.interrupt(ped, walk)
        -- 0020ABF8 passes the partner's third-party target into 002201A0.
        local otherBrain = live(partner) and PedAI.brain(partner)
        local objective = otherBrain and otherBrain.event
        if objective and (objective.intent == "fight" or objective.intent == "flee") and live(objective.target)
            and objective.target ~= ped and not PedAI.isScriptControlled(partner) then
            local brain = PedAI.brain(ped)
            if brain and brain:react("damage",objective.target,getPedWeapon(objective.target)) then return true end
        end
    end
    local gathering = walk.gatherLeader
    if gathering then
        local leaderState = actors[gathering]
        if live(gathering) and streetSocial(ped,walk) and streetSocial(gathering,leaderState)
            and leaderState.partner and not PedAI.busy(gathering) then
            if not walk.gathering then
                stopWalking(ped,walk)
                walk.gathering = true
                facePartner(ped,walk,gathering)
            end
            if not walk.lastInvite or (now-walk.lastInvite)%4294967296 >= 200 then
                walk.lastInvite = now
                local x,y,z = getElementPosition(ped)
                local nearby = getElementsWithinRange(x,y,z,10,"ped",getElementInterior(ped),getElementDimension(ped)) or {}
                local count = 0
                local info = PedAIModels[walk.originalModelId]
                for _,other in ipairs(nearby) do
                    local state = actors[other]
                    local entry = state and PedAIModels[state.originalModelId]
                    if other ~= ped and state and state.gatherLeader and entry and entry[1] == info[1] then count=count+1 end
                end
                if count < 5 then
                    for _,other in ipairs(nearby) do
                        local state = actors[other]
                        local entry = state and PedAIModels[state.originalModelId]
                        if streetSocial(other,state) and not isPedInVehicle(other)
                            and state.queued > 0 and entry[1] == info[1] and not state.partner
                            and not state.gatherLeader and not state.leader and not state.crossing and live(other)
                            and not PedAI.busy(other) and not PedActivity.active(other)
                            and not (PedAI.isScriptControlled and PedAI.isScriptControlled(other)) then
                            state.gatherLeader = gathering
                        end
                    end
                end
            end
            return true
        end
        -- A group is admitted one actor at a time. Wait for the partner's
        -- clearance result before allowing the odd member to start following.
        if not walk.gathering and live(gathering) and not walk.gatherSince then walk.gatherSince = now end
        if not walk.gathering and walk.gatherSince and (now-walk.gatherSince)%4294967296 < 2000 then return true end
        if walk.facingTarget then removeElementData(ped,facingTarget) end
        walk.facingTarget,walk.gathering, walk.gatherLeader, walk.gatherSince = nil,nil,nil,nil
    end
    local leader = walk.leader
    if not leader then return false end
    if not live(leader) or PedAI.isScriptControlled and PedAI.isScriptControlled(leader) or getElementDimension(ped) ~= getElementDimension(leader)
        or getElementInterior(ped) ~= getElementInterior(leader) then
        if walk.followTask then stopWalking(ped, walk) end
        local brain = PedAI.brain(ped)
        if brain and brain.leader == leader then brain.leader = nil end
        walk.followTask, walk.leader, walk.assisted = nil, nil, nil
        return false
    end
    -- A fighting leader's current opponent can change without the formation
    -- changing. Associate assistance with that objective instance.
    local chief,brain = PedAI.brain(leader),PedAI.brain(ped)
    local goal = chief and chief.event
    if goal and goal.intent == "fight" and goal ~= walk.assisted and live(goal.target)
        and goal.target ~= ped and brain and not isPedInVehicle(ped) then
        walk.assisted = goal
        if brain:react("ally",goal.target,getPedWeapon(goal.target),"fight","run",8000) then
            walk.followTask = nil
            return true
        end
    end
    local car, aboard = getPedOccupiedVehicle(leader), getPedOccupiedVehicle(ped)
    local peer = getElementSyncer(ped)
    if aboard then
        walk.followTask = nil
        if aboard ~= car and isElement(peer) and (not walk.boardTick or (now-walk.boardTick)%4294967296 >= 2000) then
            triggerClientEvent(peer,"npchlc_traffic:occupantExit",resourceRoot,ped,aboard,getPedOccupiedVehicleSeat(ped))
            walk.boardTick = now
        end
        return true
    end
    if car and isElement(peer) then
        local x,y,z = getElementPosition(ped)
        local a,b,c = getElementPosition(car)
        if (a-x)^2+(b-y)^2+(c-z)^2 < 16 and not isVehicleLocked(car) then
            for slot=1,getVehicleMaxPassengers(car) or 0 do
                if not getVehicleOccupant(car,slot) then
                    if not walk.boardTick or (now-walk.boardTick)%4294967296 >= 2500 then
                        stopWalking(ped,walk)
                        walk.followTask,walk.boardTick = nil,now
                        triggerClientEvent(peer,"npchlc_traffic:boardPassenger",resourceRoot,ped,car)
                    end
                    return true
                end
            end
        end
    end
    if not walk.followTask then
        stopWalking(ped, walk)
        local task = walk.slotX and {"walkFormation",leader,0.45,walk.slotX,walk.slotY}
            or {"walkFollowElement",leader,1.15}
        walk.followTask = hlc:setNPCTask(ped,task)
    end
    return walk.followTask
end
local function facing(ped,other,dx,dy)
    local _,_,az = getElementRotation(ped)
    local _,_,bz = getElementRotation(other)
    local length = math.sqrt(dx*dx+dy*dy)
    if length < 0.001 then return false end
    az,bz = math.rad(az),math.rad(bz)
    return -math.sin(az)*dx+math.cos(az)*dy > 0.5*length
        and math.sin(bz)*dx-math.cos(bz)*dy > 0.5*length
end

local function mayChat(a,b,model)
    if a == 10 or b == 10 or model == 54 or model >= 66 and model <= 68 then return false end
    if a == b then return true end
    return a ~= 18 and b ~= 6 and b >= 4 and not (a >= 7 and a <= 15 or b >= 7 and b <= 15)
end

function PedSocial.meet(ped,walk,actors,now)
    if walk.crossing or walk.gatherLeader or walk.leader or walk.partner or not streetSocial(ped,walk)
        or isPedInVehicle(ped) then return false end
    local profile = PedAI.profile(ped)
    if not profile then return false end
    local look = profile.pedType == 4 and (not walk.lookTick or (now-walk.lookTick)%4294967296 >= walk.lookDelay)
    -- 001F1A58 rolls before reading the deadline. Each failed roll postpones
    -- the next opportunity, even when the previous 200 ms have not elapsed.
    local chat = false
    if math.random() >= 0.5 then
        walk.socialTick = now
    else
        chat = (not walk.socialTick or (now-walk.socialTick)%4294967296 > 200)
            and (not walk.chatEnded or (now-walk.chatEnded)%4294967296 >= 30000)
    end
    if not look and not chat then return false end
    if look then walk.lookTick, walk.lookDelay = now,10000 end
    local x,y,z = getElementPosition(ped)
    for _,other in ipairs(getElementsWithinRange(x,y,z,look and 10 or 1.8,"ped",getElementInterior(ped),getElementDimension(ped)) or {}) do
        local partner = actors[other]
        if ped ~= other and partner and live(other) and not PedAI.busy(other)
            and not (PedAI.isScriptControlled and PedAI.isScriptControlled(other)) then
            local a,b,c = getElementPosition(other)
            local dx,dy = a-x,b-y
            local d = dx*dx+dy*dy+(c-z)^2
            local target = PedAI.profile(other)
            if target and facing(ped,other,dx,dy) then
                if look and target.pedType == 5 and target.social > profile.social and d < 100 then
                    local observers = getElementsWithinRange(x,y,z,80,"player",getElementInterior(ped),getElementDimension(ped))
                    if observers and #observers > 0 then triggerClientEvent(observers,"npchlc_traffic:socialLook",resourceRoot,ped,other,4000) end
                    if PedVoice then PedVoice.emit(ped,"look") end
                    walk.lookDelay,look = 4000,false
                end
                if chat and d < 1.8^2 and streetSocial(other,partner) and partner.queued > 0 and not partner.crossing
                    and not partner.leader and not partner.partner and not partner.gatherLeader
                    and not partner.mug and not partner.theft and not partner.wait and not partner.roadFall and not partner.hitAt
                    and not PedActivity.active(other) and not isPedInVehicle(other)
                    and (not partner.chatEnded or (now-partner.chatEnded)%4294967296 >= 30000)
                    and mayChat(profile.pedType,target.pedType,partner.originalModelId) then
                    chatPair(ped,other,actors,10000+math.random(0,65535)%4000,now)
                    return true
                end
            end
        end
    end
    return false
end
