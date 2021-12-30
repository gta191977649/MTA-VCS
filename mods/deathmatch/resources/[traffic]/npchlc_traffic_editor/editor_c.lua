function initEditor()
	node_root = getFakeElementByID("path_nodes")
	conn_root = getFakeElementByID("path_conns")
	forb_root = getFakeElementByID("path_forbs")
	name_root = getFakeElementByID("paths_name")

	initNodes()
	initConns()
	initForbs()

	initPathRendering()

	initEditorGUI()
end

function isPositionOnAnyWindow(x,y)
	local windows = getElementsByType("gui-window")
	for wnum,window in ipairs(windows) do
		if guiGetVisible(window) then
			local x1,y1 = guiGetPosition(window,false)
			local x2,y2 = guiGetSize(window,false)
			x2,y2 = x1+x2,y1+y2
			if x1 <= x and x < x2 and y1 <= y and y < y2 then return true end
		end
	end
	return false
end

function getMouseWorldPosition()
	local smx,smy = getCursorPosition()
	if not smx then return end
	local sw,sh = guiGetScreenSize()
	smx,smy = smx*sw,smy*sh
	local cx,cy,cz = getCameraMatrix()
	local x,y,z = getWorldFromScreenPosition(smx,smy,1000)
	local hit
	hit,x,y,z = processLineOfSight(cx,cy,cz,x,y,z,true,false,false,true)
	return x,y,z
end

