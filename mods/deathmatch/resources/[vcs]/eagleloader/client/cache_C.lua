
globalCache = {}
idCache = {}
useLODs = {}

allowcateDefaultIDs = true --// If we're out of custom IDs can we dig into SA?

function requestModelID(modelID)

	if not idCache[modelID] then
		idCache[modelID] = engineRequestModel('object')
		
		if not idCache[modelID] then
			if allowcateDefaultIDs then
				idCache[modelID] = engineRequestSAModel('object')
			end
		end
		return idCache[modelID],true
	end
		

	return idCache[modelID]
end

function requestTextureArchive(path,resourceName)
	if fileExists(path) then
		globalCache[resourceName][path] = globalCache[resourceName][path] or engineLoadTXD(path)
		return globalCache[resourceName][path],path
	else
		return false
	end
end

function requestCollision(path,resourceName)
	if fileExists(path) then
		globalCache[resourceName][path] = globalCache[resourceName][path] or engineLoadCOL(path)
		return globalCache[resourceName][path],path
	else
		return false
	end
end

function requestModel(path,resourceName)
	if path then
		globalCache[resourceName][path] = globalCache[resourceName][path] or engineLoadDFF(path)
		return globalCache[resourceName][path],path
	end
end

function releaseCatche(resourceName)
	if globalCache[resourceName] then
		for path,loaded in pairs(globalCache[resourceName]) do
			globalCache[resourceName][path] = nil
		end
		globalCache[resourceName] = nil
		return true
	else
		return false
	end
end