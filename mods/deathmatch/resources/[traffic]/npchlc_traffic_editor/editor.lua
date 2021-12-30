function getNodeID(node)
	return getFakeElementData(node,"nodeid")
end

function getConnID(conn)
	return getFakeElementData(conn,"connid")
end

function getForbID(forb)
	return getFakeElementData(forb,"forbid")
end

function setNodePosition(node,x,y,z)
	setFakeElementData(node,"x",x)
	setFakeElementData(node,"y",y)
	setFakeElementData(node,"z",z)
end

function getNodePosition(node)
	return getFakeElementData(node,"x"),getFakeElementData(node,"y"),getFakeElementData(node,"z")
end

function setNodeRotation(node,rx,ry)
	setFakeElementData(node,"rx",rx)
	setFakeElementData(node,"ry",ry)
end

function getNodeRotation(node)
	return getFakeElementData(node,"rx"),getFakeElementData(node,"ry")
end

function setConnNodes(conn,n1,n2)
	setFakeElementData(conn,"n1",n1)
	setFakeElementData(conn,"n2",n2)
	node_conns[n1][n2] = conn
	node_conns[n2][n1] = conn
	node_conns[n1][conn] = n2
	node_conns[n2][conn] = n1
end

function getConnNodes(conn)
	return getFakeElementData(conn,"n1"),getFakeElementData(conn,"n2")
end

function setConnBend(conn,nb)
	nb = nb or false
	local n1,n2 = getConnNodes(conn)
	if nb == n1 or nb == n2 then return end
	local pb = getFakeElementData(conn,"nb")
	if pb then node_bends[pb][conn] = nil end
	setFakeElementData(conn,"nb",nb)
	if nb then node_bends[nb][conn] = true end
end

function getConnBend(conn)
	return getFakeElementData(conn,"nb")
end

CONN_TYPE_PEDS   = 1
CONN_TYPE_CARS   = 2
CONN_TYPE_BOATS  = 3
CONN_TYPE_PLANES = 4

function setConnType(conn,trtype)
	setFakeElementData(conn,"type",trtype)
end

function getConnType(conn)
	return getFakeElementData(conn,"type")
end

function setConnMaxSpeed(conn,speed)
	setFakeElementData(conn,"speed",speed)
end

function getConnMaxSpeed(conn)
	return getFakeElementData(conn,"speed")
end

function setConnLaneCount(conn,left,right)
	setFakeElementData(conn,"llanes",left)
	setFakeElementData(conn,"rlanes",right)
end

function getConnLaneCount(conn)
	return getFakeElementData(conn,"llanes"),getFakeElementData(conn,"rlanes")
end

function setConnDensity(conn,density)
	setFakeElementData(conn,"density",density)
end

function getConnDensity(conn)
	return getFakeElementData(conn,"density")
end

CONN_LIT_NONE = 0
CONN_LIT_NS   = 1
CONN_LIT_WE   = 2
CONN_LIT_PED  = 3

function setConnLights(conn,lights)
	setFakeElementData(conn,"lights",lights)
end

function getConnLights(conn)
	return getFakeElementData(conn,"lights")
end

function setForbConns(forb,c1,c2)
	setFakeElementData(forb,"c1",c1)
	setFakeElementData(forb,"c2",c2)
	conn_forbs_src[c1][c2] = forb
	conn_forbs_dst[c2][c1] = forb
	local n11,n12 = getConnNodes(c1)
	local n21,n22 = getConnNodes(c2)
	local node = (n11 == n21 or n11 == n22) and n11 or n12
	setFakeElementData(forb,"node",node)
	node_forbs[node][forb] = true
end

function getForbConns(forb)
	return getFakeElementData(forb,"c1"),getFakeElementData(forb,"c2")
end

function getForbNode(forb)
	return getFakeElementData(forb,"node")
end

