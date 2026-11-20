PedMugging = {}
local hlc = exports.npc_hlc
local motion = "npchlc_traffic:activityMotion"
local targets = setmetatable({}, {__mode="kv"})
local function age(now,tick) return (now-tick)%4294967296 end

function PedMugging.cancel(ped,walk)
    local event = walk.mug
    if not event then return end
    if targets[event.target] == ped then targets[event.target] = nil end
    if event.gesture and isElement(ped) then removeElementData(ped,motion) end
    walk.mug = nil
end

local function usable(ped)
    return isElement(ped) and not isPedDead(ped) and not isPedInVehicle(ped)
        and not (PedAI.isScriptControlled and PedAI.isScriptControlled(ped))
end

function PedMugging.update(ped, walk, actors, now)
    local model = PedAIModels[walk.originalModelId]
    if not model or model[1] ~= 18 then return false end
    local event = walk.mug
    local x,y,z = getElementPosition(ped)
    if not event then
        if walk.queued == 0 or walk.partner or walk.leader or walk.theft or PedActivity.active(ped)
            or isPedInVehicle(ped) or walk.mugRoll and age(now,walk.mugRoll) <= 5000 then return false end
        walk.mugRoll = now
        -- 0x001F16D0 first draws for a car, then tests the low three bits.
        if math.random(0,65535)%100 < 10 then return PedTheft.seekOccupied(ped,walk,now) end
        if math.random(0,7) ~= 0 then return false end
        local best, distance = nil,49
        for _,other in ipairs(getElementsWithinRange(x,y,z,7,"ped",getElementInterior(ped),getElementDimension(ped)) or {}) do
            local victim = actors[other]
            if other ~= ped and victim and not victim.mug and not targets[other] and usable(other) then
                local info = PedAIModels[victim.originalModelId]
                local role = info and info[1]
                if role == 4 or role == 5 or role == 18 or role == 19 or role == 20 then
                    local a,b,c = getElementPosition(other)
                    local d = (a-x)^2+(b-y)^2+(c-z)^2
                    if d <= distance then best,distance = other,d end
                end
            end
        end
        if not best or not hlc:setNPCTask(ped,{"walkFollowElement",best,1}) then return false end
        targets[best],walk.mug = ped,{target=best}
        walk.queued, walk.anchor, walk.blockedSince, walk.crossing = 0,nil,nil,nil
        return true
    end
    local other = event.target
    if usable(other) and getElementDimension(ped) == getElementDimension(other)
        and getElementInterior(ped) == getElementInterior(other) then
        local a,b,c = getElementPosition(other)
        local d = (a-x)^2+(b-y)^2+(c-z)^2
        if d <= 1.4^2 then
            if not event.gesture then
                hlc:clearNPCTasks(ped)
                setElementRotation(ped,0,0,math.deg(math.atan2(x-a,b-y)),"default",true)
                event.gesture = now
                setElementData(ped,motion,{"fucku",false,now,PedActivityClips.fucku,now},"broadcast","deny")
            elseif age(now,event.gesture) > 0.8*PedActivityClips.fucku then
                PedMugging.cancel(ped,walk)
                local brain,victim = PedAI.brain(ped),PedAI.brain(other)
                if not brain or not victim then return false end
                brain.dropCash = true
                victim:react("damage",ped,getPedWeapon(ped))
                local fighting = victim.event and victim.event.intent == "fight" and victim.event.target == ped
                brain:react("passenger",other,0,"flee",fighting and "sprint" or "run",15000)
                if PedVoice then PedVoice.emit(other,"mugVictim") PedVoice.emit(ped,"mugger") end
                local observers = getElementsWithinRange(x,y,z,80,"player",getElementInterior(ped),getElementDimension(ped))
                if observers and #observers > 0 then
                    triggerClientEvent(observers,"npchlc_traffic:mugPunch",resourceRoot,ped)
                end
            end
            return true
        elseif d <= 100 then
            if event.gesture then
                event.gesture = nil
                removeElementData(ped,motion)
                hlc:setNPCTask(ped,{"walkFollowElement",other,1})
            end
            return true
        end
    end
    PedMugging.cancel(ped,walk)
    hlc:clearNPCTasks(ped)
    return false
end
