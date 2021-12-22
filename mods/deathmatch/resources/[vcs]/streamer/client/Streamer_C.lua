DEBUG = exports.DEBUG

debug.sethook(nil)

-- Tables --
cache = {}
resource = {}

function onResourceStart(resourcea)
	triggerServerEvent ( "onResourceLoad", resourceRoot, getResourceName(resourcea))
end
addEventHandler( "onClientResourceStart", getRootElement( ),onResourceStart)


function loadMap ( Proccessed,resourceName )
	setGameSpeed(0)
	setElementPosition(localPlayer,3000,3000,10)
	
	startTickCount = getTickCount ()
	resource[resourceName] = {}
	
	local dataToLoad = {}
	for i,v in pairs(Proccessed) do
		table.insert(dataToLoad,v)
	end
	local loaded = 0
	Async:setPriority("high")
	Async:foreach(dataToLoad, function(data)
		--iprint(data)
		if data ~= nil then
			if data.flag ~= "SA_PROP" then
				
				print(string.format("request: %s",data.model))
				
				-- load txd
				local path = ':'..resourceName..'/Content/textures/'..data.texture..'.txd'
				local texture,cache = requestTextureArchive(path,data.texture)
				engineImportTXD(texture,data.id)
				table.insert(resource[resourceName],cache)
	
				-- load dff
				local path = ':'..resourceName..'/Content/models/'..data.model..'.dff'
				local model,cache = requestModel(path,data.model)
				engineReplaceModel(model,data.id,isTransparentFlag(data.flag))
				table.insert(resource[resourceName],cache)

				-- load col
				local path = ':'..resourceName..'/Content/coll/'..data.collision..'.col'
				local collision,cache = requestCollision(path,data.collision)
				engineReplaceCOL(collision,data.id)
				table.insert(resource[resourceName],cache)

				if tonumber(data.turnOn) and tonumber(data.turnOff) then
					engineSetModelVisibleTime(data.id,data.turnOn,data.turnOff)
					addNightElement(data.model,tonumber(data.turnOn),tonumber(data.turnOff))
				end
				-- deal with common flags properties, e.g. breakable
				--setElementFlagProperty(data.object,data.flag)
				engineSetModelLODDistance(data.id,data.draw)
			end
			
		end

		loaded = loaded + 1
		DEBUG:addDebugMessage(string.format("%d OF %d remain.\n",loaded,#dataToLoad))
		if loaded >= #dataToLoad then 
			engineRestreamWorld()
			vegitationElementReload()
			loadedFunction(resourceName)
			outputChatBox ("Used memory by the GTA streamer: "..engineStreamingGetUsedMemory ()..".")
			setElementPosition(localPlayer,-1389.450195,-882.062622,20.855408)
			setGameSpeed(1)
		end
	end)
end
addEvent( "Client_loadModel", true )
addEventHandler( "Client_loadModel", localPlayer, loadMap )

function loadedFunction (resourceName)
	local endTickCount = getTickCount ()-startTickCount
	triggerServerEvent ( "onPlayerLoad", root, tostring(endTickCount),resourceName )
	createTrayNotification( 'You have finished loading : '..resourceName, "info" )

	cache = {} -- clearn the cache
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
