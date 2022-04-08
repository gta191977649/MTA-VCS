debug = false

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
	if ai[npc] ~= nil then
		ai[npc]["decision"] = aiDecision[3];
	end
end


function makeNPCWalkToPos(npc,x,y,z)
	--print(x)
	local px,py = getElementPosition(npc)
	if not isElementInWater( npc) then 
		setPedCameraRotation(npc,math.deg(math.atan2(x-px,y-py)))
	else 
		--local rx,ry,rz = getElementRotation(npc)
		local angle = 360-math.deg(math.atan2(x-px,y-py))
		setPedRotation(npc,angle)
	end
	setPedControlState(npc,"forwards",true)
	local speed = getNPCWalkSpeed(npc)
	setPedControlState(npc,"walk",speed == "walk")
	setPedControlState(npc,"sprint", speed == "sprint" or speed == "sprintfast" and not getPedControlState(npc,"sprint"))
end

function makeNPCEnterToVehicle(npc,vehicle,seat) 
	print("[C] Set setPedEnterVehicle")
	local x,y,z = getElementPosition(npc)
	local vx,vy,vz = getElementPosition(vehicle)

	local dis = getDistanceBetweenPoints3D(x,y,z,vx,vy,vz)
	if dis <= 3 then 
		setPedEnterVehicle (npc,vehicle,seat)
	else 
		makeNPCWalkToPos(npc,vx,vy,vz)
	end
end
function makeNPCExitFromVehicle(npc) 
	if not getPedOccupiedVehicle(npc) then return false end
	setPedExitVehicle (npc)
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
status = {"DRIVENORMAL","BACKREVERSE","DIRVESTUCK","DRIVEAGGRESSIVE"}
aiDecision = {"IDLE","WAITFOROBS","WAIT_TRAFFICLIGHT"}
ai = { }

addEventHandler("onClientElementDestroy", getRootElement(), function ()
	if getElementType(source) == "ped" then
		if ai[ped] ~= nil then
			ai[ped] = nil
			--local msg = string.format("CG: removed ped ")
			--print(msg)
		end
	end
end)

function handleVehicleDamage(attacker, weapon, loss, x, y, z, tire)
	for seat, player in pairs(getVehicleOccupants(source)) do
		local npc = player
		--and bodyPart == 3
		if ai[npc] ~= nil and attacker == localPlayer then
			if ai[npc]["status"] ~= status[4] then
				ai[npc]["status"] = status[4]
				print("Ai set agrresive due hit by player")
				setTimer(function()
					ai[npc]["status"] = status[1]
				end,10000,1)
			end
		end
	end
end
addEventHandler("onClientVehicleDamage", root, handleVehicleDamage)

addEventHandler("onClientVehicleCollision", root,
	function(theHitElement,force, bodyPart, x, y, z, nx, ny, nz)
		for seat, player in pairs(getVehicleOccupants(source)) do
			local npc = player
			--and bodyPart == 3
			if theHitElement ~= nil and ai[npc] ~= nil and not ai[npc]["ignoreCollision"]  and (ai[npc]["task"] == "bend" or  ai[npc]["task"] == "line" and getElementType(theHitElement) == "object" ) then
				if not ai[npc]["raycast_m"] then
					--outputConsole("found")
					--outputChatBox(bodyPart)
					ai[npc]["ignoreCollision"] = true
					ai[npc]["status"] = status[2]
					print("set collision timer")
					setTimer(function(npc)
						ai[npc]["status"] = status[1]
						ai[npc]["ignoreCollision"] = false
					end,2000,1,npc)

					-- force does not take into account the collision damage multiplier (this is what makes heavy vehicles take less damage than banshees for instance) so take that into account to get the damage dealt
					local fDamageMultiplier = getVehicleHandling(source).collisionDamageMultiplier
					-- Create a marker (Scaled down to 1% of the actual damage otherwise we will get huge markers)
					local m = createMarker(x, y, z, "corona", force * fDamageMultiplier * 0.01, 231,0 , 0)
					-- Destroy the marker in 2 seconds
					setTimer(destroyElement, 2000, 1, m)
				end
			end
		end
	end
)
function makeNPCDriveToPos(npc,wx,wy,wz,task,checkSight)
	local tx,ty,tz = wx,wy,wz
	-- setup ai logic
	--outputConsole("set ai to pos -> "..getElementType(npc))
	if ai [npc] == nil then
		ai[npc] = {
			raycast_m = nil,
			raycase_l = nil,
			raycase_r = nil,
			status = status[1],
			decision = aiDecision[1],
			suckTurn = 0,
			task = "line",
			presskey="",
			ignoreCollision = false,
		}
		--outputConsole("AI初期化設置している -> "..getElementType(npc))
	end
	ai[npc]["task"] = task
	-- Drive to pos logic
	local car = getPedOccupiedVehicle(npc)
	if not isElementStreamedIn(car) then return end
	local m = getElementMatrix(car)

	local crx,_,_ = getElementRotation ( car )
	if crx > 180 and crx < 270 then setElementHealth(car,0) end -- fliped boom

	wx,wy,wz = wx-m[4][1],wy-m[4][2],wz-m[4][3]
	local rx,ry,rz =
	wx*m[1][1]+wy*m[1][2]+wz*m[1][3],
	wx*m[2][1]+wy*m[2][2]+wz*m[2][3],
	wx*m[3][1]+wy*m[3][2]+wz*m[3][3]
	if ry <= 0 then
		setPedControlState(npc,"vehicle_left",rx < 0)
		setPedControlState(npc,"vehicle_right",rx >= 0)
	else
		local secondpart = getTickCount()%100
		setPedControlState(npc,"vehicle_left",rx*500/ry < -secondpart)
		setPedControlState(npc,"vehicle_right",rx*500/ry > secondpart)
	end



	local x1,y1,z1,x2,y2,z2 = getElementBoundingBox(car)
	z1 = z1+1

	local vx,vy,vz = m[4][1]+m[3][1]*z1,m[4][2]+m[3][2]*z1,m[4][3]+m[3][3]*z1
	local mult = (y2+6)/math.sqrt(wx*wx+wy*wy+wz*wz)
	local dx,dy,dz = wx*mult,wy*mult,wz*mult
	local sideCut = 0


	--[[
	if checkSight and not raycast_m then
		speed = 0
	else
		speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan(math.abs(rx/ry))*0.75)
	end
	--]]
	-- setup ai sensor
	local vehPtr = car
	local x0, y0, z0, x1, y1, z1 = getElementBoundingBox( vehPtr )
	local vWidth = math.abs(y0 - y1)
	local vHeight = math.abs(x0 -x1)

	local raycast_lx,raycast_ly,raycast_lz = getPositionFromElementOffset(vehPtr,-sensorOffset,vWidth+1,sensorOffsetZ)
	local raycast_mx,raycast_my,raycast_mz = getPositionFromElementOffset(vehPtr,0,vWidth+1.5,sensorOffsetZ)
	local raycast_rx,raycast_ry,raycast_rz = getPositionFromElementOffset(vehPtr,sensorOffset,vWidth+1,sensorOffsetZ)
	-- Side sensors
	local raycast_slx,raycast_sly,raycast_slz = getPositionFromElementOffset(vehPtr, -(vHeight/2 + 1),0,sensorOffsetZ)
	local raycast_srx,raycast_sry,raycast_srz = getPositionFromElementOffset(vehPtr, vHeight/2 + 1,0,sensorOffsetZ)
	-- back sensors
	local raycast_bx,raycast_by,raycast_bz = getPositionFromElementOffset(vehPtr, 0,-(vWidth/2+1),sensorOffsetZ)

	local x,y,z = getElementPosition(vehPtr)

	-- raycasts

	local raycast_l, _, _, _, hit_l,raycast_lnx,raycast_lny,raycast_lnz = processLineOfSight (x,y,z+sensorOffsetZ,
			raycast_lx,raycast_ly,raycast_lz,true,true,true,true,false,true,true,false,vehPtr,true)
	local raycast_m, _, _, _, hit_m,raycast_mnx,raycast_mny,raycast_mnz = processLineOfSight (x,y,z+sensorOffsetZ,
			raycast_mx,raycast_my,raycast_mz,true,true,true,true,false,true,true,false,vehPtr,true)
	local raycast_r, _, _, _, hit_r,raycast_rnx,raycast_rny,raycast_rnz = processLineOfSight (x,y,z+sensorOffsetZ,
			raycast_rx,raycast_ry,raycast_rz,true,true,true,true,false,true,true,false,vehPtr,true)
	local raycast_sl, _, _, _,surface,raycast_slnx,raycast_slny,raycast_slnz = processLineOfSight (x,y,z+sensorOffsetZ,raycast_slx,raycast_sly,raycast_slz,true,true,true,true,false,true,true,false,vehPtr,true)
	local raycast_sr, _, _, _,surface,raycast_srnx,raycast_srny,raycast_srnz = processLineOfSight (x,y,z+sensorOffsetZ,raycast_srx,raycast_sry,raycast_srz,true,true,true,true,false,true,true,false,vehPtr,true)
	local raycast_b , _, _, _,surface,raycast_bnx,raycast_bny,raycast_bnz = processLineOfSight (x,y,z+sensorOffsetZ,raycast_bx,raycast_by,raycast_bz,true,true,true,true,false,true,true,false,vehPtr,true)

	local angle2Normal = 0

	-- calculate raycast status
	raycast_l = not raycast_l
	raycast_m = not raycast_m
	raycast_r = not raycast_r
	raycast_sl = not raycast_sl
	raycast_sr = not raycast_sr
	raycast_b = not raycast_b

	-- slop check ignore other collision except object
	local dL,dM,dR = false,false,false
	if not raycast_m or not raycast_l or not raycast_r then
		local vRay_x,vRay_y,vRay_z = 0,0,0
		local vNor_x,vNor_y,vNor_z = 0,0,0

		if not raycast_m and hit_m ~=nil and getElementType(hit_m) == "object" then
			vRay_x,vRay_y,vRay_z = coords2Vector(raycast_mx,raycast_my,raycast_mz,raycast_mx+raycast_mnx,
					raycast_my+ raycast_mny,raycast_mz)
			vNor_x,vNor_y,vNor_z = coords2Vector(raycast_mx,raycast_my,raycast_mz,raycast_mx+raycast_mnx,
					raycast_my+raycast_mny,raycast_mz+raycast_mnz)

			angle2Normal = angleBetween2Vec(vNor_x,vNor_y,vNor_z,vRay_x,vRay_y,vRay_z)
			dxDrawLine3D ( raycast_mx,raycast_my,raycast_mz,raycast_mx+raycast_mnx, raycast_my+raycast_mny,
					raycast_mz+raycast_mnz,tocolor ( 255, 255, 0, 230 ), 1)

			if not isObstcle(angle2Normal) then
				raycast_m = true
				dM = true

			end
		end

		if not raycast_l and hit_l ~=nil and getElementType(hit_l) == "object" then
			vRay_x,vRay_y,vRay_z = coords2Vector(raycast_lx,raycast_ly,raycast_lz,raycast_lx+raycast_lnx,
					raycast_ly+ raycast_lny,raycast_lz)
			vNor_x,vNor_y,vNor_z = coords2Vector(raycast_lx,raycast_ly,raycast_lz,raycast_lx+raycast_lnx,
					raycast_ly+raycast_lny,raycast_lz+raycast_lnz)

			angle2Normal = angleBetween2Vec(vNor_x,vNor_y,vNor_z,vRay_x,vRay_y,vRay_z)
			dxDrawLine3D ( raycast_lx,raycast_ly,raycast_lz,raycast_lx+raycast_lnx, raycast_ly+raycast_lny,raycast_lz+raycast_lnz,tocolor ( 255, 255, 0, 230 ), 1)
			if not isObstcle(angle2Normal) then
				raycast_l = true
				dL = true
			end

		end

		if not raycast_r and  hit_r ~=nil and getElementType(hit_r) == "object" then
			vRay_x,vRay_y,vRay_z = coords2Vector(raycast_rx,raycast_ry,raycast_rz,raycast_rx+raycast_rnx,
					raycast_ry+ raycast_rny,raycast_rz)
			vNor_x,vNor_y,vNor_z = coords2Vector(raycast_rx,raycast_ry,raycast_rz,raycast_rx+raycast_rnx,
					raycast_ry+raycast_rny,raycast_rz+raycast_rnz)

			dxDrawLine3D ( raycast_rx,raycast_ry,raycast_rz,raycast_rx+raycast_rnx, raycast_ry+raycast_rny,
					raycast_rz+raycast_rnz,tocolor ( 255, 255, 0, 230 ), 1)
			angle2Normal = angleBetween2Vec(vNor_x,vNor_y,vNor_z,vRay_x,vRay_y,vRay_z)
			if not isObstcle(angle2Normal) then
				raycast_r = true
				dR = true
			end
		end


	end
	-- update raycast
	-- assign to npc prorperties
	ai[npc]["raycast_m"] = raycast_m
	ai[npc]["raycast_l"] = raycast_l
	ai[npc]["raycast_r"] = raycast_r

	if debug == true then
        local msg = string.format("Obstacle Check: %s|%s|%s",dL and "NO" or "YES",dM and "NO" or "YES",dR and
                "NO" or "YES")
        dxDrawTextOnElement(vehPtr,msg,1.6,20,0,255,255,255,1.5,"Default")
        local l_color = raycast_l == true and tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_lx,raycast_ly,raycast_lz,l_color, 1) -- left
        l_color = raycast_m == true and tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_mx,raycast_my,raycast_mz, l_color, 1) -- Middle
        l_color = raycast_r == true  and tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_rx,raycast_ry,raycast_rz, l_color, 1) -- righ
        l_color = raycast_sl == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_slx,raycast_sly,raycast_slz, l_color, 1) -- side left
        l_color = raycast_sr == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_srx,raycast_sry,raycast_srz, l_color, 1) -- side right
        l_color = raycast_b == true and  tocolor ( 0, 255, 0, 230 ) or tocolor ( 255, 0, 0, 230 )
        dxDrawLine3D ( x,y,z+sensorOffsetZ,raycast_bx,raycast_by,raycast_bz, l_color, 1) -- side right
        local status = string.format("States:%s\nDecision:%s\nStuck Turning Decition:%d\nslop angle:%f\nTASK:%s",
        ai[npc]["status"], ai[npc]["decision"],ai[npc]["suckTurn"],angle2Normal,ai[npc]["task"])
        --debug waypoint
        dxDrawLine3D ( tx,ty,tz,x,y,z, tocolor ( 0, 0, 255, 230 ), 1)

        -- debug status text
        dxDrawTextOnElement(vehPtr,status,1,20,255,255,255,255,1.5,"Default")

	-- calc speed for ai
	--local speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan(math.abs(rx/ry))*0.75)
	 
	end
	speed = getNPCDriveSpeed(npc)*math.sin(math.pi*0.5-math.atan(math.abs(rx/ry))*0.75)
	--aiLogic(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed,hit_m)
	if not checkSight then
		raycast_l = true
		raycast_m = true
		raycast_r = true
		raycast_sl = true
		raycast_sr = true
		raycast_b = true

	end
	aiLogic(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed,hit_m)
end

function getNpcFromVehicle(vehielceElement)
	return getVehicleOccupant ( vehielceElement, 0 )
end
function aiLogic(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed,hit_m)
	if not raycast_m and hit_m ~= nil and getElementType(hit_m) == "vehicle" then
		--print(getElementType(hit_m))
		local hit_npc = getNpcFromVehicle(hit_m)
		if ai[hit_npc]~=nil then
			if ai[hit_npc]["decision"] == aiDecision[3] then
				ai[npc]["decision"] = aiDecision[3]
			end
		end
	elseif ai[npc]["decision"] == aiDecision[3] then
		ai[npc]["decision"] = aiDecision[1]
	end
	--ai logic

	if ai[npc]["status"] == status[3] then
		aiStatusStucked(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed)
	end
	if ai[npc]["status"] == status[2] then
		aiStatusBackwards(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed)
	end

	if ai[npc]["status"] == status[1] then
		if ai[npc]["task"] == "bend" then
			if not raycast_m or not raycast_r or not raycast_l then
					speed = 0
					--setPedControlState (npc,"handbrake", true )
					controlForward(npc,speed)
					--controlBreak(npc)
				-- wait for a time if still blocked then drive aggresively (how rockstar does)
				if ai[npc]["decision"]  == aiDecision[1] then
					ai[npc]["decision"] = aiDecision[2]
					print("agressive timer")
					setTimer(function(npcid)
						ai[npcid]["status"] = status[4]
						ai[npc]["decision"] = aiDecision[1]
					end,10000,1,npc)

				end
				return
				--end
			end
		elseif ai[npc]["task"] == "line" then
			if not raycast_m then
				speed = 0
				--setPedControlState (npc,"handbrake", true )
				controlForward(npc,speed)
				--controlBreak(npc)
				-- wait for a time if still blocked then drive aggresively (how rockstar does)
				if ai[npc]["decision"]  == aiDecision[1] then
					ai[npc]["decision"] = aiDecision[2]
					print("agressive timer")
					setTimer(function(npcid)
						ai[npcid]["status"] = status[4]
						ai[npc]["decision"] = aiDecision[1]
					end,10000,1,npc)

				end
				return
				--end
			end
		end
		if not raycast_l and not raycast_m and not raycast_r and raycast_b then -- When Drive backwords
			--check if can go left or right in side sensor

			if raycast_sl then
				controlRight(npc)
			elseif raycast_sr then
				controlLeft(npc)
			else
				ai[npc]["status"] = status[2]
				print("backwards timer")
				setTimer(function(npcid)
					ai[npcid]["status"] = status[1]
				end,2000,1,npc)
			end
		elseif not raycast_m and not raycast_b then -- When getting stucked
			if ai[npc]["decision"] == aiDecision[1] or ai[npc]["decision"] == aiDecision[2] then
				ai[npc]["status"] = status[3]
				print("stuck timer")
				setTimer(function(npcid)
					ai[npcid]["status"] = status[1]
					ai[npcid]["suckTurn"] = 0
				end,3000,1,npc)
			end
		end

		if not raycast_m and not raycast_l and not raycast_r then
			ai[npc]["status"] = status[3]
			print("stuck timer")
			setTimer(function(npcid)
				ai[npcid]["status"] = status[1]
			end,2000,1,npc)
		end


		if not raycast_l or not raycast_sl then
			--controlForward(npc,speed)
			speed = speed * 0.5
			controlRight(npc)
		end
		if not raycast_r or not raycast_sr then
			--controlForward(npc,speed)
			speed = speed * 0.5
			controlLeft(npc)
		end

		if not raycast_sl then
			controlRight(npc)
		end
		if not raycast_sr then
			controlLeft(npc)
		end

		-- forward logic ?
		controlForward(npc,speed)
	end
	if ai[npc]["status"] == status[4] then -- DRIVE AGGRESSIVE
		--speed = speed * 1.5
		--[[
		if not raycast_m then
			ai[npc]["status"] = status[2]

			setTimer(function(npcid)
				ai[npcid]["status"] = status[4]
				print("settimer")
			end,3000,1,npc)
			return
		end
		--]]
		if ai[npc]["decision"] == aiDecision[3] then -- if wait light
			if not raycast_m or not raycast_r or not raycast_l then
				speed = 0
				--setPedControlState (npc,"handbrake", true )
				controlForward(npc,speed)
				controlBreak(npc)
				return
			end
		end

		if not raycast_m then
			-- check if can turn out
			if raycast_l then
				controlLeft(npc)
				controlForward(npc,speed)
				return
			elseif raycast_r then
				controlRight(npc)
				controlForward(npc,speed)
				return
			elseif raycast_b then -- backwords
				if hit_m ~= nil and not getElementType(hit_m) == "object" then
					setAIDriveBackwards(npc)
				else
					setAIDriveStuck(npc)
				end
			else -- stuck
				setAIDriveStuck(npc)
			end
			controlForward(npc,speed)
			return
		end
		if not raycast_l and not raycast_r then
			--check if can go left or right in side sensor

			if  raycast_sl then
				controlRight(npc)
			elseif raycast_sr then
				controlLeft(npc)
			else
				ai[npc]["status"] = status[2]

				setTimer(function()
					ai[npc]["status"] = status[1]
				end,10000,1)
				return
			end
		elseif not raycast_m and not raycast_b then -- When getting stucked
			setAIDriveStuck(npc)
			return
		end



		if not raycast_l or not raycast_l and not raycast_m then
			--controlForward(npc,speed)
			speed = speed * 0.5
			controlRight(npc)
		end
		if not raycast_r  or not raycast_r and not raycast_m  then
			--controlForward(npc,speed)
			speed = speed * 0.5
			controlLeft(npc)
		end

		if not raycast_sl then
			controlRight(npc)
		end
		if not raycast_sr then
			controlLeft(npc)
		end

		-- forward logic ?
		controlForward(npc,speed)
	end
	--controlForward(npc,speed)

end


function aiStatusStucked(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed)
	-- When stucked, check coresponding sensors for where we can drive around outputChatBox
	if raycast_r and raycast_l and raycast_m then
		ai[npc]["status"] = status[1]
		return
	end

	if not raycast_l and not raycast_r and not raycast_b then
		speed = speed * 2
		controlForward(npc,speed)
		if ai[npc]["suckTurn"] == 0 then
			if not raycast_sl then
				ai[npc]["suckTurn"] = 1
			elseif not raycast_sr then
				ai[npc]["suckTurn"] = 2
			end
		end
		if ai[npc]["suckTurn"] == 1 then
			controlRight(npc)
		end
		if ai[npc]["suckTurn"]  == 2 then
			controlLeft(npc)
		end
	else
		if raycast_b then
			if  raycast_sl then
				controlLeft(npc)
			elseif raycast_sr then
				controlRight(npc)
			end
			controlBackward(npc,speed)
		end
	end
end
function aiStatusBackwards(npc,raycast_l,raycast_m,raycast_r,raycast_sl,raycast_sr,raycast_b,speed)


	controlBackward(npc,speed)

	if not raycast_b then
		ai[npc]["status"] = status[4]
		controlForward(npc,speed)
		return
	end
	--[[



	if not raycast_sl and not raycast_sr then
		local selection = math.random(0, 1)
		if selection == 0 then
			controlRight(npc)
		end
		if selection == 1 then
			controlLeft(npc)
		end
	end
	--]]
	if not raycast_sl then
		controlRight(npc)
	elseif not raycast_sr then
		controlLeft(npc)
	else
		--controlDirCancel(npc)
	end

end
function setAIDriveStuck(npc)
	ai[npc]["status"] = status[3]
	print("set ai stuck")
	setTimer(function(npc)
		ai[npc]["status"] = status[1]
	end,10000,1,npc)
end

function setAIDriveBackwards(npc)
	ai[npc]["status"] = status[2]
	print("set ai backwards")
	setTimer(function(npcid)
		ai[npcid]["status"] = status[1]
	end,3000,1,npc)
end
function controlForward(npc,speed)
	local vehPtr = getPedOccupiedVehicle(npc)
	local vx,vy,vz = getElementVelocity(vehPtr)
	local m = getElementMatrix(vehPtr)
	local vrx,vry,vrz = vx*m[1][1]+vy*m[1][2]+vz*m[1][3], vx*m[2][1]+vy*m[2][2]+vz*m[2][3], vx*m[3][1]+vy*m[3][2]+vz*m[3][3]
	setPedControlState(npc,"accelerate",vry < speed)
	setPedControlState(npc,"brake_reverse",vry > speed*0.9)
	setPedControlState(npc,"handbrake",vry > speed*0.95)
end
function controlBreak(npc)
	local vehPtr = getPedOccupiedVehicle(npc)
	setPedControlState (npc,'accelerate', false)
	if getElementSpeed(vehPtr) > 0 then
		--outputChatBox("[AI]: w")
		setPedControlState (npc,"brake_reverse", true )
	end
	setPedControlState (npc,"handbrake", true )
end
function controlLeft(npc)
	setPedControlState (npc,"vehicle_left", true )
	setPedControlState (npc,"vehicle_right ", false )
end
function controlRight(npc)
	setPedControlState (npc,"vehicle_right", true )
	setPedControlState (npc,"vehicle_left", false )
end
function controlDirCancel(npc)
	setPedControlState (npc,"vehicle_right", false )
	setPedControlState (npc,"vehicle_left", false )
end

function controlBackward(npc,speed)
	--[[
	speed = -speed
	local vehPtr = getPedOccupiedVehicle(npc)
	local vx,vy,vz = getElementVelocity(vehPtr)
	local m = getElementMatrix(vehPtr)
	local vrx,vry,vrz = vx*m[1][1]+vy*m[1][2]+vz*m[1][3], vx*m[2][1]+vy*m[2][2]+vz*m[2][3], vx*m[3][1]+vy*m[3][2]+vz*m[3][3]

	setPedControlState(npc,"accelerate",vry < speed)
	setPedControlState(npc,"brake_reverse",vry > speed*1.1)
	--]]
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
	makeNPCDriveToPos(npc,destx,desty,destz,"line",true)
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
	makeNPCDriveToPos(npc,destx,desty,destz,"bend",true)
end
function getElementSpeed(theElement, unit)
	-- Check arguments for errors
	assert(isElement(theElement), "Bad argument 1 @ getElementSpeed (element expected, got " .. type(theElement) .. ")")
	local elementType = getElementType(theElement)
	assert(elementType == "player" or elementType == "ped" or elementType == "object" or elementType == "vehicle" or elementType == "projectile", "Invalid element type @ getElementSpeed (player/ped/object/vehicle/projectile expected, got " .. elementType .. ")")
	assert((unit == nil or type(unit) == "string" or type(unit) == "number") and (unit == nil or (tonumber(unit) and (tonumber(unit) == 0 or tonumber(unit) == 1 or tonumber(unit) == 2)) or unit == "m/s" or unit == "km/h" or unit == "mph"), "Bad argument 2 @ getElementSpeed (invalid speed unit)")
	-- Default to m/s if no unit specified and 'ignore' argument type if the string contains a number
	unit = unit == nil and 0 or ((not tonumber(unit)) and unit or tonumber(unit))
	-- Setup our multiplier to convert the velocity to the specified unit
	local mult = (unit == 0 or unit == "m/s") and 50 or ((unit == 1 or unit == "km/h") and 180 or 111.84681456)
	-- Return the speed by calculating the length of the velocity vector, after converting the velocity to the specified unit
	return (Vector3(getElementVelocity(theElement)) * mult).length
end
function getPositionFromElementOffset(element,offX,offY,offZ)
	local m = getElementMatrix ( element )  -- Get the matrix
	local x = offX * m[1][1] + offY * m[2][1] + offZ * m[3][1] + m[4][1]  -- Apply transform
	local y = offX * m[1][2] + offY * m[2][2] + offZ * m[3][2] + m[4][2]
	local z = offX * m[1][3] + offY * m[2][3] + offZ * m[3][3] + m[4][3]
	return x, y, z                               -- Return the transformed point
end

-- ai helper functions (provides tools for simple vector based math)
function getPositionFromElementOffset(element,offX,offY,offZ)
	local m = getElementMatrix ( element )  -- Get the matrix
	local x = offX * m[1][1] + offY * m[2][1] + offZ * m[3][1] + m[4][1]  -- Apply transform
	local y = offX * m[1][2] + offY * m[2][2] + offZ * m[3][2] + m[4][2]
	local z = offX * m[1][3] + offY * m[2][3] + offZ * m[3][3] + m[4][3]
	return x, y, z                               -- Return the transformed point
end

function getPointFromDistanceRotation(element, dist, angle)
	local x,y,z = getElementPosition(element)
	local a = math.rad(90 - angle);
	local dx = math.cos(a) * dist;
	local dy = math.sin(a) * dist;
	return x+dx, y+dy,z;
end
function getPointFromDistanceRotationEx(x,y,z, dist, angle)
	local a = math.rad(90 - angle);
	local dx = math.cos(a) * dist;
	local dy = math.sin(a) * dist;
	return x+dx, y+dy,z;
end
function coords2Vector(x1,y1,z1,x2,y2,z2)
	x,y,z = x2-x1,y2-y1,z2-z1
	return x,y,z
end
function round(num, numDecimalPlaces)
	local mult = 10^(numDecimalPlaces or 0)
	return math.floor(num * mult + 0.5) / mult
end
function angleBetween2Vec(v1x,v1y,v1z,v2x,v2y,v2z)
	-- DOT PODUCT : cos(o) = a . b / |a| |b|
	local x = (v1x * v2x) + (v1y * v2y) + (v1z * v2z) -- a . b
	local y = math.sqrt( (v1x*v1x) + (v1y*v1y) + (v1z*v1z))  * math.sqrt( (v2x*v2x) + (v2y*v2y)  + (v2z*v2z))
	if x > 1 then x = 1 end
	if x < -1 then x = 1 end
	if y > 1 then y = 1 end
	if y < -1 then y = 1 end
	x = round(x,2)
	y = round(y,2)
	--print(y)
	-- domain -1 to 1
	return math.acos(  x / y ) * 180 / math.pi
end
function angleBetween2Vec2D(v1x,v1y,v2x,v2y)
	-- DOT PODUCT : cos(o) = a . b / |a| |b|
	local x = (v1x * v2x) + (v1y * v2y)  -- a . b
	local y = math.sqrt( (v1x*v1x) + (v1y*v1y) )  * math.sqrt( (v2x*v2x) + (v2y*v2y) )
	return math.acos(  x / y ) * 180 / math.pi
end
function coordRotZAxes(x,y,angle)
	-- Convert to rad
	local a = math.rad(angle)
	local x2 = x * math.cos(a) - y * math.sin(a)
	local y2 = x * math.sin(a) + y * math.cos(a)
	return x2,y2
end

function isObstcle(a)
	if a < 5 then
		return true
	end
	return false
end

function dxDrawTextOnElement(TheElement,text,height,distance,R,G,B,alpha,size,font)
	dxDrawTextOnElementEx(TheElement,text,height,distance,0,0,0,255,size,font)
	local x, y, z = getElementPosition(TheElement)
	local x2, y2, z2 = getCameraMatrix()
	local distance = distance or 20
	local height = height or 1

	if (isLineOfSightClear(x, y, z+2, x2, y2, z2)) then
		local sx, sy = getScreenFromWorldPosition(x, y, z+height)
		if(sx) and (sy) then
			local distanceBetweenPoints = getDistanceBetweenPoints3D(x, y, z, x2, y2, z2)
			if(distanceBetweenPoints < distance) then
				dxDrawText(text, sx+2, sy+2, sx, sy, tocolor(R or 255, G or 255, B or 255, alpha or 255), (size or 1)-(distanceBetweenPoints / distance), font or "arial", "center", "center")
			end
		end
	end
end

function dxDrawTextOnElementEx(TheElement,text,height,distance,R,G,B,alpha,size,font)
	local x, y, z = getElementPosition(TheElement)
	local x2, y2, z2 = getCameraMatrix()
	local distance = distance or 20
	local height = height or 1

	if (isLineOfSightClear(x, y, z+2, x2, y2, z2)) then
		local sx, sy = getScreenFromWorldPosition(x, y, z+height-0.01)
		if(sx) and (sy) then
			local distanceBetweenPoints = getDistanceBetweenPoints3D(x, y, z, x2, y2, z2)
			if(distanceBetweenPoints < distance) then
				dxDrawText(text, sx+2, sy+2, sx, sy, tocolor(R or 255, G or 255, B or 255, alpha or 255), (size or 1)-(distanceBetweenPoints / distance), font or "arial", "center", "center")
			end
		end
	end
end