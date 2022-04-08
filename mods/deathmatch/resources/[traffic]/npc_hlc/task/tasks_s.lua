performTask = {}

function performTask.enterToVehicle(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	return makeNPCEnterToVehicle(npc,task[2],task[3],maxtime)
end
function performTask.exitFromVehicle(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	return makeNPCExitFromVehicle(npc,maxtime)
end
function performTask.walkToPos(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	return makeNPCWalkToPos(npc,task[2],task[3],task[4],maxtime)
end

function performTask.walkAlongLine(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	return makeNPCWalkAlongLine(npc,task[2],task[3],task[4],task[5],task[6],task[7],task[8],maxtime)
end

function performTask.walkAroundBend(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	return makeNPCWalkAroundBend(npc,task[2],task[3],task[4],task[5],task[6],task[7],task[8],task[9],task[10],maxtime)
end

function performTask.walkFollowElement(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end

function performTask.followElement(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	local follow = task[2]
	if isElement(follow) then
		local x,y,z = getElementPosition(follow)
		return makeNPCWalkToPos(npc,x,y,z,maxtime)
	end
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end

function performTask.shootPoint(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end

function performTask.shootElement(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end

function performTask.killPed(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end

function performTask.attackElement(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end
function performTask.arrestElement(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end
function performTask.chaseElement(npc,task,maxtime)
	setElementPosition(npc,getElementPosition(npc))
	return maxtime
end
function performTask.runAvoidTarget(npc,task,maxtime)
	if getElementSyncer(npc) then return maxtime end
	
	local element,safedist = task[2],task[3]
	if not isElement(element) then return true end
	local x,y,z = getElementPosition(npc) -- 获取NPC坐标
	local fx,fy = getElementPosition(element) --获取远离目标坐标
	local ax,ay = 0,0; -- 生成一个离玩家比较远的点
	local dx,dy = fx-x,fy-y -- 获取平面距离

	offset = Vector3(-dx,-dy,0):getNormalized()*safedist; -- 获取远离玩家方向的模向量*安全距离
	ax = x + offset:getX();
	ay = y + offset:getY();


	if dx*dx+dy*dy > safedist*safedist then 
		return maxtime 
	end
	return makeNPCWalkToPos(npc,ax,ay,z,maxtime)
end

function performTask.driveToPos(npc,task,maxtime)
	local vehicle = getPedOccupiedVehicle(npc)
	if not vehicle then return 0 end
	if getElementSyncer(vehicle) then return maxtime end
	return makeNPCDriveToPos(npc,task[2],task[3],task[4],maxtime)
end

function performTask.driveAlongLine(npc,task,maxtime)
	local vehicle = getPedOccupiedVehicle(npc)
	if not vehicle then return 0 end
	if getElementSyncer(vehicle) then return maxtime end
	return makeNPCDriveAlongLine(npc,task[2],task[3],task[4],task[5],task[6],task[7],task[8],maxtime)
end

function performTask.driveAroundBend(npc,task,maxtime)
	local vehicle = getPedOccupiedVehicle(npc)
	if not vehicle then return 0 end
	if getElementSyncer(vehicle) then return maxtime end
	return makeNPCDriveAroundBend(npc,task[2],task[3],task[4],task[5],task[6],task[7],task[8],task[9],task[10],maxtime)
end

function performTask.waitForGreenLight(npc,task,maxtime)
	-- skip if npc is set to drive agressive
	if getNPCDriveStyle(npc) ~= "aggressive" then
		local ctrlelm = getPedOccupiedVehicle(npc) or npc
		if getElementSyncer(ctrlelm) then return maxtime end
		local state = getTrafficLightState()
		if
			state == 6 or state == 9 or
			task[2] == "NS" and (state == 0 or state == 5 or state == 8) or
			task[2] == "WE" and (state == 3 or state == 5 or state == 7) or
			task[2] == "ped" and state == 2
		then
			maxtime = 0
		end
		setElementPosition(ctrlelm,getElementPosition(ctrlelm))
	end
	
	return maxtime
end

addEvent("setPedDoingGangDriveby", true)
addEventHandler("setPedDoingGangDriveby", resourceRoot,function (ped, state )
	if isElement(ped) then
		setPedDoingGangDriveby(ped, state )  
	end
end, false)