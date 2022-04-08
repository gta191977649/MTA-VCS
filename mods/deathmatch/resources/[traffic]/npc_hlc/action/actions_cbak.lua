function stopAllNPCActions(npc)
	stopNPCWalkingActions(npc)
	stopNPCWeaponActions(npc)
	stopNPCDrivingActions(npc)
	setPedControlState(npc,"vehicle_fire",false)
	setPedControlState(npc,"vehicle_secondary_fire",false)
	setPedControlState(npc,"steer_forward",false)
	setPedControlState(npc,"steer_back",false)
	setPedControlState(npc,"horn",false)
	setPedControlState(npc,"handbrake",false)
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

--Ai Detect Settings (By Nurupo)
sensorOffset =2
sensorOffsetZ =0
sensorOffsetY =1
sensorDetectLength =7

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
end

function makeNPCWalkToPos(npc,x,y,speed)
	speed = speed or getNPCWalkSpeed(npc)
	local px,py = getElementPosition(npc)
	setPedCameraRotation(npc,math.deg(math.atan2(x-px,y-py)))
	setPedControlState(npc,"forwards",true)
	
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
	local yx,yy,yz = 0,0,1
	local xx,xy,xz = yy*z-yz*y,yz*x-yx*z,yx*y-yy*x
	yx,yy,yz = y*xz-z*xy,z*xx-x*xz,x*xy-y*xx
	local inacc = 1-getNPCWeaponAccuracy(npc)
	local ticks = getTickCount()
	local xmult = inacc*math.sin(ticks*0.01 )*1000/math.sqrt(xx*xx+xy*xy+xz*xz)
	local ymult = inacc*math.cos(ticks*0.011)*1000/math.sqrt(yx*yx+yy*yy+yz*yz)
	local mult = 1000/math.sqrt(x*x+y*y+z*z)
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
		x,y,z = getPedBonePosition(target,3)
		local vehicle = getPedOccupiedVehicle(target)
		if vehicle then
			vx,vy,vz = getElementVelocity(vehicle)
		end
	end
	vx,vy,vz = vx*6,vy*6,vz*6
	makeNPCShootAtPos(npc,x+vx,y+vy,z+vz)
end


function makeNPCDriveToPos(npc,x,y,z,checkSight)
	local car = getPedOccupiedVehicle(npc)
	local m = getElementMatrix(car)
	x,y,z = x-m[4][1],y-m[4][2],z-m[4][3]
	local rx,ry,rz =
	x*m[1][1]+y*m[1][2]+z*m[1][3],
	x*m[2][1]+y*m[2][2]+z*m[2][3],
	x*m[3][1]+y*m[3][2]+z*m[3][3]
	if ry <= 0 then
		setPedControlState(npc,"vehicle_left",rx < 0)
		setPedControlState(npc,"vehicle_right",rx >= 0)
	else
		local secondpart = getTickCount()%100
		setPedControlState(npc,"vehicle_left",rx*500/ry < -secondpart)
		setPedControlState(npc,"vehicle_right",rx*500/ry > secondpart)
	end
	local vx,vy,vz = getElementVelocity(car)
	local vrx,vry,vrz =
	vx*m[1][1]+vy*m[1][2]+vz*m[1][3],
	vx*m[2][1]+vy*m[2][2]+vz*m[2][3],
	vx*m[3][1]+vy*m[3][2]+vz*m[3][3]
	local speed

	local x1,y1,z1,x2,y2,z2 = getElementBoundingBox(car)
	z1 = z1+1
	local vx,vy,vz = m[4][1]+m[3][1]*z1,m[4][2]+m[3][2]*z1,m[4][3]+m[3][3]*z1
	local mult = (y2+6)/math.sqrt(x*x+y*y+z*z)
	local dx,dy,dz = x*mult,y*mult,z*mult
	local sideCut = 0
	local raycast_lx,raycast_ly,raycast_lz = getPositionFromElementOffset(car,-sensorOffset,sensorDetectLength-sideCut,sensorOffsetZ)
	--local raycast_mlx,raycast_mly,raycast_mlz = getPositionFromElementOffset(car,-sensorOffset/2,sensorDetectLength-sideCut,sensorOffsetZ)
	local raycast_mx,raycast_my,raycast_mz = getPositionFromElementOffset(car,0,sensorDetectLength,sensorOffsetZ)
	--local raycast_mrx,raycast_mry,raycast_mrz = getPositionFromElementOffset(car,sensorOffset/2,sensorDetectLength-sideCut,sensorOffsetZ)
	local raycast_rx,raycast_ry,raycast_rz = getPositionFromElementOffset(car,sensorOffset,sensorDetectLength-sideCut,sensorOffsetZ)

	--local px,py,pz = getElementPosition(car)
	local px,py,pz = getPositionFromElementOffset(car,0,0,0)
	-- raycasts
	local raycast_l = isLineOfSightClear (px,py,pz+sensorOffsetZ,raycast_lx,raycast_ly,raycast_lz,true,true,true,true,false,true,true,car)
	--local raycast_ml = isLineOfSightClear (px,py,pz+sensorOffsetZ,raycast_mlx,raycast_mly,raycast_mlz,true,true,true,true,false,true,true,car)
	local raycast_m = isLineOfSightClear (px,py,pz+sensorOffsetZ,raycast_mx,raycast_my,raycast_mz,true,true,true,true,false,true,true,car)
	--local raycast_mr = isLineOfSightClear (px,py,pz+sensorOffsetZ,raycast_mrx,raycast_mry,raycast_mrz,true,true,true,true,false,true,true,car)
	local raycast_r = isLineOfSightClear (px,py,pz+sensorOffsetZ,raycast_rx,raycast_ry,raycast_rz,true,true,true,true,false,true,true,car)

	speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan(math.abs(rx/ry))*0.75)
	--[[
	if checkSight and not raycast_m then
		speed = 0
	else
		speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan(math.abs(rx/ry))*0.75)
	end
	--]]

	if checkSight then
		local l_color = raycast_l == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
		dxDrawLine3D ( px,py,pz+sensorOffsetZ,raycast_lx,raycast_ly,raycast_lz,l_color, 1) -- left
		l_color = raycast_m == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
		dxDrawLine3D ( px,py,pz+sensorOffsetZ,raycast_mx,raycast_my,raycast_mz, l_color, 1) -- Middle
		l_color = raycast_r == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
		dxDrawLine3D ( px,py,pz+sensorOffsetZ,raycast_rx,raycast_ry,raycast_rz, l_color, 1) -- right

		if not raycast_l and not raycast_m and not raycast_r then
			controlBackward(npc)
			speed = -5
			return
		end
		if not raycast_l and not raycast_m then
			controlBackward(npc)
			controlLeft(npc)
			speed = -5
			return
		end
		if not raycast_r and not raycast_m then
			controlBackward(npc)
			controlRight(npc)
			speed = -5
			return
		end
		if not raycast_m then
			speed = 0
			--controlBackward(npc)
		end

		if not raycast_l  then
			controlRight(npc)
		end
		if not raycast_r then
			controlLeft(npc)
		end
	end

	setPedControlState(npc,"accelerate",vry < speed)
	setPedControlState(npc,"brake_reverse",vry > speed*1.1)
end

function controlForward(npc)
	local vehPtr = getPedOccupiedVehicle(npc)
	if getElementSpeed(vehPtr) < speedLimit then
		--outputChatBox("[AI]: w")
		setPedControlState (npc,'accelerate', true)
		setPedControlState (npc,"brake_reverse", false )
		setPedControlState (npc,"handbrake", false )

	else
		outputChatBox("[AI]: s")
		setPedControlState (npc'accelerate', false)
		--setControlState ("brake_reverse", true )
		--setControlState ("handbrake", true )
	end
end
function controlBreak(npc)
	local vehPtr = getPedOccupiedVehicle(npc)
	if getElementSpeed(vehPtr) > 0 then
		--outputChatBox("[AI]: w")
		setPedControlState (npc,'accelerate', false)
		setPedControlState (npc,"brake_reverse", true )
		setPedControlState (npc,"handbrake", true )
	end
end
function controlLeft(npc)
	setPedControlState (npc,"vehicle_left", true )
	setPedControlState (npc,"vehicle_right ", false )
end
function controlRight(npc)
	setPedControlState (npc,"vehicle_right", true )
	setPedControlState (npc,"vehicle_left", false )
end

function controlBackward(npc)
	setPedControlState (npc,"brake_reverse", true )
	setPedControlState (npc,'accelerate', false)

	--outputChatBox("[AI]:s back")
end
function makeNPCDriveAlongLine(npc,x1,y1,z1,x2,y2,z2,off)
	local car = getPedOccupiedVehicle(npc)
	local x,y,z = getElementPosition(car)
	local p2 = getPercentageInLine(x,y,x1,y1,x2,y2)
	local len = getDistanceBetweenPoints3D(x1,y1,z1,x2,y2,z2)
	p2 = p2+off/len
	local p1 = 1-p2
	local destx,desty,destz = p1*x1+p2*x2,p1*y1+p2*y2,p1*z1+p2*z2
	makeNPCDriveToPos(npc,destx,desty,destz,true)
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
	makeNPCDriveToPos(npc,destx,desty,destz,false)
end

function getPositionFromElementOffset(element,offX,offY,offZ)
	local m = getElementMatrix ( element )  -- Get the matrix
	local x = offX * m[1][1] + offY * m[2][1] + offZ * m[3][1] + m[4][1]  -- Apply transform
	local y = offX * m[1][2] + offY * m[2][2] + offZ * m[3][2] + m[4][2]
	local z = offX * m[1][3] + offY * m[2][3] + offZ * m[3][3] + m[4][3]
	return x, y, z                               -- Return the transformed point
end