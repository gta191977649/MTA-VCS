-- Tables --
off = {}
nightElements = {}
switchTimes = {}

-- Functions --
function addNightElement(name,ona,offa)
	nightElements[name] = nightElements[name] or {}
	switchTimes[name] = {on=ona,off=offa}
	for i,v in pairs(getElementsByType('object')) do
		if getElementData(v,'id') == name then
			table.insert(nightElements[name],v)
		end
	end
end

function isWithinTimeRange(start,stop)
	hour = getTime()

	if start > stop then
		return (hour < start and hour > stop)
	else
		return (not (hour < stop and hour > start))
	end
end

function fadeNightElements()
	for i,v in pairs(nightElements) do
		if tonumber(switchTimes[i].on) then
			if isWithinTimeRange(tonumber(switchTimes[i].on),tonumber(switchTimes[i].off)) then
				if not (off[i] == 1) then
					off[i] = 1
					for ia,va in pairs(v) do
						if isElement(va) then
							setObjectScale(va,0)
						end
					end
				end
			else
				if not (off[i] == 2) then
					off[i] = 2
					for ia,va in pairs(v) do
						if isElement(va) then
							setObjectScale(va,1)
						end
					end
				end
			end
		end
	end
end
setTimer(fadeNightElements,1000,0)



