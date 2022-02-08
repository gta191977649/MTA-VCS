DEBUG = exports.DEBUG
--FX = exports["2dfx"]
-- Tables --
cache = {}
resource = {}
mapdata = {}
model_cache = {}
function onResourceStart(resourcea)
	setOcclusionsEnabled(false)
	triggerServerEvent ( "onResourceLoad", root, getResourceName(resourcea))
end
addEventHandler( "onClientResourceStart", root,onResourceStart)


function loadModel(data,resourceName) 
	if data and data.flag ~= "SA_PROP" then
		print(string.format("request: %s",data.model))
		local id = data.id
		if USE_REQUEST_MODEL == true then
			id = engineRequestModel("object")
			mapdata[resourceName].mapping[data.id] = id
		end

		
		-- load col
		local path = ':'..resourceName..'/Content/coll/'..data.collision..'.col'
		local collision,cache = requestCollision(path,data.collision)
		engineReplaceCOL(collision,id)
		table.insert(resource[resourceName],cache)

		-- load txd
		path = ':'..resourceName..'/Content/textures/'..data.texture..'.txd'
		local texture,cache = requestTextureArchive(path,data.texture)
		engineImportTXD(texture,id)
		table.insert(resource[resourceName],cache)

		-- load dff
		path = ':'..resourceName..'/Content/models/'..data.model..'.dff'
		local model,cache = requestModel(path,data.model)
		engineReplaceModel(model,id,isTransparentFlag(data.flag))
		table.insert(resource[resourceName],cache)


		-- deal with common flags properties, e.g. breakable
		--setElementFlagProperty(data.object,data.flag)
		-- clamp
		--[[
		// fLodDistanceUnscaled values:
		//
		// With the draw distance setting in GTA SP options menu set to maximum:
		//      0 - 170     roughly correlates to a LOD distance of 0 - 300 game units
		//      170 - 480   sets the LOD distance to 300 game units and has a negative effect on the alpha fade-in
		//      490 - 1e7   sets the LOD distance to 300 game units and removes the alpha fade-in completely
		//
		// With the draw distance setting in GTA SP options menu set to minimum:
		//      0 - 325     roughly correlates to a LOD distance of 0 - 300 game units
		//      340 - 960   sets the LOD distance to 300 game units and has a negative effect on the alpha fade-in
		//      1000 - 1e7  sets the LOD distance to 300 game units and removes the alpha fade-in completely
		//
		// So, to ensure the maximum draw distance with a working alpha fade-in, fLodDistanceUnscaled has to be
		// no more than: 325 - (325-170) * draw_distance_setting -> 170 * draw_distance_setting
		//
		--]]
		local drawdist = MAX_DRAW_DIST and 1000 or tonumber(data.draw)
		if drawdist >= 1000 then -- should be lods
			drawdist = drawdist > 325 and 325 or drawdist
		else -- if is normal obj
			drawdist = drawdist > 170 and 170 or drawdist -- from MTA Source
		end
		engineSetModelLODDistance(id,drawdist)
		model_cache[data.model] = id
		return id
	end
end
function getLODInfo(map,lodname,x,y) 
	for i,v in ipairs(mapdata[map].ipls) do 
		-- shit approach better to consider alternative
		if v.model == lodname and  getDistanceBetweenPoints2D(x,y,v.pos[1],v.pos[2]) < 10 then 
			return v
		end
	end
	return false 
end

function loadObject(data,mapname) 
	if data.flag == "LOD" then return end -- we skip lod, it will created later manually
	local cull,lod,id,drawdist,flag = data.info.cull,data.info.lod,data.info.id,data.info.draw,data.info.flag
	local x,y,z = unpack(data.pos)
	local xr,yr,zr = unpack(data.rot)
	local int, dim = tonumber(data.int), tonumber(data.dim)
	local model = data.model

	-- when use request model method
	if USE_REQUEST_MODEL then 
		id = mapdata[mapname].mapping[id]
	end

	-- create objects
	local object = createObject(id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0)
	setElementID(object,model)	
	setElementData(object,'id',model)
	setElementInterior(object,int >= 0 and int or 0)
	setElementDimension(object,dim or -1)
	setElementDoubleSided(object,true)
	setElementParent(object,mapdata[mapname].map)
	if flag ~= "SA_PROP" then 
		setElementFrozen(object,true)
		setObjectBreakable(object,false)
	end
	-- deal with night obj
	if flag ~= "SA_PROP" and data.info.turnOn ~= nil then
		engineSetModelVisibleTime(id,data.info.turnOn,data.info.turnOff)
		addNightElement(data.model,object,tonumber(data.info.turnOn),tonumber(data.info.turnOff))
	end


	-- deal with lods
	if lod or tonumber(data.info.draw) >= 1000 or FORCE_LODS then
		if flag ~= "SA_PROP" then
			local lodinfo = getLODInfo(mapname,lod,x,y,z) 
			if USE_LODS then -- do it when it enabled
				if lodinfo then
					-- get lod info
					x,y,z = unpack(lodinfo.pos)
					xr,yr,zr = unpack(lodinfo.rot)
					id = lodinfo.id
					model = lodinfo.model
				else
					local debugMsg = string.format("LOD ERROR: Requested: %s Not Found! Will Use itself as Lod.\n",model)
					DEBUG:addDebugMessage(debugMsg)
				end
			end
			-- create lod
			local lowLOD = createObject (id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0,true)
			setElementID(lowLOD,model)	
			setElementData(lowLOD,'id',model)
			setElementCollisionsEnabled(lowLOD,false)
			setObjectBreakable(lowLOD,false)
			setElementFrozen(lowLOD,true)
			setLowLODElement (object,lowLOD)
			setElementDoubleSided(lowLOD,true)
			setElementInterior(lowLOD,int >= 0 and int or 0)
			setElementDimension(lowLOD,dim or -1)
			setElementParent(lowLOD,object)
		else
			local debugMsg = string.format("LOD ERROR: Requested: %s Parent Model is SA_PROP, Skipped.\n",model)
			DEBUG:addDebugMessage(debugMsg)
		end
	end
end
function loadMap(ipls,ides,mapname) 
	startTickCount = getTickCount ()
	resource[mapname] = {}
	mapdata[mapname] = {}
	loaded = 0
	setGameSpeed(0)
	--setElementPosition(localPlayer,3000,3000,10)

	mapdata[mapname] = {
		ipls = ipls,
		ides = ides,
		mapping = {},
		map = createElement(string.format("map_%s",mapname)),
	}


	local total = 0
	for _,v in pairs(ides) do
		total = total + 1
	end


	--Async:setPriority(100, 1000);
	Async:setPriority("normal");
	Async:forkey(ides, function(key,data) 
		-- load model
		if model_cache[data.model] == nil and data.flag ~= "SA_PROP" then
			loadModel(data,mapname)
		else
			DEBUG:addDebugMessage(string.format("Exist: %s has already loaded or is a SA Prop, skipping...\n",data.model))
		end

		loaded = loaded + 1
		if loaded >= total then 
			-- object should always created after engine function is done.
			for _,data in ipairs(ipls) do 
				loadObject(data,mapname) 
			end

			vegitationElementReload()
			setWaterDrawnLast(true)
			outputChatBox (string.format("[Streamer]: Map %s loaded, memory: %d",mapname,engineStreamingGetUsedMemory ()))
			loadedFunction(mapname)
		end
	end)

end
addEvent( "MTAStream_ClientLoad", true )
addEventHandler( "MTAStream_ClientLoad", localPlayer, loadMap )


function loadedFunction (resourceName)
	local endTickCount = getTickCount ()-startTickCount
	triggerServerEvent ( "onPlayerLoad", root, tostring(endTickCount),resourceName )
	createTrayNotification( 'You have finished loading : '..resourceName, "info" )
	cache = {}
	--FX:init()
	engineStreamingFreeUpMemory (104857600)
	engineRestreamWorld ()

	setElementPosition(localPlayer,-1389.450195,-882.062622,20.855408)
	setGameSpeed(1)
end

function setClientMapDimension(map,dim) 
	if mapdata[map] then 
		local elements = getElementChildren(mapdata[map].map) 
		for k,v in ipairs(elements) do
			setElementDimension(v,dim)
		end
	else
		outputChatBox("Map "..map.." is not rendered or exists in client.")
	end
end
addEvent( "MTAStream_ClientSetDim", true )
addEventHandler( "MTAStream_ClientSetDim", localPlayer, setClientMapDimension )


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

function restoreAllModel()
	for i = 550, 20000 do
		engineRestoreModel ( i )
		engineRestoreCOL( i )
		engineResetModelLODDistance(i)
		engineSetModelVisibleTime(i,0,0)
	end
end
addEvent( "restoreAllModel", true )
addEventHandler( "restoreAllModel", localPlayer, restoreAllModel )


function getMaps()
	local tempTable = {}
	for i,v in pairs(resource) do
		table.insert(tempTable,i)
	end
	return tempTable
end

function unloadAllMap() 
	for name,v in pairs(mapdata) do 
		-- free all model ids
		for idx,id in pairs(v.mapping) do
			engineFreeModel(id)
			print(id.." is free")
		end
		destroyElement(v.map)

		mapdata[name] = {}
	end

	--restoreAllModel()
	outputChatBox("[Streamer]: Map has been unloaded")
end
addEvent( "MTAStream_ClientUnLoadAll", true )
addEventHandler( "MTAStream_ClientUnLoadAll", localPlayer, unloadAllMap )