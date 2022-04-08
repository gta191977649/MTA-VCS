local function onVehicleHit(collider, damageImpulseMag, bodyPart, x, y, z, nx, ny, nz,hitElementforce,model)
	if collider ~= nil and tonumber(model) then return end
	if isModelObstcle(model) then
		--print(model)
		if AI[npc] ~= nil and AI[npc].decision == AI.decisions[2] and bodyPart == 4 or AI[npc] ~= nil and collider == nil then
			AI[npc].decision = AI.decisions[3]
			AI[npc].lastDecisionTick = getTickCount()
		end
	end		
end

function initalAIParameter(npc)
	if AI[npc] == nil then
		AI[npc] = {}
		AI[npc].decision = AI.decisions[1]
		AI[npc].light = false
		AI[npc].hited = false
		AI[npc].temper = getElementData(npc,"npchlc:temper") or -1
		
		AI[npc].lastAttackTick = getTickCount()
		AI[npc].horn = {
			lastTick = getTickCount()
		}
		if debug then
			AI[npc].text = DGS:dgsCreate3DText(0,0,2,"D:IDLE",white)
			DGS:dgsSetProperty(AI[npc].text,"fadeDistance",20)
			DGS:dgsSetProperty(AI[npc].text,"textSize",{0.5,0.5})
			DGS:dgsSetProperty(AI[npc].text,"shadow",{0.2,0.2,tocolor(0,0,0,255),true})
			DGS:dgs3DTextAttachToElement(AI[npc].text,npc,0,0)
			--DGS:dgsAttachToAutoDestroy(npc,AI[npc].text)
		end
		local veh = getPedOccupiedVehicle(npc)
		if veh and getPedOccupiedVehicleSeat(npc) == 0 then
			--setVehicleWheelStates ( veh, 0, 0,0,0 )
			--setVehicleGravity(veh,0,0,-0.8)
			--[[
			local min_x,min_y,min_z,max_x,max_y,max_z = getElementBoundingBox (veh)
			local x,y,z = max_x - min_x, max_y - min_y, max_z - min_z
			
			AI[npc].colshape = createColCuboid (0,0,0,x,y,z)
			attachElements(AI[npc].colshape,veh,-x/2,-y/2,-z/2)
			]]
			
			addEventHandler("onClientVehicleCollision", veh,onVehicleHit)
				--setVehicleWheelStates ( veh, -1,-1,-1,-1 )
				--setVehicleGravity(veh,0,0,-1)
				addEventHandler("onClientElementDestroy", veh, function ()
					removeEventHandler("onClientVehicleCollision", veh,onVehicleHit)
				end)
			end
		addEventHandler("onClientElementDestroy", npc, function ()
			if AI[source] ~= nil then
				if isTimer(AI[source].timer) then killTimer(AI[source].timer) end
				
				if debug then
					destroyElement(AI[source].text)
				end
				AI[source] = nil
			end
		end)
	end
end
function checkAddtionalAIParams(npc) 
	-- avoid crash 
	if AI[npc].colshape == nil and streamed_npcs[npc].avoid_crash == true then
		AI[npc].colshape = createColSphere(0,0,0,5)
		setElementParent(AI[npc].colshape,npc)
		attachElements(AI[npc].colshape,npc)
		addEventHandler("onClientColShapeHit",AI[npc].colshape,function(hit,dim) 
			if not getPedOccupiedVehicle(npc) and hit and isElement(hit) and getElementType(hit) == "player" then
				if getElementSpeed(hit) > 20 then
					local _,_,na = getElementRotation(npc)
					local _,_,pa = getElementRotation(hit)
					local delta = ((hit.matrix:getPosition()-npc.matrix:getPosition()):getNormalized())
					local direction = delta:cross(hit.matrix:getForward()):getY()

					if direction > 0 then 
						setElementRotation(npc,0,0,pa+90)
					else 
						setElementRotation(npc,0,0,pa-90)
					end
					setPedAnimation(npc,"ped","ev_dive", -1, false, true, false, false)
					--npcMat:getPosition():getX()
					iprint("----------")
					--local forwardVec = Vector2(px,py)
					--print(angle)
				end
			end

		end)
	end
end