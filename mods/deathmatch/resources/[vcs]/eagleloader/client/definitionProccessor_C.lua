
-- Tables --
resource		    = {}
resourceModels 	 	= {}

streamingDistances  = {}

validID 			= {}
streamEverything    = true

timeTableID         = {}
timeTable           = {}

definitionZones     = {}
idObjectProperties  = {}
lodAttach 			= {}
lodAttach['tram']   = true

failed              = {}

function loadMapDefinitions ( resourceName,mapDefinitions,last)

	if globalCache[resourceName] then
		releaseCatche(resourceName)
	end
	
	globalCache[resourceName] = {}
	resourceModels[resourceName] = {}
	startTickCount = getTickCount ()
	resource[resourceName] = {}
	

	for i,v in pairs(getElementsByType('object')) do -- // Loop through all of the objects and mark which IDs exist
		local id = getElementID(v)
		
		local lodID = getElementData(v,'lodID')
		validID[lodID] = true
		validID[id] = true
	end
	

	Async:setPriority("medium")
	Async:foreach(mapDefinitions, function(data)

		if not (data.default == 'true') then
			--iprint(data)
			local modelID,new = requestModelID(data.id,true)

			if modelID then
				
				
				if new then
					resourceModels[resourceName][modelID] = true
				end
					
				if streamEverything or validID[data.id] then

					local zone = data.zone
					
					definitionZones[modelID] = zone
					
					engineSetModelLODDistance (modelID,(tonumber(data.lodDistance or 200)))
					streamingDistances[modelID] = (tonumber(data.lodDistance or 200))

					local LOD = data.lod
					local LODID = data.lodID
						
					if LOD then
						if (LOD == 'true') then
							useLODs[data.id] = (data.lodID or data.id)
						end
					end
					
					if data.flags then
						getFlags(data)
					end
					
					idObjectProperties[data.id] = {}
					
					idObjectProperties[data.id]['doubleSided'] = data.doubleSided
					idObjectProperties[data.id]['breakable'] = data.breakable
					
					-- // Textures
					
					local textureString = data.txd

					local TXDPath = ':'..resourceName..'/zones/'..zone..'/txd/'..textureString..'.txd'

					local texture,textureCache = requestTextureArchive(TXDPath,resourceName)

					if texture then
						if engineImportTXD(texture,modelID) then
							--table.insert(resource[resourceName],textureCache)
						else
							print('Texture : '..textureString..' could not be loaded!')
						end
					else
						print('Texture : '..textureString..' could not be loaded!')
					end
					
					-- // Collisions
					
					local collisionString = data.col

					local COLPath = ':'..resourceName..'/zones/'..zone..'/col/'..collisionString..'.col'

					local collision,collisionCache = requestCollision(COLPath,resourceName)

					if collision then
						if not engineReplaceCOL(collision,modelID) then
							print('Collision : '..collisionString..' could not be loaded!')
						end
					else
						print('Collision : '..collisionString..' could not be loaded!')
					end
					
					-- // Models
					
					local modelString = data.dff or data.id
					
					local DFFPath = ':'..resourceName..'/zones/'..zone..'/dff/'..modelString..'.dff'
					local model,modelCache = requestModel(DFFPath,resourceName)
						
					if model then
						if (data.alphaTransparency == 'true') or (data.alphaTransparency == true) then
							if not engineReplaceModel(model,modelID,true) then
								print('Model : '..modelString..' could not be loaded!')
								failed[data.id] = true
							end
						else
							if not engineReplaceModel(model,modelID) then
								print('Model : '..modelString..' could not be loaded!')
								failed[data.id] = true
							end
						end
					else
						print('Model : '..modelString..' could not be loaded!')
						failed[data.id] = true
					end
					
					if tonumber(data.timeIn) and tonumber(data.timeOut) then
						setModelStreamTime (modelID, tonumber(data.timeIn), tonumber(data.timeOut))
						timeTableID[data.id] = true
					end
				end
				
				if (data.id == last) then
					loaded(resourceName)
				end
			end
		end
	end)
end

function loaded(resourceName)
	loadedFunction (resourceName)
	initializeObjects()
	releaseCatche(resourceName)
end
					

function initializeObjects()
	Async:setPriority("medium")
	Async:foreach(getElementsByType("object"), function(object)
	
		local id = getElementID(object)
		
		if failed[id] then
			destroyElement(object)
		else
			changeObjectModel(object,id,true,true)
		end
	end)
end

function loadedFunction (resourceName)
	local endTickCount = getTickCount ()-startTickCount
	triggerServerEvent ( "onPlayerLoad", resourceRoot, tostring(endTickCount),resourceName )
	createTrayNotification( 'You have finished loading : '..resourceName, "info" )
end


function changeObjectModel (object,newModel,streamNew,inital)
	local id = getElementID(object)
	
	if id or streamNew then
		if idCache[newModel] then
			if not inital then
				if id then
					print(id..'- Changed to : '..newModel)
				else
					print('New object streamed with ID: '..newModel)
				end
			end
			setElementModel(object,idCache[newModel])
			setElementID(object,newModel)
			setElementData(object,'Zone',definitionZones[id])
			setElementDoubleSided(object,(idObjectProperties[newModel]['doubleSided'] or false))
			
			setObjectBreakable(object,(idObjectProperties[newModel]['breakable'] or false))
			
			if timeTableID[newModel] then
				timeTable[object] = true
			else
				timeTable[object] = false
			end
			
			local LOD = getLowLODElement(object)
			if LOD then
				destroyElement(LOD) -- // Clear LOD if it exists
			end
			
			local lodID = useLODs[newModel] or (getElementData(object,'lodID'))
			
			if idCache[lodID] then -- // Create new LOD if this model has a LOD assigned to it
				
				local x,y,z,xr,yr,zr = getElementPosition (object)
				local xr,yr,zr = getElementRotation (object)
				local nObject = createObject (idCache[lodID],x,y,z,xr,yr,zr,true)
				local cull,dimension,interior = isElementDoubleSided(object),getElementDimension(object),getElementInterior(object)
				setElementData(nObject,'Zone',definitionZones[lodID])
				setElementDoubleSided(nObject,cull)
				setElementInterior(nObject,interior)
				setElementDimension(nObject,dimension)
				setElementID(nObject,lodID)
				setLowLODElement(object,nObject)
				
				if timeTableID[lodID] then
					timeTable[nObject] = true
				else
					timeTable[nObject] = false
				end
				if lodAttach[lodID] then
					attachElements(nObject,object)
				end
			end
		end
	end
end
addEvent( "changeObjectModel", true )
addEventHandler( "changeObjectModel", resourceRoot, changeObjectModel )


function streamObject(id,x,y,z,xr,yr,zr)
	local x = x or 0
	local y = y or 0
	local z = z or 0
	local obj = createObject(1337,x,y,z,xr,yr,zr)
	changeObjectModel(obj,id,true)
	setElementID(obj,id)
	return obj
end



function onElementDataChange(dataName, oldValue)
    if (dataName == "id") then
        local newId = getElementID(source)
		if idCache[newId] then
			if (newId ~= oldValue) then
				changeObjectModel (source,newId)
			end
		end
    end
end
addEventHandler("onElementDataChange", root, onElementDataChange)

function unloadMapDefinitions(name) -- // Feed this the resource name in order to unload the definitions loaded.
	if resourceModels[name] then
		for ID,_ in pairs(resourceModels[name]) do
			engineFreeModel(ID)
		end
	end
	resourceModels[name] = nil
end
addEvent( "resourceStop", true )
addEventHandler( "resourceStop", localPlayer, unloadMapDefinitions )

function onElementDestroy()
	if idCache[getElementID(source)] then -- // Only destroying the LOD if it's a custom model
		if getElementType(source) == "object" then
			if getLowLODElement(source) then
				destroyElement(getLowLODElement(source))
			end
		end
	end
end
addEventHandler("onElementDestroy",resourceRoot,onElementDestroy)


function getMaps()
	local tempTable = {}
	for i,v in pairs(resource) do
		table.insert(tempTable,i)
	end
	return tempTable
end
