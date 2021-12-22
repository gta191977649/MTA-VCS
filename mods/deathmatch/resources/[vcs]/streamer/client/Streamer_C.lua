DEBUG = exports.DEBUG

debug.sethook(nil)

-- Tables --
cache = {}
resource = {}
model_cache = {}
function onResourceStart(resourcea)
	triggerServerEvent ( "onResourceLoad", root, getResourceName(resourcea))
end
addEventHandler( "onClientResourceStart", root,onResourceStart)

--[[
function loadModel ( Proccessed,resourceName )
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
-]]

function loadModel(data,resourceName) 
	if data and data.flag ~= "SA_PROP" then
		print(string.format("request: %s",data.model))
		local id = data.id
		-- load col
		local path = ':'..resourceName..'/Content/coll/'..data.collision..'.col'
		local collision,cache = requestCollision(path,data.collision)
		engineReplaceCOL(collision,id)
		table.insert(resource[resourceName],cache)

		-- load txd
		local path = ':'..resourceName..'/Content/textures/'..data.texture..'.txd'
		local texture,cache = requestTextureArchive(path,data.texture)
		engineImportTXD(texture,id)
		table.insert(resource[resourceName],cache)

		-- load dff
		local path = ':'..resourceName..'/Content/models/'..data.model..'.dff'
		local model,cache = requestModel(path,data.model)
		engineReplaceModel(model,id,isTransparentFlag(data.flag))
		table.insert(resource[resourceName],cache)

		if data.turnOn and tonumber(data.turnOn) and data.turnOff and tonumber(data.turnOff) then
			engineSetModelVisibleTime(id,data.turnOn,data.turnOff)
			addNightElement(data.model,tonumber(data.turnOn),tonumber(data.turnOff))
		end
		-- deal with common flags properties, e.g. breakable
		--setElementFlagProperty(data.object,data.flag)
		-- clamp
		--local drawdist = tonumber(data.draw) > 300 and 300 or tonumber(data.draw)
		local drawdist = tonumber(data.draw)
		engineSetModelLODDistance(id,math.max(drawdist,150))

		model_cache[data.model] = id
		return id
	end
end

function loadObject(data) 
	local cull,lod,id,drawdist,flag = data.info.cull,data.info.lod,data.info.id,data.info.draw,data.info.flag
	local x,y,z = unpack(data.pos)
	local xr,yr,zr = unpack(data.rot)
	local int, dim = tonumber(data.int), tonumber(data.dim)
	local object = createObject(id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0)
	local model = data.model
	setElementID(object,model)	
	setElementData(object,'id',model)
	if cull then
		setElementDoubleSided(object,true)
	end
	
	if flag and tonumber(flag) ~= 0 then 
		setElementFlagProperty(object,data.flag)
	end
	-- deal with lods
	if lod or tonumber(data.info.draw) > 900 then
		if flag ~= "SA_PROP" then -- we don't want mess with sa models
			local lowLOD = createObject (id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0,true)
			setLowLODElement(lowLOD, false)
			setLowLODElement (object,lowLOD)
			setElementID(lowLOD,model)	
			setElementData(lowLOD,'id',model)
			setElementCollisionsEnabled(lowLOD,false)

			if cull then 
				setElementDoubleSided(lowLOD,true)
			end

			setElementInterior(lowLOD,int >= 0 and int or 0)
			setElementDimension(lowLOD,dim or -1)
		end
	else
		setLowLODElement(object,false)
	end
	return object

end
function loadMap(ipls,ides,mapname) 
	startTickCount = getTickCount ()
	resource[mapname] = {}
	loaded = 0
	setOcclusionsEnabled(false)
	setGameSpeed(0)
	setElementPosition(localPlayer,3000,3000,10)

	-- create object
	for i,data in ipairs(ipls) do 
		loadObject(data) 
	end


	local dataToLoad = {}
	for i,v in pairs(ides) do
		table.insert(dataToLoad,v)
	end

	ides = {}

	Async:setPriority(100, 1000);
	Async:foreach(dataToLoad, function(data) 
		-- load model
		if model_cache[data.model] == nil and data.flag ~= "SA_PROP"then
			loadModel(data,mapname)
		else
			DEBUG:addDebugMessage(string.format("Exist: %s has already loaded or is a SA Prop, skipping...\n",data.model))
		end

		loaded = loaded + 1
		local debugMsg = string.format("Request: %s | %d OF %d remain.\n",data.model,loaded,#dataToLoad)
		print(debugMsg)
		DEBUG:addDebugMessage(debugMsg)

		if loaded >= #dataToLoad then 
			vegitationElementReload()
			engineStreamingFreeUpMemory(104857600)
			engineRestreamWorld()
			outputChatBox ("Used memory by the GTA streamer: "..engineStreamingGetUsedMemory ()..".")
			setElementPosition(localPlayer,-1389.450195,-882.062622,20.855408)
			setGameSpeed(1)
			loadedFunction(mapname)
		end
	end)

end
addEvent( "MTAStream_Client", true )
addEventHandler( "MTAStream_Client", localPlayer, loadMap )


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
