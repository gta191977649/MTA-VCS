print("Writing Map Data")
Map = {}

for i,v in pairs(IPLList) do
	local model = removeSpace(v[1])
	local Interior = removeSpace(v[2])

	local X = removeSpace(v[3])+GlobalX
	local Y = removeSpace(v[4])+GlobalY
	local Z = removeSpace(v[5])+GlobalZ

	local XR = removeSpace(v[6])
	local YR = removeSpace(v[7])
	local ZR = removeSpace(v[8])
	local FLAG = removeSpace(v[9])

	table.insert(Map,model..','..Interior..',-1,'..X..','..Y..','..Z..','..XR..','..YR..','..ZR..','..FLAG)
end


local file = fileCreate (MapName..'/gta3.JSP' )


fileWrite(file,"0,0,0\n")

for i,v in pairs(Map) do
	fileWrite(file,v.."\n")
end

fileClose(file)