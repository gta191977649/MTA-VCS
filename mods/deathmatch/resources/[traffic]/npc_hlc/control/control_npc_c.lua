DGS = exports.dgs
local _Async = Async


local EXEC_TIME = 0
local STREAM_NPCS = 0
local BUFFER_NPCS = 0
local FRAME_TIME = getTickCount()
local LAST_TICKTIME = 0




--Async:setPriority(500, 33); 

addEventHandler( "onClientElementStreamIn", root,
    function ( )
		--setElementCollisionsEnabled(source,false)
        if getElementType( source ) == "ped" then				
            if isHLCEnabled(source) then
				setPedCanBeKnockedOffBike(source,true)
				--[[
				local veh = getPedOccupiedVehicle(source)
				if veh then 
					setVehicleWheelStates(veh,3,3,3,3)
					setElementCollisionsEnabled(veh,false)
					--setElementFrozen(veh,true)
					print("set")
				end
				]]
				if streamed_npcs[source] == nil then
					initNPCData(source)
				end
			end
        end
    end
);

addEventHandler("onClientElementDestroy", root, function ()
 	if getElementType( source ) == "ped" then
        if streamed_npcs[source] then
			streamed_npcs[source] = nil
		end
    end
end)

--[[
addEventHandler( "onClientElementStreamOut", root,
    function ( )
        if getElementType( source ) == "ped" then
            if streamed_npcs[source] ~= nil then
				streamed_npcs[source] = nil
			end
        end
    end
);
--]]
--_Async:setDebug(true); 
--_Async:setPriority("low"); 

function cycleNPCs() 
	local TICK_TIME = getTickCount()
	local STREAM = 0
	local BUFFER = 0
	_Async:forkey(streamed_npcs,function(npc) 
		if isElementStreamedIn(npc) and getElementHealth(getPedOccupiedVehicle(npc) or npc) >= 0 then
			--checkAddtionalAIParams(npc) 
			local task = getNPCCurrentTask(npc)
			if task ~= nil and task ~= false then
				if performTask[task[1]](npc,task) then
					setNPCTaskToNext(npc)
				end
			else
				stopAllNPCActions(npc)
			end
			STREAM = STREAM + 1
		end
		BUFFER = BUFFER + 1
	end,function() 
		STREAM_NPCS = STREAM
		BUFFER_NPCS = BUFFER
		EXEC_TIME = getTickCount() - TICK_TIME
		initNPCControl()
	end)
end
cycleNPCs_old = function()
	--local data = getElementsByType("ped",root,true)

	local TICK_TIME = getTickCount()
	local STREAM = 0
	local BUFFER = 0
	local data = getElementsByType("ped",root,true)
	_Async:foreach(data, function(npc,pednum) 
		if isElement(npc) then
			if isElementStreamedIn(npc) and isHLCEnabled(npc) then
				if getElementHealth(getPedOccupiedVehicle(npc) or npc) >= 0 then
					checkAddtionalAIParams(npc) 
					local task = getNPCCurrentTask(npc)
					if task ~= nil and task ~= false then
						if performTask[task[1]](npc,task) then
							setNPCTaskToNext(npc)
						end
					else
						stopAllNPCActions(npc)
					end
				
				end
				STREAM = STREAM + 1
			end
			BUFFER = BUFFER + 1
		end
		
	end,function() 
		STREAM_NPCS = STREAM
		BUFFER_NPCS = BUFFER
		EXEC_TIME = getTickCount() - TICK_TIME
		initNPCControl()
	end)
end

addEventHandler( "onClientRender",root,function() 
	local currentTick = getTickCount()
	LAST_TICKTIME = currentTick - FRAME_TIME
	FRAME_TIME = currentTick
end)

local debug = DGS:dgsCreateLabel(0.001,0.96,0,0,"",true)
DGS:dgsSetProperty(debug,"font","sans")
DGS:dgsSetProperty(debug,"shadow",{2,2,tocolor(0,0,0,255),2})
DGS:dgsSetProperty(debug,"textSize",{1.3,1.3})
DGS:dgsSetEnabled(debug,false)
setTimer(function() 
	local info = dxGetStatus()
	DGS:dgsSetProperty(debug,"text",string.format("NPCHLC BUFFER: %d | STREAMED: %d | CPU_TIME: %d ms | FRAME_TIME: %d ms",BUFFER_NPCS,STREAM_NPCS,EXEC_TIME,LAST_TICKTIME))
end,1000,0)