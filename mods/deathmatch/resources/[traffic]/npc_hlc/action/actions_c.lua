DGS = exports.dgs



local _isLineOfSightClear = isLineOfSightClear
local _processLineOfSight = processLineOfSight
function processLineOfSight(startX,startY,startZ,endX,endY,endZ,checkBuildings,checkVehicles,checkPlayers,checkObjects,checkDummies,seeThroughStuff,ignoreSomeObjectsForCamera,shootThroughStuff,ignoredElement,includeWorldModelInformation)
	local isClear = isLineOfSightClear(startX,startY,startZ,endX,endY,endZ,checkBuildings,checkVehicles,checkPlayers,checkObjects,checkDummies,seeThroughStuff,ignoreSomeObjectsForCamera,ignoredElement)
	if not isClear then
		return _processLineOfSight(startX,startY,startZ,endX,endY,endZ,checkBuildings,checkVehicles,checkPlayers,checkObjects,checkDummies,seeThroughStuff,ignoreSomeObjectsForCamera,shootThroughStuff,ignoredElement,includeWorldModelInformation )
	end
	return false
end


function stopAllNPCActions(npc)
	stopNPCWalkingActions(npc)
	stopNPCWeaponActions(npc)
	stopNPCDrivingActions(npc)
	setPedDoingGangDriveby(npc,false)
	setPedControlState(npc,"vehicle_fire",false)
	setPedControlState(npc,"vehicle_secondary_fire",false)
	setPedControlState(npc,"steer_forward",false)
	setPedControlState(npc,"steer_back",false)
	setPedControlState(npc,"horn",false)
	setPedControlState(npc,"handbrake",false)
	--[[
	if AI[npc] ~= nil then
		AI[npc].decision = AI.decisions[1]
	end
	]]
end

function stopNPCWalkingActions(npc)
	setPedControlState(npc,"forwards",false)
	setPedControlState(npc,"backwards",false)
	setPedControlState(npc,"sprint",false)
	setPedControlState(npc,"walk",false)
	setPedControlState(npc,"right",false)
	setPedControlState(npc,"left",false)
end

function stopNPCWeaponActions(npc)
	setPedControlState(npc,"aim_weapon",false)
	setPedControlState(npc,"fire",false)
end

function stopNPCDrivingActions(npc)
	local car = getPedOccupiedVehicle(npc)
	if not car then return end
	local m = getElementMatrix(car)
	local vx,vy,vz = getElementVelocity(car)
	vy = vx*m[2][1]+vy*m[2][2]+vz*m[2][3]
	setPedControlState(npc,"accelerate",vy < -0.01)
	setPedControlState(npc,"brake_reverse",vy > 0.01)
	setPedControlState(npc,"vehicle_left",false)
	setPedControlState(npc,"vehicle_right",false)
	setPedControlState(npc,"steer_forward",false)
	setPedControlState(npc,"steer_back",false)
end

function makeNPCWalkToPos(npc,x,y,speed,ingnoreRaycast)
	if isPedInVehicle (npc) then return end
	ingnoreRaycast = ingnoreRaycast or false
	speed = speed ~= nil and speed or getNPCWalkSpeed(npc)
	
	AI[npc].task = getNPCCurrentTask(npc)[1]
	local px,py,pz = getElementPosition(npc)
	local cameraAngle = math.deg(mathAtan2(x-px,y-py))
	setPedCameraRotation(npc,cameraAngle)
	local ray_eye_l = false
	local ray_eye_m = false
	local ray_eye_r = false
	if ingnoreRaycast == false then
		ray_eye_l = createPedRaycast(npc,"raycast_eye_l")
		ray_eye_m = createPedRaycast(npc,"raycast_eye_m")
		ray_eye_r = createPedRaycast(npc,"raycast_eye_r")
	end
	local currentTick = getTickCount()

	if AI[npc].decision == AI.decisions[1] then
		if ray_eye_l and ray_eye_r and ray_eye_m or ray_eye_l and ray_eye_r then 
			
			AI[npc].decision = AI.decisions[7]
			AI[npc].lastDecisionTick = currentTick
		end
		
		if ray_eye_l then 
			--controlPedRight(npc)
			AI[npc].decision = AI.decisions[5]
			AI[npc].lastDecisionTick = currentTick
		end
		if ray_eye_r then 
			--controlPedLeft(npc)
			AI[npc].decision = AI.decisions[6]
			AI[npc].lastDecisionTick = currentTick
		end
		if ray_eye_m then 
			--setPedAnimation(npc,"ped","ev_dive")
			local dir = math.random(1,2)
			if dir == 1 then
				AI[npc].decision = AI.decisions[5]
				AI[npc].lastDecisionTick = currentTick
			end
			if dir == 2 then
				AI[npc].decision = AI.decisions[6]
				AI[npc].lastDecisionTick = currentTick
			end
		end

		if isElementInWater(npc) then 
			local angle = 360-math.deg(math.atan2(x-px,y-py))
			setPedRotation(npc,angle)
		end

	end
	
	-- ai decision
	if AI[npc].decision == AI.decisions[5] then 
		controlPedRight(npc)
		--setPedCameraRotation(npc,cameraAngle + 90)
		if not ray_eye_l or AI[npc].lastDecisionTick ~= nil and currentTick - AI[npc].lastDecisionTick >= AI.config.decision_walk_timeout then
			AI[npc].decision = AI.decisions[1]
		end
		
	end
	if AI[npc].decision == AI.decisions[6] then 
		controlPedLeft(npc)
		--setPedCameraRotation(npc,cameraAngle - 90)
		if not ray_eye_r or currentTick - AI[npc].lastDecisionTick >= AI.config.decision_walk_timeout then
			AI[npc].decision = AI.decisions[1]
		end
		
	end
	if AI[npc].decision == AI.decisions[7] then 
		
		controlPedBack(npc)
		--setPedCameraRotation(npc,cameraAngle + 180)
		if currentTick - AI[npc].lastDecisionTick >= AI.config.decision_walk_timeout then
			AI[npc].decision = AI.decisions[1]
		end
		
	end

	setPedControlState(npc,"forwards",true)
	setPedControlState(npc,"walk",speed == "walk")
	setPedControlState(npc,"sprint",speed == "sprint" or speed == "sprintfast" and not getPedControlState(npc,"sprint"))

	if debug and AI[npc] ~= nil then
		renderDebug(npc)
	end
end

function makeNPCEnterToVehicle(npc,vehicle,speed)
	if not isElement(npc) or not isElement(vehicle) then return end
	speed = speed or getNPCWalkSpeed(npc)
	--print("[C] Set setPedEnterVehicle")
	local x,y,z = getElementPosition(npc)
	local vx,vy,vz = getElementPosition(vehicle)

	local dis = getDistanceBetweenPoints3D(x,y,z,vx,vy,vz)
	if dis <= 3.5 then
		setPedEnterVehicle(npc,vehicle)
	else
		makeNPCWalkToPos(npc,vx,vy,speed)
	end
end
function makeNPCAttackTarget(npc,target) 
	if getPedOccupiedVehicle(npc) then 	
		stopAllNPCActions(npc)
		makeNPCExitFromVehicle(npc)
	end
	local x,y,z = getElementPosition(npc)
	local tx,ty,tz = getElementPosition(target)
	local dx,dy = tx-x,ty-y
	local distsq = dx*dx+dy*dy


	local dist = distsq

	local followdist = 10
	local shootdist = 10
	-- perform using weapon, if have one 
	local hasWeapon = getPedAvaiableWeaponSlot(npc)
	if hasWeapon ~= 0 then -- switch to what ever weapon it has
		setPedWeaponSlot (npc,hasWeapon)
	end

	if isNPCCurrentHoldingMeleeWeapon(npc) then 
		local veh = getPedOccupiedVehicle(target) -- if on vehicle
		if veh then 
			--stopAllNPCActions(npc)
			makeNPCEnterToVehicle(npc,veh,"run")	
		else
			if dist > 1.1 then 
				makeNPCWalkToPos(npc,tx,ty,"run")
			else 
				stopNPCWalkingActions(npc)
				setPedAimTarget(npc,tx,ty,tz)
				--stopAllNPCActions(npc)
				makeNPCShootAtElement(npc,target)
			end
		end
		
	else
		
		if distsq < shootdist*shootdist then
			setPedWeaponSlot (npc,hasWeapon)
			makeNPCShootAtElement(npc,target)
			setPedRotation(npc,-math.deg(math.atan2(dx,dy)))
		end
		if distsq > followdist*followdist then
			makeNPCWalkToPos(npc,tx,ty,"run")
		else
			stopNPCWalkingActions(npc)
	
		end
	
	end
end
-- Runing inverse the target
function makeNpcRunAvoidTarget(npc,target,dist)
	local nx,ny,nz = getElementPosition(npc)
	local tx,ty,tz = getElementPosition(target)
	local d = getDistanceBetweenPoints3D (nx,ny,nz,tx,ty,tz)
	if d < dist then  
		local x,y,z = getPositionFromElementOffset(target,0,dist,0)
		makeNPCWalkToPos(npc,x,y,"run")
		if debug then 
			dxDrawLine3D(tx,ty,tz, x,y,z,tocolor ( 255, 0, 0, 255 ))
		end
	end
end
function makeNPCStopMovement(npc)
	setPedControlState(npc,"forwards",false)
end

function makeNPCExitFromVehicle(npc)
	--if not isPedInVehicle(npc) then return true end
	if getPedSimplestTask(npc) == "TASK_SIMPLE_CAR_DRIVE" then 
		setPedDoingGangDriveby(npc, false)
		setPedExitVehicle(npc)
		--print(getPedSimplestTask(npc))
	end	
end

function makeNPCWalkAlongLine(npc,x1,y1,z1,x2,y2,z2,off)
	local x,y,z = getElementPosition(npc)
	local p2 = getPercentageInLine(x,y,x1,y1,x2,y2)
	local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
	p2 = p2+off/len
	local p1 = 1-p2
	local destx,desty = p1*x1+p2*x2,p1*y1+p2*y2
	makeNPCWalkToPos(npc,destx,desty)
end

function makeNPCWalkAroundBend(npc,x0,y0,x1,y1,x2,y2,off)
	local x,y,z = getElementPosition(npc)
	local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*mathPi*0.5
	local p2 = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)/mathPi*2+off/len
	local destx,desty = getPosFromBend(p2*mathPi*0.5,x0,y0,x1,y1,x2,y2)
	makeNPCWalkToPos(npc,destx,desty)
end

function makeNPCShootAtPos(npc,x,y,z,reloadTime)
	if getPedWeapon(npc) ~= 0 then
		reloadTime = reloadTime or 500
	else 
		--reloadTime = reloadTime or 250
		reloadTime = 500
	end
	if not isElement(npc) then return end
	if getTickCount() - AI[npc].lastAttackTick < reloadTime then return end
	local sx,sy,sz = getElementPosition(npc)
	x,y,z = x-sx,y-sy,z-sz
	local yx,yy,yz = 0,0,1
	local xx,xy,xz = yy*z-yz*y,yz*x-yx*z,yx*y-yy*x
	yx,yy,yz = y*xz-z*xy,z*xx-x*xz,x*xy-y*xx
	local inacc = 1-getNPCWeaponAccuracy(npc)
	local ticks = getTickCount()
	local xmult = inacc*mathSin(ticks*0.01 )*1000/math.sqrt(xx*xx+xy*xy+xz*xz)
	local ymult = inacc*mathCos(ticks*0.011)*1000/math.sqrt(yx*yx+yy*yy+yz*yz)
	local mult = 1000/math.sqrt(x*x+y*y+z*z)
	xx,xy,xz = xx*xmult,xy*xmult,xz*xmult
	yx,yy,yz = yx*ymult,yy*ymult,yz*ymult
	x,y,z = x*mult,y*mult,z*mult
	setPedAimTarget(npc,sx+xx+yx+x,sy+xy+yy+y,sz+xz+yz+z)
	local rz = findRotation(sx,sy,sx+xx+yx+x,sy+xy+yy+y ) 
	setElementRotation(npc,0,0,rz)
	if isPedInVehicle(npc) then
		setPedControlState(npc,"vehicle_fire",not getPedControlState(npc,"vehicle_fire"))
	else	
		setPedControlState(npc,"aim_weapon",true)
		setPedControlState(npc,"fire",not getPedControlState(npc,"fire"))
		setPedControlState(npc,"enter_exit",not getPedControlState(npc,"fire"))
		if not getPedWeapon(npc) == 0 then
			if isPedReloadingWeapon(npc) then
				AI[npc].lastAttackTick = getTickCount()
			end
		else
			AI[npc].lastAttackTick = getTickCount()
		end
	end
	if debug == true then
		dxDrawLine3D(sx,sy,sz,sx+xx+yx+x,sy+xy+yy+y,sz+xz+yz+z,tocolor ( 255, 0, 0, 255 ))
	end
end

function makeNPCShootAtElement(npc,target,reloadTime)
	if not isElement(npc) then return end
	local x,y,z = getElementPosition(target)
	local vx,vy,vz = getElementVelocity(target)
	local tgtype = getElementType(target)
	if tgtype == "ped" or tgtype == "player" then
		x,y,z = getPedBonePosition(target,3)
		local vehicle = getPedOccupiedVehicle(target)
		if vehicle then
			vx,vy,vz = getElementVelocity(vehicle)
		end
	end
	vx,vy,vz = vx*6,vy*6,vz*6
	makeNPCShootAtPos(npc,x+vx,y+vy,z+vz,reloadTime)
end


function isVehicleWaitingTrafficLight(veh)
	if isElement(veh) and getElementType(veh) == "vehicle" then
		local npc = getVehicleOccupant (veh,0)
		if AI[npc] ~= nil then 
			if AI[npc].task == "waitForGreenLight" then return true end
		end
	end
	return false
end
function isGreenLight(direction)
	local state = getTrafficLightState()
	if direction == "NS" then 
		return state == 0 or state == 5 or state == 8
	end
	if direction == "WE" then 
		return state == 3 or state == 5 or state == 7
	end
end
function makeNPCChasePlayer(npc,player) 
	if not isElement(npc) then return end
	local car = getPedOccupiedVehicle(npc)
	if car then -- if in vehicle
		if isElementStreamedIn(car) then -- do it only when the car is streamed in
			local type = getVehicleType (car)
			if type == "Automobile" or type == "BMX" or type == "Bike" or type == "Quad" or type == "Monster Truck" or type == "Boat" then
				AI[npc].light = false
				doNPCChasePlayer(npc,car,player)
			end
			if type == "Helicopter" then
				doNPCDriveHelicopter(npc,car,x,y,z)
			end

			if debug and AI[npc] ~= nil then
				renderDebug(npc)
			end
		end
	else --if on foot
		local x,y,_ = getPositionFromElementOffset(player,0,2,0)
		makeNPCWalkToPos(npc,x,y)
	end
end
function makeNPCDriveToPos(npc,x,y,z,light)
	if not isElement(npc) then return end
	local car = getPedOccupiedVehicle(npc)
	if car == nil then return end
	light = light or false
	
	
	if isElementStreamedIn(car) then -- do it only when the car is streamed in

		local type = getVehicleType (car)
		if type == "Automobile" or type == "BMX" or type == "Bike" or type == "Quad" or type == "Monster Truck" or type == "Boat" then
			AI[npc].light = light
			doNPCDriveCar(npc,car,x,y,z)
		end
		if type == "Helicopter" then
			doNPCDriveHelicopter(npc,car,x,y,z)
		end
		if type == "Boat" then
			doNPCDriveBoat(npc,car,x,y,z)
		end

		if debug and AI[npc] ~= nil then
			renderDebug(npc)
		end
	end
	

end

--[[
addEventHandler("onClientVehicleCollision", root,
	function(collider, damageImpulseMag, bodyPart, x, y, z, nx, ny, nz,hitElementforce,model)
		if collider ~= nil then return end
		local npc = getVehicleOccupant (source,0)

		if isModelObstcle(model) then
			if AI[npc] ~= nil and AI[npc].decision == AI.decisions[2] and bodyPart == 4 or AI[npc] ~= nil and collider == nil then
				AI[npc].decision = AI.decisions[3]
				AI[npc].lastDecisionTick = getTickCount()
			end
		end		
	end
)
]]
function makeNPCDriveAlongLine(npc,x1,y1,z1,x2,y2,z2,off,light)
	local car = getPedOccupiedVehicle(npc)
	local x,y,z = getElementPosition(car)
	local p2 = getPercentageInLine(x,y,x1,y1,x2,y2)
	local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
	p2 = p2+off/len
	local p1 = 1-p2
	local destx,desty,destz = p1*x1+p2*x2,p1*y1+p2*y2,p1*z1+p2*z2
	makeNPCDriveToPos(npc,destx,desty,destz,light)
end

function makeNPCDriveAroundBend(npc,x0,y0,x1,y1,z1,x2,y2,z2,off)
	local car = getPedOccupiedVehicle(npc)
	local x,y,z = getElementPosition(car)
	local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*mathPi*0.5
	local p2 = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)/mathPi*2

	--print(p2)
	--setElementAngularVelocity(car,0,0,p2/100)
	p2 = math.max(0,math.min(1,p2))
	p2 = p2+off/len
	--print(x1-x0)
	--setElementAngularVelocity(car,0,0,1-p2)
	local destx,desty = getPosFromBend(p2*mathPi*0.5,x0,y0,x1,y1,x2,y2)
	local destz = (1-p2)*z1+p2*z2
	makeNPCDriveToPos(npc,destx,desty,destz)
end

function makeNPCwaitForGreenLight(npc)
	stopAllNPCActions(npc)
	if AI[npc] ~= nil then
		AI[npc].task = getNPCCurrentTask(npc)[1]
	end
	if debug and AI[npc] ~= nil then
		renderDebug(npc)
	end
end

function renderDebug(npc) 
	light = AI[npc].light or nil
	-- render debug text
	local group = getElementData(npc,"npchlc:group") == false and "DEFAULT" or getElementData(npc,"npchlc:group")
	local temper = getElementData(npc,"npchlc:temper") == false and "N/A" or getElementData(npc,"npchlc:temper")

	local task_complex = getPedTask(npc,"primary",3)
	DGS:dgsSetProperty(AI[npc].text,"text",string.format("%s\nGROUP:%s\nTEMPER:%d\nDECISION:%s\nLIGHT:%s\nPED_TASK:%s\nT_COMP:%s\nIS_HITED:%s",AI[npc].task,group or "N/A",temper,AI[npc].decision,light ~= nil and light or "N/A",getPedSimplestTask (npc),task_complex or "N/A",AI[npc].hited and "true" or "false"))
end

