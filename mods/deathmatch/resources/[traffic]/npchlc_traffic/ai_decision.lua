--[[
    AI Decision Logic
    Dev: Nurupo
]]

AI_DECISION = {}


function AI_DECISION.excuteAIDecisionDefault(npc)
    --AI_DECISION.excuteAIDecisionPsyco(npc)
    if isPedInVehicle(npc) then
        if getElementData(npc,"npchlc:temper") < 20 then AI_DECISION.excuteAIDecisionWeak(npc) end
    else
        AI_DECISION.excuteAIDecisionWeak(npc)
    end
end
function AI_DECISION.excuteAIDecisionWeak(npc)
    if isPedInVehicle(npc) then
        npc_hlc:setNPCDriveStyle(npc,"aggressive")
    else
        --local currentTask = npc_hlc:getNPCTask(npc)
        npc_hlc:clearNPCTasks(npc)
        for nodenum = 1,4 do addRandomNodeToPedRoute(npc) end
        npc_hlc:setNPCWalkSpeed(npc,"sprint")
    end
    
end

function AI_DECISION.excuteAIDecisionPsyco(npc)
    local attacker = getElementData(npc,"npchlc:attacker")
    if isElement(attacker) then 
        --print(attacker)
        --npc_hlc:setNPCWalkSpeed (npc, "run")
        if isPedInVehicle(npc) then 
            local choice = math.random(0,1)
            if choice == 0 then
                npc_hlc:setNPCTask(npc,{"chaseElement", attacker})
                npc_hlc:setNPCDriveStyle(npc,"aggressive")
            else
                npc_hlc:setNPCTask(npc,{"attackElement", attacker})
            end
        else
            npc_hlc:setNPCTask(npc,{"attackElement", attacker})
        end
    end
end
function AI_DECISION.excuteAIDecisionCop(npc)
    local attacker = getNPCAttacker(npc)
    if attacker and isElement(attacker) then 
        --print("set cop arrest")
        --print(attacker)
        --npc_hlc:setNPCWalkSpeed (npc, "run")
        npc_hlc:setNPCTask(npc,{"arrestElement", attacker})
        npc_hlc:setNPCDriveStyle(npc,"aggressive")
    else
        npc_hlc:setNPCWalkSpeed(npc,"walk")
    end
end
function excuteAIDecision(npc)
    --print(getElementData(npc,"npchlc:group"))
    local group = getElementData(npc,"npchlc:group") == false and "DEFAULT" or getElementData(npc,"npchlc:group")
    excutePedGroupDecision(npc,group)
end
addEvent("traffic.server.excuteAIDecision",true)
addEventHandler("traffic.server.excuteAIDecision",root,excuteAIDecision)
