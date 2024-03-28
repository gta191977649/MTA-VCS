

function getLines(file)
	local fData = fileRead(file, fileGetSize(file))
	local fProccessed = split(fData,10) -- Split the lines
	fileClose (file)
	return fProccessed
end

function onResourceStart(resourceThatStarted)
	local resourceName = getResourceName(resourceThatStarted)
	local path = ((":%s/%s"):format(resourceName,'eagleZones.txt'))
	local exists = fileExists(path) --// We want to check if the resource has an eagleZones file, this is so we don't have to go through server side which may cause issues.
	local definitionList = {}
	
	if exists then
		local zones = getLines(fileOpen(path))
		for _,zone in pairs(zones) do
			local list = loadZone(resourceName,zone)
			for i,v in pairs(list) do
				table.insert(definitionList,v)
			end
		end
	end
	

	local last = definitionList[#definitionList]
	if last then
		local lastID = last.id
		loadMapDefinitions(resourceName,definitionList,lastID)
	end
end



addEventHandler( "onClientResourceStart", root, onResourceStart)

function loadZone(resourceName,zone)
	local path = ':'..resourceName..'/zones/'..zone..'/'..zone..'.definition'
	local zoneDefinitions = xmlLoadFile(path)
	print(path)
	local sDefintions = xmlNodeGetChildren(zoneDefinitions)
	local newTable = {}
	
	for _,definiton in pairs (sDefintions) do
		local attributes = xmlNodeGetAttributes(definiton)
		table.insert(newTable,attributes)
	end
	
	xmlUnloadFile(zoneDefinitions)
	return newTable
end

