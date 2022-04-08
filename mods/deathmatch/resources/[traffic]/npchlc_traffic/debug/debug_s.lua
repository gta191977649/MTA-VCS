addCommandHandler("beatme",function(player,cmd,param) 
    local count = 0
    for npc, val in pairs(population.peds) do 
		local group = population.peds[npc].group
		setNPCAttacker(npc,player)
        AI_DECISION.excuteAIDecisionPsyco(npc)
        count = count + 1
	end
    outputChatBox(getPlayerName(player))
    outputChatBox("All npc attacker set. "..count)
end)

addCommandHandler("cop",function(player) 
	for npc, val in pairs(population.peds) do 
		local group = population.peds[npc].group
		if isEnforcementGroup(group) then
			local target = getNPCAttacker(npc)
			if target then
				print("has target "..getTickCount())
			end
		end
	end
end)
addCommandHandler("stopnpc",function(player) 
	for npc, val in pairs(population.peds) do 
		npc_hlc:clearNPCTasks(npc)
	end
end)
addCommandHandler("npcrun",function(player) 
	for v in pairs(population.peds) do
		if v and isElement(v) then
			setNPCAttacker(v,player)
			npc_hlc:clearNPCTasks(v)
			allocateNewRandomTaskForNPC(v)
			AI_DECISION.excuteAIDecisionWeak(v)
		end
	end
end)