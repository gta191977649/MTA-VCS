

function initTrafficMap()	
	square_id = {}
	square_conns = {}
	square_cpos1 = {}
	square_cpos2 = {}
	square_cdens = {}
	square_ttden = {}
end

function addConnToTrafficMap(connid)
	local n1,n2,nb = conn_n1[connid],conn_n2[connid],conn_nb[connid]
	local x1,y1 = node_x[n1],node_y[n1]
	local x2,y2 = node_x[n2],node_y[n2]
	local density = conn_density[connid]
	do
		local lanes = conn_lanes.left[connid]+conn_lanes.right[connid]
		density = density*(lanes == 0 and 1 or lanes)
	end

	local SQUARE_SIZE = SQUARE_SIZE
	local getDistanceBetweenPoints2D = getDistanceBetweenPoints2D
	local addConnToSquare = addConnToSquare
	local math_min,math_max = math.min,math.max
	local math_floor,math_ceil = math.floor,math.ceil
	local math_abs,math_huge = math.abs,math.huge

	if nb then
		local bx,by = node_x[nb],node_y[nb]
		local mxx,mxy,myx,myy = x1-bx,y1-by,x2-bx,y2-by

		local det_inv = 1/(mxy*myx-mxx*myy)
		local ixx,ixy =  myy*det_inv, myx*det_inv
		local iyx,iyy = -mxy*det_inv,-mxx*det_inv

		local minx_alg = math_floor((bx+math_min(mxx,myx,mxx+myx)            )/SQUARE_SIZE)*SQUARE_SIZE
		local maxx_alg = math_floor((bx+math_max(mxx,myx,mxx+myx)+SQUARE_SIZE)/SQUARE_SIZE)*SQUARE_SIZE
		local miny_alg = math_floor((by+math_min(mxy,myy,mxy+myy)            )/SQUARE_SIZE)*SQUARE_SIZE
		local maxy_alg = math_floor((by+math_max(mxy,myy,mxy+myy)+SQUARE_SIZE)/SQUARE_SIZE)*SQUARE_SIZE

		local pos_list = {0,math.pi*0.5}

		for x = minx_alg,maxx_alg,SQUARE_SIZE do
			local pos1,pos2 = getArcAndLineCrossPos(x-bx,0-by,x-bx,SQUARE_SIZE-by,ixx,ixy,iyx,iyy)
			if pos1 and not pos_list[pos1] then table.insert(pos_list,pos1) pos_list[pos1] = true end
			if pos2 and not pos_list[pos2] then table.insert(pos_list,pos2) pos_list[pos2] = true end
		end
		for y = miny_alg,maxy_alg,SQUARE_SIZE do
			local pos1,pos2 = getArcAndLineCrossPos(0-bx,y-by,SQUARE_SIZE-bx,y-by,ixx,ixy,iyx,iyy)
			pos1,pos2 = pos1 and math.pi*0.5-pos1,pos2 and math.pi*0.5-pos2
			if pos1 and not pos_list[pos1] then table.insert(pos_list,pos1) pos_list[pos1] = true end
			if pos2 and not pos_list[pos2] then table.insert(pos_list,pos2) pos_list[pos2] = true end
		end

		table.sort(pos_list)
		for posnum = 1,#pos_list-1 do
			local pos1,pos2 = pos_list[posnum],pos_list[posnum+1]
			local posavg = (pos1+pos2)*0.5
			local possin,poscos = math.sin(posavg),math.cos(posavg)
			local sqx,sqy = bx+mxx*possin+myx*poscos,by+mxy*possin+myy*poscos
			sqx = math_floor(sqx/SQUARE_SIZE)
			sqy = math_floor(sqy/SQUARE_SIZE)

			local square = getSquare(sqx,sqy) or createSquare(sqx,sqy)
			local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*0.5*(pos2-pos1)*density
			addConnToSquare(square,connid,pos1,pos2,len)
		end
	else
		local miny = math_min(y1,y2)
		local maxy = math_max(y1,y2)
		local miny_alg = math_floor(miny/SQUARE_SIZE)
		local maxy_alg = math_floor(maxy/SQUARE_SIZE)
		for sqy = miny_alg,maxy_alg do
			local y = sqy*SQUARE_SIZE
			local row_y1 = math_min(maxy,math_max(miny,y))
			local row_y2 = math_min(maxy,math_max(miny,y+SQUARE_SIZE))
			local row_pos1 = (row_y1-y1)/(y2-y1)
			local row_pos2 = (row_y2-y1)/(y2-y1)
			if row_pos1 ~= row_pos1 or math_abs(row_pos1) == math_huge then
				row_pos1,row_pos2 = 0,1
			end
			local row_x1 = x1*(1-row_pos1)+x2*row_pos1
			local row_x2 = x1*(1-row_pos2)+x2*row_pos2

			local minx = math_min(row_x1,row_x2)
			local maxx = math_max(row_x1,row_x2)
			local minx_alg = math_floor(minx/SQUARE_SIZE)
			local maxx_alg = math_floor(maxx/SQUARE_SIZE)
			for sqx = minx_alg,maxx_alg do
				local x = sqx*SQUARE_SIZE
				local sqr_x1 = math_min(maxx,math_max(minx,x))
				local sqr_x2 = math_min(maxx,math_max(minx,x+SQUARE_SIZE))
				local sqr_pos1 = (sqr_x1-row_x1)/(row_x2-row_x1)
				local sqr_pos2 = (sqr_x2-row_x1)/(row_x2-row_x1)
				if sqr_pos1 ~= sqr_pos1 or math_abs(sqr_pos1) == math_huge then
					sqr_pos1,sqr_pos2 = 0,1
				end
				local sqr_y1 = row_y1*(1-sqr_pos1)+row_y2*sqr_pos1
				local sqr_y2 = row_y1*(1-sqr_pos2)+row_y2*sqr_pos2
				local square = getSquare(sqx,sqy) or createSquare(sqx,sqy)
				local pos1 = row_pos1+(row_pos2-row_pos1)*sqr_pos1
				local pos2 = row_pos1+(row_pos2-row_pos1)*sqr_pos2
				local len = getDistanceBetweenPoints2D(sqr_x1,sqr_y1,sqr_x2,sqr_y2)*density
				addConnToSquare(square,connid,pos1,pos2,len)
			end
		end
	end
end

function getArcAndLineCrossPos(x1,y1,x2,y2,ixx,ixy,iyx,iyy)
	local rx  = x1*ixx+y1*ixy
	local ry  = x1*iyx+y1*iyy
	local ryx = x2*ixx+y2*ixy-rx
	local ryy = x2*iyx+y2*iyy-ry

	local rmult = 1/math.sqrt(ryx*ryx+ryy*ryy)
	ryx,ryy = ryx*rmult,ryy*rmult
	local nry = (0-rx)*ryx+(0-ry)*ryy

	local nx = rx+ryx*nry
	local ny = ry+ryy*nry
	local ndist = math.sqrt(nx*nx+ny*ny)
	local adddist = math.sqrt(1-ndist*ndist)

	local nx1,ny1 = nx+ryx*adddist,ny+ryy*adddist
	local nx2,ny2 = nx-ryx*adddist,ny-ryy*adddist

	local pos1 = nx1 >= 0 and ny1 >= 0 and math.asin(ny1)
	local pos2 = nx2 >= 0 and ny2 >= 0 and math.asin(ny2)

	return pos1 or pos2 or nil,pos1 and pos2 or nil
end

function createSquare(x,y)
	local row = square_id[y]
	if not row then
		row = {}
		square_id[y] = row
	end
	local sqid = row[x]
	if not sqid then
		sqid = #square_conns+1
		row[x] = sqid
		
		
		square_conns[sqid] = {peds = {},cars = {},boats = {},planes = {}}
		square_cpos1[sqid] = {peds = {},cars = {},boats = {},planes = {}}
		square_cpos2[sqid] = {peds = {},cars = {},boats = {},planes = {}}
		square_cdens[sqid] = {peds = {},cars = {},boats = {},planes = {}}
		square_ttden[sqid] = {peds =  0,cars =  0,boats =  0,planes =  0}
	
		--[[
			square_conns[sqid] = {}
			square_cpos1[sqid] = {}
			square_cpos2[sqid] = {}
			square_cdens[sqid] = {}
			square_ttden[sqid] = {}
			for key,_ in pairs(population_group) do 
				square_conns[sqid][key] = {}
				square_cpos1[sqid][key] = {}
				square_cpos2[sqid][key] = {}
				square_cdens[sqid][key] = {}
				square_ttden[sqid][key] = 0
			end
		]]
		
		return sqid
	end
end

function getSquare(x,y)
	local row = square_id[y]
	if not row then return end
	local sqid = row[x]
	if not sqid then return end
	return sqid
end

function addConnToSquare(square,conn,pos1,pos2,len)
	local conntype = conn_type[conn]
	local connnum = #square_conns[square][conntype]+1
	square_conns[square][conntype][connnum] = conn
	square_cpos1[square][conntype][connnum] = pos1
	square_cpos2[square][conntype][connnum] = pos2
	square_cdens[square][conntype][connnum] = len

	square_ttden[square][conntype] = square_ttden[square][conntype]+len
end
function getPlayerNearestSquare(player) 
	local size = 4
	local x,y,z = getElementPosition(player)
	local dim = getElementDimension(player)
	x,y = math.floor(x/SQUARE_SIZE),math.floor(y/SQUARE_SIZE)
	for sy = y-size,y+size do 
		for sx = x-size,x+size do
			local square = getPopulationSquare(sx,sy,dim)
			if square then return square,x,y end
		end
	end
	return nil
end
function findSpawnPositionFromSquare(x,y,traffic_type)
	local square_tm_id = square_id[y] and square_id[y][x]
	if not square_tm_id then return nil end


	local conns = square_conns[square_tm_id][traffic_type]
	local cpos1 = square_cpos1[square_tm_id][traffic_type]
	local cpos2 = square_cpos2[square_tm_id][traffic_type]
	local cdens = square_cdens[square_tm_id][traffic_type]
	local ttden = square_ttden[square_tm_id][traffic_type]

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
	return x,y,z,rz
end
function spawnPedAtPlayerNearestSquare(player,model)
	local sq,x,y = getPlayerNearestSquare(player)
	if sq then
		local x,y,z,rz = findSpawnPositionFromSquare(x,y,"peds")
		if x and y and z then 
			local ped = createPed(model,x,y,z+1)
			element_timers[ped] = {}
			population.peds[ped] = {
				group = "DEFAULT",
			}
			addEventHandler("onElementDestroy",ped,function() 
				removePedFromListOnDestroy("peds")
			end,false)
			iprint(sq)
			sq.count["peds"] = sq.count["peds"]+1
			return ped
		end
	end
	return false
end
function getPlayerNearestSquarePos(player)
	local sq,x,y = getPlayerNearestSquare(player)
	if sq then
		local x,y,z,rz = findSpawnPositionFromSquare(x,y,"peds")
		if x and y and z then 
			return x,y,z,rz
		end
	end
	return false
end
function getTrafficXY(x,y) 
	x,y = math.floor(x/SQUARE_SIZE),math.floor(y/SQUARE_SIZE)
	return x,y
end
--[[
addCommandHandler("traffic",function(player) 
	local ped = spawnPedAtPlayerNearestSquare(player,x,y,7)
	if not ped then print("not in a node") end
end)
]]