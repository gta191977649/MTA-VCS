local function setControlAxis(npc, negative, positive, value)
	-- MTA neutralizes a stick axis when both directions are pressed.
	if value < 0 then
		setPedAnalogControlState(npc, positive, 0)
		setPedAnalogControlState(npc, negative, math.min(1, -value))
	else
		setPedAnalogControlState(npc, negative, 0)
		setPedAnalogControlState(npc, positive, math.min(1, value))
	end
end

function setNPCVehicleInputs(npc, steering, pedal, handbrake, pitch)
	setControlAxis(npc, "vehicle_left", "vehicle_right", steering)
	setControlAxis(npc, "steer_forward", "steer_back", pitch or 0)
	if handbrake then
		setControlAxis(npc, "brake_reverse", "accelerate", 0)
		setPedControlState(npc, "handbrake", true)
	else
		setPedControlState(npc, "handbrake", false)
		setControlAxis(npc, "brake_reverse", "accelerate", pedal)
	end
end

function stopAllNPCActions(npc)
	stopNPCWalkingActions(npc)
	stopNPCWeaponActions(npc)
	stopNPCDrivingActions(npc)

	setPedControlState(npc,"vehicle_fire",false)
	setPedControlState(npc,"vehicle_secondary_fire",false)
	setPedControlState(npc,"horn",false)
end

function releaseNPCActions(npc)
	stopNPCWalkingActions(npc)
	stopNPCWeaponActions(npc)
	setNPCVehicleInputs(npc, 0, 0, false)
	setPedControlState(npc,"vehicle_fire",false)
	setPedControlState(npc,"vehicle_secondary_fire",false)
	setPedControlState(npc,"horn",false)
end

function stopNPCWalkingActions(npc)
	setPedControlState(npc,"forwards",false)
	setPedControlState(npc,"sprint",false)
	setPedControlState(npc,"walk",false)
end

function stopNPCWeaponActions(npc)
	setPedControlState(npc,"aim_weapon",false)
	setPedControlState(npc,"fire",false)
end

function stopNPCDrivingActions(npc)
	local car = getPedOccupiedVehicle(npc)
	local m = car and getElementMatrix(car)
	if not m then setNPCVehicleInputs(npc, 0, 0, false) return end
	local vx,vy,vz = getElementVelocity(car)
	vy = vx*m[2][1]+vy*m[2][2]+vz*m[2][3]
	setNPCVehicleInputs(npc, 0, vy > 0.01 and -1 or 0, vy < -0.01)
end

function makeNPCWalkToPos(npc,x,y,pace)
	recordNPCDebugTarget(npc,x,y)
	local px,py = getElementPosition(npc)
	setPedCameraRotation(npc,math.deg(math.atan2(x-px,y-py)))
	setPedControlState(npc,"forwards",true)
	local speed = pace or getNPCWalkSpeed(npc)
	setPedControlState(npc,"walk",speed == "walk")
	setPedControlState(npc,"sprint",
		speed == "sprint" or
		speed == "sprintfast" and not getPedControlState(npc,"sprint")
	)
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
	local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*math.pi*0.5
	local p2 = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)/math.pi*2+off/len
	local destx,desty = getPosFromBend(p2*math.pi*0.5,x0,y0,x1,y1,x2,y2)
	makeNPCWalkToPos(npc,destx,desty)
end

function makeNPCShootAtPos(npc,x,y,z)
	local sx,sy,sz = getElementPosition(npc)
	x,y,z = x-sx,y-sy,z-sz
	local distance = math.sqrt(x*x+y*y+z*z)
	if distance == 0 then return end
	local yx,yy,yz = 0,0,1
	if x == 0 and y == 0 then yx,yz = 1,0 end
	local xx,xy,xz = yy*z-yz*y,yz*x-yx*z,yx*y-yy*x
	yx,yy,yz = y*xz-z*xy,z*xx-x*xz,x*xy-y*xx
	local inacc = 1-getNPCWeaponAccuracy(npc)
	local ticks = getTickCount()
	local xmult = inacc*math.sin(ticks*0.01 )*1000/math.sqrt(xx*xx+xy*xy+xz*xz)
	local ymult = inacc*math.cos(ticks*0.011)*1000/math.sqrt(yx*yx+yy*yy+yz*yz)
	local mult = 1000/distance
	xx,xy,xz = xx*xmult,xy*xmult,xz*xmult
	yx,yy,yz = yx*ymult,yy*ymult,yz*ymult
	x,y,z = x*mult,y*mult,z*mult
	
	setPedAimTarget(npc,sx+xx+yx+x,sy+xy+yy+y,sz+xz+yz+z)
	if isPedInVehicle(npc) then
		setPedControlState(npc,"vehicle_fire",not getPedControlState(npc,"vehicle_fire"))
	else
		setPedControlState(npc,"aim_weapon",true)
		setPedControlState(npc,"fire",not getPedControlState(npc,"fire"))
	end
end

function makeNPCShootAtElement(npc,target)
	local x,y,z = getElementPosition(target)
	local vx,vy,vz = getElementVelocity(target)
	local tgtype = getElementType(target)
	if tgtype == "ped" or tgtype == "player" then
		local bx,by,bz = getPedBonePosition(target,3)
		if bx then x,y,z = bx,by,bz end
		local vehicle = getPedOccupiedVehicle(target)
		if vehicle then
			vx,vy,vz = getElementVelocity(vehicle)
		end
	end
	vx,vy,vz = vx*6,vy*6,vz*6
	makeNPCShootAtPos(npc,x+vx,y+vy,z+vz)
end

function makeNPCDriveToPos(npc,x,y,z,traffic,cruiseSpeed)
	recordNPCDebugTarget(npc,x,y,z)
	local car = getPedOccupiedVehicle(npc)
	local m = car and getElementMatrix(car)
	if not m then setNPCVehicleInputs(npc, 0, 0, false) return end
	x,y,z = x-m[4][1],y-m[4][2],z-m[4][3]
	local distance = math.sqrt(x*x+y*y+z*z)
	if distance == 0 then stopNPCDrivingActions(npc) return end
	local rx,ry,rz =
		x*m[1][1]+y*m[1][2]+z*m[1][3],
		x*m[2][1]+y*m[2][2]+z*m[2][3],
		x*m[3][1]+y*m[3][2]+z*m[3][3]
	local turn
	if traffic then
		turn = math.atan2(rx, ry)
	elseif ry <= 0 then
		turn = rx < 0 and -1 or 1
	else
		local secondpart = getTickCount()%100
		local steering = rx * 500 / ry
		turn = steering < -secondpart and -1 or steering > secondpart and 1 or 0
	end
	local vx,vy,vz = getElementVelocity(car)
	local vrx,vry,vrz =
		vx*m[1][1]+vy*m[1][2]+vz*m[1][3],
		vx*m[2][1]+vy*m[2][2]+vz*m[2][3],
		vx*m[3][1]+vy*m[3][2]+vz*m[3][3]
	local speed
	do
		local _,_,z1,_,y2 = getElementBoundingBox(car)
		z1,y2 = (z1 or 0)+1,y2 or 0
		local vx,vy,vz = m[4][1]+m[3][1]*z1,m[4][2]+m[3][2]*z1,m[4][3]+m[3][3]*z1
		local mult = (y2+6)/distance
		local dx,dy,dz = x*mult,y*mult,z*mult
		if traffic then
			speed = (cruiseSpeed or getNPCDriveSpeed(npc))*math.sin(math.pi*0.5-math.atan2(math.abs(rx),math.abs(ry))*0.75)
			local hit,hx,hy,hz,obstacle = processLineOfSight(vx,vy,vz,vx+dx,vy+dy,vz+dz,
				false,true,true,false,true,false,false,false,car)
			if hit then
				local gap = getDistanceBetweenPoints3D(vx,vy,vz,hx,hy,hz)-y2
				local lead = 0
				if isElement(obstacle) and getElementType(obstacle) == "vehicle" then
					local ox,oy,oz = getElementVelocity(obstacle)
					lead = math.max(0,ox*m[2][1]+oy*m[2][2]+oz*m[2][3])
				end
				speed = math.min(speed, math.max(0,lead+(gap-2)*0.04))
			end
		elseif not isLineOfSightClear(vx,vy,vz,vx+dx,vy+dy,vz+dz,false,true,true,false,true,false,false,car) then
			speed = 0
		else
			speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan2(math.abs(rx),math.abs(ry))*0.75)
		end
	end
	local pedal
	if traffic then
		-- MTA controls are analog. Coast near the cruise speed and brake only
		-- for a blocked path or when entering a turn too quickly.
		local speedError = speed - vry
		if speed > 0 and speedError > 0 then
			pedal = speedError * 8
		elseif vry > 0.015 then
			pedal = speed == 0 and -1 or math.min(0, (speedError + 0.04) * 8)
		end
	else
		pedal = speed > 0 and vry < speed and 1 or vry > speed * 1.1 and -1 or 0
	end
	setNPCVehicleInputs(npc, turn, pedal or 0, speed == 0 and vry < -0.01)
end

function makeNPCDriveAlongLine(npc,x1,y1,z1,x2,y2,z2,off)
	local car = getPedOccupiedVehicle(npc)
	local x,y,z = getElementPosition(car)
	local p2 = getPercentageInLine(x,y,x1,y1,x2,y2)
	local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
	p2 = p2+off/len
	local p1 = 1-p2
	local destx,desty,destz = p1*x1+p2*x2,p1*y1+p2*y2,p1*z1+p2*z2
	makeNPCDriveToPos(npc,destx,desty,destz)
end

function makeNPCDriveAroundBend(npc,x0,y0,x1,y1,z1,x2,y2,z2,off)
	local car = getPedOccupiedVehicle(npc)
	local x,y,z = getElementPosition(car)
	local len = getDistanceBetweenPoints2D(x1,y1,x2,y2)*math.pi*0.5
	local p2 = getAngleInBend(x,y,x0,y0,x1,y1,x2,y2)/math.pi*2
	p2 = math.max(0,math.min(1,p2))
	p2 = p2+off/len
	local destx,desty = getPosFromBend(p2*math.pi*0.5,x0,y0,x1,y1,x2,y2)
	local destz = (1-p2)*z1+p2*z2
	makeNPCDriveToPos(npc,destx,desty,destz)
end

