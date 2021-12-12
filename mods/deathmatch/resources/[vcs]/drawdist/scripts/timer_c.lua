local globalTimer = nil
local luaTimers = {}

local lastID = 0
local startUpTime = getTickCount()


local luaTimerExecuted 

local putLuaTimerAtHisPlace = function (luaTimer)
	local index = 1
	if #luaTimers > 0 then
		local endTime =  luaTimer.endTime
		repeat 
			if endTime > luaTimers[index].endTime then
				break
			else
				index = index+1
			end
			
		until index > #luaTimers
	end
	table.insert(luaTimers, index, luaTimer)
end

function checkGlobalTimer (timeNow)
	local remaining
	if globalTimer and isTimer(globalTimer) then
		remaining, executesRemaining, totalExecutes = getTimerDetails(globalTimer)
	end
	if not remaining or remaining <= 0 or remaining > 50 then
		if globalTimer and isTimer(globalTimer) then
			killTimer(globalTimer)
			globalTimer = nil
		end
		if (not globalTimer or not isTimer(globalTimer)) and #luaTimers > 0 then
			local globalTimerInterval = luaTimers[#luaTimers].endTime - timeNow

			globalTimer = setTimer(luaTimerExecuted, math.max(50, globalTimerInterval),1)
		end
	end
end

function luaTimerExecuted ()
	local index = #luaTimers
	local timeNow =  getTickCount()
	
	if index > 0 then
		repeat
			
			local endLoop = false
			local luaTimerData = luaTimers[index]
			if timeNow > luaTimerData.endTime - 50 then
				
				
				
				table.remove(luaTimers, index)
				
				local stopTheTimer = false 
				if not luaTimerData.exportFunction then
					luaTimerData.theFunction(unpack(luaTimerData.arguments))
				else
					local exportData = luaTimerData.exportFunction
					local thisResource = getResourceFromName(exportData[1])
					if thisResource and getResourceState (thisResource) ==  "running" then
						if not call (thisResource, exportData[2], unpack(luaTimerData.arguments)) then
							stopTheTimer = true
						end
					else
						stopTheTimer = true
					end
				end
				
				
				
				if not stopTheTimer then
					local timesToExecute = luaTimerData.timesToExecute
					if timesToExecute ~= 0 then
						
						
						local timesAlreadyExecuted = luaTimerData.timesAlreadyExecuted - 1
						if timesAlreadyExecuted > 0 then
							luaTimerData.timesAlreadyExecuted = timesAlreadyExecuted
							luaTimerData.endTime = timeNow + luaTimerData.timeInterval
							putLuaTimerAtHisPlace (luaTimerData)
						end
					else
						luaTimerData.endTime = timeNow + luaTimerData.timeInterval
						putLuaTimerAtHisPlace (luaTimerData)
					end
				end
			else
				endLoop = true
			end
			index = index - 1
		until index == 0 or endLoop

	end
	
	
	
	if #luaTimers ~= 0 then
		checkGlobalTimer(timeNow)
	else
		globalTimer = nil

	end
end

function getResourceNameAndFunctionNameFromExport (exportString)
	local resourceName, exportFunctionName  = string.match(exportString,"exports.(.-):(.*)")
	if resourceName and exportFunctionName then
		return resourceName, exportFunctionName
	end
	return false
end

function createLuaTimer (theFunction, timeInterval, timesToExecute, ...)
	local isExportFunction = false
	local resourceName, exportFunctionName
	
	if type(theFunction) == "string" then
		resourceName, exportFunctionName = getResourceNameAndFunctionNameFromExport(theFunction)
		if resourceName and exportFunctionName then
			isExportFunction = true
		end
	end
	
	if (type(theFunction) == "function" or isExportFunction) and type(timeInterval) == "number" and timeInterval > 0 then
		if type(timesToExecute) ~= "number" or timesToExecute < 0 then
			timesToExecute = 1
		end
		local timeNow = getTickCount()
		local ID =  "luaTimerID:" .. startUpTime .. "|" .. lastID + 1  
		local luaTimerData = {
			ID = ID,
			theFunction = theFunction,
			timeInterval = timeInterval,
			timesAlreadyExecuted = timesToExecute,
			timesToExecute = timesToExecute,
			endTime = timeNow + timeInterval,
			arguments = {...},
			exportFunction = isExportFunction and {resourceName, exportFunctionName} or false
		}
		

		putLuaTimerAtHisPlace (luaTimerData)

		lastID = lastID + 1
		
		checkGlobalTimer(timeNow)
		
		return ID
	end
	return false
end

function killLuaTimer (ID)

	for i=1, #luaTimers do
		if luaTimers[i].ID == ID then
			table.remove(luaTimers, i)
			checkGlobalTimer(getTickCount())

			return true
		end
	end
	
	return false 
end


function isLuaTimer (ID)

	for i=1, #luaTimers do
		if luaTimers[i].ID == ID then
			return true
		end
	end
	
	return false 
end

function getLuaTimers ()
	return luaTimers
end


function getLuaTimerCount()
	return #luaTimers
end


function killGlobalTimer ()
	if globalTimer then
		killTimer(globalTimer)
		globalTimer = nil
	end
end


