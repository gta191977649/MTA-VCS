function isHLCEnabled(npc)
	if not isElement(npc) then return false end
	if streamed_npcs[npc] ~= nil then 
		return true 
	end
	return getElementData(npc,"npc_hlc") or false 
end

function getNPCWalkSpeed(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	if streamed_npcs[npc] ~= nil and streamed_npcs[npc].walk_speed ~= nil then 
		return streamed_npcs[npc].walk_speed 
	end
	return getElementData(npc,"npc_hlc:walk_speed")
end

function getNPCWeaponAccuracy(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	if streamed_npcs[npc] ~= nil and streamed_npcs[npc].accuracy ~= nil then 
		return streamed_npcs[npc].accuracy 
	end
	return getElementData(npc,"npc_hlc:accuracy")
end

function getNPCDriveSpeed(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	if streamed_npcs[npc] ~= nil and streamed_npcs[npc].drive_speed ~= nil then 
		return streamed_npcs[npc].drive_speed 
	end

	return getElementData(npc,"npc_hlc:drive_speed")
end

function getNPCCurrentTask(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	-- else use element data
	--[[
	local thistask = getElementData(npc,"npc_hlc:thistask")
	if thistask then
		local task = getElementData(npc,"npc_hlc:task."..thistask)

		return task
	end
	]]
	if streamed_npcs[npc] ~= nil and streamed_npcs[npc].tasks ~= nil then 
		local thistask = streamed_npcs[npc].thistask
		if thistask ~= nil then 
			local task = streamed_npcs[npc].tasks["npc_hlc:task."..thistask]
			if task ~= nil then
				--print("from cache")
				return task
			end
		end
	else
		local thistask = getElementData(npc,"npc_hlc:thistask") or nil
		if thistask ~= nil and streamed_npcs[npc] ~= nil then
			local task = getElementData(npc,"npc_hlc:task."..thistask) or nil
			if task ~= nil then
				streamed_npcs[npc].thistask = thistask
				streamed_npcs[npc].tasks["npc_hlc:task."..thistask] = task
				
				--print("From element data")
				return task
			end
		end
		
	end

	return false
end

function setNPCTaskToNext(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	
	local thistask = streamed_npcs[npc].thistask or getElementData(npc,"npc_hlc:thistask")
	streamed_npcs[npc].thistask = thistask+1
	setElementData(npc,"npc_hlc:thistask",streamed_npcs[npc].thistask)
	-- sync buffer (decrease set/get element data access)
	
end

function setNPCWalkSpeed(npc,speed)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end

	if speed ~= "walk" and speed ~= "run" and speed ~= "sprint" and speed ~= "sprintfast" then
		outputDebugString("Invalid speed argument",2)
		return false
	end
	streamed_npcs[npc].walk_speed = speed
	setElementData(npc,"npc_hlc:walk_speed",speed)
	return true
end


function setNPCDriveSpeed(npc,speed)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end

	speed = tonumber(speed)
	if not speed or speed < 0 then
		outputDebugString("Invalid speed argument",2)
		return false
	end
	streamed_npcs[npc].drive_speed = speed
	setElementData(npc,"npc_hlc:drive_speed",speed)
	return true
end

function setNPCDriveStyle(npc,style)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end

	if style ~= "normal" and style ~= "aggressive" then
		outputDebugString("Invalid speed argument",2)
		return false
	end
	streamed_npcs[npc].drive_style = style
	setElementData(npc,"npc_hlc:drive_style",style)
end

function getNPCDriveStyle(npc)
	if not isHLCEnabled(npc) then
		outputDebugString("Invalid ped argument",2)
		return false
	end
	if streamed_npcs[npc] ~= nil and streamed_npcs[npc].drive_style ~= nil then 
		return streamed_npcs[npc].drive_style 
	end
	return getElementData(npc,"npc_hlc:drive_style")
end
 