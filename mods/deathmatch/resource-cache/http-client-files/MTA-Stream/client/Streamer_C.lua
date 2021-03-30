debug.sethook(nil)

-- Tables --
cache = {}
resource = {}

function onResourceStart(resourcea)
	triggerServerEvent ( "onResourceLoad", resourceRoot, getResourceName(resourcea))
end
addEventHandler( "onClientResourceStart", getRootElement( ),onResourceStart)


function loadMap ( Proccessed,resourceName )
	startTickCount = getTickCount ()
	resource[resourceName] = {}
	
	local dataToLoad = {}
	for i,v in pairs(Proccessed) do
		table.insert(dataToLoad,v)
	end
	Async:setPriority("high")
	Async:foreach(dataToLoad, function(data)
		
		if tonumber(data[10]) then
			-- load col
			local path = ':'..resourceName..'/Content/coll/'..data[3]..'.col'
			local collision,cache = requestCollision(path,data[3])
			engineReplaceCOL(collision,data[10])
			table.insert(resource[resourceName],cache)
			
			
			-- load txd
			local path = ':'..resourceName..'/Content/textures/'..data[2]..'.txd'
			local texture,cache = requestTextureArchive(path,data[2])
			engineImportTXD(texture,data[10])
			table.insert(resource[resourceName],cache)

			-- load dff
			local path = ':'..resourceName..'/Content/models/'..data[1]..'.dff'
			local model,cache = requestModel(path,data[1])
			engineReplaceModel(model,data[10],data[5])
			if tonumber(data[8]) and tonumber(data[9]) then
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],tonumber(data[9]),tonumber(data[8]))
				end
				addNightElement(data[1],tonumber(data[8]),tonumber(data[9]))
			else
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],0,0)
				end
			end
			engineSetModelLODDistance (data[10],math.max(tonumber(data[4]),270))
			table.insert(resource[resourceName],cache)
		end
	end)

	--[[
	Async:setPriority("medium")
	Async:foreach(dataToLoad, function(data)
		if tonumber(data[10]) then
			local path = ':'..resourceName..'/Content/coll/'..data[3]..'.col'
			local collision,cache = requestCollision(path,data[3])
			engineReplaceCOL(collision,data[10])
			table.insert(resource[resourceName],cache)
		end
	end)
	
	Async:setPriority("medium")
	Async:foreach(dataToLoad, function(data)
		if tonumber(data[10]) then
			local path = ':'..resourceName..'/Content/textures/'..data[2]..'.txd'
			local texture,cache = requestTextureArchive(path,data[2])
			engineImportTXD(texture,data[10])
			table.insert(resource[resourceName],cache)
		end
	end)

	Async:setPriority("medium")
	Async:foreach(dataToLoad, function(data)
		if tonumber(data[10]) then
			local path = ':'..resourceName..'/Content/models/'..data[1]..'.dff'
			local model,cache = requestModel(path,data[1])
			engineReplaceModel(model,data[10],data[5])
			if tonumber(data[8]) and tonumber(data[9]) then
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],tonumber(data[9]),tonumber(data[8]))
				end
				addNightElement(data[1],tonumber(data[8]),tonumber(data[9]))
			else
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],0,0)
				end
			end
			
			engineSetModelLODDistance (data[10],math.max(tonumber(data[4]),270))
			
			table.insert(resource[resourceName],cache)
		end
	end)
	--]]
	vegitationElementReload()
	loadedFunction(resourceName)
end
addEvent( "MTAStream_Client", true )
addEventHandler( "MTAStream_Client", localPlayer, loadMap )

function loadedFunction (resourceName)
	local endTickCount = getTickCount ()-startTickCount
	triggerServerEvent ( "onPlayerLoad", root, tostring(endTickCount),resourceName )
	createTrayNotification( 'You have finished loading : '..resourceName, "info" )
end

function requestTextureArchive(path)
	if path then
		cache[path] = cache[path] or engineLoadTXD(path)
		return cache[path],path
	end
end

function requestCollision(path)
	if path then
		cache[path] = cache[path] or engineLoadCOL(path)
		return cache[path],path
	end
end

function requestModel(path)
	if path then
		cache[path] = cache[path] or engineLoadDFF(path)
		return cache[path],path
	end
end

function restore(model)
	engineRestoreModel ( model )
	engineRestoreCOL( model )
	engineSetModelLODDistance(model, 170)
	if engineSetModelVisibleTime then
		engineSetModelVisibleTime(model,0,0)
	end
end
addEvent( "restoreModel", true )
addEventHandler( "restoreModel", localPlayer, restore )


function forceLoad(data,resourceName)
	if (getResourceState ( getResourceFromName(resourceName) ) == 'running') then
		if tonumber(data[10]) then
			local path,cache = ':'..resourceName..'/'..data[2]..'.txd'
			local texture = requestTextureArchive(path,data[2])
			engineImportTXD(texture,data[10])
			table.insert(resource[resourceName],cache)
			
			local path,cache = ':'..resourceName..'/'..data[3]..'.col'
			local collision = requestCollision(path,data[3])
			engineReplaceCOL(collision,data[10])
			table.insert(resource[resourceName],cache)

			local path,cache = ':'..resourceName..'/'..data[1]..'.dff'
			local model = requestModel(path,data[1])
			engineReplaceModel(model,data[10],data[5])
			if tonumber(data[8]) and tonumber(data[9]) then
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],tonumber(data[9]),tonumber(data[8]))
				end
				addNightElement(data[1],tonumber(data[8]),tonumber(data[9]))
			else
				if engineSetModelVisibleTime then
					engineSetModelVisibleTime(data[10],0,0)
				end
			end
			table.insert(resource[resourceName],cache)
			engineSetModelLODDistance (data[10],math.max(tonumber(data[4]),270))
		end
	end
end
addEvent( "loadModel", true )
addEventHandler( "loadModel", localPlayer, forceLoad )

function onResourceStop(name)
	if resource[name] then
		Async:setPriority("medium")
		Async:foreach(resource[name], function(data)
			if cache[data] then
				destroyElement(cache[data])
				cache[data] = nil
			end
		end)
	end
	resource[name] = nil
end
addEvent( "resourceStop", true )
addEventHandler( "resourceStop", localPlayer, onResourceStop )

function getMaps()
	local tempTable = {}
	for i,v in pairs(resource) do
		table.insert(tempTable,i)
	end
	return tempTable
end
