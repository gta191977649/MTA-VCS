WANTED = exports.wanted
DISTORY_TIME = 3000

function initTrafficGenerator()
	server_coldata = getResourceFromName("server_coldata")
	npc_hlc = exports.npc_hlc

	--population = population_group
	population = {peds = {},cars = {},boats = {},planes = {}}
	--[[
	for key, val in pairs(population_group) do 
		population[key] = {}
	end
	]]
	element_timers = {}

	players = {}
	for plnum,player in ipairs(getElementsByType("player")) do
		players[player] = {
			rageGroups = {},
			cop_heli = nil,
		}
	end
	addEventHandler("onPlayerJoin",root,addPlayerOnJoin)
	addEventHandler("onPlayerQuit",root,removePlayerOnQuit)
	addEventHandler("onPlayerWasted",root,function() -- clean player rageGroups
		WANTED:setPlayerWanted(source,0)
		players[source].rageGroups = {}
	end)
	square_subtable_count = {}

	setTimer(updateTraffic,1000,0)
end

function addPlayerOnJoin()
	players[source] =  {
		rageGroups = {} 
	}
end

function removePlayerOnQuit()
	players[source] = nil
end

function updateTrafficDens() 
	
	local ratio = 0.85
	local h = getTime()

	local densityTimeMapping = {
		[0] = {peds = 0.002,cars = 0.004,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[1] = {peds = 0.002,cars = 0.004,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[2] = {peds = 0.002,cars = 0.004,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[3] = {peds = 0.002,cars = 0.004,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[4] = {peds = 0.003,cars = 0.004,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[5] = {peds = 0.003,cars = 0.006,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[6] = {peds = 0.004,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[7] = {peds = 0.005,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[8] = {peds = 0.006,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[9] = {peds = 0.007,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[10] = {peds = 0.008,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[11] = {peds = 0.01,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[12] = {peds = 0.01,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[13] = {peds = 0.01,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[14] = {peds = 0.01,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[15] = {peds = 0.01,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[16] = {peds = 0.008,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[17] = {peds = 0.008,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[18] = {peds = 0.01,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[19] = {peds = 0.01,cars = 0.008,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[20] = {peds = 0.007,cars = 0.007,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[21] = {peds = 0.005,cars = 0.005,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[22] = {peds = 0.004,cars = 0.003,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
		[23] = {peds = 0.002,cars = 0.002,boats = 0.002,planes = 0.01,gangs = 0.0008,cops = 0},
	}

	traffic_density = {
		peds = densityTimeMapping[h].peds * ratio,
		cars = densityTimeMapping[h].cars * ratio,
		boats = densityTimeMapping[h].boats * ratio,
		planes = densityTimeMapping[h].planes * ratio,
		gangs = densityTimeMapping[h].gangs * ratio,
		cops = densityTimeMapping[h].cops * ratio,
	}
end
function updateTraffic()
	--colcheck = get("npchlc_traffic.check_collisions")
	--colcheck = colcheck == "all" and root or colcheck == "local" and resourceRoot or nil
	updateTrafficDens()
	removeEmptySquares()
	updateSquarePopulations()
	generateTraffic()

end

function updateSquarePopulations()

	if square_population then
		for dim,square_dim in pairs(square_population) do
			for y,square_row in pairs(square_dim) do
				for x,square in pairs(square_row) do
					square.count = {peds =  0,cars =  0,boats =  0,planes =  0}
					square.list  = {peds = {},cars = {},boats = {},planes = {}}
					square.gen_mode  = "despawn"
				end
			end
		end
	end

	
	countPopulationInSquares("peds")
	countPopulationInSquares("cars")
	countPopulationInSquares("boats")
	--countPopulationInSquares("planes")

	local size = 4
	for player,exists in pairs(players) do 
		if isElement(player) then 
			local x,y = getElementPosition(player)
			local dim = getElementDimension(player)
			x,y = math.floor(x/SQUARE_SIZE),math.floor(y/SQUARE_SIZE)

			for sy = y-size,y+size do 
				for sx = x-size,x+size do
					local square = getPopulationSquare(sx,sy,dim)
					if not square then
						square = createPopulationSquare(sx,sy,dim,"spawn")
					else
						if x-(size-1) <= sx and sx <= x+(size-1) and y-(size-1) <= sy and sy <= y+(size-1) then
							square.gen_mode = "nospawn"
						else
							square.gen_mode = "spawn"
						end
					end
				end
			end
		end
	end

	--if colcheck then call(server_coldata,"generateColData",colcheck) end

	
end

function removeEmptySquares()
	if square_population then
		for dim,square_dim in pairs(square_population) do
			for y,square_row in pairs(square_dim) do
				for x,square in pairs(square_row) do
					if
						square.gen_mode == "despawn" and
						square.count.peds == 0 and
						square.count.cars == 0 and
						square.count.boats == 0 and
						square.count.planes == 0
					then
						destroyPopulationSquare(x,y,dim)
					end
				end
			end
		end
	end
end

function countPopulationInSquares(trtype)
	
	Async:forkey(population[trtype],function(element,exists) 
		if getElementType(element) ~= "ped" or not isPedInVehicle(element) then
			local x,y = getElementPosition(element)
			local dim = getElementDimension(element)
			x,y = math.floor(x/SQUARE_SIZE),math.floor(y/SQUARE_SIZE)

			for sy = y-4,y+4 do for sx = x-4,x+4 do
				local square = getPopulationSquare(sx,sy,dim)
				if sx == x and sy == y then
					if not square then square = createPopulationSquare(sx,sy,dim,"despawn") end
					square.list[trtype][element] = true
				end
				if square then square.count[trtype] = square.count[trtype]+1 end
			end end
		end
	end)
	--[[
	for element,exists in pairs(population[trtype]) do
		if getElementType(element) ~= "ped" or not isPedInVehicle(element) then
			local x,y = getElementPosition(element)
			local dim = getElementDimension(element)
			x,y = math.floor(x/SQUARE_SIZE),math.floor(y/SQUARE_SIZE)

			for sy = y-2,y+2 do for sx = x-2,x+2 do
				local square = getPopulationSquare(sx,sy,dim)
				if sx == x and sy == y then
					if not square then square = createPopulationSquare(sx,sy,dim,"despawn") end
					square.list[trtype][element] = true
				end
				if square then square.count[trtype] = square.count[trtype]+1 end
			end end
		end
	end
	--]]
end

function createPopulationSquare(x,y,dim,genmode)
	if not square_population then
		square_population = {}
		square_subtable_count[square_population] = 0
	end
	local square_dim = square_population[dim]
	if not square_dim then
		square_dim = {}
		square_subtable_count[square_dim] = 0
		square_population[dim] = square_dim
		square_subtable_count[square_population] = square_subtable_count[square_population]+1
	end
	local square_row = square_dim[y]
	if not square_row then
		square_row = {}
		square_subtable_count[square_row] = 0
		square_dim[y] = square_row
		square_subtable_count[square_dim] = square_subtable_count[square_dim]+1
	end
	local square = square_row[x]
	if not square then
		square = {}
		square_subtable_count[square] = 0
		square_row[x] = square
		square_subtable_count[square_row] = square_subtable_count[square_row]+1
	end

	square.count = {peds =  0,cars =  0,boats =  0,planes =  0}
	square.list  = {peds = {},cars = {},boats = {},planes = {}}
	--[[
	square.count = {}
	square.list = {}
	for key,_ in pairs(population_group) do 
		square.count[key] = 0
		square.list[key] = {}
	end
	]]
	square.gen_mode = genmode
	return square
end

function destroyPopulationSquare(x,y,dim)
	if not square_population then return end
	local square_dim = square_population[dim]
	if not square_dim then return end
	local square_row = square_dim[y]
	if not square_row then return end
	local square = square_row[x]
	if not square then return end
	
	square_subtable_count[square] = nil
	square_row[x] = nil
	square_subtable_count[square_row] = square_subtable_count[square_row]-1
	if square_subtable_count[square_row] ~= 0 then return end
	square_subtable_count[square_row] = nil
	square_dim[y] = nil
	square_subtable_count[square_dim] = square_subtable_count[square_dim]-1
	if square_subtable_count[square_dim] ~= 0 then return end
	square_subtable_count[square_dim] = nil
	square_population[dim] = nil
	square_subtable_count[square_population] = square_subtable_count[square_population]-1
	if square_subtable_count[square_population] ~= 0 then return end
	square_subtable_count[square_population] = nil
	square_population = nil
end

function getPopulationSquare(x,y,dim)
	if not square_population then return end
	local square_dim = square_population[dim]
	if not square_dim then return end
	local square_row = square_dim[y]
	if not square_row then return end
	return square_row[x]
end

function generateTraffic()
	if not square_population then return end
	for dim,square_dim in pairs(square_population) do
		for y,square_row in pairs(square_dim) do
			for x,square in pairs(square_row) do
				local genmode = square.gen_mode
				if genmode == "spawn" then
					spawnTrafficInSquare(x,y,dim,"peds")
					spawnTrafficInSquare(x,y,dim,"cars")
					spawnTrafficInSquare(x,y,dim,"boats")
				
					--spawnTrafficInSquare(x,y,dim,"planes")
				
					--[[
					for key,_ in pairs(population_group) do 
						if traffic_density[key] > 0 then
							spawnTrafficInSquare(x,y,dim,tostring(key))
						end
					end
					]]
				elseif genmode == "despawn" then
					despawnTrafficInSquare(x,y,dim,"peds")
					despawnTrafficInSquare(x,y,dim,"cars")
					despawnTrafficInSquare(x,y,dim,"boats")
					--despawnTrafficInSquare(x,y,dim,"planes")
					--[[
					for key,_ in pairs(population_group) do 
						if traffic_density[key] > 0 then
							despawnTrafficInSquare(x,y,dim,tostring(key))
						end
					end
					]]
				end
			end
		end
	end
end

local skins = {7,9,10,11,12,13,14,15,16,17,19,20,21,22,23,24,25,26,27,28,29,30,31,32,33,34,35,36,37,38,39,40,41,43,44,46,47,48,49,50,53,54,55,56,57,58,59,60,61,66,67,68,69,70,71,72,73,76,77,78,79,82,83,84,88,89,91,93,94,95,96,98,100,101,120,121,122,123,124,125,126,127,128,129,130,131,132,133,134,135,136,141,142,143,147,148,150,151,153,157,158,159,160,161,162,170,181,182,183,184,185,186,187,188,196,197,198,199,200,201,202,206,210,214,215,216,217,218,219,220,221,222,223,224,225,226,227,228,229,231,232,233,234,235,236,239,240,241,242,247,248,250,253,254,255,258,259,260,261,262,263}
local vehicles = {581,462,521,463,522,461,468,586,602,496,401,518,527,589,419,587,533,474,545,517,410,600,436,439,549,491,445,507,585,466,492,546,551,516,467,526,547,405,580,550,566,540,421,529,438,420,428,499,414,422,482,418,582,413,440,543,478,554,579,400,404,489,505,479,458,536,575,534,567,535,576,412,402,542,603,475,429,541,415,480,562,565,411,559,561,560,506,451,558,555,477,500,423,438,420,552,498,574,509,481,510,525,552,508,483}
--vehicles = {581,462,521,463,522,461,468,586}
local boats = {472,473,493,595,452,446,453}
skincount,vehiclecount,boatcount = #skins,#vehicles,#boats

local count_needed = 0

local gangs = {
	[1] = { --Grove(LS)
		105,106,107
	},
	[2] = { --Ballas(LS)
		102,103,104
	},
	[3] = { --Vagos(LS)
		108,109,110
	},
	[4] = { --Rifa(SF)
		173,174,175,
	},
	[5] = { --Da Nang Boys(SF)
		121,122,123
	},
	[6] = { --Mafia(LV)
		111,112,113
	},
	[7] = { --Mountain Cloud Triad(LV)
		117,118,120
	},
	[8] = { --Varrio Los Aztecas(LS)
		114,115,116
	},

}
function spawnGangs(type) 
	local model = math.random(1,#gangs[type])
	return gangs[type][model]
end


function generateVehicleGroups(x,y,z)
	local type = "cars"
	local square_players = getElementsWithinRange (x,y,z,150,"player")
	function isAreaPlayerHasHeli() 
		for idx, p in ipairs (square_players) do 
			if players[p] and players[p].cop_heli then 
				return true
			end
		end
		return false
	end
	for idx,p in ipairs (square_players) do 
		local wanted = getPlayerWantedLevel(p)
		if wanted > 0 then 
			local need_heli = math.random(0,100)
			if need_heli > 60 and wanted > 2 and not isAreaPlayerHasHeli() and players[p].cop_heli == nil then 
				return "cop_heli"
			end
			--print("found player has wanted level.."..wanted)
			local choice = math.random(0,100)
			local p_cops = wanted * 14 
			if choice < p_cops then 
				if wanted == 3 then 
					if choice < p_cops * 0.7 then
						type = "cars_swat"
					else
						type = "cars_cop_2"
					end
				elseif wanted >= 4 and wanted < 6 then 
					if choice < p_cops * 0.7 then
						type = "cars_fbi"
					else
						type = "cars_swat"
					end
				elseif wanted == 6 then 
					if choice < p_cops * 0.7 then
						type = "cars_army"
					else
						type = "cars_tank"
					end
				else
					if choice < p_cops * 0.55 then
						type = "cars_cop"
					else
						type = "cars_cop_bike"
					end
				end
			elseif choice < p_cops + 10 then 
				type = "cars"
			end
			--print(type)
			return type
		end
	end

	-- Normal
	local choice = math.random(0,100)
	if choice > 0 and choice <= 10 then 
		type = choice > 5 and "cars_cop" or "cars_cop_bike"
	end

	return type
end
function generatePedGroups(x,y,z)
	local type = "peds"
	--createMarker (x,y,z, "cylinder", 40, 255, 255, 0, 170 )

	local square_players = getElementsWithinRange (x,y,z,100,"player")
	
	for idx,p in ipairs (square_players) do 
		local zone = getPlayerCurrentZoneName(p)
		if zone == "REST" then return "gang_army" end
		local wanted = getPlayerWantedLevel(p)
		if wanted > 0 then 
			--print("found player has wanted level.."..wanted)
			local choice = math.random(0,100)
			local p_cops = wanted * 13 
			if choice < p_cops then 
				type = wanted < 3 and "cops" or "cops_2"
			elseif choice < p_cops + 10 then 
				type = "gangs"
			end
			--print(type)
			return type
		end
	end

	-- Normal Case
	local choice = math.random(0,100)
	if choice > 0 and choice < 10 then 
		type = "gangs"
	end
	if choice > 10 and choice < 30 then 
		type = "cops"
	end

	return type
end



function spawnTrafficInSquare(x,y,dim,trtype)
	local square_tm_id = square_id[y] and square_id[y][x]
	if not square_tm_id then return end
	local square = square_population and square_population[dim] and square_population[dim][y] and square_population[dim][y][x]
	if not square then return end

	local conns = square_conns[square_tm_id][trtype]
	local cpos1 = square_cpos1[square_tm_id][trtype]
	local cpos2 = square_cpos2[square_tm_id][trtype]
	local cdens = square_cdens[square_tm_id][trtype]
	local ttden = square_ttden[square_tm_id][trtype]
	--iprint(cpos1)
	
	--[[
	if square.count[npcType] < 4 then
		count_needed = count_needed+math.max(ttden*traffic_density[trtype]-square.count[trtype]/8,0)
	else
		count_needed = 0
	end
	]]
	
	--iprint(square.count[npcType])
	--local sqr_den = square.count[trtype]
	--print(ttden*traffic_density[trtype]-square.count[trtype]/20)
	--print(square.count[trtype])

	--[[
	if square.count[trtype] == 0 then
		count_needed = count_needed+math.max(ttden*traffic_density[trtype]-square.count[trtype]/8,0)
	else
		count_needed = 0
	end
	]]
	if square.count[trtype] < 4 then
		count_needed = count_needed+math.max(ttden*traffic_density[trtype]-square.count[trtype]/20,0)
	end
	
	-- deal with gangs etc

	while count_needed > 0 do
		local sqpos = ttden*math.random()
		local connpos
		local connnum = 1

		connpos = cdens[connnum]

		if connpos == nil then 
			return
		end

		for connnum = 1,#cdens do 
			connpos = cdens[connnum]
			if connpos then
				if sqpos > connpos then
					sqpos = sqpos-connpos
				else
					connpos = sqpos/connpos
					break
				end
			end
		end
		--print(connnum)
		--[[
		while true do
			connpos = cdens[connnum]
			if connpos then
				if sqpos > connpos then
					sqpos = sqpos-connpos
				else
					connpos = sqpos/connpos
					break
				end
				connnum = connnum+1
			end
		end
		--]]

		local connid = conns[connnum]
		connpos = cpos1[connnum]*(1-connpos)+cpos2[connnum]*connpos

		local n1,n2,nb = conn_n1[connid],conn_n2[connid],conn_nb[connid]
		local ll,rl = conn_lanes.left[connid],conn_lanes.right[connid]
		local lanecount = ll+rl
		if lanecount == 0 and math.random(2) > 1 or lanecount ~= 0 and math.random(lanecount) > rl then
			n1,n2,ll,rl = n2,n1,rl,ll
			connpos = (nb and math.pi*0.5 or 1)-connpos
		end
		lane = rl == 0 and 0 or math.random(rl)
		local x,y,z
		local x1,y1,z1 = getNodeConnLanePos(n1,connid,lane,false)
		local x2,y2,z2 = getNodeConnLanePos(n2,connid,lane,true)
		local dx,dy,dz = x2-x1,y2-y1,z2-z1
		local rx = math.deg(math.atan2(dz,math.sqrt(dx*dx+dy*dy)))
		local rz
		if nb then
			local bx,by,bz = node_x[nb],node_y[nb],(z1+z2)*0.5
			local x1,y1,z1 = x1-bx,y1-by,z1-bz
			local x2,y2,z2 = x2-bx,y2-by,z2-bz
			local possin,poscos = math.sin(connpos),math.cos(connpos)
			x = bx+possin*x1+poscos*x2 + 1
			y = by+possin*y1+poscos*y2 + 1
			z = bz+possin*z1+poscos*z2
			local tx = -poscos
			local ty = possin
			tx,ty = x1*tx+x2*ty,y1*tx+y2*ty
			rz = -math.deg(math.atan2(tx,ty))
		else
			x = x1*(1-connpos)+x2*connpos + 1
			y = y1*(1-connpos)+y2*connpos + 1
			z = z1*(1-connpos)+z2*connpos
			rz = -math.deg(math.atan2(dx,dy))
		end
		
		local speed = conn_maxspeed[connid]/180
		local vmult = speed/math.sqrt(dx*dx+dy*dy+dz*dz)
		local vx,vy,vz = dx*vmult,dy*vmult,dz*vmult


		-- Generate Groups npcs
		if trtype == "peds" then 
			trtype = generatePedGroups(x,y,z)
		end

		if trtype == "cars" then 
			trtype = generateVehicleGroups(x,y,z)
			--trtype = "cars_cop"
		end



		local model = nil
	
		if trtype == "boats" then 
			model = boats[math.random(boatcount)]
		end
		
		--local colx,coly,colz = x,y,z+z_offset[model]
		local create = true

		if create and trtype == "gangs" then
			--local gang = math.random(1,8)
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			local zone = getPlayerCurrentZoneName(square_players[1])
			local gang = getGangidFromZone(zone)
			if not gang then return end
			
			local data = {
				peds = {},
				group = "GANG"..gang,
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}	
			for member = 1,3 do 
				data.peds[member] = gangs[gang][member]
			end
			spawnPopulationInSquare(x,y,z,dim,"peds",data)
			
		end
		if create and trtype == "gang_army" then
			local data = {
				peds = {287},
				group = "ARMY",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}	
			spawnPopulationInSquare(x,y,z,dim,"peds",data)
		end
		if create and trtype == "cops" then
			local cop_ped = 288
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentCityName(square_players[1])
				if zone == "LS" then 
					cop_ped = 280
				end
				if zone == "SF" then 
					cop_ped = 281
				end
				if zone == "LV" then 
					cop_ped = 282
				end
			end

			local data = {
				peds = {cop_ped},
				group = "COP",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"peds",data)
		end

		if create and trtype == "cops_2" then
			local cop_ped = 288
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentCityName(square_players[1])
				if zone == "LS" then 
					cop_ped = 280
				end
				if zone == "SF" then 
					cop_ped = 281
				end
				if zone == "LV" then 
					cop_ped = 282
				end
			end

			local data = {
				peds = {cop_ped},
				group = "COP_2",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"peds",data)
		end

		if create and trtype == "peds" then
			-- select model
			local model_ped = skins[math.random(skincount)]
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentZoneName(square_players[1])
				local traffic = generateTrafficInZone(zone)
				
				if traffic ~= nil and #traffic.peds > 0 then
					--print(zone)
					model_ped = traffic.peds[math.random(#traffic.peds)]
				end
			end
			--iprint(model_car)
			local data = {
				vehicle_rot = {rx,ry,rz},
				peds = {model_ped},
				group = model_ped == 287 and "ARMY" or "DEFAULT",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"peds",data)
		elseif create and trtype == "cars_cop" then -- car
			local vehicle_model = 599
			local vehicle_ped = 283
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentCityName(square_players[1])
				if zone == "LS" then 
					vehicle_model = 596
					vehicle_ped = 280
				end
				if zone == "SF" then 
					vehicle_model = 597
					vehicle_ped = 281
				end
				if zone == "LV" then 
					vehicle_model = 598
					vehicle_ped = 282
				end
			end


			local data = {
				vehicle_model = vehicle_model,
				vehicle_rot = {rx,ry,rz},
				peds = {vehicle_ped,vehicle_ped},
				group = "COP",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)
		elseif create and trtype == "cars_cop_2" then -- car
			local vehicle_model = 599
			local vehicle_ped = 283
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentCityName(square_players[1])
				if zone == "LS" then 
					vehicle_model = 596
					vehicle_ped = 280
				end
				if zone == "SF" then 
					vehicle_model = 597
					vehicle_ped = 281
				end
				if zone == "LV" then 
					vehicle_model = 598
					vehicle_ped = 282
				end
			end

			local data = {
				vehicle_model = vehicle_model,
				vehicle_rot = {rx,ry,rz},
				peds = {vehicle_ped,vehicle_ped},
				group = "COP_2",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)

		elseif create and trtype == "cars_cop_bike" then -- car
			local data = {
				vehicle_model = 523,
				vehicle_rot = {rx,ry,rz},
				peds = {284},
				group = "COP",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)

		elseif create and trtype == "cop_heli" and players[square.player] ~= nil then
			local data = {
				vehicle_model = 497,
				vehicle_rot = {rx,ry,rz},
				peds = {285},
				group = "SWAT",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
				syncer = square.player
			}
			spawnPopulationInSquare(x,y,z+20,dim,"cop_heli",data)
			--triggerClientEvent(square.player,"traffic.vehicle.heli",square.player,nil,heli,0.2)
		
		elseif create and trtype == "cars_army" then
			local data = {
				vehicle_model = 470,
				vehicle_rot = {rx,ry,rz},
				peds = {287,287,287,287},
				group = "ARMY",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)
		elseif create and trtype == "cars_tank" then
			local data = {
				vehicle_model = 432,
				vehicle_rot = {rx,ry,rz},
				peds = {287},
				group = "ARMY",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)
		elseif create and trtype == "cars_swat" then
			local data = {
				vehicle_model = 427,
				vehicle_rot = {rx,ry,rz},
				peds = {285,285,285,285},
				group = "SWAT",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)
		elseif create and trtype == "cars_fbi" then
			local data = {
				vehicle_model = 490,
				vehicle_rot = {rx,ry,rz},
				peds = {286,286,286,286},
				group = "FBI",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)

		elseif create and trtype == "cars" then
			-- select model
			local model_car = vehicles[math.random(vehiclecount)]
			--local model_car = 411
			local model_ped = skins[math.random(skincount)]
			local square_players = getElementsWithinRange (x,y,z,100,"player")
			if square_players[1] ~= nil then
				local zone = getPlayerCurrentZoneName(square_players[1])

				local traffic = generateTrafficInZone(zone)

				if traffic ~= nil and #traffic.cars >0 and #traffic.peds > 0 then
					model_car = traffic.cars[math.random(#traffic.cars)]
					model_ped = traffic.peds[math.random(#traffic.peds)]
					
				end
			end
			--iprint(model_car)
			local data = {
				vehicle_model = model_car,
				vehicle_rot = {rx,ry,rz},
				peds = {model_ped},
				group = "DEFAULT",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)

		elseif create and trtype == "boats" then -- add boats (by Nurupo)

			local data = {
				vehicle_model = model,
				vehicle_rot = {rx,ry,rz},
				peds = {skins[math.random(skincount)]},
				group = "DEFAULT",
				n1 = n1,
				n2 = n2,
				nb = nb,
				vx = vx,
				vy = vy,
				vz = vz,
			}
			spawnPopulationInSquare(x,y,z,dim,"cars",data)

		end

		if trtype == "cops" or trtype == "gangs" or trtype == "cops_2" or trtype == "gang_army" then 
			trtype = "peds"
		end
		if trtype == "cars_cop" or trtype == "cars_cop_2" or trtype == "cars_cop_bike" or trtype == "cop_heli" or trtype == "cars_swat" or trtype == "cars_fbi" or trtype == "cars_army" or trtype == "cars_tank" then 
			trtype = "cars"
		end
		square.count[trtype] = square.count[trtype]+1
		count_needed = count_needed-1

	end
end

function removePedFromListOnDestroy(type)
	for timer,exists in pairs(element_timers[source]) do
		killTimer(timer)
	end
	element_timers[source] = nil
	population[type][source] = nil
end

function removeDeadPed()
	element_timers[source][setTimer(destroyElement,DISTORY_TIME,1,source)] = true
end

function removeCarFromListOnDestroy()
	for timer,exists in pairs(element_timers[source]) do
		killTimer(timer)
	end
	element_timers[source] = nil
	population.cars[source] = nil
end

function removeDestroyedCar()
	element_timers[source][setTimer(destroyElement,DISTORY_TIME,1,source)] = true
end

function despawnTrafficInSquare(x,y,dim,trtype)
	local square = square_population and square_population[dim] and square_population[dim][y] and square_population[dim][y][x]
	if not square then return end

	if trtype == "peds" then
		for element,exists in pairs(square.list[trtype]) do
			destroyElement(element)
		end
	else
		for element,exists in pairs(square.list[trtype]) do
			local occupants = getVehicleOccupants(element)
			local destroy = true
			for seat,ped in pairs(occupants) do
				if not population.peds[ped] then destroy = false end
			end
			if destroy then
				destroyElement(element)
				for seat,ped in pairs(occupants) do
					destroyElement(ped)
				end
			end
		end
	end
end