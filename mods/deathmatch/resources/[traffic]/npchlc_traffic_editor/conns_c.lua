function initConns()
	node_conns = {}
	node_bends = {}
	node_llanes = {}
	node_rlanes = {}
	addFakeEventHandler("traffic_edit:onClientNodeCreate",node_root,initNodeConnsInfoOnCreate)
	addFakeEventHandler("onClientElementDestroy",node_root,uninitNodeConnsInfo)

	conn_streamedin = {}
	conn_lines = {}
	conn_arrows = {}
	addFakeEventHandler("traffic_edit:onClientConnCreate",conn_root,initConnLinesOnCreate)
	addFakeEventHandler("onClientElementDestroy",conn_root,uninitConnLines)
	addFakeEventHandler("onClientElementDataChange",node_root,updateConnLinesOnNodeChange)
	addFakeEventHandler("onClientElementDataChange",conn_root,updateConnLinesOnConnChange)

	local nodes = getFakeElementChildren(node_root)
	local conns = getFakeElementChildren(conn_root)
	for nodenum,node in ipairs(nodes) do
		initNodeConnsInfo(node)
	end
	for connnum,conn in ipairs(conns) do
		initConnLines(conn)
	end
end

function initNodeConnsInfo(node)
	node_conns[node] = {}
	node_bends[node] = {}
	node_llanes[node] = 0
	node_rlanes[node] = 0
end

function initNodeConnsInfoOnCreate()
	initNodeConnsInfo(fake_source)
end

function uninitNodeConnsInfo()
	node_conns[fake_source] = nil
	node_bends[fake_source] = nil
	node_llanes[fake_source] = nil
	node_rlanes[fake_source] = nil
end

function updateNodeLaneCount(node)
	local conns = node_conns[node]
	if not conns then return end
	local llanes,rlanes
	for nextnode,conn in pairs(conns) do
		local n1,n2 = getConnNodes(conn)
		local nb = getConnBend(conn)
		local ll,rl = getConnLaneCount(conn)

		local x1,y1 = getNodePosition(node)
		local x2,y2 = getNodePosition(nextnode)
		if nb then
			local bx,by = getNodePosition(nb)
			x2,y2 = x1+x2-bx,y1+y2-by
		end
		if n1 ~= node then x1,y1,x2,y2 = x2,y2,x1,y1 end

		local rx,ry = getNodeRotation(node)
		x2,y2 = x2-x1,y2-y1
		if rx*y2-ry*x2 < 0 then
			ll,rl = rl,ll
		end

		if ll ~= 0 or rl == 0 then
			llanes = not llanes and ll or math.min(llanes,ll)
		end
		if rl ~= 0 or ll == 0 then
			rlanes = not rlanes and rl or math.min(rlanes,rl)
		end
	end
	node_llanes[node] = llanes or 0
	node_rlanes[node] = rlanes or 0
	for nextnode,conn in pairs(conns) do
		updateConnLines(conn)
	end
end

function updateConnLinesOnConnChange(dataname)
	if dataname == "nb" or dataname == "llanes" or dataname == "rlanes" or dataname == "type" then
		local n1,n2 = getConnNodes(fake_source)
		updateNodeLaneCount(n1)
		updateNodeLaneCount(n2)
	end
end

function updateConnLinesOnNodeChange()
	for conn,bent in pairs(node_bends[fake_source]) do
		local n1,n2 = getConnNodes(conn)
		updateNodeLaneCount(n1)
		updateNodeLaneCount(n2)
	end
	updateNodeLaneCount(fake_source)
	for nextnode,conn in pairs(node_conns[fake_source]) do
		updateNodeLaneCount(nextnode)
	end
end

function initConnLines(conn)
	local n1,n2 = getConnNodes(conn)
	node_conns[n1][n2] = conn
	node_conns[n2][n1] = conn
	updateNodeLaneCount(n1)
	updateNodeLaneCount(n2)
	local x1,y1 = getNodePosition(n1)
	local x2,y2 = getNodePosition(n2)
	x1,y1,x2,y2 = math.floor(x1/32),math.floor(y1/32),math.floor(x2/32),math.floor(y2/32)
	conn_streamedin[conn] = (grid_streamedin[grid_nodes[y1][x1]] or grid_streamedin[grid_nodes[y2][x2]]) and true or nil
	updateConnLines(conn)
end

function initConnLinesOnCreate()
	initConnLines(fake_source)
end

function uninitConnLines()
	if fake_source == fake_this then return end
	streamOutConn(fake_source)
	local n1,n2 = getConnNodes(fake_source)
	local nb = getConnBend(fake_source)
	if node_conns[n1] then node_conns[n1][n2] = nil end
	if node_conns[n2] then node_conns[n2][n1] = nil end
	if node_bends[nb] then node_bends[nb][fake_source] = nil end
	updateNodeLaneCount(n1)
	updateNodeLaneCount(n2)
end

function streamInConn(conn)
	if conn_streamedin[conn] then return end
	conn_streamedin[conn] = true
	updateConnLines(conn)
end

function streamOutConn(conn)
	if not conn_streamedin[conn] then return end
	conn_streamedin[conn] = nil
	updateConnLines(conn)
end

function updateConnLines(conn)
	if not conn_streamedin[conn] then
		conn_lines[conn] = nil
		conn_arrows[conn] = nil
		return
	end

	local n1,n2 = getConnNodes(conn)
	local nb = getConnBend(conn)

	local x1,y1,z1 = getNodePosition(n1)
	local x2,y2,z2 = getNodePosition(n2)
	local bx,by,bz
	if nb then
		bx,by = getNodePosition(nb)
		bz = (z1+z2)*0.5
	end

	local lines,arrows = {},{}
	conn_lines[conn] = lines
	conn_arrows[conn] = arrows

	local ll1,rl1 = node_llanes[n1],node_rlanes[n1]
	local ll2,rl2 = node_llanes[n2],node_rlanes[n2]

	local rx1,ry1 = getNodeRotation(n1)
	local rx2,ry2 = getNodeRotation(n2)
	do
		--local dirx,diry = nb and (x1+x2-bx)-x1 or x2-x1,nb and (y1+y2-by)-y1 or y2-y1
		local dirx,diry = x2-(nb and bx or x1),y2-(nb and by or y1)
		if -dirx*ry1+diry*rx1 < 0 then
			rx1,ry1 = -rx1,-ry1
			ll1,rl1 = rl1,ll1
		end
	end
	do
		--local dirx,diry = nb and x2-(x1+x2-bx) or x2-x1,nb and y2-(y1+y2-by) or y2-y1
		local dirx,diry = (nb and bx or x2)-x1,(nb and by or y2)-y1
		if -dirx*ry2+diry*rx2 < 0 then
			rx2,ry2 = -rx2,-ry2
			ll2,rl2 = rl2,ll2
		end
	end

	local ll,rl = getConnLaneCount(conn)
	local connlanes = ll+rl

	if connlanes == 0 then
		table.insert(lines,{x1,y1,z1,x2,y2,z2})
	else
		local laneoff1 = ll1-rl1
		local laneoff2 = ll2-rl2
		for lanenum = 1,math.min(ll,math.max(ll1,ll2)) do
			local lanepos1 = ll1 == 0 and 0 or laneoff1-(math.min(ll1,lanenum)*2-1)
			local lanepos2 = ll2 == 0 and 0 or laneoff2-(math.min(ll2,lanenum)*2-1)
			local lx1,ly1 = x1+rx1*lanepos1,y1+ry1*lanepos1
			local lx2,ly2 = x2+rx2*lanepos2,y2+ry2*lanepos2
			table.insert(lines,{lx1,ly1,z1,lx2,ly2,z2})
			local sx,sy,sz
			if nb then
				sx,sy,sz = lx1+lx2-bx,ly1+ly2-by,bz
			else
				sx,sy,sz = lx2,ly2,z2
			end
			table.insert(arrows,{sx,sy,sz,lx1,ly1,z1,1})
		end
		for lanenum = 1,math.min(rl,math.max(rl1,rl2)) do
			local lanepos1 = rl1 == 0 and 0 or laneoff1+(math.min(rl1,lanenum)*2-1)
			local lanepos2 = rl2 == 0 and 0 or laneoff2+(math.min(rl2,lanenum)*2-1)
			local lx1,ly1 = x1+rx1*lanepos1,y1+ry1*lanepos1
			local lx2,ly2 = x2+rx2*lanepos2,y2+ry2*lanepos2
			table.insert(lines,{lx1,ly1,z1,lx2,ly2,z2})
			local sx,sy,sz
			if nb then
				sx,sy,sz = lx1+lx2-bx,ly1+ly2-by,bz
			else
				sx,sy,sz = lx1,ly1,z1
			end
			table.insert(arrows,{sx,sy,sz,lx2,ly2,z2,2})
		end
		if getConnType(conn) == CONN_TYPE_CARS then
			local sx,sy,sz,lx1,ly1,lx2,ly2
			local rlen1,rlen2 = math.sqrt(rx1*rx1+ry1*ry1),math.sqrt(rx2*rx2+ry2*ry2)
			if ll > 0 then
				local lanepos1 = ll1 == 0 and 0 or laneoff1-(ll1*2-1+1.8/rlen1)
				local lanepos2 = ll2 == 0 and 0 or laneoff2-(ll2*2-1+1.8/rlen2)
				lx1,ly1 = x1+rx1*lanepos1,y1+ry1*lanepos1
				lx2,ly2 = x2+rx2*lanepos2,y2+ry2*lanepos2
				table.insert(lines,{lx1,ly1,z1,lx2,ly2,z2})
				if nb then
					sx,sy,sz = lx1+lx2-bx,ly1+ly2-by,bz
				else
					sx,sy,sz = lx2,ly2,z2
				end
				table.insert(arrows,{sx,sy,sz,lx1,ly1,z1,1})
			end
			if rl > 0 then
				local lanepos1 = rl1 == 0 and 0 or laneoff1+(rl1*2-1+1.8/rlen1)
				local lanepos2 = rl2 == 0 and 0 or laneoff2+(rl2*2-1+1.8/rlen2)
				lx1,ly1 = x1+rx1*lanepos1,y1+ry1*lanepos1
				lx2,ly2 = x2+rx2*lanepos2,y2+ry2*lanepos2
				table.insert(lines,{lx1,ly1,z1,lx2,ly2,z2})
				if nb then
					sx,sy,sz = lx1+lx2-bx,ly1+ly2-by,bz
				else
					sx,sy,sz = lx1,ly1,z1
				end
				table.insert(arrows,{sx,sy,sz,lx2,ly2,z2,2})
			end
		end
	end
end

function getConnUnderCursor()
	local mx,my = getCursorPosition()
	if not mx then return end
	local sw,sh = guiGetScreenSize()
	mx,my = mx*sw,my*sh
	local nearest_conn
	local nearest_dist = 16

	for conn,lines in pairs(conn_lines) do
		local nb = getConnBend(conn)
		if nb then
			local bx,by = getNodePosition(nb)
			for linenum,line in ipairs(lines) do
				local lx1,ly1,lz1,lx2,ly2,lz2 = unpack(line)
				local bz = (lz1+lz2)*0.5
				local mouse_inside = true
				--[[do
					local bx,by,bz = lx1+lx2-bx,ly1+ly2-by,lz1+lz2-bz
					local sx1,sy1 = getScreenFromWorldPosition(lx1,ly1,lz1,0x7FFFFFFF)
					local sx2,sy2 = getScreenFromWorldPosition(lx2,ly2,lz2,0x7FFFFFFF)
					local sx3,sy3 = getScreenFromWorldPosition(bx ,by ,bz ,0x7FFFFFFF)
					local x1,y1 = math.min(sx1,sx2,sx3)-16,math.min(sy1,sy2,sy3)-16
					local x2,y2 = math.max(sx1,sx2,sx3)+16,math.max(sy1,sy2,sy3)+16
					mouse_inside = x1 <= mx and mx <= x2 and y1 <= my and my <= y2
				end]]
				
				if mouse_inside then
					local x1,y1 = getScreenFromWorldPosition(lx1,ly1,lz1,0x7FFFFFFF)
					lx1,ly1,lz1 = lx1-bx,ly1-by,lz1-bz
					lx2,ly2,lz2 = lx2-bx,ly2-by,lz2-bz
					local math_sin,math_cos = math.sin,math.cos
					local delta_a = math.pi*0.0625
					for a = delta_a,(math.pi+delta_a)*0.5,delta_a do
						local sina,cosa = math_sin(a),math_cos(a)
						local x2,y2 = getScreenFromWorldPosition(bx+lx1*cosa+lx2*sina,by+ly1*cosa+ly2*sina,bz+lz1*cosa+lz2*sina,0x7FFFFFFF)
						if x1 and x2 then
							local x2,y2 = x2-x1,y2-y1
							local mx,my = mx-x1,my-y1

							local len = math.sqrt(x2*x2+y2*y2)
							local rx = (mx*y2-my*x2)/len
							local ry = (mx*x2+my*y2)/len
							rx = math.abs(rx)

							local dist = math.max(rx,ry-len,-ry)
							if dist < nearest_dist then
								nearest_conn = conn
								nearest_dist = dist
							end
						end
						x1,y1 = x2,y2
					end
				end
			end
		else
			for linenum,line in ipairs(lines) do
				local x1,y1 = getScreenFromWorldPosition(line[1],line[2],line[3],0x7FFFFFFF)
				if x1 then
					local x2,y2 = getScreenFromWorldPosition(line[4],line[5],line[6],0x7FFFFFFF)
					if x2 then
						x2,y2 = x2-x1,y2-y1
						local mx,my = mx-x1,my-y1

						--[[local yx,yy = x2,y2
						local xx,xy = yy,-yx
						local rx = (mx*yy-my*yx)/(xx*yy-xy*yx)
						local ry = (mx*xy-my*xx)/(yx*xy-yy*xx)

						local len = math.sqrt(x2*x2+y2*y2)
						rx,ry = math.abs(rx)*len,ry*len]]

						local len = math.sqrt(x2*x2+y2*y2)
						local rx = (mx*y2-my*x2)/len
						local ry = (mx*x2+my*y2)/len
						rx = math.abs(rx)

						local dist = math.max(rx,ry-len,-ry)
						if dist < nearest_dist then
							nearest_conn = conn
							nearest_dist = dist
						end
					end
				end
			end
		end
	end
	return nearest_conn
end

function toggleConnSearchMode(on)
	on = on and true or nil
	if conn_search_mode == on then return end
	conn_search_mode = on
	if on then
		addEventHandler("onClientPreRender",root,searchForConnUnderCursor)
	else
		removeEventHandler("onClientPreRender",root,searchForConnUnderCursor)
		conn_active = nil
	end
end

function searchForConnUnderCursor()
	conn_active = getConnUnderCursor()
end

function getActiveConn()
	return conn_active
end

function setSelectedConn(conn)
	conn_selected = conn
end

function getSelectedConn()
	return conn_selected
end

