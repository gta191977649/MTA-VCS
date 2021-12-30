function initSaveLoad()
	map_name = "Untitled"
	setFakeElementData(name_root,"name",map_name)

	addCommandHandler("trafficname",changeTrafficMapName)
	addCommandHandler("trafficclear",clearTraffic)
	addCommandHandler("trafficsave",saveTraffic)
	addCommandHandler("trafficload",loadTraffic)
end

function changeTrafficMapName(player,cmdname,name)
	if savetraffic_coroutine or loadtraffic_coroutine or cleartraffic_coroutine then return end
	if not name then
		outputInfoMessage("Wrong paths map name")
		return
	end
	map_name = name
	setFakeElementData(name_root,"name",map_name)
	outputInfoMessage("Changed paths map name to \""..map_name.."\"")
end

------------------------------------------------------------------------

function clearTraffic()
	if savetraffic_coroutine or loadtraffic_coroutine or cleartraffic_coroutine then return end
	cleartraffic_starttime = getTickCount()
	cleartraffic_coroutine = coroutine.create(clearTrafficThread)
	setTimer(clearTrafficResumeThread,50,1)
end

function clearTrafficThread()
	local thread_timer = getTickCount()

	local nodes = getFakeElementChildren(node_root)
	local total = #nodes
	for nodenum,node in ipairs(nodes) do
		destroyFakeElement(node)

		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Cleared "..(math.floor(nodenum*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end
end

function clearTrafficResumeThread()
	if coroutine.status(cleartraffic_coroutine) == "dead" then
		outputInfoMessage("Traffic cleared in "..(getTickCount()-cleartraffic_starttime).." ms")
		cleartraffic_coroutine = nil
		cleartraffic_starttime = nil
	else
		coroutine.resume(cleartraffic_coroutine)
		setTimer(clearTrafficResumeThread,50,1)
	end
end

------------------------------------------------------------------------

function saveTraffic()
	if savetraffic_coroutine or loadtraffic_coroutine or cleartraffic_coroutine then return end
	if not map_name then
		outputInfoMessage("Wrong paths map name")
		return
	end
	savetraffic_file = fileCreate("paths/"..map_name)
	if not savetraffic_file then
		outputInfoMessage("Failed to create paths map file")
		return
	end
	savetraffic_starttime = getTickCount()
	savetraffic_coroutine = coroutine.create(saveTrafficThread)
	setTimer(saveTrafficResumeThread,50,1)
end

function saveTrafficThread()
	local thread_timer = getTickCount()

	local node_ids,conn_ids = {},{}
	local nodes = getFakeElementChildren(node_root)
	local conns = getFakeElementChildren(conn_root)
	local forbs = getFakeElementChildren(forb_root)
	fileWrite(savetraffic_file,dataToBytes("3i",#nodes,#conns,#forbs))
	local total,done = #nodes+#conns+#forbs,0

	for nodenum,node in ipairs(nodes) do
		node_ids[node] = nodenum
		local x,y,z = getNodePosition(node)
		local rx,ry = getNodeRotation(node)
		x,y,z = math.floor(x*1000),math.floor(y*1000),math.floor(z*1000)
		rx,ry = math.floor(rx*1000),math.floor(ry*1000)
		fileWrite(savetraffic_file,dataToBytes("3i2s",x,y,z,rx,ry))

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Saved "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	for connnum,conn in ipairs(conns) do
		conn_ids[conn] = connnum
		local n1,n2 = getConnNodes(conn)
		local nb = getConnBend(conn)
		local trtype = getConnType(conn)
		local lights = getConnLights(conn)
		local speed = getConnMaxSpeed(conn)
		local ll,rl = getConnLaneCount(conn)
		local density = getConnDensity(conn)
		n1,n2 = node_ids[n1],node_ids[n2]
		nb = nb and node_ids[nb] or -1
		lights = lights[1]+lights[2]*4
		speed = math.floor(speed*10)
		density = math.floor(density*1000)
		fileWrite(savetraffic_file,dataToBytes("3i2ubus2ubus",n1,n2,nb,trtype,lights,speed,ll,rl,density))

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Saved "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	for forbnum,forb in ipairs(forbs) do
		local c1,c2 = getForbConns(forb)
		c1,c2 = conn_ids[c1],conn_ids[c2]
		fileWrite(savetraffic_file,dataToBytes("2i",c1,c2))

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Saved "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	savetraffic_nodecount,savetraffic_conncount,savetraffic_forbcount = #nodes,#conns,#forbs
end

function saveTrafficResumeThread()
	if coroutine.status(savetraffic_coroutine) == "dead" then
		fileClose(savetraffic_file)
		local time_text = "Saved paths map \""..map_name.."\" in "..(getTickCount()-savetraffic_starttime).." ms"
		local nodecount_text = savetraffic_nodecount.." node"..((savetraffic_nodecount%10 ~= 1 or savetraffic_nodecount%100 == 11) and "s" or "")
		local conncount_text = savetraffic_conncount.." connection"..((savetraffic_conncount%10 ~= 1 or savetraffic_conncount%100 == 11) and "s" or "")
		local forbcount_text = savetraffic_forbcount.." forbidden turn"..((savetraffic_forbcount%10 ~= 1 or savetraffic_forbcount%100 == 11) and "s" or "")
		outputInfoMessage(time_text..". "..nodecount_text..", "..conncount_text..", "..forbcount_text..".")
		savetraffic_coroutine = nil
		savetraffic_file = nil
		savetraffic_starttime = nil
		savetraffic_nodecount,savetraffic_conncount,savetraffic_forbcount = nil,nil,nil
	else
		coroutine.resume(savetraffic_coroutine)
		setTimer(saveTrafficResumeThread,50,1)
	end
end

------------------------------------------------------------------------

function loadTraffic()
	if savetraffic_coroutine or loadtraffic_coroutine or cleartraffic_coroutine then return end
	if not map_name then
		outputInfoMessage("Wrong paths map name")
		return
	end
	loadtraffic_file = fileOpen("paths/"..map_name,true)
	if not loadtraffic_file then
		outputInfoMessage("Failed to open paths map file")
		return
	end
	clearTraffic()
	loadtraffic_coroutine = coroutine.create(loadTrafficThread)
	setTimer(loadTrafficResumeThread,50,1)
end

function loadTrafficThread()
	local thread_timer = getTickCount()

	loadtraffic_starttime = getTickCount()

	local node_ids,conn_ids = {},{}
	local nodecount,conncount,forbcount = bytesToData("3i",fileRead(loadtraffic_file,12))
	local total,done = nodecount+conncount+forbcount,0

	for nodenum = 1,nodecount do
		local x,y,z,rx,ry = bytesToData("3i2s",fileRead(loadtraffic_file,16))
		x,y,z = x/1000,y/1000,z/1000
		rx,ry = rx/1000,ry/1000
		node_ids[nodenum] = createNode(getNextNodeID(),x,y,z,rx,ry)

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Loaded "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	for connnum = 1,conncount do
		local n1,n2,nb,trtype,lights,speed,ll,rl,density = bytesToData("3i2ubus2ubus",fileRead(loadtraffic_file,20))
		n1,n2 = node_ids[n1],node_ids[n2]
		nb = nb ~= -1 and node_ids[nb] or nil
		lights = {lights%4,math.floor(lights/4)}
		speed = speed/10
		density = density/1000
		local conn = createConn(getNextConnID(),n1,n2,trtype,speed,ll,rl,density)
		setConnBend(conn,nb)
		setConnLights(conn,lights)
		conn_ids[connnum] = conn

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Loaded "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	for forbnum = 1,forbcount do
		local c1,c2 = bytesToData("2i",fileRead(loadtraffic_file,8))
		c1,c2 = conn_ids[c1],conn_ids[c2]
		createForb(getNextForbID(),c1,c2)

		done = done+1
		local this_time = getTickCount()
		if this_time > thread_timer+4000 then
			outputInfoMessage("Loaded "..(math.floor(done*1000/total)*0.1).."%")
			coroutine.yield()
			thread_timer = getTickCount()
		end
	end

	loadtraffic_nodecount,loadtraffic_conncount,loadtraffic_forbcount = nodecount,conncount,forbcount
end

function loadTrafficResumeThread()
	if coroutine.status(loadtraffic_coroutine) == "dead" then
		fileClose(loadtraffic_file)
		local time_text = "Loaded paths map \""..map_name.."\" in "..(getTickCount()-loadtraffic_starttime).." ms"
		local nodecount_text = loadtraffic_nodecount.." node"..((loadtraffic_nodecount%10 ~= 1 or loadtraffic_nodecount%100 == 11) and "s" or "")
		local conncount_text = loadtraffic_conncount.." connection"..((loadtraffic_conncount%10 ~= 1 or loadtraffic_conncount%100 == 11) and "s" or "")
		local forbcount_text = loadtraffic_forbcount.." forbidden turn"..((loadtraffic_forbcount%10 ~= 1 or loadtraffic_forbcount%100 == 11) and "s" or "")
		outputInfoMessage(time_text..". "..nodecount_text..", "..conncount_text..", "..forbcount_text..".")
		loadtraffic_coroutine = nil
		loadtraffic_file = nil
		loadtraffic_starttime = nil
		loadtraffic_nodecount,loadtraffic_conncount,loadtraffic_forbcount = nil,nil,nil
	else
		if not cleartraffic_coroutine then coroutine.resume(loadtraffic_coroutine) end
		setTimer(loadTrafficResumeThread,50,1)
	end
end

------------------------------------------------------------------------

function outputInfoMessage(infomsg)
	outputChatBox(infomsg)
	outputServerLog(infomsg)
end

