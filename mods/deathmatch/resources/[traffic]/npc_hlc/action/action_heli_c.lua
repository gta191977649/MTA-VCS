function doNPCDriveHelicopter(npc,car,x,y,z) 
	local dist_x,dist_y,dist_z = x,y,z
	local crx,cry,crz = getElementRotation(car)
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
	local speed = 10
	-- setup tasks
	AI[npc].task = getNPCCurrentTask(npc)[1]
	AI[npc].light = false
	-- setup sensors
	local gap = 3.5
	-- left
	--local ray_l = createRaycast(car,"raycast_l",x,y,z,gap,true,true)
	-- mid
	--local ray_m,hitElement = createRaycast(car,"raycast_m",x,y,z,gap,true,true)
	-- right
	--local ray_r = createRaycast(car,"raycast_r",x,y,z,gap,true,true)
	-- back
	--local ray_b = createRaycast(car,"raycast_b",x,y,z,gap,true,true)
	-- down 
	local ray_d = createRaycast(car,"raycast_d",x,y,z,gap,true,true)
	-- side right
	--local ray_sr = createRaycast(car,"raycast_sr",x,y,z,gap,true,true)
	-- side left
	--local ray_sl = createRaycast(car,"raycast_sl",x,y,z,gap,true,true)
	-- back left
	--local ray_bl = createRaycast(car,"raycast_bl",x,y,z,gap,true,true)
	-- back right
	--local ray_br = createRaycast(car,"raycast_br",x,y,z,gap,true,true)

	local a = findRotation(px,py,dist_x,dist_y)
	if math.abs(crz - a) < 5 then 
		setElementAngularVelocity(car,0,avy,0)
	end
	--setElementRotation(car,0,0,a)
	--setElementAngularVelocity(car,0,avy,0)
	local function controlVehicleDirection()
		
		if ry <= 0 then
			--setElementAngularVelocity (npc,0,0,20)  
			setPedControlState(npc,"vehicle_look_left",rx < 0)
			setPedControlState(npc,"vehicle_look_right",rx >= 0)
		else
			local secondpart = getTickCount()%100
			setPedControlState(npc,"vehicle_look_left",rx*500/ry < -secondpart)
			setPedControlState(npc,"vehicle_look_right",rx*500/ry > secondpart)
		end
	end

	local function controlVehicleEngine() 
		if cry > 350 or cry < 5 then 
			--setPedControlState(npc,"steer_forward",true)
			--print("forward")
			setPedControlState(npc,"steer_forward",vry < speed)
			setPedControlState(npc,"accelerate",vry < speed)
			setPedControlState(npc,"steer_back",vry > speed)
			setElementForwardVelocity(npc,speed)
			
		else
			setPedControlState(npc,"steer_forward",false)
			setPedControlState(npc,"steer_back",false)
			setElementForwardVelocity(npc,-1)
		end
	end

	local dist =  getDistanceBetweenPoints2D (px,py, dist_x,dist_y )
	--print (dist)
	 

	if dist < 15 then 
		--speed = 0
		setPedControlState (npc,"steer_forward", false )
		setPedControlState (npc,"brake_reverse", true )
		controlVehicleEngine()
		setElementForwardVelocity(npc,0)
	else
		if ray_d or pz < z + 15 then 
			setPedControlState (npc,"steer_forward", false )
	
			setPedControlState (npc,"accelerate", true )
			setPedControlState (npc,"brake_reverse", false )
            setElementVelocity(car,0,0,0.2)
		else
			setPedControlState (npc,"accelerate", false )
			controlVehicleEngine()
			controlVehicleDirection()
		end
	end	
end