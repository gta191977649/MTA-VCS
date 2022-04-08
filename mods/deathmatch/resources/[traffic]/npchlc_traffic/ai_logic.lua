-- This file defines the logic response when a hit a certain event
AI_LOGIC = {}

AI_LOGIC.onAttacked = function(ped,attacker) 
	if isElement(attacker) then
		attacker = getPlayerElementInVehicle(attacker)
		if not attacker then return end
		if getElementType(attacker) == "player" then
			setElementSyncer(ped,attacker)
			local gang = getPedGroup(ped)
			if gang ~= false and isGangGroup(gang) then
				if isEnforcementGroup(gang) then 
					local wanted = getPlayerWantedLevel(attacker)
					if wanted == 0 and getElementHealth(attacker) > 0 then
						--WANTED:setPlayerWanted(attacker,1)
						WANTED:increasePlayerWanted(attacker,1)
					end
				end
				players[attacker].rageGroups[gang] = true
				for npc, _ in pairs(population.peds) do 
					if population.peds[npc].group ~= nil and population.peds[npc].group == gang then
						setNPCAttacker(npc,attacker)
						excuteAIDecision(npc)
					end
				end

			end

			setNPCAttacker(ped,attacker)
			excuteAIDecision(ped)
		elseif getElementType(attacker) == "ped" then
			if isAttackerRespect(ped,attacker) then 
				return
			end
			local group = getPedGroup(ped)
			if isEnforcementGroup(group) then
				if not hasElementHigherProperty(ped,attacker) then 
					return
				end
			end
			if group ~= "DEFAULT" then
				for npc in pairs(population.peds) do 
					if population.peds[npc].group ~= nil and population.peds[npc].group == group then
						setNPCAttacker(npc,attacker)
						excuteAIDecision(npc)
					end
				end
			end

            setNPCAttacker(ped,attacker)
            excuteAIDecision(ped)
		end

		-- see by cops
		if getElementType(attacker) == "player" then
			increaseWantedIfSeenByCops(attacker)
		end
	end
end