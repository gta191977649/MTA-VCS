--[[
	Created by IIYAMA
]]

local debugEnabled = false --[[ ! Warning ! !!!!!!!!!!!!!!!!!!!!!!!!!!!!!
	This option debugs a lot of information with the inspect function. Not all computers are able to handle this.
	When enabled, you will be inspecting the table: resourcesMapData, and you can see all the core data change. There is a little delay in updating the information, this will boost your FPS a little bit.
]]

local setTimer = createLuaTimer
local killTimer = killLuaTimer
local isTimer = isLuaTimer
local getTimers = getLuaTimers

local resourcesMapData = {
	byResource = {},
	byParentElement = {}
}

local resumeCoroutine = function  (res, mapRoot)
	local resourceMapData = resourcesMapData.byResource[res]
	if resourceMapData then
		local mapRootData = resourceMapData.mapByMapRoot[mapRoot]
		if mapRootData then
			local processObjectData = mapRootData.processObjectData
			if processObjectData and coroutine.status(processObjectData.co) ~= "dead" then
				processObjectData.processBreakTime = getTickCount() + math.floor(2 / math.max(#getTimers(), 1))
				coroutine.resume(processObjectData.co, res, mapRoot)
				return
			end
		end
	end
	outputDebugString ("A coroutine has failed along the way, if this error occurs, please report it.", 1)
end

local processObjectsForLowLOD = function (res, mapRoot)
	local resourceMapData = resourcesMapData.byResource[res]
	if resourceMapData then
		local mapRootData = resourceMapData.mapByMapRoot[mapRoot]
		if mapRootData then
			local processObjectData = mapRootData.processObjectData
			local timeStart = getTickCount()
			local cycles = 1
			
			local objects = mapRootData.objects
			local parentElement = mapRootData.parentElement
			for i=1, #objects do
				local object = objects[i]
				if isElement(object) then
					
					local alpha = getElementAlpha(object)

					if alpha == 255 then
						local model = getElementModel(object)
						local x, y, z = getElementPosition(object)
						local xr, yr, zr = getElementRotation(object)
					
						
						local lowLODObject = createObject(model, x, y, z, xr, yr, zr, true)
						if lowLODObject then
							setElementParent(lowLODObject, parentElement)
							
							
							local interior = getElementInterior(object)
							if interior ~= 0 then
								setElementInterior(lowLODObject, interior)
							end
							
							
							local dimension = getElementDimension ( object )
							if dimension ~=  0 then
								setElementDimension(lowLODObject, dimension)
							end
							
							local doubleSided = isElementDoubleSided ( object )
							
							if doubleSided then
								setElementDoubleSided(lowLODObject, true)
							end
							
							setLowLODElement(object, lowLODObject)
							
							engineSetModelLODDistance(model, 170) 
							local scale = getObjectScale(object) or 1
							if scale ~= 1 then
								setObjectScale( lowLODObject, scale)
							end
							if isObjectBreakable (object) then
								attachElements(lowLODObject, object)
								setObjectBreakable (lowLODObject, false )
							end
						end
					end
				end
				if getTickCount() > processObjectData.processBreakTime and i ~= #objects then
					processObjectData.timer = setTimer(resumeCoroutine, 100, 1, res, mapRoot)
					coroutine.yield()
					cycles = cycles + 1
				end
			end
			
			mapRootData.creationInfo = "Creating lowLod objects took " .. (getTickCount() - timeStart) .. " ms and " .. cycles .. " cycles"
		end
		--[[ 
			clean up all unnecessary data
		]]
		
		mapRootData.processObjectData = nil
		mapRootData.objects = nil
		mapRootData.ready = true
		
	end
	
end



function prepareMap (resourceMapData, mapRootData)
	local co = coroutine.create(processObjectsForLowLOD);
	return {
		co = co,
		processBreakTime = getTickCount() + 2,
		parentElement = createElement("lowLODParent")
	}
end



addEventHandler("onClientObjectBreak", root,
    function()
		local lowLODObject = getLowLODElement(source)
		
		if lowLODObject and resourcesMapData.byParentElement[getElementParent(lowLODObject)] then
			setElementAlpha(lowLODObject, 0)
		end
    end
)

addEventHandler( "onClientElementStreamOut", root,
    function ( )
        if getElementType( source ) == "object" and isObjectBreakable (source) then
			local lowLODObject = getLowLODElement(source)
			if lowLODObject and resourcesMapData.byParentElement[getElementParent(lowLODObject)] then
				setElementAlpha(lowLODObject, 255)
			end
		end
	end
)







function loadMapData (res, thisResourceRoot)
	local resourceMapData = {
		maps = {},
		mapByMapRoot = {},
		resource = res
	}
	local coroutines = {}

	local mapRoots = getElementsByType("map", thisResourceRoot)
	if mapRoots and #mapRoots > 0 then
		for i=1, #mapRoots do
			local mapRoot = mapRoots[i]
			local objects = getElementsByType("object", mapRoot)
			if #objects > 0 then
				local parentElement = createElement("lowLODParent")
				
				
				local mapRootData = {
					mapRoot = mapRoot,
					objects = objects,
					objectsCount = #objects,
					parentElement = parentElement,
					ready = false
					
				}
				local processObjectData = prepareMap (resourceMapData, mapRootData)
				mapRootData.processObjectData = processObjectData
				
				coroutines[#coroutines + 1] = {co = processObjectData.co, resource = res, mapRoot = mapRoot}
				
				resourceMapData.maps[#resourceMapData.maps + 1] = mapRootData
				resourceMapData.mapByMapRoot[mapRoot] = mapRootData
				
				resourcesMapData.byParentElement[parentElement] = resourceMapData
			end
		end
	end
	if #resourceMapData.maps > 0 then
		resourcesMapData.byResource[res] = resourceMapData
		for i=1, #coroutines do
			local coroutineData = coroutines[i]
			coroutine.resume(coroutineData.co, coroutineData.resource, coroutineData.mapRoot)
		end
	end
end

function unLoadMapData (res)
	local resourceMapData = resourcesMapData.byResource[res]
	if resourceMapData then
		resourcesMapData.byResource[res] = nil
		
		--[[
			Clean up the parentElement references
		]]
		local maps = resourceMapData.maps
		for i=1, #maps do
			local mapRootData = maps[i]
			
			local parentElement = mapRootData.parentElement
			if isElement(parentElement) then
				destroyElement(parentElement) -- < this will cut the tree from the top! Let MTA handle the falling tree to speed things up.
			end
			
			resourcesMapData.byParentElement[parentElement] = nil
			
			local processObjectData = mapRootData.processObjectData
			if processObjectData and isTimer(processObjectData.timer) then
				killTimer(processObjectData.timer )
			end
		end
		
		return true
	end
	return false
end


addEventHandler("onClientResourceStart", root, 
function (res) 
	if res ~= resource then
		if resourcesMapData.byResource[res] then
			--[[
				Something went wrong, not sure why or how. But it has never happend to me yet. So this line will clean thing up.
			]]
			unLoadMapData (res)
		end
		loadMapData (res, source)
		
	else
		--[[
			Get the resources that are already running, this is a hax for the function getResources: https://wiki.multitheftauto.com/wiki/GetResources
		]]
		local resourceRoots = getElementsByType("resource")
		for i=1, #resourceRoots do
			local thisResourceRoot = resourceRoots[i]
			local resourceName = getElementID ( thisResourceRoot ) 
			if resourceName then
				local res = getResourceFromName(resourceName)
				if res and res ~= resource and getResourceState(res)  == "running" then
					loadMapData (res, thisResourceRoot)
				end
			end
		end 
		setPedsLODDistance ( 500 )
		setVehiclesLODDistance ( 500, 500 )
	end
end)

addEventHandler("onClientResourceStop", root, 
function (res) 
	if res == resource then
		resetPedsLODDistance()
		resetVehiclesLODDistance()
	else
		unLoadMapData (res)
	end
end)



if debugEnabled then
	iprint("debug enabled")
	local debugInfo = ""
	local nextRefreshTime = 0
	addEventHandler("onClientRender", root, 
	function () 
		dxDrawText("MAX Execution time per process " .. tostring(math.floor(2 / math.max(#getTimers(), 1)) +  1), 300, 5, 2000, 2000, tocolor(255,255,255), 0.8)  
		dxDrawText(debugInfo, 300, 20, 2000, 2000, tocolor(255,255,255), 0.8)
		
		local timeNow = getTickCount()
		if timeNow > nextRefreshTime then
			
			debugInfo = inspect(resourcesMapData, {depth = 5}) -- max depth 5, else you are also displaying the objects of the map.
			--[[
				Slow down the updates depending on the process speed of the inspector: inspect
			]]
			nextRefreshTime = timeNow + 100 + (100 *(getTickCount() - timeNow))
		end
		
		if type(luaTimers) == "table" then
			local counter = 1
			for key, data in pairs(luaTimers) do
				local R,G,B = 0,200,0

				dxDrawText(" ID " .. data.ID .. " = " .. data.endTime .. " | " ..  data.endTime - getTickCount() .. "/" .. data.timeInterval , 600, 300 + (counter*20), 0,0, tocolor(R,G,B))
				counter = counter + 1
			end
		end
		
	end)
end