--[[
data = {
	vehicle_model = 1,
	peds = {},
	group = "name",
	n1,
	n2,
	nb
}

players[square.player].cop_heli = heli

addEventHandler("onElementDestroy",heli,function() 
	local player = population.cars[heli].syncer
	players[player].cop_heli = nil
end,false)


]]
PED = exports.ped

function spawnPopulationInSquare(x,y,z,dim,type,data) 
	if type == "cop_heli" then 
		if data.vehicle_model == 497 and data.syncer == nil then return end

		if #getElementsWithinRange (x,y,z,8,"vehicle") > 0 then
			return
		end

		local zoff = z_offset[data.vehicle_model]/math.cos(math.rad(data.vehicle_rot[1]))
		local car = createVehicle(data.vehicle_model,x,y,z+zoff,data.vehicle_rot[1],data.vehicle_rot[2],data.vehicle_rot[3])
		setElementHealth(car,1000)
		setElementDimension(car,dim)
		setElementVelocity(car,data.vx,data.vy,data.vz)
		setElementAngularVelocity(car,0,0,0)
		-- ghostmode for 5 second (prevent stack)
		--setElementCollidableWith (car,"vehicle", false)
		element_timers[car] = {}
	
		players[data.syncer].cop_heli = car
		

		addEventHandler("onElementDestroy",car,function() 
			removeCarFromListOnDestroy()
			if players[data.syncer] then
				players[data.syncer].cop_heli = nil
			end
		end,false)

		addEventHandler("onVehicleExplode",car,function() 
			removeDestroyedCar()
			players[data.syncer].cop_heli = nil
		end,false)
		population.cars[car] = {
			group = data.group,
			syncer = data.syncer or nil
		}

		for idx,model in ipairs(data.peds) do
			local ped = createPed(model,x,y,z+1)
			warpPedIntoVehicle(ped,car,idx-1)
			PED:setPedWalkingSAStyle(ped)
			setElementDimension(ped,dim)
			element_timers[ped] = {}
			addEventHandler("onElementDestroy",ped,function() 
				removePedFromListOnDestroy("peds")
			end,false)
			addEventHandler("onPedWasted",ped,removeDeadPed,false)
			setElementData(ped,"npchlc:group",data.group)

			population.peds[ped] = {
				group = data.group,
			}

			givePedGroupWeapon(ped)
			setPedWeaponSlot(ped,0)
			npc_hlc:enableHLCForNPC(ped,"walk",0.99,speed)
			ped_lane[ped] = lane
			initPedRouteData(ped)
			addNodeToPedRoute(ped,data.n1)
			addNodeToPedRoute(ped,data.n2,data.nb)
			for nodenum = 1,4 do addRandomNodeToPedRoute(ped) end
			if idx == 1 then 
				triggerClientEvent(data.syncer,"traffic.vehicle.heli",data.syncer,ped,car,0.2)
			end
		end
		print("heli"..getTickCount())

		return car
	end
	if type == "cars" then
		if #getElementsWithinRange (x,y,z,8,"vehicle") > 0 then
			return
		end

		local zoff = z_offset[data.vehicle_model]/math.cos(math.rad(data.vehicle_rot[1]))
		local car = createVehicle(data.vehicle_model,x,y,z+zoff,data.vehicle_rot[1],data.vehicle_rot[2],data.vehicle_rot[3])
		setElementHealth(car,1000)
		setElementDimension(car,dim)
		setElementVelocity(car,data.vx,data.vy,data.vz)
		setElementAngularVelocity(car,0,0,0)
		-- ghostmode for 5 second (prevent stack)
		--setElementCollidableWith (car,"vehicle", false)
		element_timers[car] = {}
		addEventHandler("onElementDestroy",car,removeCarFromListOnDestroy,false)
		addEventHandler("onVehicleExplode",car,removeDestroyedCar,false)
		population.cars[car] = {
			group = data.group,
			syncer = data.syncer or nil
		}

		for idx,model in ipairs(data.peds) do
			local ped = createPed(model,x,y,z+1)
			warpPedIntoVehicle(ped,car,idx-1)
			PED:setPedWalkingSAStyle(ped)
			setElementDimension(ped,dim)
			element_timers[ped] = {}
			addEventHandler("onElementDestroy",ped,function() 
				removePedFromListOnDestroy("peds")
			end,false)
			addEventHandler("onPedWasted",ped,removeDeadPed,false)
			setElementData(ped,"npchlc:group",data.group)

			population.peds[ped] = {
				group = data.group,
				attacker = false,
			}

			givePedGroupWeapon(ped)
			setPedWeaponSlot(ped,0)
			npc_hlc:enableHLCForNPC(ped,"walk",0.99,speed)
			ped_lane[ped] = lane
			initPedRouteData(ped)
			addNodeToPedRoute(ped,data.n1)
			addNodeToPedRoute(ped,data.n2,data.nb)
			for nodenum = 1,4 do addRandomNodeToPedRoute(ped) end
		end
		return car
	end

	if type == "peds" then
		local leader = nil
		for idx,model in ipairs(data.peds) do
			local ped = createPed(model,x,y,z+1)
			if idx == 1 then 
				leader = ped
			end
			PED:setPedWalkingSAStyle(ped)
			setElementDimension(ped,dim)
			element_timers[ped] = {}
			addEventHandler("onElementDestroy",ped,function() 
				removePedFromListOnDestroy("peds")
			end,false)
			addEventHandler("onPedWasted",ped,removeDeadPed,false)
			setElementData(ped,"npchlc:group",data.group)

			population.peds[ped] = {
				group = data.group,
				attacker = false,
			}

			
			npc_hlc:enableHLCForNPC(ped,"walk",0.99,speed)
			npc_hlc:setNPCAvoidCrash(ped,true)
			ped_lane[ped] = lane
			initPedRouteData(ped)
			givePedGroupWeapon(ped)
			setPedWeaponSlot(ped,0)
			addNodeToPedRoute(ped,data.n1)
			addNodeToPedRoute(ped,data.n2,data.nb)
			--for nodenum = 1,4 do addRandomNodeToPedRoute(ped) end

			if idx ~= 1 then 
				npc_hlc:addNPCTask(ped,{"followElement",leader,1.5})
			end
		end
		return ped
	end
end