debug.sethook(nil)

local File =	fileOpen('gta3.JSP')
local Data =	fileRead(File, fileGetSize(File))
local Proccessed = split(Data,10)
fileClose (File)

ObjectList = {}

XA,YA,ZA = 0

for iA,vA in pairs(Proccessed) do
	if iA == 1 then
		local x,y,z = split(vA,",")[1],split(vA,",")[2],split(vA,",")[3]
		XA,YA,ZA = tonumber(x),tonumber(y),tonumber(z)
	else
		local SplitA = split(vA,",")
		if not (SplitA[1] == '!') then -- IF #1 == ! THEN IGNORE

			local object = exports.Objs:JcreateObject(SplitA[1],tonumber(SplitA[4])+XA,tonumber(SplitA[5])+YA,tonumber(SplitA[6])+ZA,tonumber(SplitA[7]),tonumber(SplitA[8]),tonumber(SplitA[9]))
			if object then
				setElementInterior(object,tonumber(SplitA[2]))
				setElementDimension(object,tonumber(SplitA[3]))
				table.insert(ObjectList,object)
			end
		end
	end
end


addEventHandler ( "onResourceStop", resourceRoot,
function (	)
	for iA,vA in pairs(ObjectList) do
		if isElement(vA) then
			destroyElement(vA)
		end
	end
end
)

