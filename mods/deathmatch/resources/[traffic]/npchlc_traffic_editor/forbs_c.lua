function initForbs()
	node_forbs = {}
	addFakeEventHandler("traffic_edit:onClientNodeCreate",node_root,initNodeForbsOnCreate)
	addFakeEventHandler("onClientElementDestroy",node_root,uninitNodeForbs)

	addFakeEventHandler("traffic_edit:onClientForbCreate",forb_root,initForbOnCreate)
	addFakeEventHandler("onClientElementDestroy",forb_root,uninitForb)

	local nodes = getFakeElementChildren(node_root)
	local forbs = getFakeElementChildren(forb_root)
	for nodenum,node in ipairs(nodes) do
		initNodeForbs(node)
	end
	for forbnum,forb in ipairs(forbs) do
		initForb(forb)
	end
end

function initNodeForbs(node)
	node_forbs[node] = {}
end

function initNodeForbsOnCreate()
	initNodeForbs(fake_source)
end

function uninitNodeForbs()
	node_forbs[fake_source] = nil
end

function initForb(forb)
	local node = getForbNode(forb)
	node_forbs[node][forb] = true
end

function initForbOnCreate()
	initForb(fake_source)
end

function uninitForb()
	local node = getForbNode(fake_source)
	local forbslist = node_forbs[node]
	if forbslist then forbslist[fake_source] = nil end
end

