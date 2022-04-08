function handleElementChange(theKey, oldValue, newValue) 
	if streamed_npcs[source] == nil and theKey == "npc_hlc" then 
		initNPCData(source)
	end
	-- sync when need to reset
	if streamed_npcs[source] then 
        --print(theKey,oldValue)
		if theKey == "npc_hlc" then 
			if newValue == false then 
				streamed_npcs[source] = nil 
				return
			end
		else -- deal with normal rpc
			local rpc = split(theKey,":")[2]
			
            if rpc then
                if not string.find(rpc,"task.") then -- when is normal rpc
                    setNPCData(source,rpc,newValue) 
                else -- when is task rpc (array)
                    
                    local task_no = string.match(theKey, '%d+')
                    if theKey ~= nil and task_no ~= nil and streamed_npcs[source] then 
						if streamed_npcs[source].tasks[theKey] ~= newValue then -- only update changed
                        	streamed_npcs[source].tasks[theKey] = newValue
						end
                    end
                end
			end
		end
	end
end
addEventHandler("onClientElementDataChange", root,handleElementChange)

addEvent("npc_hlc:sentClientSyncRPC",true)
addEventHandler("npc_hlc:sentClientSyncRPC",root,function(rpc,value)
    print(rpc)
end)