-- 
-- c_attach.lua
--
		
---------------------------------------------------------------------------------------------------
-- global settings
---------------------------------------------------------------------------------------------------
attachFuncTable = {}
attachTable = { inputLights = {}, thisLight = 0 }

---------------------------------------------------------------------------------------------------
-- draw lights
---------------------------------------------------------------------------------------------------
function attachFuncTable.create(theElement, lightElementID, xPosOffset, yPosOffset, zPosOffset, xRotOffset, yRotOffset, zRotOffset)
	local w = findEmptyEntry(attachTable.inputLights)
	if not attachTable.inputLights[w] then attachTable.inputLights[w] = {} end
	attachTable.inputLights[w].lightID = lightElementID
	attachTable.inputLights[w].element = theElement
	attachTable.inputLights[w].posOffset = {xPosOffset, yPosOffset, zPosOffset}
	attachTable.inputLights[w].rotOffset = {xRotOffset, yRotOffset, zRotOffset}
	attachTable.inputLights[w].enabled = true
	local lightType = lightTable.inputLights[lightElementID].lType
	local isRotOffset = ((lightType == 2) or (lightType == 4))
	attachTable.inputLights[w].isRotOffset = isRotOffset
	outputDebugString('Attached Light ID:'..lightElementID..' as instance:'..w)
	return w
end

function attachFuncTable.destroyAllAttachedToElement(theElement)
	for index,this in ipairs(attachTable.inputLights) do
		if this.enabled then
			if this.element == theElement then
				attachFuncTable.destroy(index)
			end
		end
	end
end

function attachFuncTable.destroy(w)
	if attachTable.inputLights[w] then
		local lightElementID = attachTable.inputLights[w].lightID
		if attachTable.inputLights[w].enabled then
			attachTable.inputLights[w].enabled = false
			outputDebugString('Detached Light ID:'..lightElementID..' instance: '..w)
			attachTable.inputLights[w].element = nil
			return true
		else
			outputDebugString('Instance:'..w..' already detached')
			return false
		end
	else
		outputDebugString('Have Not Detached instance:'..w)
		return false 
	end
end

addEventHandler("onClientPedsProcessed", root, function()
	if #attachTable.inputLights == 0 then return end
	attachTable.thisLight = 0
	for index,this in ipairs(attachTable.inputLights) do
		if this.enabled then
			if isElementStreamedIn(this.element) then
				if this.isRotOffset then
					applyPosDirOffsets(this.lightID, this.element, this.posOffset, this.rotOffset)
					dxSetShaderValue(lightTable.entity[this.lightID], "sLightPosition", unpack(lightTable.inputLights[this.lightID].pos))
					dxSetShaderValue(lightTable.entity[this.lightID], "sLightDir", unpack(lightTable.inputLights[this.lightID].dir ))
				else
					applyPosOffsets(this.lightID, this.element, this.posOffset)
					dxSetShaderValue(lightTable.entity[this.lightID], "sLightPosition", unpack(lightTable.inputLights[this.lightID].pos))
				end
			end
		end
	end
end
,true ,"high+6")

function applyPosDirOffsets(lightElementID, theElement, posOffset, rotOffset)
	local mat1 = getRotationMatrixFromZXYRotation(math.rad(rotOffset[1]), math.rad(rotOffset[2]), math.rad(rotOffset[3]))
	
	local rotX2, rotY2, rotZ2 = getElementRotation ( theElement , "ZXY" )
	local mat2 = getRotationMatrixFromZXYRotation(math.rad(rotX2), math.rad(rotY2), math.rad(rotZ2))

	-- multiply rotation matrices
	local matOut = {}
	for i = 1,#mat1 do
		matOut[i] = {}
		for j = 1,#mat2[1] do
			local num = mat1[i][1] * mat2[1][j]
			for n = 2,#mat1[1] do
				num = num + mat1[i][n] * mat2[n][j]
			end
			matOut[i][j] = num
		end
	end
	lightTable.inputLights[lightElementID].dir = {matOut[2][1], matOut[2][2], matOut[2][3]}
	lightTable.inputLights[lightElementID].pos = getPositionFromElementOffset(theElement, posOffset)
end

function applyPosOffsets(lightElementID, theElement, posOffset)
	lightTable.inputLights[lightElementID].pos = getPositionFromElementOffset(theElement, posOffset)
end

function getPositionFromElementOffset(theElement,posOffset)
    local mat1 = getElementMatrix ( theElement )  -- Get the matrix
    local x = posOffset[1] * mat1[1][1] + posOffset[2] * mat1[2][1] + posOffset[3] * mat1[3][1] + mat1[4][1]  -- Apply transform
    local y = posOffset[1] * mat1[1][2] + posOffset[2] * mat1[2][2] + posOffset[3] * mat1[3][2] + mat1[4][2]
    local z = posOffset[1] * mat1[1][3] + posOffset[2] * mat1[2][3] + posOffset[3] * mat1[3][3] + mat1[4][3]
    return {x, y, z}                               -- Return the transformed point
end

function getRotationMatrixFromZXYRotation( rotX, rotY, rotZ )
	return {
			{math.cos(rotZ) * math.cos(rotY) - math.sin(rotZ) * math.sin(rotX) * math.sin(rotY), 
                math.cos(rotY) * math.sin(rotZ) + math.cos(rotZ) * math.sin(rotX) * math.sin(rotY), -math.cos(rotX) * math.sin(rotY)},
			{-math.cos(rotX) * math.sin(rotZ), math.cos(rotZ) * math.cos(rotX), math.sin(rotX)},
			{math.cos(rotZ) * math.sin(rotY) + math.cos(rotY) * math.sin(rotZ) * math.sin(rotX), math.sin(rotZ) * math.sin(rotY) - 
                math.cos(rotZ) * math.cos(rotY) * math.sin(rotX), math.cos(rotX) * math.cos(rotY)}
			}
end
