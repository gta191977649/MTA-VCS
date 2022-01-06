DEBUG = exports.DEBUG
FX = exports["2dfx"]
debug.sethook(nil)
-- Config -- 
USE_LODS = true -- if disabled, we will use the model itself as lod.
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

		if data.turnOn and tonumber(data.turnOn) and data.turnOff and tonumber(data.turnOff) then
			engineSetModelVisibleTime(id,data.turnOn,data.turnOff)
			addNightElement(data.model,tonumber(data.turnOn),tonumber(data.turnOff))
		end
		-- deal with common flags properties, e.g. breakable
		--setElementFlagProperty(data.object,data.flag)
		-- clamp
		--local drawdist = tonumber(data.draw) > 300 and 300 or tonumber(data.draw)
		local drawdist = tonumber(data.draw)
		engineSetModelLODDistance(id,drawdist)

		model_cache[data.model] = id
		return id
	end
end
function getLODInfo(lodname) 
	for i,v in ipairs(mapdata.ipls) do 
		if v.model == lodname then 
			return v
		end
	end
	return false 
end
function loadObject(data) 
	if data.flag == "LOD" then return end -- we skip lod, it will created later manually
	local cull,lod,id,drawdist,flag = data.info.cull,data.info.lod,data.info.id,data.info.draw,data.info.flag
	local x,y,z = unpack(data.pos)
	local xr,yr,zr = unpack(data.rot)
	local int, dim = tonumber(data.int), tonumber(data.dim)
	local object = createObject(id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0)
	local model = data.model
	setElementID(object,model)	
	setElementData(object,'id',model)
	setElementInterior(object,int >= 0 and int or 0)
	setElementDimension(object,dim or -1)
	if cull then
		setElementDoubleSided(object,true)
	end
	if flag ~= "SA_PROP" then 
		setElementFrozen(object,true)
	end

	--[[
	if flag and tonumber(flag) ~= 0 then 
		setElementFlagProperty(object,data.flag)
	end
	]]
	-- deal with lods
	if lod or tonumber(data.info.draw) >= 1000 then
		if flag ~= "SA_PROP" then
			local lodinfo = getLODInfo(lod) 
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
			--setElementCollisionsEnabled(lowLOD,false)
			setElementFrozen(lowLOD,true)
			setLowLODElement (object,lowLOD)
			if cull then 
				setElementDoubleSided(lowLOD,true)
			end
			setElementInterior(lowLOD,int >= 0 and int or 0)
			setElementDimension(lowLOD,dim or -1)
		else
			local debugMsg = string.format("LOD ERROR: Requested: %s Parent Model is SA_PROP, Skipped.\n",model)
			DEBUG:addDebugMessage(debugMsg)
		end
	end
end
function loadMap(ipls,ides,mapname) 
	startTickCount = getTickCount ()
	resource[mapname] = {}
	loaded = 0
	setGameSpeed(0)
	setElementPosition(localPlayer,3000,3000,10)

	mapdata = {
		ipls = ipls,
		ides = ides,
	}
	-- create object
	for _,data in ipairs(ipls) do 
		loadObject(data) 
	end

	local total = 0
	for _,v in pairs(ides) do
		total = total + 1
	end


	Async:setPriority(100, 1000);
	Async:forkey(ides, function(key,data) 
		-- load model
		if model_cache[data.model] == nil and data.flag ~= "SA_PROP"then
			loadModel(data,mapname)
		else
			DEBUG:addDebugMessage(string.format("Exist: %s has already loaded or is a SA Prop, skipping...\n",data.model))
		end

		loaded = loaded + 1
		if loaded >= total then 
			vegitationElementReload()
			outputChatBox ("Used memory by the GTA streamer: "..engineStreamingGetUsedMemory ()..".")
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
	mapdata = {}
	resource = {}
	cache = {}
	FX:init()
	engineStreamingFreeUpMemory (104857600)
	engineRestreamWorld ()

	setElementPosition(localPlayer,-1389.450195,-882.062622,20.855408)
	setGameSpeed(1)
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
