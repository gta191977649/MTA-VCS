print("Copying Files")
TXDs = {}
DFFs = {}
COLs = {}

for i,v in pairs(IDEList) do
	local txd = v[2]
	local dff = v[1]
	local col = v[1]
	TXDs[txd] = removeSpace(v[2])
	DFFs[dff] = removeSpace(v[1])
	COLs[col] = removeSpace(v[1])
end

for i,v in pairs(TXDs) do
	if fileExists ("Resources/"..v..".txd") then
		if not fileExists (MapName.."/Content/textures/"..v..".txd") then
			print("Copying File : "..v..".txd")
			fileCopy ("Resources/"..v..".txd",MapName.."/Content/textures/"..v..".txd")
		end

		local Filepath = "Content/textures/"..v..".txd"
		table.insert(meta,'	<file src="'..Filepath..'" type="client" />')
	else
		OutPutDebug2("TXD:"..v.." Missing TXD")
	end
end
table.insert(meta,' ')
table.insert(meta,' ')

for i,v in pairs(DFFs) do
	if fileExists ("Resources/"..v..".dff") then

		if not fileExists (MapName.."/Content/models/"..v..".dff") then
			print("Copying File : "..v..".dff")
			fileCopy ("Resources/"..v..".dff",MapName.."/Content/models/"..v..".dff")
		end

		local Filepath = "Content/models/"..v..".dff"
		table.insert(meta,'	<file src="'..Filepath..'" type="client" />')
	else
		OutPutDebug2("Model:"..v.." Missing DFF")
	end
end


table.insert(meta,' ')
table.insert(meta,' ')


for i,v in pairs(COLs) do
	if fileExists ("Resources/"..v..".col") then

		if not fileExists (MapName.."/Content/coll/"..v..".col") then
			print("Copying File : "..v..".col")
			fileCopy ("Resources/"..v..".col",MapName.."/Content/coll/"..v..".col")
		end

		local Filepath = "Content/coll/"..v..".col"
		table.insert(meta,'	<file src="'..Filepath..'" type="client" />')
	else
		OutPutDebug2("Col:"..v.." Missing COL")
	end
end

-- Copy Files
fileCopy ("Scripts/Presets/ClientLoader/JSDLoader.lua",MapName.."/Loaders/JSDLoader.lua",true)
fileCopy ("Scripts/Presets/ServerLoader/JSPLoader.lua",MapName.."/Loaders/JSPLoader.lua",true)


--- Copy files to new dictonary

