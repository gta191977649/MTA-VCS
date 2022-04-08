function isModelObstcle(model_id)
	if not tonumber(model_id) then 
		return false
	end
	local dff = engineGetModelNameFromID(model_id) -- check if not road
	
	if dff ~= false and tostring(dff) then 
		local isRoad = string.match(dff, 'road')
		if isRoad ~= nil then
			--print(string.format( "%d : %s NO",model_id,dff))
			return false
		end
	end
	return true
end

function obstacleCheck(hitModel)
	if hitModel~= nil and tonumber(hitModel) then 
		return isModelObstcle(hitModel)
	end
	return true
end

function createPedRaycast(element,type) 
	local px,py,pz = getElementPosition(element)
	local x0, y0, z0, x1, y1, z1 = getElementBoundingBox( element )
	local vWidth = mathAbs(y0 - y1)
	local vHeight = mathAbs(x0 -x1)
	if type == "raycast_eye_l" then
		local lx,ly,lz = getPositionFromElementOffset(element,-1,vWidth,0)
		--local ray,_,_,_,hitElement,_,_,_,_,_,_,hitModel = processLineOfSight(px,py,pz,lx,ly,lz,true,true,true,true,false,true,true,false,element,true)
		local ray = isLineOfSightClear(px,py,pz,lx,ly,lz,true,true,true,true,true,false,false,element)
		if debug then dxDrawLine3D( px,py,pz, lx,ly,lz,ray == false and tocolor ( 255, 0, 0, 255 )  or tocolor ( 0, 255, 0, 255 ) ,1 ) end
		return not ray
	end
	if type == "raycast_eye_m" then
		local lx,ly,lz = getPositionFromElementOffset(element,0,vWidth+0.5,0)
		--local ray,_,_,_,hitElement,_,_,_,_,_,_,hitModel = processLineOfSight(px,py,pz,lx,ly,lz,true,true,true,true,false,true,true,false,element,true)
		local ray = isLineOfSightClear(px,py,pz,lx,ly,lz,true,true,true,true,true,false,false,element)
		if debug then dxDrawLine3D( px,py,pz, lx,ly,lz,ray == false and tocolor ( 255, 0, 0, 255 )  or tocolor ( 0, 255, 0, 255 ) ,1 ) end
		return not ray
	end
	if type == "raycast_eye_r" then
		local lx,ly,lz = getPositionFromElementOffset(element,1,vWidth,0)
		--local ray,_,_,_,hitElement,_,_,_,_,_,_,hitModel = processLineOfSight(px,py,pz,lx,ly,lz,true,true,true,true,false,true,true,false,element,true)
		local ray = isLineOfSightClear(px,py,pz,lx,ly,lz,true,true,true,true,true,false,false,element)
		if debug then dxDrawLine3D( px,py,pz, lx,ly,lz,ray == false and tocolor ( 255, 0, 0, 255 )  or tocolor ( 0, 255, 0, 255 ) ,1 ) end
		return not ray
	end
end
function createRaycast(element,type,dist_x,dist_y,dist_z,gap,ingnoreRotation,ignoreRoadCheck)
	gap = gap or 2
	ingnoreRotation = ingnoreRotation or false
	ignoreRoadCheck = ignoreRoadCheck or false
	local px,py,pz = getElementPosition(element)
	local rx,ry,rz = getElementRotation(element)
	local dist = Vector2(px,py) + Vector2(dist_x,dist_y)

	if debug then 
		dxDrawLine3D( px,py,pz,dist.x,dist.y,pz,tocolor ( 255, 0, 255, 255 ))
	end

	local dx = dist.x - px
	local dy = dist.y - py
	local a = mathAtan2(dx,dy)

	if not ingnoreRotation then
		local angle = 360 -  (a * 180/math.pi)
		--print(angleWrapping(angle))
		if math.abs(rz - angle) < 90 then
			rz = angle
		end
	end

	
	local x0, y0, z0, x1, y1, z1 = getElementBoundingBox( element )
	local vWidth = mathAbs(y0 - y1) 
	local vHeight = mathAbs(x0 -x1)
	local lx,ly,lz = 0
	if type == "raycast_l" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz,-gap,vWidth+0.5,AI.config.sensorOffsetZ)
	end
	if type == "raycast_m" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz,0,vWidth+2,AI.config.sensorOffsetZ)
	end
	if type == "raycast_r" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz,gap,vWidth+0.5,AI.config.sensorOffsetZ)
	end
	if type == "raycast_b" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz, 0,-(vWidth/2+1),AI.config.sensorOffsetZ)
	end
	if type == "raycast_d" then
		lx,ly,lz = px,py,pz-15
	end
	if type == "raycast_sr" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz,vHeight/2 + 1,0,AI.config.sensorOffsetZ)
	end
	if type == "raycast_sl" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz,-(vHeight/2 + 1),0,AI.config.sensorOffsetZ)
	end
	if type == "raycast_bl" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz, gap+0.5,-(vWidth/2+1),AI.config.sensorOffsetZ)
	end
	if type == "raycast_br" then
		lx,ly,lz = getPositionFromOffsetByPosRot(px,py,pz,rx,ry,rz, -gap-0.5,-(vWidth/2+1),AI.config.sensorOffsetZ)
	end
	local ray,_,_,_,hitElement,_,_,_,_,_,_,hitModel
	if type == "raycast_m" then 
		ray,_,_,_,hitElement,_,_,_,_,_,_,hitModel = processLineOfSight(px,py,pz+AI.config.sensorOffsetZ,lx,ly,lz,true,true,true,true,false,true,true,false,element,true)
	else
		ray = not isLineOfSightClear(px,py,pz+AI.config.sensorOffsetZ,lx,ly,lz,true,true,true,true,false,true,true,element)
	end

	hitModel = hitModel or false
	if ray and hitModel ~= false and hitElement ~= nil and getElementType(hitElement) == "object" and ignoreRoadCheck == false then
		ray = obstacleCheck(hitModel)
	end
	if debug then dxDrawLine3D( px,py,pz, lx,ly,lz,ray == true and tocolor ( 255, 0, 0, 255 )  or tocolor ( 0, 255, 0, 255 ) ,1 ) end

	return ray,hitElement,hitModel
end