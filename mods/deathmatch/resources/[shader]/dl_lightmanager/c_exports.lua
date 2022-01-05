--
-- c_exports.lua
--

function createPointLight(posX,posY,posZ,colorR,colorG,colorB,colorA,attenuation,...)
	local reqParam = {posX,posY,posZ,colorR,colorG,colorB,colorA,attenuation}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param~=nil and (type(param) == "number")
		assert(type(param) == "number", "Expected number at argument "..countParam.." , got "..type(param))
	end
	local optParam = {...}
	if not isThisValid or (#optParam > 4 or #reqParam ~= 8 ) or (countParam ~= 8) then 
		return false 
	end
	if (type(optParam[1]) ~= "boolean") then
		optParam[1] = false
	end
	if (type(optParam[2]) ~= "boolean") then
		optParam[3] = false
	end
	if (type(optParam[3]) ~= "number") then
		optParam[4] = -1
	end
	if (type(optParam[4]) ~= "number") then
		optParam[4] = -1
	end
	local generateNormals = optParam[1]
	local skipNormals = optParam[2]
	local lightDimension = optParam[3]
	local lightInterior = optParam[4]
	local lightElementID = lightFuncTable.create(1,posX,posY,posZ,colorR,colorG,colorB,colorA,0,0,-1,0,0,0,attenuation
		,generateNormals,skipNormals,lightDimension,lightInterior)
	local lightElement = createElement("dynamiclight", tostring(lightElementID))
	return lightElement
end

function createSpotLight(posX,posY,posZ,colorR,colorG,colorB,colorA,dirX,dirY,dirZ,falloff,theta,phi,attenuation,...)
	local reqParam = {posX,posY,posZ,colorR,colorG,colorB,colorA,dirX,dirY,dirZ,falloff,theta,phi,attenuation}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param~=nil and (type(param) == "number")
		assert(type(param) == "number", "Expected number at argument "..countParam.." , got "..type(param))
	end
	local optParam = {...}
	if not isThisValid or (#optParam > 4 or #reqParam ~= 14 ) or (countParam ~= 14) then
		return false 
	end
	if (type(optParam[1]) ~= "boolean") then
		optParam[1] = false
	end
	if (type(optParam[2]) ~= "boolean") then
		optParam[2] = false
	end
	if (type(optParam[3]) ~= "number") then
		optParam[3] = -1
	end
	if (type(optParam[4]) ~= "number") then
		optParam[4] = -1
	end
	local generateNormals = optParam[1]
	local skipNormals = optParam[2]
	local lightDimension = optParam[3]
	local lightInterior = optParam[4]
	local lightElementID = lightFuncTable.create(2,posX,posY,posZ,colorR,colorG,colorB,colorA,dirX,dirY,dirZ,falloff,theta,phi,attenuation
			,generateNormals,skipNormals,lightDimension,lightInterior)
	local lightElement = createElement("dynamiclight", tostring(lightElementID))
	return lightElement
end

function destroyLight(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if type(lightElementID) == "number" then
		if attachTable.inputLights[lightElementID] then
			if attachTable.inputLights[lightElementID].enabled then
				detachLight(w)
			end
		end
		return destroyElement(w) and lightFuncTable.destroy(lightElementID)
	else
		return false
	end
end

function getLightType(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].lightType
		else
			return false
		end
	else
		return false
	end
end

function setLightDimension(w,dimension)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(dimension) == "number", "Expected number at argument 2, got "..type(dimension))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(dimension) == "number") then 
		lightTable.inputLights[lightElementID].dimension = dimension
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightDimension(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].dimension
		else
			return false
		end
	else
		return false
	end
end

function setLightInterior(w,interior)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(interior) == "number", "Expected number at argument 2, got "..type(interior))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(interior) == "number") then 
		lightTable.inputLights[lightElementID].interior = interior
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightInterior(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].interior
		else
			return false
		end
	else
		return false
	end
end

function setLightDistFade(w,fadeEnd,fadeStart)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	local reqParam = {lightElementID,fadeEnd,fadeStart}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param and (type(param) == "number")
	end
	assert(isThisValid, "Expected 2 sets of numbers (distance fade) at argument 2,3")
	if lightTable.inputLights[lightElementID] and isThisValid then
		if (countParam == 3) then
			lightTable.inputLights[lightElementID].distFade = {fadeEnd,fadeStart}
			dxSetShaderValue(lightTable.entity[lightElementID], "gDistFade", fadeEnd,fadeStart )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end

function getLightDistFade(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return unpack(lightTable.inputLights[lightElementID].distFade)
		else
			return false
		end
	else
		return false
	end
end

function setLightDirection(w,dirX,dirY,dirZ)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	local reqParam = {lightElementID,dirX,dirY,dirZ}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param and (type(param) == "number")
	end
	assert(isThisValid, "Expected 3 sets of numbers (direction vector) at argument 2,3,4")
	if lightTable.inputLights[lightElementID] and isThisValid then
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) and (countParam == 4) then
			lightTable.inputLights[lightElementID].dir = {dirX,dirY,dirZ}
			dxSetShaderValue(lightTable.entity[lightElementID], "sLightDir", dirX,dirY,dirZ )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end

function getLightDirection(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) and (lightTable.inputLights[lightElementID].enabled == true) then
			return unpack(lightTable.inputLights[lightElementID].dir)
		else
			return false
		end
	else
		return false
	end
end

function setLightRotation(w,rotX,rotY,rotZ)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	local reqParam = {lightElementID,rotX,rotY,rotZ}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param and (type(param) == "number")
	end
	assert(isThisValid, "Expected 3 sets of numbers (world rotation) at argument 2,3,4")
	if lightTable.inputLights[lightElementID] and isThisValid then
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) and (countParam == 4) then
			local rx, rz = math.rad(rotX), math.rad(rotZ)
			local dirX, dirY, dirZ = -math.cos(rx) * math.sin(rz), math.cos(rz) * math.cos(rx), math.sin(rx)
			lightTable.inputLights[lightElementID].dir = {dirX, dirY, dirZ}
			dxSetShaderValue(lightTable.entity[lightElementID], "sLightDir", dirX,dirY,dirZ )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end

function getLightRotation(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) and (lightTable.inputLights[lightElementID].enabled == true) then
			local vx, vy, vz = unpack(inputLights[lightElementID].dir)
			local len = math.sqrt(vx * vx + vy * vy + vz * vz)
			return math.deg(math.asin(vz / len)), 0, -math.deg(math.atan2(vx, vy))
		else
			return false
		end
	else
		return false
	end
end

function setLightPosition(w,posX,posY,posZ)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	local reqParam = {lightElementID,posX,posY,posZ}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param and (type(param) == "number")
	end
	assert(isThisValid, "Expected 3 sets of numbers (world position) at argument 2,3,4")
	if lightTable.inputLights[lightElementID] and isThisValid  and (countParam == 4) then
		lightTable.inputLights[lightElementID].pos = {posX,posY,posZ}
		dxSetShaderValue(lightTable.entity[lightElementID], "sLightPosition", posX,posY,posZ)
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightPosition(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return unpack(lightTable.inputLights[lightElementID].pos)
		else
			return false
		end
	else
		return false
	end
end

function setLightColor(w,colorR,colorG,colorB,colorA)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	local reqParam = {lightElementID,colorR,colorG,colorB,colorA}
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(reqParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param and (type(param) == "number")
	end
	assert(isThisValid, "Expected 4 sets of numbers (rgba color) at argument 2,3,4,5")
	if lightTable.inputLights[lightElementID] and isThisValid  and (countParam == 5)  then
		lightTable.inputLights[lightElementID].color = {colorR,colorG,colorB,colorA}
		dxSetShaderValue(lightTable.entity[lightElementID], "sLightColor", colorR / 255,colorG / 255,colorB / 255,colorA / 255)		
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightColor(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return unpack(lightTable.inputLights[lightElementID].color)
		else
			return false
		end
	else
		return false
	end
end

function setLightBlend(w,lightBlend)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(lightBlend) == "number", "Expected number (0 - 1) at argument 2, got "..type(lightBlend))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(lightBlend) == "number") then 
		lightTable.inputLights[lightElementID].lightBlend = lightBlend
		dxSetShaderValue(lightTable.entity[lightElementID], "sTexBlend", lightBlend)
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightBlend(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].lightBlend
		else
			return false
		end
	else
		return false
	end
end

function setLightAttenuation(w,attenuation)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(attenuation) == "number", "Expected number at argument 2, got "..type(attenuation))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(attenuation) == "number") then 
		lightTable.inputLights[lightElementID].attenuation = attenuation
		dxSetShaderValue(lightTable.entity[lightElementID], "sLightAttenuation", attenuation)
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightAttenuation(w)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].attenuation
		else
			return false
		end
	else
		return false
	end
end

function setLightAttenuationPower(w,attenuationPower)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(attenuationPower) == "number", "Expected number at argument 2, got "..type(attenuationPower))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(attenuationPower) == "number") then 
		lightTable.inputLights[lightElementID].attenuationPower = attenuationPower
		dxSetShaderValue(lightTable.entity[lightElementID], "sLightAttenuationPower", attenuationPower)
		lightTable.isInValChanged = true
		return true
	else
		return false
	end
end

function getLightAttenuationPower(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) then
			return lightTable.inputLights[lightElementID].attenuationPower
		else
			return false
		end
	else
		return false
	end
end	
		
function setLightFalloff(w,falloff)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(falloff) == "number", "Expected number at argument 2, got "..type(falloff))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and type(falloff) == "number" then	
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then	
			lightTable.inputLights[lightElementID].falloff = falloff
			dxSetShaderValue(lightTable.entity[lightElementID], "sLightFalloff", falloff )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end

function getLightFalloff(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) and ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then
			return lightTable.inputLights[lightElementID].falloff
		else
			return false
		end
	else
		return false
	end
end

function setLightTheta(w,theta)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(theta) == "number", "Expected number at argument 2, got "..type(theta))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(theta) == "number") then 
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then 
			lightTable.inputLights[lightElementID].theta = theta
			dxSetShaderValue(lightTable.entity[lightElementID],  "sLightTheta", theta )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end

function getLightTheta(w)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) and ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then
			return lightTable.inputLights[lightElementID].theta
		else
			return false
		end
	else
		return false
	end
end

function setLightPhi(w,phi)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(type(phi) == "number", "Expected number at argument 2, got "..type(phi))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] and (type(phi) == "number") then 
		if ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then 
			lightTable.inputLights[lightElementID].phi = phi
			dxSetShaderValue(lightTable.entity[lightElementID],  "sLightPhi", phi )
			lightTable.isInValChanged = true
			return true
		else
			return false
		end
	else
		return false
	end
end	

function getLightPhi(w)
	if not isElement(w) then
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then
		if (lightTable.inputLights[lightElementID].enabled == true) and ((lightTable.inputLights[lightElementID].lType == 2) or (lightTable.inputLights[lightElementID].lType == 4)) then
			return lightTable.inputLights[lightElementID].phi
		else
			return false
		end
	else
		return false
	end
end
 
function attachLightToElement(w,theElement,...)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	if not isElement(theElement) then 
		assert(isElement(theElement), "Expected element at argument 2, got "..type(theElement))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	assert(getElementType(theElement) == "ped" or getElementType(theElement) == "player" or getElementType(theElement) == "vehicle" or getElementType(theElement) == "object", "Expected element attached to light at argument 2 to be player, ped, vehicle or object, got "..getElementType(theElement))

	local optParam = {...}
	if (#optParam > 6) then
		assert(true, "Exceeded the number of optional arguments")
		return false 
	end
	local isThisValid = true
	local countParam = 0
	for m, param in ipairs(optParam) do
		countParam = countParam + 1
		isThisValid = isThisValid and param~=nil and (type(param) == "number")
		assert(type(param) == "number", "Expected number at argument "..countParam.." , got "..type(param))
	end
	
	if (type(optParam[1]) ~= "number") then
		optParam[1] = 0
	end
	if (type(optParam[2]) ~= "number") then
		optParam[2] = 0
	end
	if (type(optParam[3]) ~= "number") then
		optParam[3] = 0
	end
	if (type(optParam[4]) ~= "number") then
		optParam[4] = 0
	end
	if (type(optParam[5]) ~= "number") then
		optParam[5] = 0
	end
	if (type(optParam[6]) ~= "number") then
		optParam[6] = 0
	end
	local xPosOffset, yPosOffset, zPosOffset, xRotOffset, yRotOffset, zRotOffset = unpack(optParam)
	local lightElementID = tonumber(getElementID(w))
	if lightTable.inputLights[lightElementID] then 
		return attachFuncTable.create(theElement, lightElementID, xPosOffset, yPosOffset, zPosOffset, xRotOffset, yRotOffset, zRotOffset)
	else
		assert(type(lightElementID) == "number", "Expected proper lightElementID at argument 2 , got "..type(param))
		return false
	end
end

function detachLight(w)
	if not isElement(w) then 
		assert(isElement(w), "Expected element at argument 1, got "..type(w))
		return false
	end
	assert(getElementType(w) == "dynamiclight", "Expected dynamiclight element at argument 1, got "..getElementType(w))
	local lightElementID = tonumber(getElementID(w))
	if type(lightElementID) == "number" then
		return attachFuncTable.destroy(lightElementID)
	else
		return false
	end
end

function detachFromElement(theElement)
	if not isElement(theElement) then 
		assert(isElement(theElement), "Expected element at argument 1, got "..type(theElement))
		return false
	end
	assert(getElementType(theElement) == "ped" or getElementType(theElement) == "player" or getElementType(theElement) == "vehicle" or getElementType(theElement) == "object", "Expected element attached to light at argument 2 to be player, ped, vehicle or object, got "..getElementType(theElement))
	return attachFuncTable.destroyAllAttachedToElement(theElement)
end
