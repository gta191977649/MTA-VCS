function isStringTrue (str)
	return (str == 'true')
end

function startsWithLOD(str)
    return string.sub(str, 1, 3) == "LOD"
end

streamTimes = {}
streamTimeObj = {}

function setModelStreamTime(model,sIn,sOut)
	streamTimes[model] = {sIn,sOut}
end


function isTimeBetween(startTimeHour, startTimeMinute, endTimeHour, endTimeMinute)
    local currentHour, currentMinute = getTime()

    local startTotalMinutes = startTimeHour * 60 + startTimeMinute
    local endTotalMinutes = endTimeHour * 60 + endTimeMinute
    local currentTotalMinutes = currentHour * 60 + currentMinute

    if startTotalMinutes <= endTotalMinutes then
        return currentTotalMinutes >= startTotalMinutes and currentTotalMinutes <= endTotalMinutes
    else
        return currentTotalMinutes >= startTotalMinutes or currentTotalMinutes <= endTotalMinutes
    end
end


setTimer(function()
    local hours = getTime()
	for obj,_ in pairs(timeTable) do
		if streamTimes[getElementModel(obj)] then
			local sIn,sOut = unpack(streamTimes[getElementModel(obj)])
			
			if sIn and sOut then
				if isTimeBetween(sIn,0,sOut,0) then
					if not (streamTimeObj[obj] == 1) then
						streamTimeObj[obj] = 1
						setObjectScale(obj,1)
						if streamingDistances[getElementModel(obj)] then
							engineSetModelLODDistance (getElementModel(obj),300)
						else
							engineResetModelLODDistance(getElementModel(obj))
						end
					end
				else
					if not (streamTimeObj[obj] == 2) then
						streamTimeObj[obj] = 2
						setObjectScale(obj,0)
						engineSetModelLODDistance (getElementModel(obj),0)
					end
				end
			end
		end
	end
end, 1000, 0)


local flagsTableNew = {}

local flagsTable = {
    {1, "IS_ROAD"},
    {2, "-"},
    {4, "DRAW_LAST", 'alphaTransparency'},
    {8, "ADDITIVE", 'alphaTransparency'},
    {16, "-"},
    {32, ""},
    {64, "NO_ZBUFFER_WRITE"},
    {128, "DONT_RECEIVE_SHADOWS"},
    {256, "-"},
    {512, "IS_GLASS_TYPE_1"},
    {1024, "IS_GLASS_TYPE_2"},
    {2048, "IS_GARAGE_DOOR"},
    {4096, "IS_DAMAGABLE", 'breakable'},
    {8192, "IS_TREE"},
    {16384, "IS_PALM"},
    {32768, "DOES_NOT_COLLIDE_WITH_FLYER"},
    {65536, "-"},
    {131072, "-"},
    {262144, "-"},
    {524288, "-"},
    {1048576, "IS_TAG"},
    {2097152, "DISABLE_BACKFACE_CULLING", 'doubleSided'},
    {4194304, "IS_BREAKABLE_STATUE"}
}

for _,data in pairs(flagsTable) do
	flagsTableNew[data[1]] = data[3]
end

function countCommas(str)
    local count = 0
    for i=1,#str do
        if str:sub(i,i) == "," then
            count = count + 1
        end
    end
    return count
end

function flagList(flags)
	if countCommas(flags) > 1 then
		return split(flags,',')
	else
		return {flags}
	end
end
	
function getFlags(attribute,flags)
	local flags = attribute.flags
	
	local list = flagList(flags)
	
	for _,flag in pairs(list) do
		local flag = tonumber(flag)
		if flagsTableNew[flag] then
			attribute[flagsTableNew[flag]] = true
		end
	end
end
