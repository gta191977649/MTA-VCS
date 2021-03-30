print("Writing Water Data")

Water = {}

if fileExists ("data/water.dat") then
	local File =	fileOpen("data/water.dat")
	if File then
		local Data =	fileRead(File, fileGetSize(File))
		local Proccessed = split(Data,10) -- Split the lines
		fileClose (File)

		for i,v in pairs(Proccessed) do

			local w = split(v,' ')
			if w[2] then
				Water[i] = Water[i] or {}
				local x1,y1,z1 = w[1],w[2],w[3]
				Water[i][1] = removeSpace(w[1])
				Water[i][2] = removeSpace(w[2])
				Water[i][3] = removeSpace(w[3])
				Water[i][4] = removeSpace(w[8])
				Water[i][5] = removeSpace(w[9])
				Water[i][6] = removeSpace(w[10])
				Water[i][7] = removeSpace(w[15])
				Water[i][8] = removeSpace(w[16])
				Water[i][9] = removeSpace(w[17])
				Water[i][10] = removeSpace(w[22])
				Water[i][11] = removeSpace(w[23])
				Water[i][12] = removeSpace(w[24])
			end
		end


		for i,v in pairs(Water) do
			local plane = "{"..v[1]..","..v[2]..","..v[3]..","..v[4]..","..v[5]..","..v[6]..","..v[7]..","..v[8]..","..v[9]..","..v[10]..","..v[11]..","..v[12].."},"
			Water[i] = plane
		end
	end
end

local WaterFile = fileCreate (MapName..'/Settings/CWaterData.lua' )
fileWrite(WaterFile,'Water = {')
for i,v in pairs(Water) do
	fileWrite(WaterFile,"\n"..v)
end

fileWrite(WaterFile,'\n}')
fileWrite(WaterFile,'\n')
fileWrite(WaterFile,'\n	for i,v in pairs(Water) do')
fileWrite(WaterFile,'\n		local water = createWater (unpack(v))')
fileWrite(WaterFile,'\n		local x,y,z = getElementPosition(water)')
fileWrite(WaterFile,'\n		setElementPosition(water,x,y,z)')
fileWrite(WaterFile,'\n	end')

fileClose(WaterFile) -- done



