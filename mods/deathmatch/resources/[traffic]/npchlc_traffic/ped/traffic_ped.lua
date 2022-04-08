PedGroup = {}
Peds = {}
Cars = {}
PedProps = {}
function loadPedIde() 
	local f = fileOpen("data/ped.ide")
	local lines = fileRead( f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i=1,#lines do 
		local vals = split(lines[i],",")
		local model = tonumber(vals[1])
		local name = tostring(vals[2])
		Peds[name] = {
			id = model,
		}
	end
end
function loadCarIde() 
	local f = fileOpen("data/vehicles.ide")
	local lines = fileRead( f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i=1,#lines do 
		local vals = split(lines[i],",")
		local model = tonumber(vals[1])
		local name = tostring(vals[2])
		Cars[name] = {
			id = model,
		}
	end
	--iprint(Cars)
end
function loadPedProps() 
	local f = fileOpen("data/traffic_props.dat")
	local lines = fileRead( f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i=1,#lines do 
		local vals = split(lines[i],",")
		local id = tostring(vals[1])
		local name = tostring(vals[2])
		PedProps[id] = {
			name = name,
			distribution = {
				POPCYCLE_GROUP_GANGS = tonumber(vals[3]),
				POPCYCLE_GROUP_DEALERS = tonumber(vals[4]),
				POPCYCLE_GROUP_WORKERS = tonumber(vals[5]),
				POPCYCLE_GROUP_BUSINESS = tonumber(vals[6]),
				POPCYCLE_GROUP_CLUBBERS = tonumber(vals[7]),
				POPCYCLE_GROUP_FARMERS = tonumber(vals[8]),
				POPCYCLE_GROUP_BEACHFOLK = tonumber(vals[9]),
				POPCYCLE_GROUP_PARKFOLK = tonumber(vals[10]),
				POPCYCLE_GROUP_CASUAL_RICH = tonumber(vals[11]),
				POPCYCLE_GROUP_CASUAL_AVERAGE = tonumber(vals[12]),
				POPCYCLE_GROUP_CASUAL_POOR = tonumber(vals[13]),
				POPCYCLE_GROUP_PROSTITUTES = tonumber(vals[14]),
				POPCYCLE_GROUP_CRIMINALS = tonumber(vals[15]),
				POPCYCLE_GROUP_GOLFERS = tonumber(vals[16]),
				POPCYCLE_GROUP_SERVANTS = tonumber(vals[17]),
				POPCYCLE_GROUP_AIRCREW	= tonumber(vals[18]),
				POPCYCLE_GROUP_ENTERTAINERS = tonumber(vals[19]),
				POPCYCLE_GROUP_OUT_OF_TOWN_FACTORY_WORKERS = tonumber(vals[20]),
				POPCYCLE_GROUP_DESERT_FOLK = tonumber(vals[21]),
				POPCYCLE_GROUP_AIRCREW_RUNWAY = tonumber(vals[22]),
				POPCYCLE_GROUP_RESTRICTED_AREA = tonumber(vals[23]),
			}
		}
	end
	--iprint(PedProps)
end
function loadPedGroup() 
	-- load ped first
	local f = fileOpen("data/ped_group.dat")
	local lines = fileRead( f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i=1,#lines do 
		local vals = split(lines[i],",")
		local group = string.gsub(vals[#vals], "\r", "")
		PedGroup[group] = {
			peds = {},
			cars = {},
		}
		for j=1,#vals do 
			if Peds[vals[j]] ~= nil then 
				--PedGroup[group].peds[j] = Peds[vals[j]].id
				table.insert(PedGroup[group].peds,Peds[vals[j]].id)
			end
		end
	end
	-- load cars
	local f = fileOpen("data/cargrp.dat")
	local lines = fileRead( f,fileGetSize(f))
	fileClose(f)
	lines = split(lines,"\n")
	for i=1,#lines do 
		
		local vals = split(lines[i],",")
		
		local group = string.gsub(vals[#vals], "\r", "")
		
		for j=1,#vals do 
			if PedGroup[group] ~= nil and Cars[vals[j]] ~= nil then 
				table.insert(PedGroup[group].cars,Cars[vals[j]].id)
				--PedGroup[group].cars[j] = Cars[vals[j]].id
			end
		end
	end
	--iprint(PedGroup)
end
function getPedModelsInGroup(group_name) 
	if PedGroup[group_name] ~= nil then 
		return PedGroup[group_name].peds
	end
	return nil
end

local function init() 
	loadPedIde() 
	loadCarIde() 
	loadPedProps()
	loadPedGroup()
	--iprint(getPedModelsInGroup("POPCYCLE_GROUP_WORKERS") )
end
init()