print("Writing Client Object Data")
ObjectDataC = {}

function AdditionalFlag(InPut)
	if InPut == 4 or InPut == 8 then
		return 'true'
	else
		return 'nil'
	end
end

Culled = {}

function CulledA(InPut)
	if InPut == 2097152 then
		return 'true'
	else
		return 'nil'
	end
end

for i,v in pairs(IDEList) do
	if v[7] then
		local model = removeSpace(v[1])
		local texture = removeSpace(v[2])
		local drawdistance = removeSpace(v[3])
		local Flag = AdditionalFlag(removeSpace(v[6]))
		local Culled = CulledA(removeSpace(v[6]))
		local LOD = (tonumber(v[7]) > -1) and "true" or "nil"

		if v[4] and v[5] then
			table.insert(ObjectDataC,model..','..model..','..texture..','..model..','..drawdistance..','..Flag..','..Culled..','..LOD..','..removeSpace(v[4])..','..removeSpace(v[5]))
		else
			table.insert(ObjectDataC,model..','..model..','..texture..','..model..','..drawdistance..','..Flag..','..Culled..','..LOD)
		end
	end
end


local file = fileCreate (MapName..'/gta3.JSD' )
for i,v in pairs(ObjectDataC) do
	fileWrite(file,v.."\n")
end

fileClose(file) -- done