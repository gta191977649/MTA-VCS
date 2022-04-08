performTask = {}

function performTask.walkToPos(npc,task)
	if isPedInVehicle(npc) then 
		setPedExitVehicle(npc)
	else
		local destx,desty,destz,dest_dist = task[2],task[3],task[4],task[5]
		local x,y = getElementPosition(npc)
		local distx,disty = destx-x,desty-y
		local dist = distx*distx+disty*disty
		local dest_dist = task[5]
		if dist < dest_dist*dest_dist then 
			stopAllNPCActions(npc)
			return true 
		end
		stopNPCWeaponActions(npc)
		makeNPCWalkToPos(npc,destx,desty)
	end
end
function performTask.enterToVehicle(npc,task)
	print("[C] performTask.enterToVehicle")
	if isPedInVehicle(npc) then 
		return true 
	end
	stopAllNPCActions(npc)
	makeNPCEnterToVehicle(npc,task[2],task[3])
end
function performTask.exitFromVehicle(npc)
	print("[C] performTask.enterToVehicle")
	if not isPedInVehicle(npc) then
		return true 
	end
	stopAllNPCActions(npc)
	makeNPCExitFromVehicle(npc)
end

function performTask.walkAlongLine(npc,task)
	if isPedInVehicle(npc) then
		setPedExitVehicle(npc)
	else
		local x1,y1,z1,x2,y2,z2 = task[2],task[3],task[4],task[5],task[6],task[7]
		local off,enddist = task[8],task[9]
		local x,y,z = getElementPosition(npc)
		local pos = getPercentageInLine(x,y,x1,y1,x2,y2)
		local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
		if pos >= 1-enddist/len then return true end
		--随机偏移node位置，防止NPC撞一起
		--local offset = math.random(0,1) 
		stopNPCWeaponActions(npc)
		makeNPCWalkAlongLine(npc,x1,y1,z1,x2,y2,z2,off)
	end
end

function performTask.walkAroundBend(npc,task)
	if isPedInVehicle(npc) then
		setPedExitVehicle(npc)
	else
		local x0,y0 = task[2],task[3]
		local x1,y1,z1 = task[4],task[5],task[6]
		local x2,y2,z2 = task[7],task[8],task[9]
		local off,enddist = task[10],task[11]
		local x,y,z = getElementPosition(npc)
		local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*math.pi*0.5
		local angle = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)+enddist/len
		if angle >= math.pi*0.5 then 
			stopAllNPCActions(npc)
			return true 
		end

		stopNPCWeaponActions(npc)
		makeNPCWalkAroundBend(npc,x0,y0,x1,y1,x2,y2,off)
	end
end

function performTask.walkFollowElement(npc,task)
	if isPedInVehicle(npc) then
		setPedExitVehicle(npc)
	else
		local followed,mindist = task[2],task[3]
		if not isElement(followed) then return true end
		local x,y = getElementPosition(npc)
		local fx,fy = getElementPosition(followed)
		local dx,dy = fx-x,fy-y
		if dx*dx+dy*dy > mindist*mindist then
			stopNPCWeaponActions(npc)
			makeNPCWalkToPos(npc,fx,fy)
		else
			stopAllNPCActions(npc)
		end
	end
end
function performTask.followElement(npc,task)
	if isPedInVehicle(npc) then return true end
	local followed,mindist = task[2],task[3]
	if not isElement(followed) then return true end
	local x,y = getElementPosition(npc)
	local fx,fy = getElementPosition(followed)
	local dx,dy = fx-x,fy-y
	if dx*dx+dy*dy > mindist*mindist then
		stopNPCWeaponActions(npc)
		--setNPCWalkSpeed (npc, "run")
		makeNPCWalkToPos(npc,fx,fy,"run")
	elseif dx*dx+dy*dy > mindist*mindist - 3 then
		stopNPCWeaponActions(npc)
		--setNPCWalkSpeed (npc, "walk")
		makeNPCWalkToPos(npc,fx,fy,"walk")
	else
		stopAllNPCActions(npc)
	end
end

function performTask.shootPoint(npc,task)
	local x,y,z = task[2],task[3],task[4]
	makeNPCShootAtPos(npc,x,y,z)
end

function performTask.shootElement(npc,task)
	local target = task[2]
	if not isElement(target) then return true end
	makeNPCShootAtElement(npc,target)
end

function performTask.killPed(npc,task)
	if isPedInVehicle(npc) then return true end
	local target,shootdist,followdist = task[2],task[3],task[4]
	if not isElement(target) or getElementHealth(target) < 1 then return true end
	local x,y,z = getElementPosition(npc)
	local tx,ty,tz = getElementPosition(target)
	local dx,dy = tx-x,ty-y
	local distsq = dx*dx+dy*dy
	if distsq < shootdist*shootdist then
		makeNPCShootAtElement(npc,target)
		setPedRotation(npc,-math.deg(math.atan2(dx,dy)))
	else
		stopNPCWeaponActions(npc)
	end
	if distsq > followdist*followdist then
		makeNPCWalkToPos(npc,tx,ty)
	else
		stopNPCWalkingActions(npc)
	end
	return false
end

function performTask.runAvoidTarget(npc,task)
	if isPedInVehicle(npc) then 
		stopAllNPCActions(npc)
		makeNPCExitFromVehicle(npc)
	end

	local element,safedist = task[2],task[3]
	if not isElement(element) then return true end
	local x,y = getElementPosition(npc) -- 获取NPC坐标
	local fx,fy = getElementPosition(element) --获取远离目标坐标
	local ax,ay = 0,0; -- 生成一个离玩家比较远的点
	local dx,dy = fx-x,fy-y -- 获取平面距离

	offset = Vector3(-dx,-dy,0):getNormalized()*safedist; -- 获取远离玩家方向的模向量*安全距离
	ax = x + offset:getX();
	ay = y + offset:getY();
	--outputChatBox("ax:"..tostring(ax).." ay:"..tostring(ay))

		-- 如果太靠近

	if dx*dx+dy*dy > safedist*safedist then -- 足够安全了
		--outputChatBox("I AM SAFE");
		stopAllNPCActions(npc) -- 我要休息
		return true -- 任务完成！
	else
		makeNPCWalkToPos(npc,ax,ay,"run") -- 继续跑
	end

end
-- arrest element
function performTask.arrestElement(npc,task)
	local target = task[2]
	if not isElement(target) or not isElementStreamedIn(target) or target == nil then 
		return true
	end
	if getElementType(target) == "vehicle" then 
		return true 
	end
	if getElementHealth(target) < 1 or getElementHealth(npc) < 1 then 
		stopAllNPCActions(npc)
		return true 
	end
	if target == npc then 
		return true
	end
	local pTask = getPedSimplestTask(npc)
	if getElementType(target) == "player" and pTask == "TASK_SIMPLE_CAR_SLOW_DRAG_PED_OUT" then 
		stopAllNPCActions(npc)
		setPedExitVehicle (npc)
		--removePedFromVehicle (localPlayer)    
		triggerServerEvent ( "onPlayerBusted", target,npc)
		--print("Busted!")
		return true
	end

	local x,y,z = getElementPosition(npc)
	local tx,ty,tz = getElementPosition(target)
	local dx,dy = tx-x,ty-y
	local distsq = dx*dx+dy*dy


	local dist = distsq

	local followdist = 10
	local shootdist = 10
	

	local hasWeapon = getPedAvaiableWeaponSlot(npc)

	local t_speed = getElementSpeed(target,1)
	local n_speed = getElementSpeed(npc,1)

	local car = getPedOccupiedVehicle(npc)
	if car and getVehicleType(car) == "Helicopter" then 
		stopAllNPCActions(npc)
		makeNPCDriveToPos(npc,tx,ty,tz,false)		
	elseif car then -- if is in vehicle

		stopAllNPCActions(npc)
		--print(getElementSpeed(target,1))
		if getPedOccupiedVehicleSeat(npc) == 0 then
			setNPCDriveSpeed(npc,t_speed + 20)
			setVehicleSirensOn ( car, true )
			makeNPCChasePlayer(npc,target)	
		end
		if distsq <= 20 and t_speed < 40 then 
			stopAllNPCActions(npc)
			--triggerServerEvent("setPedDoingGangDriveby", resourceRoot, npc, false )
			makeNPCExitFromVehicle(npc)
		end

	else
		--setPedDoingGangDriveby(npc, false)
		-- perform using weapon, if have one 
		if hasWeapon ~= 0 then -- switch to what ever weapon it has
			setPedWeaponSlot (npc,hasWeapon)
		end
	
		if isNPCCurrentHoldingMeleeWeapon(npc) then 
			local veh = getPedOccupiedVehicle(target) -- if on vehicle
			if veh then 
				--stopAllNPCActions(npc)
				makeNPCEnterToVehicle(npc,veh,"run")	
			else
				if dist > 1.1 and t_speed < 50 then 
					makeNPCWalkToPos(npc,tx,ty,"run")
				else 
					stopNPCWalkingActions(npc)
					setPedAimTarget(npc,tx,ty,tz)
					--stopAllNPCActions(npc)
					makeNPCShootAtElement(npc,target,0)
					
				end
			end
			
		else
			stopAllNPCActions(npc)
			local veh = getPedOccupiedVehicle(target)
			if veh and distsq < 100 then -- shoot
				makeNPCShootAtElement(npc,target,0)
				return
			elseif distsq < shootdist*shootdist then
				--setPedWeaponSlot (npc,hasWeapon)
				--setPedRotation(npc,-math.deg(math.atan2(dx,dy)))
				makeNPCShootAtElement(npc,target,0)
				return
			else
				makeNPCWalkToPos(npc,tx,ty,"run")
				return
			end
			
		end
	end

end
-- attack target using any way
function performTask.chaseElement(npc,task)
	local target = task[2]
	if not isElement(target) or not isElementStreamedIn(target) or target == nil then 
		return false
	end
	if getElementType(target) == "vehicle" then 
		return true 
	end
	if getElementHealth(target) < 1 or getElementHealth(npc) < 1 then 
		stopAllNPCActions(npc)
		return false 
	end
	if target == npc then 
		return true
	end
	makeNPCChasePlayer(npc,target) 
end
function performTask.attackElement(npc,task)
	local target= task[2]
	if not isElement(target) or target == nil then 
		return true
	end
	if target == npc then 
		return true
	end
	if not isElement(target) or getElementHealth(target) < 1 then 
		stopAllNPCActions(npc)
		return true 
	end
	if getElementHealth(npc) < 1 then 
		stopAllNPCActions(npc)
		return false 
	end
	makeNPCAttackTarget(npc,target)
	
end

function performTask.driveToPos(npc,task)
	if getPedOccupiedVehicle(npc) == false then return false end
	local veh = getPedOccupiedVehicle(npc)
	if veh == false then return false end
	local destx,desty,destz,dest_dist = task[2],task[3],task[4],task[5]
	local x,y,z = getElementPosition(getPedOccupiedVehicle(npc))
	local distx,disty,distz = destx-x,desty-y,destz-z
	local dist = distx*distx+disty*disty+distz*distz
	local vType = getVehicleType (veh)
	if vType == "Helicopter" then
		if dist < dest_dist*dest_dist and math.abs(distz) < 3 then 
			stopAllNPCActions(npc)
			return true 
		end
	else
		if dist < dest_dist*dest_dist then 
			stopAllNPCActions(npc)
			return true 
		end
	end
	
	makeNPCDriveToPos(npc,destx,desty,destz)
end

function performTask.driveAlongLine(npc,task)
	if getPedOccupiedVehicle(npc) == false then return false end
	local x1,y1,z1,x2,y2,z2 = task[2],task[3],task[4],task[5],task[6],task[7]
	local off,enddist,light = task[8],task[9],task[10]
	local x,y,z = getElementPosition(getPedOccupiedVehicle(npc))
	local pos = getPercentageInLine(x,y,x1,y1,x2,y2)
	local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
	if pos >= 1-enddist/len then 
		stopAllNPCActions(npc)
		return true 
	end
	makeNPCDriveAlongLine(npc,x1,y1,z1,x2,y2,z2,off,light)
end

function performTask.driveAroundBend(npc,task)
	if getPedOccupiedVehicle(npc) == false then return false end
	local x0,y0 = task[2],task[3]
	local x1,y1,z1 = task[4],task[5],task[6]
	local x2,y2,z2 = task[7],task[8],task[9]
	local off,enddist = task[10],task[11]
	local x,y,z = getElementPosition(getPedOccupiedVehicle(npc))
	local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*math.pi*0.5
	local angle = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)+enddist/len
	if angle >= math.pi*0.5 then 
		stopAllNPCActions(npc)
		return true 
	end
	makeNPCDriveAroundBend(npc,x0,y0,x1,y1,z1,x2,y2,z2,off)
end

function performTask.waitForGreenLight(npc,task)
	if getPedOccupiedVehicle(npc) == false then return false end
	-- skip if npc is set to drive agressive
	if getNPCDriveStyle(npc) ~= "aggressive" then
		makeNPCwaitForGreenLight(npc)
		local state = getTrafficLightState()
		if state == 6 or state == 9 then return true end
		if task[2] == "NS" then
			return state == 0 or state == 5 or state == 8
		elseif task[2] == "WE" then
			return state == 3 or state == 5 or state == 7
		elseif task[2] == "ped" then
			return state == 2
		end
	end
	return true
end

