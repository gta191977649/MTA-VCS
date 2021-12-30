function initPathRendering()
	render_area_size = 8
	render_conns,render_nodes = true,true
	addEventHandler("onClientHUDRender",root,renderPaths)
	addCommandHandler("renderconns",toggleRenderConns)
	addCommandHandler("rendernodes",toggleRenderNodes)
	addCommandHandler("renderarea",setAreaSize)
	cx_prev,cy_prev = 0,0
	render_area_size_prev = 0
end

function toggleRenderConns()
	render_conns = not render_conns or nil
end

function toggleRenderNodes()
	render_nodes = not render_nodes or nil
end

function setAreaSize(cmdname,size)
	size = tonumber(size)
	if not size or size < 0 then
		outputChatBox("Wrong size specified")
		return
	end
	render_area_size = size
end

local map_name_color = tocolor(255,255,192,255)

function renderPaths()
	streamConnsInAndOut()
	if render_conns then renderConns() end
	if render_nodes then renderNodes() end

	local w,h = guiGetScreenSize()
	local name = getFakeElementData(name_root,"name")
	drawOutlinedText(w-224,h*0.3,"Map name: "..tostring(name),map_name_color,"left","top")
end

function streamConnsInAndOut()
	local cx,cy = getCameraMatrix()
	cx,cy = math.floor(cx/32),math.floor(cy/32)
	local y1,y2 = cy-render_area_size,cy+render_area_size
	local x1,x2 = cx-render_area_size,cx+render_area_size
	local y1_prev,y2_prev = cy_prev-render_area_size_prev,cy_prev+render_area_size_prev
	local x1_prev,x2_prev = cx_prev-render_area_size_prev,cx_prev+render_area_size_prev
	cx_prev,cy_prev = cx,cy
	render_area_size_prev = render_area_size

	for grid_y = y1_prev,y2_prev do
		local grid_row = grid_nodes[grid_y]
		if grid_row then
			for grid_x = x1_prev,x2_prev do
				if grid_x < x1 or grid_x > x2 or grid_y < y1 or grid_y > y2 then
					local grid_square = grid_row[grid_x]
					if grid_square and grid_streamedin[grid_square] then
						streamOutGridSquare(grid_square)
					end
				end
			end
		end
	end

	for grid_y = y1,y2 do
		local grid_row = grid_nodes[grid_y]
		if grid_row then
			for grid_x = x1,x2 do
				local grid_square = grid_row[grid_x]
				if grid_square and not grid_streamedin[grid_square] then
					streamInGridSquare(grid_square)
				end
			end
		end
	end
end

function streamInGridSquare(square)
	grid_streamedin[square] = true
	for n1,exists in pairs(square) do
		for n2,conn in pairs(node_conns[n1]) do
			if getFakeElementType(conn) == "npcpaths:conn" then
				streamInConn(conn)
			end
		end
	end
end

function streamOutGridSquare(square)
	grid_streamedin[square] = nil
	for n1,exists in pairs(square) do
		for n2,conn in pairs(node_conns[n1]) do
			if getFakeElementType(conn) == "npcpaths:conn" then
				local x2,y2 = getNodePosition(n2)
				x2,y2 = math.floor(x2/32),math.floor(y2/32)
				local streamed2 = grid_nodes[y2]
				streamed2 = streamed2 and streamed2[x2]
				streamed2 = streamed2 and grid_streamedin[streamed2]
				if not streamed2 then
					streamOutConn(conn)
				end
			end
		end
	end
end

function renderNodes()
	local active = getActiveNode()
	local selected = getSelectedNode()
	local color_white = tocolor(255,255,255,255)
	local cx,cy = getCameraMatrix()
	cx,cy = math.floor(cx/32),math.floor(cy/32)
	local y1,y2 = cy-render_area_size,cy+render_area_size
	local x1,x2 = cx-render_area_size,cx+render_area_size
	for grid_y = y1,y2 do
		local grid_row = grid_nodes[grid_y]
		if grid_row then
			for grid_x = x1,x2 do
				local grid_square = grid_row[grid_x]
				if grid_square then
					for node,exists in pairs(grid_square) do
						local x,y,z = getNodePosition(node)
						local rx,ry = getNodeRotation(node)

						local fzoff = 0.25
						for forb,exists in pairs(node_forbs[node]) do
							local c1,c2 = getForbConns(forb)
							local n11,n12 = getConnNodes(c1)
							local n21,n22 = getConnNodes(c2)
							local n1 = n11 ~= node and n11 or n12
							local n2 = n21 ~= node and n21 or n22
							local x1,y1,z1 = getNodePosition(n1)
							local x2,y2,z2 = getNodePosition(n2)
							drawForb(x,y,z+fzoff,x1,y1,z1+fzoff,x2,y2,z2+fzoff)
							fzoff = fzoff+0.25
						end

						drawNode(x,y,z,rx,ry,(node == active or node == selected) and tocolor(255,0,0,255) or color_white)
					end
				end
			end
		end
	end
end

function renderConns()
	local active = getActiveConn()
	local selected = getSelectedConn()
	local color_ped   = {255,0,0}
	local color_car   = {0,0,255}
	local color_boat  = {0,255,0}
	local color_plane = {255,0,255}
	local colors = {color_ped,color_car,color_boat,color_plane}
	local color_active = tocolor(255,255,0,255)

	local trlit_red = tocolor(255,96,0,255)
	local trlit_green = tocolor(0,255,0,255)
	local tlstate = getTrafficLightState()
	local tlcolor_ns = (tlstate == 0 or tlstate == 5 or tlstate == 8) and trlit_green or trlit_red
	local tlcolor_we = (tlstate == 3 or tlstate == 5 or tlstate == 7) and trlit_green or trlit_red
	local tlcolor_ped = tlstate == 2 and trlit_green or trlit_red

	for conn,lines in pairs(conn_lines) do
		local nb = getConnBend(conn)
		local trtype = getConnType(conn)
		local color,colorop
		if conn == active or conn == selected then
			color,colorop = color_active,color_active
		else
			local r,g,b = unpack(colors[trtype])
			local a = getConnDensity(conn)*148+32
			color = tocolor(r,g,b,math.max(32,math.min(a,255)))
			colorop = tocolor(r,g,b,255)
		end
		if nb then
			local bx,by = getNodePosition(nb)
			for linenum,line in ipairs(lines) do
				drawConnectionBend(bx,by,line[1],line[2],line[3],line[4],line[5],line[6],color)
			end
		else
			for linenum,line in ipairs(lines) do
				drawConnectionLine(line[1],line[2],line[3],line[4],line[5],line[6],color)
			end
		end
		local ll,rl = getConnLaneCount(conn)
		local l1,l2 = unpack(getConnLights(conn))
		local arrows = conn_arrows[conn]
		if arrows then
			for arrownum,arrow in ipairs(arrows) do
				local ax1,ay1,az1,ax2,ay2,az2 = arrow[1],arrow[2],arrow[3],arrow[4],arrow[5],arrow[6]
				drawConnectionArrow(ax1,ay1,az1,ax2,ay2,az2,color)
						if arrow[7] == 1 then
				if l1 ~= CONN_LIT_NONE then
						drawTrafficLightMarker(ax1,ay1,az1,ax2,ay2,az2,l1,l1 == CONN_LIT_NS and tlcolor_ns or l1 == CONN_LIT_WE and tlcolor_we or tlcolor_ped)
					end
				else
					if l2 ~= CONN_LIT_NONE then
						drawTrafficLightMarker(ax1,ay1,az1,ax2,ay2,az2,l2,l2 == CONN_LIT_NS and tlcolor_ns or l2 == CONN_LIT_WE and tlcolor_we or tlcolor_ped)
					end
				end
			end
		end
		if lines and ll == 0 and rl == 0 then
			local x1,y1,z1,x2,y2,z2 = unpack(lines[1])
			if l1 ~= CONN_LIT_NONE then
				drawTrafficLightMarker(x2,y2,z2,x1,y1,z1,l1,l1 == CONN_LIT_NS and tlcolor_ns or l1 == CONN_LIT_WE and tlcolor_we or tlcolor_ped)
			end
			if l2 ~= CONN_LIT_NONE then
				drawTrafficLightMarker(x1,y1,z1,x2,y2,z2,l2,l2 == CONN_LIT_NS and tlcolor_ns or l2 == CONN_LIT_WE and tlcolor_we or tlcolor_ped)
			end
		end
		if trtype ~= 1 then
			local n1,n2 = getConnNodes(conn)
			local x,y,z
			local x1,y1,z1 = getNodePosition(n1)
			local x2,y2,z2 = getNodePosition(n2)
			z = (z1+z2)*0.5
			if nb then
				local bx,by = getNodePosition(nb)
				x,y = ((x1+x2)*0.5-bx)*1.41421356237+bx,((y1+y2)*0.5-by)*1.41421356237+by
			else
				x,y = (x1+x2)*0.5,(y1+y2)*0.5
			end
			drawTextIn3D(x,y,z,tostring(getConnMaxSpeed(conn)),colorop)
		end
	end
end

