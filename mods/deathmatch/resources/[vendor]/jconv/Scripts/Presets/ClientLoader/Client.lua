local File =	fileOpen('gta3.JSD')
local Data =	fileRead(File, fileGetSize(File))
local Proccessed = split(Data,10)
fileClose (File)

function toBolean(input)
	if input == 'true' then
		return true
	else
		return false
	end
end

for iA,vA in pairs(Proccessed) do
	local Split = split(vA,",")
	exports.Objs:JCreateObjectDefinition(Split[1],'Content\models'..Split[2]..'.dff','Content\textures'..Split[3]..'.txd','Content\collisions'..Split[4]..'.col',toBolean(Split[5]),toBolean(Split[6]),toBolean(Split[7]),toBolean(Split[8]))
end

-- If used externally use
print ('Map Loaded')