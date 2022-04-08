function doNPCDriveCar(npc,car,x,y,z)
	--dxDrawWiredSphere(x,y,z,1,tocolor(0,255,0,255))
	local tox,toy,toz = x,y,z
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
	local avx,avy,avz = getElementAngularVelocity(car)
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
	speed = getNPCDriveSpeed(npc)*mathSin(mathPi*0.5-mathAtan(mathAbs(rx/ry))*0.75) 
	--[[
	if AI[npc].task == "driveAroundBend" then -- slow down on blending
		speed = getNPCDriveSpeed(npc)*mathSin(mathPi*0.5-mathAtan(mathAbs(rx/ry))*0.75) * 0.6
	else 
		speed = getNPCDriveSpeed(npc)*mathSin(mathPi*0.5-mathAtan(mathAbs(rx/ry))*0.75) 
	end
	--]]

	-- logic for idle
	-- render debug text

	local function isObstcle(hit) 
		if not hit then return false end
		if getElementType(hit) == "vehicle" then 
			return getVehicleOccupant(hit)
		end
		local vaildHitElements = {
			["vehicle"] = true,
			["ped"] = true,
			["player"] = true,
		}
		return isElement(hit) and vaildHitElements[getElementType(hit)]
	end
	local function controlVehicleEngine(speed) 
		if getNPCDriveStyle(npc) == "aggressive" then 
			speed = speed * 2
		end
		--setElementForwardVelocity( car, vry < speed and 0.1 or 0) 
		speed = AI[npc].task == "driveAroundBend" and speed * 0.6 or speed
		setPedControlState(npc,"accelerate",vry < speed)
		setPedControlState(npc,"brake_reverse",vry > speed*1.2)
		if vry > speed*1.2 then
			setElementVelocity(car,vx*0.8,vy*0.8,vz) 
		end
	end

	local function controlVehicleDirection()
	
		local velocity = 0.015
		local vfrz = rx < 0 and velocity or rx >= 0 and -velocity or 0

		
		if AI[npc].task == "driveAroundBend" and vfrz and not AI[npc].hitted then
			setElementAngularVelocity (car,0,0,vfrz)
			--setElementRotation(car,crx,cry,crz+vrz)
		end 

		
		local T_INTP = 30
		if ry <= 0 then
			setPedControlState(npc,"vehicle_left",rx < 0)
			setPedControlState(npc,"vehicle_right",rx >= 0)
		else
			local secondpart = getTickCount()%T_INTP
			setPedControlState(npc,"vehicle_left",rx*T_INTP/ry < -secondpart)
			setPedControlState(npc,"vehicle_right",rx*T_INTP/ry > secondpart)
		end
		
		
	end
	-- check if is train then stop do nothing
	local currentTick = getTickCount()
	if AI[npc].decision == AI.decisions[1] then
		local function executeNormalDriveBehavior(hit) 
			if isObstcle(hit) and getNPCDriveStyle(npc) ~= "aggressive" then
				AI[npc].decision = AI.decisions[4] -- wait for obstacle
				AI[npc].lastDecisionTick = currentTick
				--print(AI[npc].task)
			else 
				AI[npc].decision = AI.decisions[2] -- avoid obstacle
				AI[npc].lastDecisionTick = currentTick
			end
		end
		if ray_m then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_m",x,y,z)
			executeNormalDriveBehavior(hit) 
			return
		end
		if ray_l then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_l",x,y,z)
			executeNormalDriveBehavior(hit) 
			return
		end
		if ray_r then
			-- check if is vehile & wait for green light
			local _,hit = createRaycast(car,"raycast_r",x,y,z)
			executeNormalDriveBehavior(hit) 
			return
		end
		if ray_sl or ray_sr then
			AI[npc].decision = AI.decisions[4] -- wait for obstacle
			AI[npc].lastDecisionTick = currentTick
			return
		end
		controlVehicleDirection()
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
			speed = speed * 0.5
			controlVehicleLeft(npc)
		elseif ray_l then
			speed = speed * 0.5
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



		if not ray_l and not ray_r and not ray_m then 
			AI[npc].decision = AI.decisions[1]
			AI[npc].lastDecisionTick = currentTick
			return
		end
		
		if currentTick - AI[npc].lastDecisionTick >= AI.config.drive_wait_obstcleTimer then
			AI[npc].decision = AI.decisions[2]
			return
		end
		speed = 0
		controlVehicleEngine(speed)
		return
	end
	--setElementVelocity(car,vx,vy,vz)
	--setElementAngularVelocity(car,avx,avy,avz)
	

end
function doNPCChasePlayer(npc,car,player)
    local x,y,z = getPositionFromElementOffset(player,0,2,0)
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
	local playerVehicleSpeed = getElementSpeed(player) 
	--print(playerVehicleSpeed)
	
	local speed = 60 + playerVehicleSpeed

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

	-- render debug text

	local function isObstcle(hit) 
		return hit ~=nil and isElement(hit) and getElementType(hit) == "vehicle" or hit ~=nil and isElement(hit) and getElementType(hit) == "ped" or  hit ~=nil and isElement(hit) and getElementType(hit) == "player"

	end
	local function controlVehicleEngine() 
		setPedControlState (npc,"handbrake",false)
		setPedControlState(npc,"accelerate",vry < speed)
		setPedControlState(npc,"brake_reverse",vry > speed*1.2)

		if vry > speed*1.2 then
			setElementVelocity(car,vx*0.8,vy*0.8,vz) 
		end
	end

	local function controlVehicleDirection()
		local velocity = 0.02
		--print(ry)
		--print(vry)
		--setElementAngularVelocity (car,0,0,vry)
		if ry <= 0 then
			setPedControlState(npc,"vehicle_left",rx < 0)
			setPedControlState(npc,"vehicle_right",rx >= 0)
		else
			local secondpart = getTickCount()%100
			setPedControlState(npc,"vehicle_left",rx*500/ry < -secondpart)
			setPedControlState(npc,"vehicle_right",rx*500/ry > secondpart)
			
	
		end
	end
    
	-- check if is train then stop do nothing
	local currentTick = getTickCount()
	-- logic for forward aovding obstcle
	if AI[npc].decision == AI.decisions[1] then
		--deal with light
		controlVehicleEngine(speed)
		if ray_m and ray_r and ray_l then
			--speed = speed * 0.2
			AI[npc].decision = AI.decisions[2]
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

		
		
	end
	-- logic for backwords avoding obstcles
	if AI[npc].decision == AI.decisions[2] then
		controlVehicleBackward(npc)
		if ray_b and currentTick - AI[npc].lastDecisionTick > 5000 then
			AI[npc].decision = AI.decisions[1]
		end
		if not ray_l or not ray_r then
			if not ray_l then
				controlVehicleRight(npc)
			end
			if not ray_r then
				controlVehicleLeft(npc)
			end
			if currentTick - AI[npc].lastDecisionTick >= AI.config.backwardsTimer then
				AI[npc].decision = AI.decisions[1]
				return
			end
		end

		if ray_bl then
			controlVehicleRight(npc)
		end

		if ray_br then
			controlVehicleLeft(npc)
		end
		
		

		
		return
	end
	
	--setElementAngularVelocity(car,avx,avy,avz)
	
end

-- test
--[[
addEventHandler("onClientRender",root,function() 
    local car = getPedOccupiedVehicle(localPlayer)
    if car then 
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
    end
end)
]]