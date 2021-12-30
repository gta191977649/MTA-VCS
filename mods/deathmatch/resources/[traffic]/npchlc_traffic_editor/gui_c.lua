function initEditorGUI()
	createEditorWindow()
	bindKey("mouse2","both",toggleMouseLook)
	addCommandHandler("edittraffic",function()
		setEditorWindowVisibile(not isEditorWindowVisible())
	end)

	editor_mode = "none"
end

--------------------------------------------------------------

function createEditorWindow()
	local sw,sh = guiGetScreenSize()
	editor_window = guiCreateWindow((sw-264)*0.5,sh-160-16,324,160,"Traffic editor",false)
	guiWindowSetSizable(editor_window,false)

	local tabs = guiCreateTabPanel(8,24,308,128,false,editor_window)
	editor_nodes = guiCreateTab("Nodes"          ,tabs)
	editor_conns = guiCreateTab("Connections"    ,tabs)
	editor_forbs = guiCreateTab("Forbidden turns",tabs)

	editor_nodes_create  = guiCreateButton(38,40,52,24,"Create",false,editor_nodes)
	editor_nodes_destroy = guiCreateButton(98,40,52,24,"Destroy",false,editor_nodes)
	editor_nodes_move    = guiCreateButton(158,40,52,24,"Move",false,editor_nodes)
	editor_nodes_rotate  = guiCreateButton(218,40,52,24,"Rotate",false,editor_nodes)

	editor_conns_create  = guiCreateButton(8,8,52,24,"Create",false,editor_conns)
	editor_conns_destroy = guiCreateButton(68,8,52,24,"Destroy",false,editor_conns)
	editor_conns_bend    = guiCreateButton(128,8,52,24,"Bend",false,editor_conns)
	editor_conns_unbend  = guiCreateButton(188,8,52,24,"Unbend",false,editor_conns)
	editor_conns_lights  = guiCreateButton(248,8,52,24,"Lights",false,editor_conns)
	editor_conns_type    = guiCreateButton(68,40,52,24,"Peds",false,editor_conns)
	editor_conns_speed   = guiCreateEdit(188,40,52,24,"40",false,editor_conns)
	editor_conns_llane   = guiCreateEdit(48,72,32,24,"0",false,editor_conns)
	editor_conns_rlane   = guiCreateEdit(88,72,32,24,"0",false,editor_conns)
	editor_conns_density = guiCreateEdit(188,72,52,24,"1",false,editor_conns)
	editor_conns_set     = guiCreateButton(248,40,52,24,"Set",false,editor_conns)
	editor_conns_get     = guiCreateButton(248,72,52,24,"Get",false,editor_conns)
	local editor_conns_type_label    = guiCreateLabel(8,40,52,24,"Type:",false,editor_conns)
	local editor_conns_speed_label   = guiCreateLabel(128,40,52,24,"Speed:",false,editor_conns)
	local editor_conns_lane_label    = guiCreateLabel(8,72,40,24,"Lanes:",false,editor_conns)
	local editor_conns_density_label = guiCreateLabel(128,72,52,24,"Density:",false,editor_conns)
	guiLabelSetVerticalAlign(editor_conns_type_label,"center")
	guiLabelSetVerticalAlign(editor_conns_speed_label,"center")
	guiLabelSetVerticalAlign(editor_conns_lane_label,"center")
	guiLabelSetVerticalAlign(editor_conns_density_label,"center")
	guiLabelSetHorizontalAlign(editor_conns_type_label,"right")
	guiLabelSetHorizontalAlign(editor_conns_speed_label,"right")
	guiLabelSetHorizontalAlign(editor_conns_density_label,"right")

	editor_forbs_create  = guiCreateButton(98,40,52,24,"Create",false,editor_forbs)
	editor_forbs_destroy = guiCreateButton(158,40,52,24,"Destroy",false,editor_forbs)

	editor_mode_buttons =
	{
		[editor_nodes_create ] = "node:create" ,["node:create" ] = editor_nodes_create ,
		[editor_nodes_destroy] = "node:destroy",["node:destroy"] = editor_nodes_destroy,
		[editor_nodes_move   ] = "node:move"   ,["node:move"   ] = editor_nodes_move   ,
		[editor_nodes_rotate ] = "node:rotate" ,["node:rotate" ] = editor_nodes_rotate ,

		[editor_conns_create ] = "conn:create" ,["conn:create" ] = editor_conns_create ,
		[editor_conns_destroy] = "conn:destroy",["conn:destroy"] = editor_conns_destroy,
		[editor_conns_bend   ] = "conn:bend"   ,["conn:bend"   ] = editor_conns_bend   ,
		[editor_conns_unbend ] = "conn:unbend" ,["conn:unbend" ] = editor_conns_unbend ,
		[editor_conns_lights ] = "conn:lights" ,["conn:lights" ] = editor_conns_lights ,
		[editor_conns_set    ] = "conn:set"    ,["conn:set"    ] = editor_conns_set    ,
		[editor_conns_get    ] = "conn:get"    ,["conn:get"    ] = editor_conns_get    ,

		[editor_forbs_create ] = "forb:create" ,["forb:create" ] = editor_forbs_create ,
		[editor_forbs_destroy] = "forb:destroy",["forb:destroy"] = editor_forbs_destroy
	}
	
	editor_mode_initfunc =
	{
		["node:create" ] = nil            ,
		["node:destroy"] = initNodeDestroy,
		["node:move"   ] = initNodeMove   ,
		["node:rotate" ] = initNodeRotate ,

		["conn:create" ] = initConnCreate ,
		["conn:destroy"] = initConnDestroy,
		["conn:bend"   ] = initConnBend   ,
		["conn:unbend" ] = initConnUnbend ,
		["conn:lights" ] = initConnLights ,
		["conn:set"    ] = initConnSet    ,
		["conn:get"    ] = initConnGet    ,

		["forb:create" ] = initForbCreate ,
		["forb:destroy"] = initForbDestroy
	}
	editor_mode_uninitfunc =
	{
		["node:create" ] = uninitNodeCreate ,
		["node:destroy"] = uninitNodeDestroy,
		["node:move"   ] = uninitNodeMove   ,
		["node:rotate" ] = uninitNodeRotate ,

		["conn:create" ] = uninitConnCreate ,
		["conn:destroy"] = uninitConnDestroy,
		["conn:bend"   ] = uninitConnBend   ,
		["conn:unbend" ] = uninitConnUnbend ,
		["conn:lights" ] = uninitConnLights ,
		["conn:set"    ] = uninitConnSet    ,
		["conn:get"    ] = uninitConnGet    ,

		["forb:create" ] = uninitForbCreate ,
		["forb:destroy"] = uninitForbDestroy
	}

	next_traffic_type = {Peds = "Cars",Cars = "Boats",Boats = "Planes",Planes = "Peds"}

	addEventHandler("onClientGUIClick",editor_window,setEditorModeWithButtons)
	addEventHandler("onClientGUIClick",editor_conns_type,setTrafficTypeWithButton,false)
	addEventHandler("onClientClick",root,clickOnWorld)

	guiSetVisible(editor_window,false)
end

function setEditorWindowVisibile(visible)
	if isEditorWindowVisible() == visible then return end
	if not visible then setTrafficEditorMode("none") end
	guiSetVisible(editor_window,visible)
	showCursor(visible)
end

function isEditorWindowVisible()
	return guiGetVisible(editor_window)
end

function toggleMouseLook(key,keystate)
	if not isEditorWindowVisible() then return end
	showCursor(keystate == "up")
end

--------------------------------------------------------------

function getConnParameters()
	local trtype  =          guiGetText(editor_conns_type   )
	local speed   = tonumber(guiGetText(editor_conns_speed  ))
	local ll      = tonumber(guiGetText(editor_conns_llane  ))
	local rl      = tonumber(guiGetText(editor_conns_rlane  ))
	local density = tonumber(guiGetText(editor_conns_density))
	trtype =
		trtype == "Peds"   and CONN_TYPE_PEDS   or
		trtype == "Cars"   and CONN_TYPE_CARS   or
		trtype == "Boats"  and CONN_TYPE_BOATS  or
		trtype == "Planes" and CONN_TYPE_PLANES
	if not (speed and ll and rl and density) then return end
	if speed < 0        then return end
	if ll < 0 or rl < 0 then return end
	if density < 0      then return end
	return trtype,speed,ll,rl,density
end

function setConnParameters(trtype,speed,ll,rl,density)
	trtype =
		trtype == CONN_TYPE_PEDS   and "Peds"   or
		trtype == CONN_TYPE_CARS   and "Cars"   or
		trtype == CONN_TYPE_BOATS  and "Boats"  or
		trtype == CONN_TYPE_PLANES and "Planes" or
		nil
	if trtype            then guiSetText(editor_conns_type   ,         trtype  ) end
	if tonumber(speed  ) then guiSetText(editor_conns_speed  ,tostring(speed  )) end
	if tonumber(ll     ) then guiSetText(editor_conns_llane  ,tostring(ll     )) end
	if tonumber(rl     ) then guiSetText(editor_conns_rlane  ,tostring(rl     )) end
	if tonumber(density) then guiSetText(editor_conns_density,tostring(density)) end
end

--------------------------------------------------------------

function setButtonActiveMode(button,active)
	if active then
		guiSetProperty(button,"NormalTextColour","FF00C000")
		guiSetProperty(button,"HoverTextColour","FF00C0C0")
		guiSetProperty(button,"PushedTextColour","FF00FF00")
	else
		guiSetProperty(button,"NormalTextColour","FFAAAAAA")
		guiSetProperty(button,"HoverTextColour","FFAAAAFF")
		guiSetProperty(button,"PushedTextColour","FFFFFFFF")
	end
end

function setTrafficEditorMode(mode)
	if editor_mode == mode then return end
	local prev_btn = editor_mode_buttons[editor_mode]
	local this_btn = editor_mode_buttons[       mode]
	if prev_btn then setButtonActiveMode(prev_btn,false) end
	if this_btn then setButtonActiveMode(this_btn,true ) end
	local uninitCurrentMode = editor_mode_uninitfunc[editor_mode]
	local   initCurrentMode = editor_mode_initfunc  [       mode]
	if uninitCurrentMode then uninitCurrentMode() end
	if   initCurrentMode then   initCurrentMode() end
	editor_mode = mode
end

function getTrafficEditorMode()
	return editor_mode
end

--------------------------------------------------------------

function setEditorModeWithButtons(button,state,x,y)
	if button ~= "left" or state ~= "up" then return end
	local mode = editor_mode_buttons[source]
	if not mode then return end
	if getTrafficEditorMode() == mode then mode = "none" end
	setTrafficEditorMode(mode)
end

function setTrafficTypeWithButton(button,state,x,y)
	if button ~= "left" or state ~= "up" then return end
	guiSetText(source,next_traffic_type[guiGetText(source)])
end

--------------------------------------------------------------

clickOnWorldAction = {}

function clickOnWorld(button,state,sx,sy,wx,wy,wz,we)
	if button ~= "left" or state ~= "down" then return end
	if isPositionOnAnyWindow(sx,sy) then return end
	local clickFunc = clickOnWorldAction[getTrafficEditorMode()]
	if not clickFunc then return end
	clickFunc()
end



function uninitNodeCreate()
	if node_create_x then
		node_create_x,node_create_y,node_create_z = nil,nil,nil
		removeEventHandler("onClientHUDRender",root,drawNodeBeforeCreation)
		unbindKey("mouse1","up",createNodeOnRelease)
	end
end

clickOnWorldAction["node:create"] = function()
	node_create_x,node_create_y,node_create_z = getMouseWorldPosition()
	if not node_create_x then return end
	addEventHandler("onClientHUDRender",root,drawNodeBeforeCreation)
	bindKey("mouse1","up",createNodeOnRelease)
end

function drawNodeBeforeCreation()
	local x,y = getMouseWorldPosition()
	if not x then return end
	x,y = x-node_create_x,y-node_create_y
	drawNode(node_create_x,node_create_y,node_create_z,x,y,tocolor(255,0,0,255))
end

function createNodeOnRelease(key,keystate)
	if not node_create_x then return end
	local x,y = getMouseWorldPosition()
	if x then
		x,y = x-node_create_x,y-node_create_y
		triggerFakeServerEvent("traffic_edit:createNode",root,node_create_x,node_create_y,node_create_z,x,y)
	end
	uninitNodeCreate()
end



function initNodeDestroy()
	toggleNodeSearchMode(true)
end

function uninitNodeDestroy()
	toggleNodeSearchMode(false)
end

clickOnWorldAction["node:destroy"] = function()
	local node = getActiveNode()
	if not isFakeElement(node) then return end
	triggerFakeServerEvent("traffic_edit:destroyNode",node)
end



function initNodeMove()
	toggleNodeSearchMode(true)
	addEventHandler("onClientPreRender",root,moveSelectedNode)
end

function uninitNodeMove()
	toggleNodeSearchMode(false)
	removeEventHandler("onClientPreRender",root,moveSelectedNode)
	if getSelectedNode() then
		stopMovingNodeOnRelease()
	end
end

clickOnWorldAction["node:move"] = function()
	local node = getActiveNode()
	if not isFakeElement(node) then return end
	setSelectedNode(node)
	toggleNodeSearchMode(false)
	bindKey("mouse1","up",stopMovingNodeOnRelease)
end

function moveSelectedNode()
	local node = getSelectedNode()
	if not isFakeElement(node) then return end
	local x,y,z = getMouseWorldPosition()
	if not x then return end
	setNodePosition(node,x,y,z)
end

function stopMovingNodeOnRelease(key,keystate)
	setSelectedNode(nil)
	toggleNodeSearchMode(true)
	unbindKey("mouse1","up",stopMovingNodeOnRelease)
end



function initNodeRotate()
	toggleNodeSearchMode(true)
	addEventHandler("onClientPreRender",root,rotateSelectedNode)
end

function uninitNodeRotate()
	toggleNodeSearchMode(false)
	removeEventHandler("onClientPreRender",root,rotateSelectedNode)
	if getSelectedNode() then
		stopRotatingNodeOnRelease()
	end
end

clickOnWorldAction["node:rotate"] = function()
	local node = getActiveNode()
	if not isFakeElement(node) then return end
	setSelectedNode(node)
	toggleNodeSearchMode(false)
	bindKey("mouse1","up",stopRotatingNodeOnRelease)
end

function rotateSelectedNode()
	local node = getSelectedNode()
	if not isFakeElement(node) then return end
	local x,y = getMouseWorldPosition()
	if not x then return end
	local nx,ny = getNodePosition(node)
	x,y = x-nx,y-ny
	setNodeRotation(node,x,y)
end

function stopRotatingNodeOnRelease(key,keystate)
	setSelectedNode(nil)
	toggleNodeSearchMode(true)
	unbindKey("mouse1","up",stopRotatingNodeOnRelease)
end



function initConnCreate()
	toggleNodeSearchMode(true)
end

function uninitConnCreate()
	setSelectedNode(nil)
	toggleNodeSearchMode(false)
end

clickOnWorldAction["conn:create"] = function()
	local selected = getSelectedNode()
	local active = getActiveNode()
	if isFakeElement(selected) then
		if isFakeElement(active) then
			local trtype,speed,ll,rl,density = getConnParameters()
			if trtype then
				triggerFakeServerEvent("traffic_edit:createConn",root,selected,active,trtype,speed,ll,rl,density)
			end
		end
		setSelectedNode(nil)
	else
		setSelectedNode(active)
	end
end



function initConnDestroy()
	toggleConnSearchMode(true)
end

function uninitConnDestroy()
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:destroy"] = function()
	local conn = getActiveConn()
	if not isFakeElement(conn) then return end
	triggerFakeServerEvent("traffic_edit:destroyConn",conn)
end



function initConnBend()
	toggleConnSearchMode(true)
end

function uninitConnBend()
	setSelectedConn(nil)
	toggleNodeSearchMode(false)
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:bend"] = function()
	local conn = getSelectedConn()
	if isFakeElement(conn) then
		local node = getActiveNode()
		if isFakeElement(node) then
			setConnBend(conn,node)
		end
		setSelectedConn(nil)
		toggleNodeSearchMode(false)
		toggleConnSearchMode(true)
	else
		local conn = getActiveConn()
		if not isFakeElement(conn) then return end
		setSelectedConn(conn)
		toggleNodeSearchMode(true)
		toggleConnSearchMode(false)
	end
end



function initConnUnbend()
	toggleConnSearchMode(true)
end

function uninitConnUnbend()
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:unbend"] = function()
	local conn = getActiveConn()
	if not isFakeElement(conn) then return end
	setConnBend(conn,nil)
end



function initConnLights()
	toggleNodeSearchMode(true)
	toggleConnSearchMode(true)
end

function uninitConnLights()
	toggleNodeSearchMode(false)
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:lights"] = function()
	local conn = getActiveConn()
	if not isFakeElement(conn) then return end
	local node = getActiveNode()
	if not isFakeElement(node) then return end
	local n1,n2 = getConnNodes(conn)
	local nodenum = n1 == node and 1 or n2 == node and 2 or nil
	if not nodenum then return end
	local lights = getConnLights(conn)
	lights[nodenum] = (lights[nodenum]+1)%4
	setConnLights(conn,lights)
end



function initConnSet()
	toggleConnSearchMode(true)
end

function uninitConnSet()
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:set"] = function()
	local conn = getActiveConn()
	if not isFakeElement(conn) then return end
	local trtype,speed,ll,rl,density = getConnParameters()
	if not trtype then return end
	setConnType(conn,trtype)
	setConnMaxSpeed(conn,speed)
	setConnLaneCount(conn,ll,rl)
	setConnDensity(conn,density)
end



function initConnGet()
	toggleConnSearchMode(true)
end

function uninitConnGet()
	toggleConnSearchMode(false)
end

clickOnWorldAction["conn:get"] = function()
	local conn = getActiveConn()
	if not isFakeElement(conn) then return end
	local trtype = getConnType(conn)
	local speed = getConnMaxSpeed(conn)
	local ll,rl = getConnLaneCount(conn)
	local density = getConnDensity(conn)
	setConnParameters(trtype,speed,ll,rl,density)
end



function initForbCreate()
	toggleConnSearchMode(true)
end

function uninitForbCreate()
	setSelectedConn(nil)
	toggleConnSearchMode(false)
end

clickOnWorldAction["forb:create"] = function()
	local selected = getSelectedConn()
	local active = getActiveConn()
	if isFakeElement(selected) then
		if isFakeElement(active) then
			triggerFakeServerEvent("traffic_edit:createForb",root,selected,active)
		end
		setSelectedConn(nil)
	else
		setSelectedConn(active)
	end
end



function initForbDestroy()
	toggleNodeSearchMode(true)
end

function uninitForbDestroy()
	toggleNodeSearchMode(false)
end

clickOnWorldAction["forb:destroy"] = function()
	local node = getActiveNode()
	if not isFakeElement(node) then return end
	triggerFakeServerEvent("traffic_edit:destroyForb",node)
end

