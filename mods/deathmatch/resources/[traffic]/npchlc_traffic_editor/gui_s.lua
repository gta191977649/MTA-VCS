function initEditorGUI()
	addFakeEventHandler("traffic_edit:createNode",root,createNodeOnClick)
	addFakeEventHandler("traffic_edit:destroyNode",root,destroyNodeOnClick)
	addFakeEventHandler("traffic_edit:createConn",root,createConnOnClick)
	addFakeEventHandler("traffic_edit:destroyConn",root,destroyConnOnClick)
	addFakeEventHandler("traffic_edit:createForb",root,createForbOnClick)
	addFakeEventHandler("traffic_edit:destroyForb",root,destroyForbOnClick)
end

function createNodeOnClick(x,y,z,rx,ry)
	createNode(getNextNodeID(),x,y,z,rx,ry)
end

function destroyNodeOnClick()
	destroyFakeElement(fake_source)
end

function createConnOnClick(n1,n2,trtype,maxspeed,ll,rl,density)
	createConn(getNextConnID(),n1,n2,trtype,maxspeed,ll,rl,density)
end

function destroyConnOnClick()
	destroyFakeElement(fake_source)
end

function createForbOnClick(c1,c2)
	createForb(getNextForbID(),c1,c2)
end

function destroyForbOnClick()
	for forb,exists in pairs(node_forbs[fake_source]) do
		if getFakeElementType(forb) == "npcpaths:forb" then
			destroyFakeElement(forb)
		end
	end
end

