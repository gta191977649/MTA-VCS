COP_SPOTS_RANGE = 15
function initAI()
	ped_nodes = {}
	ped_conns = {}
	ped_thisnode = {}
	ped_lastnode = {}
	ped_lane = {}
	ped_drivespeed = {}
	ped_interrupted_task = {}
end
function getPlayerElementInVehicle(element) 
	if getElementType(element) == "vehicle" then
		local ped = getVehicleOccupant(element)
		return ped
	else
		return element
	end
end

function setNPCAttacker(npc,target)
	if population.peds[npc] == nil then return end
	setElementData(npc,"npchlc:attacker",target)
	--iprint(population.peds[npc])
end
function getNPCAttacker(npc)
	if not population.peds[npc] then return false end
	return getElementData(npc,"npchlc:attacker")
end

function increaseWantedIfSeenByCops(attacker) 
	if isElement(attacker) then
		if getElementType(attacker) == "player" and getPlayerWantedLevel(attacker) == 0 then -- when is player
			local x, y, z = getElementPosition(attacker)
			local nearbyCops = getElementsWithinRange(x, y, z, COP_SPOTS_RANGE, "ped") 
			for i,v in ipairs(nearbyCops) do
				if v and isElement(v) then
					local ped_group = getPedGroup(v)
					if isEnforcementGroup(ped_group) and getElementHealth(attacker) > 0 then -- seen by cops
						WANTED:increasePlayerWanted(attacker,1)
						return
					end
				end
			end
		end
		if getElementType(attacker) == "ped" then -- when is ped, help the player
			local x, y, z = getElementPosition(attacker)
			local nearbyCops = getElementsWithinRange(x, y, z, COP_SPOTS_RANGE, "ped") 
			for i,v in ipairs(nearbyCops) do
				if v and isElement(v) then
					local ped_group = getPedGroup(v)
					if isEnforcementGroup(ped_group) and getElementHealth(attacker) > 0 then 
						setNPCAttacker(v,attacker)
						excuteAIDecision(v)
					end
				end
			end
		end
	end
end
function initPedRouteData(ped)
	
	ped_nodes[ped] = {}
	ped_conns[ped] = {}
	ped_drivespeed[ped] = {}

	local model = getElementModel(ped)
	local group = getPedGroup(ped)
	
	setElementData(ped,"npchlc:temper",math.random(0,100))
	--setElementData(ped,"npchlc:temper",0)
	setNPCAttacker(ped,false)
	npc_hlc:setNPCWeaponAccuracy(ped,0.95)
	--npc_hlc:setNPCDriveStyle(ped,"aggressive")


	addEventHandler("onElementDestroy",ped,uninitPedRouteDataOnDestroy)
	addEventHandler("npc_hlc:onNPCTaskDone",ped,function(task)
		--iprint(task[1])
		continuePedRoute(task)
	end)
	--[[
	addEventHandler("npc_hlc:onNPCTaskClear",ped,function(task)
		--iprint(task)
		--setNPCAttacker(ped,false)
		--for nodenum = 1,4 do addRandomNodeToPedRoute(ped) end
	end)
	--]]

	--npc_hlc:onNPCThreaten
	addEventHandler("npc_hlc:onNPCThreaten",ped,function(attacker) 
		AI_LOGIC.onAttacked(ped,attacker)
	end)
	addEventHandler("npc_hlc:onNPCDamage",ped,function(attacker) 
		AI_LOGIC.onAttacked(ped,attacker)
	end)
	addEventHandler("npc_hlc:onNPCVehicleJacked", ped,function(jacker) 
		if getElementType(jacker) == "player" then
			setNPCAttacker(ped,jacker)
			excuteAIDecision(ped)
			--print(getPlayerName(jacker))
			--print("set attacker!")
			local group = getPedGroup(ped)
			if isEnforcementGroup(group) and getPlayerWantedLevel(jacker) == 0 and getElementHealth(jacker) > 0 then 
				WANTED:increasePlayerWanted(jacker,1)
			else
				increaseWantedIfSeenByCops(jacker) 
			end
		end
		if getElementType(jacker) == "ped" then
			if isAttackerRespect(jacker,attacker) then 
				return
			end
			setNPCAttacker(ped,jacker)
			excuteAIDecision(ped)
		end
	end)
	local veh = getPedOccupiedVehicle(ped)
	if veh then
		addEventHandler("npc_hlc:onNPCVehicleDamage",veh,function(attacker,weapon,loss)
			if isElement(attacker) and isElement(ped) and getPedOccupiedVehicle(ped) then
				if getElementType(attacker) == "vehicle" then
					local driver = getVehicleOccupant (attacker)
					if isElement(driver) and getElementType(driver) == "player" then 
						setElementSyncer(ped,driver)
						setElementSyncer(veh,driver)
						setNPCAttacker(ped,driver)
						excuteAIDecision(ped)
						local group = getPedGroup(ped)
						if isEnforcementGroup(group) and getPlayerWantedLevel(driver) == 0 and getElementHealth(driver) > 0 then 
							WANTED:increasePlayerWanted(driver,1)
						end
					end
				end	
				if getElementType(attacker) == "player" then
					setNPCAttacker(ped,attacker)
					excuteAIDecision(ped)
					if isEnforcementGroup(group) and getPlayerWantedLevel(attacker) == 0 and getElementHealth(attacker) > 0 then 
						WANTED:increasePlayerWanted(attacker,1)
					end
				end	
				if getElementType(attacker) == "ped" then
					if isAttackerRespect(ped,attacker) then 
						return
					end
					if isEnforcementGroup(group) then
						if not hasElementHigherProperty(ped,attacker) then 
							return
						end
					end
					setNPCAttacker(ped,attacker)
					excuteAIDecision(ped)
				end	

			end
			
		end)
		
	end

end


function uninitPedRouteDataOnDestroy()
	ped_nodes[source] = nil
	ped_conns[source] = nil
	ped_thisnode[source] = nil
	ped_lastnode[source] = nil
	ped_lane[source] = nil
	ped_drivespeed[source] = nil
end

function continuePedRoute(task)
	if task == nil or task[1] == "waitForGreenLight" then return end
	local thisnode = ped_thisnode[source]
	if thisnode then 
		local speed = ped_drivespeed[source][thisnode]
		if speed then
			--call(npc_hlc,"setNPCDriveSpeed",source,speed/180)
			--npc_hlc:setNPCWalkSpeed (source, "walk")
			npc_hlc:setNPCDriveSpeed(source,speed/180)

			ped_drivespeed[source][thisnode] = nil
		end
		ped_thisnode[source] = thisnode+1
		addRandomNodeToPedRoute(source)
	end
end

function allocateNewRandomTaskForNPC(npc)
	local thisnode = ped_thisnode[npc]
	if thisnode then 
		local speed = ped_drivespeed[npc][thisnode]
		if speed then
			--call(npc_hlc,"setNPCDriveSpeed",source,speed/180)
			--npc_hlc:setNPCWalkSpeed (source, "walk")
			npc_hlc:setNPCDriveSpeed(npc,speed/180)

			ped_drivespeed[npc][thisnode] = nil
		end
		ped_thisnode[npc] = thisnode+1
		addRandomNodeToPedRoute(npc)
	end
	for nodenum = 1,4 do addRandomNodeToPedRoute(npc) end

end

function addNodeToPedRoute(ped,nodeid,nb)
	local n1num = ped_lastnode[ped]
	if not n1num then
		ped_nodes[ped][1] = nodeid
		ped_lastnode[ped] = 1
		return
	end
	local n0num,n2num = n1num-1,n1num+1
	local prevnode = ped_nodes[ped][n1num]
	local connid = node_conns[prevnode][nodeid]
	local lane = ped_lane[ped]
	ped_nodes[ped][n2num] = nodeid
	ped_conns[ped][n2num] = connid

	local n0 = ped_nodes[ped][n0num]
	local speed = conn_maxspeed[connid]
	if n0 and conn_maxspeed[node_conns[n0][n1]] ~= speed then
		ped_drivespeed[ped][n1num-1] = speed
	end

	local x1,y1,z1 = getNodeConnLanePos(prevnode,connid,lane,false)
	local x2,y2,z2 = getNodeConnLanePos(nodeid,connid,lane,true)
	if not x1 or not x2 then return end
	local zoff
	local vehicle = getPedOccupiedVehicle(ped)
	local model = getElementModel(vehicle or ped)
	if vehicle then
		local dx,dy,dz = x2-x1,y2-y1,z2-z1
		dx,dy,dz = dx*dx,dy*dy,dz*dz
		zoff = z_offset[model]*math.sqrt((dx+dy)/(dx+dy+dz))
	else
		zoff = 1
	end

	z1,z2 = z1+zoff,z2+zoff

	local lights
	if nodeid == conn_n1[connid] then
		lights = conn_light1[connid]
	else
		lights = conn_light2[connid]
	end

	if vehicle then
		local off = speed*0.1
		local enddist = lights and call(server_coldata,"getModelBoundingBox",model,"y2")+5 or off
		if nb then
			--call(npc_hlc,"addNPCTask",ped,{"driveAroundBend",node_x[nb],node_y[nb],x1,y1,z1,x2,y2,z2,off,enddist})
			npc_hlc:addNPCTask(ped,{"driveAroundBend",node_x[nb],node_y[nb],x1,y1,z1,x2,y2,z2,off,enddist})
		else
			--call(npc_hlc,"addNPCTask",ped,{"driveAlongLine",x1,y1,z1,x2,y2,z2,off,enddist,lights})
			npc_hlc:addNPCTask(ped,{"driveAlongLine",x1,y1,z1,x2,y2,z2,off,enddist,lights})
		end
	else
		--print("random add")

		if nb then
			--call(npc_hlc,"addNPCTask",ped,{"walkAroundBend",node_x[nb],node_y[nb],x1,y1,z1,x2,y2,z2,1,1})
			npc_hlc:addNPCTask(ped,{"walkAroundBend",node_x[nb],node_y[nb],x1,y1,z1,x2,y2,z2,1,1})
		else
			--call(npc_hlc,"addNPCTask",ped,{"walkAlongLine",x1,y1,z1,x2,y2,z2,1,1})
			npc_hlc:addNPCTask(ped,{"walkAlongLine",x1,y1,z1,x2,y2,z2,1,1})
		end
	end
	if not ped_thisnode[ped] then ped_thisnode[ped] = 1 end
	ped_lastnode[ped] = n2num

	if lights then
		--call(npc_hlc,"addNPCTask",ped,{"waitForGreenLight",lights})
		npc_hlc:addNPCTask(ped,{"waitForGreenLight",lights})
	end
end

function addRandomNodeToPedRoute(ped)
	local ped_x,ped_y,ped_z = getElementPosition(ped)
	local n2num = ped_lastnode[ped]
	local n1num,n3num = n2num-1,n2num+1
	local n1,n2 = ped_nodes[ped][n1num],ped_nodes[ped][n2num]
	local possible_turns = {}
	local total_density = 0
	local c12 = node_conns[n1][n2]
	for n3,connid in pairs(node_conns[n2]) do
		local c23 = node_conns[n2][n3]
		if not conn_forbidden[c12][c23] then
			if conn_lanes.left[connid] == 0 and conn_lanes.right[connid] == 0 then
				if n3 ~= n1 then
					local density = conn_density[connid]
					total_density = total_density+density
					table.insert(possible_turns,{n3,connid,density})
				end
			else
				local dirmatch1 = areDirectionsMatching(n2,n1,n2)
				local dirmatch2 = areDirectionsMatching(n2,n2,n3)
				if dirmatch1 == dirmatch2 then
					local density = conn_density[connid]
					total_density = total_density+density
					table.insert(possible_turns,{n3,connid,density})
				end
			end
		end
	end
	local n3,connid
	local possible_count = #possible_turns
	if possible_count == 0 then
		n3,connid = next(node_conns[n2])
	else
		local pos = math.random()*total_density
		local num = 1
		while true do
			num = num%possible_count+1
			local turn = possible_turns[num]
			pos = pos-turn[3]
			if pos <= 0 then
				n3,connid = turn[1],turn[2]
				break
			end
		end
	end
	addNodeToPedRoute(ped,n3,conn_nb[connid])
end
-- events
--[[
addEventHandler("onPlayerWeaponFire",root,function(weapon, endX, endY, endZ, hitElement, startX, startY, startZ) 

	if attacker and getElementType(attacker) == "player" then 
		local x, y, z = getElementPosition(attacker)
		local nearbyCops = getElementsWithinRange(x, y, z, COP_SPOTS_RANGE, "ped") 
		for i,v in ipairs(nearbyCops) do
			if v and isElement(v) then
				local ped_gang = getPedGroup(v)
				if isEnforcementGroup(ped_gang) then 
					setNPCAttacker(v,attacker)
					excuteAIDecision(v)
					if getElementType(attacker) == "player" and getPlayerWantedLevel(attacker) == 0 and getElementHealth(attacker) > 0 then 
						WANTED:increasePlayerWanted(attacker,1)
					end
					return
				end
			end
		end
	end

end)
--]]
--[[
addEventHandler("onPedWasted", root,function(totalAmmo,killer) 
	killer = getNPCAttacker(source)
	if killer ~= false and getElementType(killer) == "player" then 
		local group = getPedGroup(source)
		if group == "COP" and getPlayerWantedLevel(killer) < 3 and getElementHealth(killer) > 0 then
			WANTED:increasePlayerWanted(killer,1)
		end
		if group == "COP_2" and getPlayerWantedLevel(killer) < 3 and getElementHealth(killer) > 0 then
			WANTED:increasePlayerWanted(killer,1)
		end
		if group == "SWAT" and getPlayerWantedLevel(killer) < 4 and getElementHealth(killer) > 0 then
			WANTED:increasePlayerWanted(killer,1)
		end
		if group == "FBI" and getPlayerWantedLevel(killer) < 6 and getElementHealth(killer) > 0 then
			WANTED:increasePlayerWanted(killer,1)
		end
	end
end)
--]]
addEvent("onTrafficPedWasted",true)
addEventHandler("onTrafficPedWasted",root,function() 
	if population.peds[source] then
		local attacker = getNPCAttacker(source)
		if attacker ~= false and isElement(attacker) and getElementType(attacker) == "player" and attacker == client then 
			local group = getPedGroup(source)
			if group == "COP" and getPlayerWantedLevel(attacker) < 3 and getElementHealth(attacker) > 0 then
				WANTED:increasePlayerWanted(attacker,1)
			end
			if group == "COP_2" and getPlayerWantedLevel(attacker) < 3 and getElementHealth(attacker) > 0 then
				WANTED:increasePlayerWanted(attacker,1)
			end
			if group == "SWAT" and getPlayerWantedLevel(attacker) < 4 and getElementHealth(attacker) > 0 then
				WANTED:increasePlayerWanted(attacker,1)
			end
			if group == "FBI" and getPlayerWantedLevel(attacker) < 6 and getElementHealth(attacker) > 0 then
				WANTED:increasePlayerWanted(attacker,1)
			end
		end
		killPed(source)
		--setNPCAttacker(source,false)
		element_timers[source][setTimer(destroyElement,DISTORY_TIME,1,source)] = true
	end
end)
-- cop help player when seen
addEvent("onTrafficPlayerWasted",true)
addEventHandler ("onTrafficPlayerWasted",root, function(attacker) 
	if attacker and isElement(attacker) then 
		if getElementType(attacker) == "ped" and getPlayerWantedLevel(client) == 0 then -- only help if player had zero wanted
			--outputChatBox("you hit by npc")
			increaseWantedIfSeenByCops(attacker)
		end
		if getElementType(attacker) == "player" then -- when a player hited by other player
			--outputChatBox("you hit by other player")
			increaseWantedIfSeenByCops(attacker)
		end
	end
end) 
-- make npc scard when heard weapon

addEventHandler( "onPlayerWeaponFire", root,function (weapon)
	if isElement( source ) and getElementType(source) == "player" then
		local x, y, z = getElementPosition(source)
		local nearbyNPC = getElementsWithinRange(x, y, z, 50, "ped") 
		for i,v in ipairs(nearbyNPC) do
			if v and isElement(v) then
				local ped_group = getPedGroup(v)
				if not isEnforcementGroup(ped_group) then
					setNPCAttacker(v,source)
					AI_DECISION.excuteAIDecisionWeak(v)
				end
			end
		end
	end
end)

addEventHandler("onElementStartSync", root, function(syncer) 
	if population.peds[source] then
		local gang = getPedGroup(source)
		if isEnforcementGroup(gang) and getPlayerWantedLevel(syncer) > 0 and getElementHealth(syncer) > 0 then 
			npc_hlc:clearNPCTasks(source)
			setNPCAttacker(source,syncer)
			excuteAIDecision(source)
		
		end 
	end	
end)

addEventHandler("onPlayerWanted",root,function(wanted) 
	--print(string.format("%s Wanted -> %d",getPlayerName(source),wanted))
	if getElementHealth(source) < 1 then 
		return 
	end

	wanted = tonumber(wanted)



	for npc, _ in pairs(population.peds) do 
		local group = getPedGroup(source)
		if isEnforcementGroup(group) then
			local target = getNPCAttacker(npc)
			if wanted == 0 then
				if isElement(target) and getElementType(target) == "ped" or isElement(target) and target == source then
					setNPCAttacker(npc,false)
					npc_hlc:clearNPCTasks(npc)
					allocateNewRandomTaskForNPC(npc)
					AI_DECISION.excuteAIDecisionCop(npc)
					--excuteAIDecision(npc)
				end
			end
			if wanted > 0 then
				if not target or isElement(target) and getElementType(target) ~= "player" then
					--npc_hlc:clearNPCTasks(npc)
					setNPCAttacker(npc,source)
					excuteAIDecision(npc)
				end
			end
		end
	end

	local veh = getPedOccupiedVehicle(source)
	if veh then 
		for seat, player in pairs(getVehicleOccupants(veh)) do
			if player ~= source then
				setPlayerWantedLevel(player,wanted)
			end
		end
	end
end)
