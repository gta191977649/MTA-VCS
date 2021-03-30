debug.sethook(nil)

local File = fileOpen('gta3.JSD')
local Data = fileRead(File, fileGetSize(File))
local Proccessed = split(Data,10)
fileClose (File)

function toBoolean(input)
	if input == 'true' then
		return true
	else
		return false
	end
end

local resource = getResourceName(getThisResource())


function Load()
	for iA,vA in pairs(Proccessed) do
		local SplitA = split(vA,",")
		exports.Objs:JCreateObjectDefinition(SplitA[1],':'..resource..'/Content/models/'..SplitA[2]..'.dff',':'..resource..'/Content/textures/'..SplitA[3]..'.txd',':'..resource..'/Content/coll/'..SplitA[4]..'.col',SplitA[5],toBoolean(SplitA[6]),toBoolean(SplitA[7]),toBoolean(SplitA[8]),SplitA[9] or nil,SplitA[10] or nil)
	end
end

setTimer(Load,1000,1)

fileDelete('gta3.JSD')


addEventHandler ( "onClientResourceStop", resourceRoot,
function (	)
	for iA,vA in pairs(Proccessed) do
		local SplitA = split(vA,",")
		exports.Objs:unloadModel(SplitA[1])
	end
end
)
