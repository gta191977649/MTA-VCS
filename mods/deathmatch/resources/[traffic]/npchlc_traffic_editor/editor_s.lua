function initEditor()
	node_root = createFakeElement("npcpaths:data","path_nodes")
	conn_root = createFakeElement("npcpaths:data","path_conns")
	forb_root = createFakeElement("npcpaths:data","path_forbs")
	name_root = createFakeElement("npcpaths:data","paths_name")

	nodes = {}
	conns = {}
	forbs = {}

	node_conns = {}
	node_bends = {}
	conn_forbs_src = {}
	conn_forbs_dst = {}
	node_forbs = {}

	addFakeEventHandler("onElementDataChange",conn_root,updateConnBendData)
	addFakeEventHandler("onElementDestroy",node_root,destroyNodeData)
	addFakeEventHandler("onElementDestroy",conn_root,destroyConnData)
	addFakeEventHandler("onElementDestroy",forb_root,destroyForbData)

	initEditorGUI()

	initSaveLoad()
end
addEventHandler("onResourceStart",resourceRoot,initEditor)

function getNextNodeID()
	return #nodes+1
end

function getNextConnID()
	return #conns+1
end

function getNextForbID()
	return #forbs+1
end

function createNode(id,x,y,z,rx,ry)
	local node = createFakeElement("npcpaths:node")
	setFakeElementData(node,"nodeid",id)
	setNodePosition(node,x,y,z)
	setNodeRotation(node,rx,ry)
	nodes[id] = node
	node_conns[node] = {}
	node_bends[node] = {}
	node_forbs[node] = {}
	setFakeElementParent(node,node_root)
	triggerFakeClientEvent("traffic_edit:onClientNodeCreate",node)
	return node
end

function createConn(id,n1,n2,trtype,maxspeed,ll,rl,density)
	if n1 == n2 or node_conns[n1][n2] then return nil end
	local conn = createFakeElement("npcpaths:conn")
	setFakeElementData(conn,"connid",id)
	setConnNodes(conn,n1,n2)
	setConnType(conn,trtype)
	setConnMaxSpeed(conn,maxspeed)
	setConnLaneCount(conn,ll,rl)
	setConnDensity(conn,density)
	setConnLights(conn,{CONN_LIT_NONE,CONN_LIT_NONE})
	conn_forbs_src[conn] = {}
	conn_forbs_dst[conn] = {}
	conns[id] = conn
	setFakeElementParent(conn,conn_root)
	triggerFakeClientEvent("traffic_edit:onClientConnCreate",conn)
	return conn
end

function createForb(id,c1,c2)
	if c1 == c2 or conn_forbs_src[c1][c2] then return nil end
	local n11,n12 = getConnNodes(c1)
	local n21,n22 = getConnNodes(c2)
	if n11 ~= n21 and n11 ~= n22 and n12 ~= n21 and n12 ~= n22 then return nil end
	local forb = createFakeElement("npcpaths:forb")
	setFakeElementData(forb,"forbid",id)
	setForbConns(forb,c1,c2)
	forbs[id] = forb
	setFakeElementParent(forb,forb_root)
	triggerFakeClientEvent("traffic_edit:onClientForbCreate",forb)
	return forb
end

function destroyNodeData()
	if fake_source == fake_this then return end
	for nextnode,conn in pairs(node_conns[fake_source]) do
		if getFakeElementType(conn) == "npcpaths:conn" then
			destroyFakeElement(conn)
		end
	end
	for conn,bent in pairs(node_bends[fake_source]) do
		setConnBend(conn,false)
	end
	local id = getFakeElementData(fake_source,"nodeid")
	node_conns[fake_source] = nil
	node_bends[fake_source] = nil
	node_forbs[fake_source] = nil
	nodes[id] = nil
end

function destroyConnData()
	if fake_source == fake_this then return end
	for c2,forb in pairs(conn_forbs_src[fake_source]) do
		destroyFakeElement(forb)
	end
	for c1,forb in pairs(conn_forbs_dst[fake_source]) do
		destroyFakeElement(forb)
	end
	local id = getFakeElementData(fake_source,"connid")
	local n1,n2 = getConnNodes(fake_source)
	local nb = getConnBend(fake_source)
	conn_forbs_src[fake_source] = nil
	conn_forbs_dst[fake_source] = nil
	node_conns[n1][fake_source] = nil
	node_conns[n2][fake_source] = nil
	node_conns[n1][n2] = nil
	node_conns[n2][n1] = nil
	if nb then node_bends[nb][fake_source] = nil end
	conns[id] = nil
end

function destroyForbData()
	if fake_source == fake_this then return end
	local id = getFakeElementData(fake_source,"forbid")
	local c1,c2 = getForbConns(fake_source)
	local node = getForbNode(fake_source)
	conn_forbs_src[c1][c2] = nil
	conn_forbs_dst[c2][c1] = nil
	node_forbs[node][fake_source] = nil
	forbs[id] = nil
end

function updateConnBendData(dataname,oldval)
	if fake_source == fake_this then return end
	if dataname ~= "nb" then return end
	local newval = getFakeElementData(fake_source,dataname)
	if oldval then
		node_bends[oldval][fake_source] = nil
	end
	if newval then
		node_bends[newval][fake_source] = true
	end
end

