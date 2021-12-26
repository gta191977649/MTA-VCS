
-- Tables --
idIndex = 0
global = {}
idused = {}
modelID = {}
count = 0

-- Functions --

function string.count (text, search)
	if ( not text or not search ) then return false end
	
	return select ( 2, text:gsub ( search, "" ) );
end


function readFile()
	local File =  fileOpen('data/IDs.ID')   
	local Data =  fileRead(File, fileGetSize(File))
	 fileClose ( File)
	return split(Data,10)
end

function readFile2()
	local File =  fileOpen('data/FullIDs.ID')   
	local Data =  fileRead(File, fileGetSize(File))
	 fileClose ( File)
	return split(Data,10)
end

-- skip problematic object models
local badModelList = {
	"DYN_","kmb_shutter","ab_carcass"
}
function isProblemModel(model_name) 
	for _,model in ipairs(badModelList) do 
		if string.find(model_name,model) then return true end
	end
	return false

end
function index(table,all)
	for idx,v in ipairs(table) do
		local split = split(v,",")
		if not all then
			if not isProblemModel(split[2]) then
				count = count + 1
				global[count] = tonumber(split[1])
			end
		end
		
		modelID[tonumber(split[1])] = split[2]
		modelID[split[2]] = tonumber(split[1])
	end
end
index(readFile()) 
index(readFile2(),true) 

function getModelFromID(id)
	return (tonumber(id) or tonumber(modelID[id]))
end

function getFreeID(name,looped)
	if data.id[name] then
		return data.id[name]
	else
		idIndex = idIndex + 1
		if tonumber(global[idIndex]) then
			if not idused[global[idIndex]] then
				idused[global[idIndex]] = name
				data.id[name] = global[idIndex]
				return global[idIndex]
			else
				return getFreeID(name,looped)
			end
		else
			if (idIndex >= #global) and looped then
				print('MTA Stream:','Out of IDs')
				return
			else
				idIndex = 0
				return getFreeID(name,true)
			end
		end
	end
end
