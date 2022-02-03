
Debug = {}
IPLList = {}
IPLList2 = {}

function OutPutDebug2(Messege)
	print (Messege) -- Print our messege
	table.insert(Debug,"ERROR - "..Messege)
end

function string.count (text, search)
	if ( not text or not search ) then return false end

	return select ( 2, text:gsub ( search, "" ) );
end

function quaternion_to_euler_angle(w, x, y, z)
	local qw = tonumber(w) or 0
	local qx = tonumber(x) or 0
	local qy = tonumber(y) or 0
	local qz = tonumber(z) or 0

	local X = math.deg(math.atan2(-2*(qy*qz-qw*qx), qw*qw-qx*qx-qy*qy+qz*qz))
	local Y = math.deg(math.asin(2*(qx*qz + qw*qy)))
	local Z = math.deg(math.atan2(-2*(qx*qy-qw*qz), qw*qw+qx*qx-qy*qy-qz*qz))

	return -X,-Y,-Z
end

function removeSpace(Text)
	if Text then
		return string.gsub(string.gsub(Text,'%s',""),' ',"")
	else
		return ''
	end
end

function Pass(ID)
	return true
end

LODS = {}

IDEList1 = {}
IDEList = {}

Exists = {}
for i,v in pairs(IPLTable) do
	local File =	fileOpen(v)
	local Data =	fileRead(File, fileGetSize(File))
	local Proccessed = split(Data,10)
	fileClose (File)

	local Proccessed_tmp = {}
	for iA,vA in pairs(Proccessed) do
		local Split = split(vA,",")
		if Split[2] then 
			table.insert(Proccessed_tmp,Split)
		end
	end

	for iA,vA in ipairs(Proccessed_tmp) do
		if vA[2] and tonumber(vA[1]) and tonumber(vA[3]) and tonumber(vA[4]) and (not tonumber(vA[2])) then

			Exists[removeSpace(vA[2])] = true
			local lod_index = vA[11] and tonumber(vA[11])+1 or nil
			if Proccessed_tmp[lod_index] then 
				LODS[removeSpace(vA[2])] = removeSpace(Proccessed_tmp[lod_index][2])
			else
				LODS[removeSpace(vA[2])] = -1
			end
			--print(Proccessed_tmp[lod_index][2])
			--LODS[removeSpace(vA[2])] = tonumber(vA[11])
		end
	end
end
for i,v in pairs(IDETable) do
	local File =	fileOpen(v)
	local Data =	fileRead(File, fileGetSize(File))
	local Proccessed = split(Data,10)
	fileClose (File)

	for iA,vA in pairs(Proccessed) do
		local Split = split(vA,",")
		if Split[2] and tonumber(Split[1]) and (not tonumber(Split[2])) then
			-- Id, ModelName, TxdName, MeshCount, DrawDistance, Flags -VC
			local ID = tonumber(Split[1])
			local Model = removeSpace(Split[2])
			local Texture = removeSpace(Split[3])
			local DrawDistance = Version == "SA" and tonumber(Split[4]) or tonumber(Split[5])
			local TimeOn = Version == "SA" and tonumber(Split[6]) or nil or nil
			local TimeOff = Version == "SA" and tonumber(Split[7]) or nil or nil
			local Flag = Version == "SA" and Split[5] or Split[6]
			--if (string.count(Model,"LOD") < 1 and string.count(Model,"lod") < 1) or Defaults2[Model] then
			if fileExists ("Resources/"..Model..".dff") then
				if USE_SA_PROPS and Defaults2[Model] then
					Flag = "SA_PROP"
					Defaults[Model] = true
				end
				IDEList1[Model] = {Model,Texture,DrawDistance,TimeOn,TimeOff,Flag,LODS[Model]} -- Flag is important for optmization!
			else
				if Exists[removeSpace(Model)] then
					OutPutDebug2("Model:"..Model.." Missing DFF")
				end
			end
			--end
		end
	end
end

for i,v in pairs(IPLTable) do
	local File =	fileOpen(v)
	local Data =	fileRead(File, fileGetSize(File))
	local Proccessed = split(Data,10)
	fileClose (File)
	for iA,vA in pairs(Proccessed) do
		local Split = split(vA,",")

		--local One = string.split(vA)[1]
		if Split[2] and tonumber(Split[1]) and tonumber(Split[3]) and tonumber(Split[4]) and (not tonumber(Split[2])) then
			local vaildData = true
			local ID = tonumber(Split[1])
			local Model = removeSpace(Split[2])
			-- III Does not has interior
			local Interior = Version == "III" and 0 or tonumber(Split[3])
			local PosX,PosY,PosZ = Split[4],Split[5],Split[6]


			local QX,QY,QZ,QW = 0,0,0,0
			if Version == "III" then
				QX,QY,QZ,QW = Split[9],Split[10],Split[11],Split[12]
			elseif Version == "VC" then 
				QX,QY,QZ,QW = Split[10],Split[11],Split[12],Split[13]
			elseif Version == "SA" then
				QX,QY,QZ,QW = Split[7],Split[8],Split[9],Split[10]
			else
				OutPutDebug2("Incorrect IPL Posistion Data on model id-> "..ID)
				vaildData = false
			end
	
			local xr,yr,zr = fromQuaternion(QX,QY,QZ,QW)
			
			-- Only Sa has the lod flag in ipl
			local LOD = Version == "SA" and tonumber(Split[11]) or -1

			if vaildData then
				if (string.count(Model,"LOD") < 1 and string.count(Model,"lod") < 1) then
					if IDEList1[Model] or Defaults[Model] or Defaults2[Model] then -- If it doesn't exist ignore it
						IPLList2[Model] = true
						table.insert(IPLList,{Model,Interior,PosX,PosY,PosZ,xr,yr,zr,"OBJ"})
					else
						if string.count(Model,"LOD") < 1 and string.count(Model,"lod") < 1	then
							OutPutDebug2("IPL:"..Model.." Missing IDE")
						end
					end
				else
					table.insert(IPLList,{Model,Interior,PosX,PosY,PosZ,xr,yr,zr,"LOD"})
				end
			end
		end
	end
end

IDEList = IDEList1