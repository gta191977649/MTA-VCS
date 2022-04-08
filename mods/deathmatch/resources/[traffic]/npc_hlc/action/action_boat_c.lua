function doNPCDriveBoat(npc,car,x,y,z) 
	local crx,cry,crz = getElementRotation(car)
	if crx > 180 and crx < 270 then return setElementHealth(car,0) end -- fliped boom
	if getElementHealth( car ) < 1 then 
		return
	end
	local px,py,pz = getElementPosition(car)
	local m = getElementMatrix(car)
	local _rx,_ry,_rz = crx*degToPi,cry*degToPi,crz*degToPi
	local rxCos,ryCos,rzCos,rxSin,rySin,rzSin = mathCos(_rx),mathCos(_ry),mathCos(_rz),mathSin(_rx),mathSin(_ry),mathSin(_rz)
	local m11,m12,m13,m21,m22,m23,m31,m32,m33 = rzCos*ryCos-rzSin*rxSin*rySin,ryCos*rzSin+rzCos*rxSin*rySin,-rxCos*rySin,-rxCos*rzSin,rzCos*rxCos,rxSin,rzCos*rySin+ryCos*rzSin*rxSin,rzSin*rySin-rzCos*ryCos*rxSin,rxCos*ryCos
	x,y,z = x-px,y-py,z-pz
	local rx,ry,rz = x*m11+y*m12+z*m13,x*m21+y*m22+z*m23,x*m31+y*m32+z*m33
	local vx,vy,vz = getElementVelocity(car)
	--local avx,avy,avz = getElementAngularVelocity(car)
	local vrx,vry,vrz = vx*m11+vy*m12+vz*m13,vx*m21+vy*m22+vz*m23,vx*m31+vy*m32+vz*m33
	
	local speed
	-- setup tasks
	AI[npc].task = getNPCCurrentTask(npc)[1]
	-- setup sensors

	-- left
	local ray_l = createRaycast(car,"raycast_l",x,y,z)
	-- mid
	local ray_m,hitElement = createRaycast(car,"raycast_m",x,y,z)
	-- right
	local ray_r = createRaycast(car,"raycast_r",x,y,z)
	-- back
	local ray_b = createRaycast(car,"raycast_b",x,y,z)
	-- side right
	local ray_sr = createRaycast(car,"raycast_sr",x,y,z)
	-- side left
	local ray_sl = createRaycast(car,"raycast_sl",x,y,z)
	-- back left
	local ray_bl = createRaycast(car,"raycast_bl",x,y,z)
	-- back right
	local ray_br = createRaycast(car,"raycast_br",x,y,z)

	-- logic
	
	if AI[npc].task == "driveAroundBend" then
		speed = getNPCDriveSpeed(npc)*mathSin(mathPi*0.5-mathAtan(mathAbs(rx/ry))*0.75) * 0.8
	else 
		speed = getNPCDriveSpeed(npc)*mathSin(mathPi*0.5-mathAtan(mathAbs(rx/ry))*0.75) 
	end
	-- logic for idle
	-- render debug text

	local function isObstcle(hit) 
		return hit ~=nil and isElement(hit) and getElementType(hit) == "vehicle" or hit ~=nil and isElement(hit) and getElementType(hit) == "ped" or  hit ~=nil and isElement(hit) and getElementType(hit) == "player"

	end
	local function controlVehicleEngine(speed) 
		setPedControlState (npc,"handbrake",vry > speed*1.2)
		setPedControlState(npc,"accelerate",vry < speed)
		setPedControlState(npc,"brake_reverse",vry > speed*1.2)
		if vry > speed*1.2 then
			setElementVelocity(car,vx*0.8,vy*0.8,vz) 
		end
	end

	local function controlVehicleDirection()
		local velocity = 0.01
		--print(ry)
		--print(vry)
		--setElementAngularVelocity (car,0,0,0)

		if ry <= 0 then
			setPedControlState(npc,"vehicle_left",rx < 0)
			setPedControlState(npc,"vehicle_right",rx >= 0)
			setElementAngularVelocity (car,0,0,rx < 0 and -velocity or rx >= 0 and velocity or 0)
		else
			local secondpart = getTickCount()%100
			setPedControlState(npc,"vehicle_left",rx*500/ry < -secondpart)
		    setPedControlState(npc,"vehicle_right",rx*500/ry > secondpart)
			setElementAngularVelocity (car,0,0,rx*500/ry < -secondpart and velocity or rx*500/ry >= secondpart and -velocity or 0)
		end
	end
	-- check if is train then stop do nothing
	local currentTick = getTickCount()
	if AI[npc].decision == AI.decisions[1] then
		controlVehicleDirection()
		if ray_m then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_m",x,y,z)
			if isObstcle(hit) then 

				AI[npc].decision = AI.decisions[4] -- wait for obstacle
				AI[npc].lastDecisionTick = currentTick
			else
				AI[npc].decision = AI.decisions[2]
				AI[npc].lastDecisionTick = currentTick
			end
			
		end
		if ray_l then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_l",x,y,z)
			if isObstcle(hit) then 
				AI[npc].decision = AI.decisions[4] -- wait for obstacle
				AI[npc].lastDecisionTick = currentTick
			else
				AI[npc].decision = AI.decisions[2]
				AI[npc].lastDecisionTick = currentTick
			end
			
		end
		if ray_r then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_r",x,y,z)
			if isObstcle(hit) then 
				AI[npc].decision = AI.decisions[4] -- wait for obstacle
				AI[npc].lastDecisionTick = currentTick
			else
				AI[npc].decision = AI.decisions[2]
				AI[npc].lastDecisionTick = currentTick
			end
			
		end
		if ray_sl or ray_sr then
			AI[npc].decision = AI.decisions[2]
			AI[npc].lastDecisionTick = currentTick
		end
		
		controlVehicleEngine(speed)
	end
	-- logic for forward aovding obstcle
	if AI[npc].decision == AI.decisions[2] then
		--deal with light
		if ray_m and AI[npc].task == "driveAlongLine" then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_m",x,y,z)
			if hit and getElementType(hit) == "vehicle" then
				local ped = getNPCFromVechile(hit)
				if ped ~= false and AI[ped] ~= nil and AI[ped].light~= false then 
					speed = 0
					AI[npc].lastDecisionTick = currentTick
					return controlVehicleEngine(speed)
				end
			end
		end

		if ray_m and currentTick - AI[npc].lastDecisionTick > AI.config.decision_timeout then
			--speed = speed * 0.2
			AI[npc].decision = AI.decisions[3]
			AI[npc].lastDecisionTick = currentTick
		end

		if ray_r then
			--speed = speed * 0.5
			controlVehicleLeft(npc)
		elseif ray_l then
			--speed = speed * 0.5
			controlVehicleRight(npc)

		elseif ray_sl then
			controlVehicleRight(npc)

		elseif ray_sr then
			controlVehicleLeft(npc)
		else
			controlVehicleDirection()
		end

		controlVehicleEngine(speed)
		
	end
	-- logic for backwords avoding obstcles
	if AI[npc].decision == AI.decisions[3] then
		
		-- control turning angle
		--[[
		if ry <= 0 then
			setPedControlState(npc,"vehicle_right",rx < 0)
			setPedControlState(npc,"vehicle_left",rx >= 0)
		else
			local secondpart = getTickCount()%100
			setPedControlState(npc,"vehicle_right",rx*500/ry < -secondpart)
			setPedControlState(npc,"vehicle_left",rx*500/ry > secondpart)
		end
		]]

		speed = speed * 0.5
		if ray_b then
			AI[npc].decision = AI.decisions[2]
		end
		if not ray_l or not ray_r then
			if not ray_l then
				controlVehicleRight(npc)
			end
			if not ray_r then
				controlVehicleLeft(npc)
			end
			if currentTick - AI[npc].lastDecisionTick >= AI.config.backwardsTimer then
				AI[npc].decision = AI.decisions[2]
				return
			end
		end

		if ray_bl then
			controlVehicleRight(npc)
		end

		if ray_br then
			controlVehicleLeft(npc)
		end

		controlVehicleBackward(npc)
		setPedControlState(npc,"brake_reverse",vry < speed)
		setPedControlState(npc,"accelerate",vry > speed*1.1)
		
		return
	end
	-- logic for wait obstcle
	if AI[npc].decision == AI.decisions[4] then
		if not ray_l and not ray_r then 
			AI[npc].decision = AI.decisions[2]
			AI[npc].lastDecisionTick = currentTick
			return
		end
		speed = 0
		controlVehicleEngine(speed)

		if currentTick - AI[npc].lastDecisionTick >= AI.config.drive_wait_obstcleTimer then
			AI[npc].decision = AI.decisions[2]
			return
		end

		-- make vehicle horn
		--[[
		print(currentTick - AI[npc].horn.lastTick)
		if currentTick - AI[npc].horn.lastTick > 500 then
			AI[npc].horn.lastTick = currentTick
			setPedControlState(npc,"horn",true)
		else 
			setPedControlState(npc,"horn",false)
		end
		]]
		
		return
	end
	--setElementVelocity(car,vx,vy,vz)
	--setElementAngularVelocity(car,avx,avy,avz)
	

end