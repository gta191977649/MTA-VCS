function initNodes()
	grid_list_sizes = {}
	grid_nodes = {}
	grid_streamedin = {}

	addFakeEventHandler("traffic_edit:onClientNodeCreate",node_root,initNodeOnCreate)
	addFakeEventHandler("onClientElementDestroy",node_root,uninitNode)
	addFakeEventHandler("onClientElementDataChange",node_root,updateNodeGridPositionOnMove)

	local nodes = getFakeElementChildren(node_root)
	for nodenum,node in ipairs(nodes) do
		initNode(node)
	end
end

function addNodeToGrid(node,x,y)
	local row = grid_nodes[y]
	if not row then
		row = {}
		grid_nodes[y] = row
		grid_list_sizes[row] = 0
	end
	local square = row[x]
	if not square then
		grid_list_sizes[row] = grid_list_sizes[row]+1
		square = {}
		row[x] = square
		grid_list_sizes[square] = 0
	end
	local exists = square[node]
	if not exists then
		grid_list_sizes[square] = grid_list_sizes[square]+1
		square[node] = true
	end
end

function removeNodeFromGrid(node,x,y)
	local row = grid_nodes[y]
	if not row then return end
	local square = row[x]
	if not square then return end
	local exists = square[node]
	if not exists then return end
	square[node] = nil
	grid_list_sizes[square] = grid_list_sizes[square]-1
	if grid_list_sizes[square] ~= 0 then return end

	grid_streamedin[square] = nil

	grid_list_sizes[square] = nil
	row[x] = nil
	grid_list_sizes[row] = grid_list_sizes[row]-1
	if grid_list_sizes[row] ~= 0 then return end
	grid_list_sizes[row] = nil
	grid_nodes[y] = nil
end

function initNode(node)
	local x,y = getNodePosition(node)
	x,y = math.floor(x/32),math.floor(y/32)
	addNodeToGrid(node,x,y)
end

function initNodeOnCreate()
	initNode(fake_source)
end

function uninitNode()
	if fake_source == fake_this then return end
	local x,y = getNodePosition(fake_source)
	x,y = math.floor(x/32),math.floor(y/32)
	removeNodeFromGrid(fake_source,x,y)
end

function updateNodeGridPositionOnMove(dataname,oldval)
	if fake_source == fake_this then return end
	if not oldval then return end
	local changed_x = dataname == "x"
	local changed_y = dataname == "y"
	if not changed_x and not changed_y then return end
	local old_x,old_y
	local new_x,new_y = getNodePosition(fake_source)
	if changed_x then old_x,old_y = oldval,new_y end
	if changed_y then old_x,old_y = new_x,oldval end
	old_x,old_y = math.floor(old_x/32),math.floor(old_y/32)
	new_x,new_y = math.floor(new_x/32),math.floor(new_y/32)
	if new_x == old_x and new_y == old_y then return end
	removeNodeFromGrid(fake_source,old_x,old_y)
	addNodeToGrid(fake_source,new_x,new_y)
end

function getNodeUnderCursor()
	local mx,my = getCursorPosition()
	if not mx then return end
	local sw,sh = guiGetScreenSize()
	mx,my = mx*sw,my*sh
	local nearest_node
	local nearest_dist = 16
	local cx,cy,cz = getCameraMatrix()
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
						local ax,ay = getNodeRotation(node)

						local this_dist
						if ax == 0 and ay == 0 then
							local sx,sy = getScreenFromWorldPosition(x,y,z,0x7FFFFFFF)
							if sx then
								sx,sy = sx-mx,sy-my
								this_dist = math.sqrt(sx*sx+sy*sy)
							end
						else
							local x1,y1 = getScreenFromWorldPosition(x-ax,y-ay,z,0x7FFFFFFF)
							if x1 then
								local x2,y2 = getScreenFromWorldPosition(x+ax,y+ay,z,0x7FFFFFFF)
								if x2 then
									local mx,my = mx-x1,my-y1

									--[[local yx,yy = x2-x1,y2-y1
									local xx,xy = yy,-yx
									local rx = (mx*yy-my*yx)/(xx*yy-xy*yx)
									local ry = (mx*xy-my*xx)/(yx*xy-yy*xx)

									local len = math.sqrt(yx*yx+yy*yy)
									rx,ry = math.abs(rx)*len,ry*len]]

									local yx,yy = x2-x1,y2-y1
									local len = math.sqrt(yx*yx+yy*yy)
									local rx = (mx*yy-my*yx)/len
									local ry = (mx*yx+my*yy)/len

									rx = math.abs(rx)

									this_dist = math.max(rx,ry-len,-ry)
								end
							end
						end

						if this_dist and this_dist < nearest_dist then
							nearest_node = node
							nearest_dist = this_dist
						end
					end
				end
			end
		end
	end
	return nearest_node
end

function toggleNodeSearchMode(on)
	on = on and true or nil
	if node_search_mode == on then return end
	node_search_mode = on
	if on then
		addEventHandler("onClientPreRender",root,searchForNodeUnderCursor)
	else
		removeEventHandler("onClientPreRender",root,searchForNodeUnderCursor)
		node_active = nil
	end
end

function searchForNodeUnderCursor()
	node_active = getNodeUnderCursor()
end

function getActiveNode()
	return node_active
end

function setSelectedNode(node)
	node_selected = node
end

function getSelectedNode()
	return node_selected
end

