USE_ORIGINAL_LODS = false
debug.sethook(nil)
-- initial setup --
for i = 550, 20000 do
	removeWorldModel(i,10000,0,0,0)
end
setWaterLevel(-5000)
setOcclusionsEnabled(false)
-- Events --
events = {'onPlayerLoad','onElementBreak','onPlayerFailedLoad','fetchID','prepOriginals'}
for i = 1,#events do
	addEvent( events[i], true )
end

-- Tables --
system = {
	objs = 0,
	lods = 0,
}
data = {
	id={},
	resourceObjects={},
	globalObjects = {},
	resourceData={},
	globalData = {},
	placementData = {},
}
suffixList = {'gta3','mta'}

blacklist = {}
-- ID defines the assigned SA ID, objects are the objects per SID, resource defines objects per resource.

-- Functions --
 
function blackList(model)
	if (type(model) == 'table') then
		for i,v in pairs(model) do
			if getModelFromID(v) then
				local restoreID = getModelFromID(v)
				if idused[restoreID] and (not (idused[restoreID] == restoreID)) then
					local name = idused[restoreID]
					data.id[idused[restoreID]] = nil
					idused[restoreID] = true
					triggerClientEvent ("restoreModel",root,restoreID)
					changeObjectModel(name,getFreeID(name)) -- Changes previous element to a new ID and loads the SA default
				end
				idused[restoreID] = restoreID -- Locks said ID to SA model
			end
		end
	else
		if getModelFromID(model) then
			local restoreID = getModelFromID(model)
			if idused[restoreID] and (not (idused[restoreID] == restoreID)) then
				local name = idused[restoreID]
				data.id[idused[restoreID]] = nil
				idused[restoreID] = true
				triggerClientEvent ("restoreModel",root,restoreID)
				changeObjectModel(name,getFreeID(name)) -- Changes previous element to a new ID and loads the SA default
			end
			idused[restoreID] = restoreID -- Locks said ID to SA model
		end
	end
end
blackList(blacklist)

function loadStreamerMap( resource )																	 -- // On map start, if it has the 'Streamer' or 'cStream' tag load it.
	if getResourceInfo ( resource, 'Streamer') or getResourceInfo ( resource, 'cStream') then
		loadMap(resource)
	end
end 
addEventHandler ( "onResourceStart", root,loadStreamerMap)

function toBoolean(input)
	return (string.count(input,'tru') > 0)
end

function fetchPlacement(dictonary,sufix)																		 -- // Allows backwards compatability
	if fileExists(':'..dictonary..'/'..sufix..'.CSP') then
		return fileOpen(':'..dictonary..'/'..sufix..'.CSP')
	elseif fileExists(':'..dictonary..'/'..sufix..'.JSP') then
		return fileOpen(':'..dictonary..'/'..sufix..'.JSP')
	elseif fileExists(':'..dictonary..'/'..sufix..'.MSP') then
		return fileOpen(':'..dictonary..'/'..sufix..'.MSP')
	else
		return false
	end
end

function fetchDefintion(dictonary,sufix)																		 -- // Allows backwards compatability
	if fileExists(':'..dictonary..'/'..sufix..'.CSD') then
		return fileOpen(':'..dictonary..'/'..sufix..'.CSD')
	elseif fileExists(':'..dictonary..'/'..sufix..'.JSD') then
		return fileOpen(':'..dictonary..'/'..sufix..'.JSD')
	elseif fileExists(':'..dictonary..'/'..sufix..'.MSD') then
		return fileOpen(':'..dictonary..'/'..sufix..'.MSD')
	else
		return false
	end
end


function loadMap (resource)																				 -- // Load the map
	local tickCount = getTickCount()
	local resourceName = getResourceName(resource)
	data.resourceObjects[resourceName] = {}
	data.resourceData[resourceName] = {}
	
	for _,suffix in pairs(suffixList) do
		local File = fetchPlacement(resourceName,suffix)
		
		if File then
			local Data = fileRead(File, fileGetSize(File))
			local ProccessedA = split(Data,10)
			fileClose (File)
			
			for i,vA in pairs(ProccessedA) do
				if not (i == 1) then
					local SplitB = split(vA,",")
					if not (SplitB[1] == '!') then -- If the first character is equal to # then ignore, used for debugging.
						local model = (SplitB[1])
						if model then
							if getModelFromID(model) then
								blackList(model)
							end
						end
					end
				end
			end
			
			
			local File = fetchDefintion(resourceName,suffix)
			
			local Data =  fileRead(File, fileGetSize(File))
			local Proccessed = split(Data,10)
			fileClose (File)

			iA = 0
			
			Async:setPriority("medium")

			Async:foreach(Proccessed, function(vA)
				iA = iA + 1
				local SplitA = split(vA,",")
				if (type(SplitA) == 'table') then
					if not (SplitA[1] == '!') then -- If the first character is equal to # then ignore, used for debugging.
						for i=1,8 do
							if not SplitA[i] then
								print(SplitA[1],'| Object definition load error','| Row '..i)					-- // If there is any missing information inform the server, added 'Row' information for better debugging.
								return
							end
						end
						defineDefintion(SplitA,resourceName) -- ## 
					end
				end
			end)
			
		

			XA,YA,ZA = 0,0,0
			iA = 0
			Async:setPriority("medium")
			Async:foreach(ProccessedA, function(vA)
				iA = iA + 1
				if (iA == 1) then
					local x,y,z = split(vA,",")[1],split(vA,",")[2],split(vA,",")[3]
					XA,YA,ZA = tonumber(x),tonumber(y),tonumber(z)
				else
					local SplitB = split(vA,",")
					if not (SplitB[1] == '!') then -- If the first character is equal to # then ignore, used for debugging.
						for i=1,9 do
							if not SplitB[i] then
								print(SplitB[1],'| Object placement load error','| Row '..i)					-- // If there is any missing information inform the server, added 'Row' information for better debugging.
								return
							end
						end
				
						local object = streamObject(SplitB[1],tonumber(SplitB[4])+XA,tonumber(SplitB[5])+YA,tonumber(SplitB[6])+ZA,tonumber(SplitB[7]),tonumber(SplitB[8]),tonumber(SplitB[9]),resourceName,tonumber(SplitB[3]),tonumber(SplitB[2]))  -- ## 
						if object then
							setElementInterior(object,tonumber(SplitB[2]))
							setElementDimension(object,tonumber(SplitB[3]))
						end
	
					end
				end
			end)

		end
	end
	
	local endTick = getTickCount()
	print(resourceName,'Loaded In : '..tonumber(endTick-tickCount),'Milisecounds')
	print(string.format("TOTAL OBJS: %d, LODS: %d",system.objs,system.lods))
end

function defineDefintion(dTable,resourceName) -- Define defintion stuff
	local ID,model,texture,collision,draw,flag,backface,lod,turnOn,turnOff = unpack(dTable)
	--data.resourceData[resourceName][ID] = {model,texture,collision,draw,flag,toBoolean(backface),lod,turnOn,turnOff,getFreeID(ID),resourceName} -- # If SA model exists using same ID then this will be re proccessed!
	data.resourceData[resourceName][ID] = {
		id = getFreeID(ID),
		model = model,
		texture = texture,
		collision = collision,
		draw = tonumber(draw),
		flag = flag,
		cull = toBoolean(backface),
		lod = lod == "nil" and false or lod,
		turnOn = tonumber(turnOn),
		turnOff = tonumber(turnOff),
		resourceName = resourceName,
	}
	data.globalData[ID] = data.resourceData[resourceName][ID]
	
end


function getData(name)
	if data.globalData[name] then
		return data.globalData[name]
	else
		return false
	end
end
function setElementFlag(element,flag)

	local flagTable = {
		["2097152"] = function() -- disable backface culling
			setElementDoubleSided(element,true)
		end,
		["128"] = function() -- breakable
			print("Breakable")
			--setObjectBreakable(element,true)
		end,
		["2097228"] = function() -- alpha on

		end,
	}
	if flagTable[flag] then flagTable[flag]() end
end

function streamObject(model,x,y,z,xr,yr,zr,resource,dim,int)
	--[[
	if getModelFromID(model) then
		blackList(model)
	end
	]]
	local modelInfo = getData(model)
	if not modelInfo then 
		print(model.." not found")
		return
	end
	local cull,lod,id,drawdist,flag = modelInfo.cull,modelInfo.lod,modelInfo.id,modelInfo.draw ,modelInfo.flag

	if flag == "SA_PROP" then -- deal with sa object
		id = getModelFromID(model)
	end
	
	if tonumber(id) then
		local object = createObject(id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0)
	
		setElementID(object,model)	
		setElementData(object,'id',model)
		if cull then
			setElementDoubleSided(object,true)
		end
		
		if flag and tonumber(flag) ~= 0 then 
			setElementFlag(object,flag)
		end
		-- deal with lods
		if lod or drawdist and tonumber(drawdist) > 999 then
			if flag ~= "SA_PROP" then -- we don't want mess with sa models
				local lowLOD
				if USE_ORIGINAL_LODS then
					lowLOD = createObject (getFreeID(lod),x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0,true)
					setLowLODElement (object,lowLOD)
					setElementID(lowLOD,lod)	
					setElementData(lowLOD,'id',lod)
				else
					lowLOD = createObject (id,x or 0,y or 0,z or 0,xr or 0,yr or 0,zr or 0,true)
					setElementID(lowLOD,model)	
					setElementData(lowLOD,'id',model)
				end
				--setElementCollisionsEnabled(lowLOD,false)

				setElementInterior(lowLOD,int >= 0 and int or 0)
				setElementDimension(lowLOD,dim or -1)
				if flag then 
					setElementFlag(lowLOD,flag)
				end
				if cull then 
					setElementDoubleSided(lowLOD,true)
				end
				if resource then
					table.insert(data.resourceObjects[resource],lowLOD)
					data.globalData[model].object_lod = lowLOD
				end
				system.lods = system.lods + 1
			end
		end
		
		if resource then
			table.insert(data.resourceObjects[resource],object)
			data.globalData[model].object = object
		end
		system.objs = system.objs + 1

		return object
	end
end

function changeObjectModel(name,newModel)
	if data.globalData[name] then
		print(name,'Revoked')
		data.globalData[name].id = newModel
		local resName = data.globalData[name].resourceName
		data.resourceData[resName][name].id = newModel
		
		
		for i,v in pairs(getElementsByType('object')) do
			if (getElementData(v,'id') == name) then
				setElementModel(v,newModel)
			end
		end
		triggerClientEvent ("loadModel",root,data.globalData[name],resName)
	end
end

function onResourceLoad ( resource )
	local resource = getResourceFromName(resource)
	if getResourceInfo ( resource, 'Streamer') or getResourceInfo ( resource, 'cStream') then
		local name = getResourceName(resource)
		triggerClientEvent("Client_loadModel",client,data.resourceData[name],name )
	end
end
addEvent( "onResourceLoad", true )
addEventHandler( "onResourceLoad", resourceRoot, onResourceLoad )

function playerLoaded ( loadTime,resource )
	print(getPlayerName(client),'Loaded '..resource..' In : '..(tonumber(loadTime)*0.01),'Secounds')
end
addEventHandler( "onPlayerLoad", resourceRoot, playerLoaded )



function onResourceLoading(resouce)
	print(resouce)
end
addEvent( "onResourceLoading", true )
addEventHandler( "onResourceLoading", resourceRoot, onResourceLoading )

function onElementDestroy()
	if getElementType(source) == "object" then
		if getLowLODElement(source) then
			destroyElement(getLowLODElement(source))
		end
	end
end
addEventHandler("onElementDestroy",resourceRoot,onElementDestroy)


function onResourceStop(resource)
	if getResourceInfo ( resource, 'Streamer') or getResourceInfo ( resource, 'cStream') then
		local name = getResourceName(resource)
		triggerClientEvent ( root, "resourceStop",name)
		if data.resourceObjects[name] then
			for i,v in pairs(data.resourceObjects[name]) do
				if isElement(v) then
					destroyElement(v)
				end
			end
		end
		if data.resourceData[name] then
			for i,v in pairs(data.resourceData[name]) do
				data.id[v[10]] = nil
				idused[v[10]] = nil
			end
		end
		data.resourceData[name] = nil
		data.resourceObjects[name] = nil
	end
end
addEventHandler( "onResourceStop", root,onResourceStop)

function getMaps()
	local tempTable = {}
	for i,v in pairs(data.resourceObjects) do
		table.insert(tempTable,i)
	end
	return tempTable
end

function getMapElements(map)
	return data.resourceObjects[map]
end

