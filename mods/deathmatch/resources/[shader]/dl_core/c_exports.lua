--
-- c_exports.lua
--

----------------------------------------------------------------------------------------------------
-- exports
----------------------------------------------------------------------------------------------------
function getRenderTargets()
	if targetTable.RTColor and targetTable.RTNormal then
		return targetTable.RTColor, targetTable.RTNormal
	else
		return false, false
	end
end

function passGTASAObjectNormals(isPassNormals)
	assert(type(isPassNormals) == "boolean", "Expected boolean at argument 1 , got "..type(isPassNormals))
	if shaderTable.SHWorld and shaderTable.SHWorldNoZWrite then
		return functionTable.disableNormals(not isPassNormals)
	else
		return false
	end
end		
		
function applyEmissiveEffectToWorld(texName, ...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	local otherVars = {...}
	local thisEntity = nil
	local isSecondTextureState = false
	if isElement(otherVars[1]) then
		if getElementType(otherVars[1]) == "object" then
			thisEntity = otherVars[1]
		else
			thisEntity = nil
		end
	end
	local SHWorldEmissive = dxCreateShader(unpack(shaderParams.SHWorldEmissiveAdd))
	if SHWorldEmissive then
		functionTable.applyRTToTextureShader(SHWorldEmissive)
		engineApplyShaderToWorldTexture(SHWorldEmissive, texName or "", thisEntity)
		return SHWorldEmissive
	else
		return false
	end
end

function applyEmissiveTextureToWorld(texName,emissTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(emissTex), "Expected element at argument 2, got "..type(emissTex))
	assert(getElementType(emissTex) == "texture", "Expected texture element at argument 2, got "..getElementType(emissTex))
	local optParam = {...}
	
	if isElement(optParam[1]) then
		assert(getElementType(theElement) == "object", "Expected object element at argument 4, got "..type(theElement))		
	else
		optParam[1] = nil
	end
	local thisEntity = unpack(optParam)	
	
	local worldEmissiveShader = dxCreateShader(unpack(shaderParams.SHWorldEmissive))
	if worldEmissiveShader then
		functionTable.applyRTToTextureShader(worldEmissiveShader)
		dxSetShaderValue(worldEmissiveShader, "gTextureEmissive", emissTex) 
		engineApplyShaderToWorldTexture(worldEmissiveShader, texName, thisEntity or nil)
		return worldEmissiveShader
	else 
		return false
	end
end

function setEmissiveTextureBlurIntensity(myShader, sBrightMult)
	assert(getElementType(myShader) == "shader", "Expected shader element at argument 1, got "..getElementType(myShader))
	if myShader then
		dxSetShaderValue(myShader, "sBrightMult", sBrightMult or 0)
	else
		return false
	end
end

function setEmissiveTextureBrightnessAdd(myShader, sBrightnessAdd)
	assert(getElementType(myShader) == "shader", "Expected shader element at argument 1, got "..getElementType(myShader))
	if myShader then
		dxSetShaderValue(myShader, "sBrightAdd", sBrightnessAdd or 0)
	else
		return false
	end
end

function setEmissivePostEffectEnabled(setEnabled)
	assert(type(setEnabled) == "boolean", "Expected bool at argument 1 , got "..type(texName))
	if setEnabled then
		 return functionTable.createEmissivePostEffect()
	else
		return not functionTable.destroyEmissivePostEffect()
	end
end

function applyNormalTextureToPed(texName,normalTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(normalTex), "Expected element at argument 2, got "..type(normalTex))
	assert(getElementType(normalTex) == "texture", "Expected texture element at argument 2, got "..getElementType(normalTex))
	local optParam = {...}
	
	if (type(optParam[1]) ~= "number") then
		optParam[1] = 0.5
	end
	if isElement(optParam[2]) then
		assert(getElementType(theElement) == "ped" or getElementType(theElement) == "player", "Expected ped element at argument 4, got "..type(theElement))		
	else
		optParam[2] = nil
	end
	local lerpNormal, thisEntity = unpack(optParam)	
	
	local pedNormalShader = dxCreateShader(unpack(shaderParams.SHPedNormal))
	if pedNormalShader then
		functionTable.applyRTToTextureShader(pedNormalShader)
		dxSetShaderValue(pedNormalShader, "fLerpNormal", lerpNormal or 0.5) 
		dxSetShaderValue(pedNormalShader, "gTextureNormal", normalTex) 
		engineApplyShaderToWorldTexture(pedNormalShader, texName, thisEntity or nil)
		return pedNormalShader
	else 
		return false
	end
end

function applyNormalTextureToWorld(texName,normalTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(normalTex), "Expected element at argument 2, got "..type(normalTex))
	assert(getElementType(normalTex) == "texture", "Expected texture element at argument 2, got "..getElementType(normalTex))
	local optParam = {...}
	
	if (type(optParam[1]) ~= "number") then
		optParam[1] = 0.5
	end
	if isElement(optParam[2]) then
		assert(getElementType(theElement) == "object", "Expected object element at argument 4, got "..type(theElement))		
	else
		optParam[2] = nil
	end
	local lerpNormal, thisEntity = unpack(optParam)	
	
	local worldNormalShader = dxCreateShader(unpack(shaderParams.SHWorldNormal))
	if worldNormalShader then
		functionTable.applyRTToTextureShader(worldNormalShader)
		dxSetShaderValue(worldNormalShader, "fLerpNormal", lerpNormal or 0.5) 
		dxSetShaderValue(worldNormalShader, "gTextureNormal", normalTex) 
		engineApplyShaderToWorldTexture(worldNormalShader, texName, thisEntity or nil)
		return worldNormalShader
	else 
		return false
	end
end

function setNormalStrength(myShader, lerpNormal)
	assert(getElementType(myShader) == "shader", "Expected shader element at argument 1, got "..getElementType(myShader))
	if myShader then
		dxSetShaderValue(myShader, "fLerpNormal", lerpNormal or 0.5)
	else
		return false
	end
end


function applyTextureReplaceToWorld(texName,colorTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(colorTex), "Expected element at argument 2, got "..type(colorTex))
	assert(getElementType(colorTex) == "texture", "Expected texture element at argument 2, got "..getElementType(colorTex))
	local optParam = {...}

	if isElement(optParam[1]) then
		assert(getElementType(theElement) == "object", "Expected object element at argument 4, got "..type(theElement))		
	else
		optParam[1] = nil
	end
	local thisEntity = unpack(optParam)	
	
	local texReplaceShader = dxCreateShader(unpack(shaderParams.SHWorldReplace))
	if texReplaceShader then
		functionTable.applyRTToTextureShader(texReplaceShader)
		dxSetShaderValue(texReplaceShader, "gTextureColor", colorTex) 
		engineApplyShaderToWorldTexture(texReplaceShader, texName, thisEntity or nil)
		return texReplaceShader
	else 
		return false
	end
end

function applyTextureReplaceToPed(texName,colorTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(colorTex), "Expected element at argument 2, got "..type(colorTex))
	assert(getElementType(colorTex) == "texture", "Expected texture element at argument 2, got "..getElementType(colorTex))
	local optParam = {...}

	if isElement(optParam[1]) then
		assert(getElementType(theElement) == "ped", "Expected ped element at argument 4, got "..type(theElement))		
	else
		optParam[1] = nil
	end
	local thisEntity = unpack(optParam)	
	
	local texReplaceShader = dxCreateShader(unpack(shaderParams.SHPedReplace))
	if texReplaceShader then
		functionTable.applyRTToTextureShader(texReplaceShader)
		dxSetShaderValue(texReplaceShader, "gTextureColor", colorTex) 
		engineApplyShaderToWorldTexture(texReplaceShader, texName, thisEntity or nil)
		return texReplaceShader
	else 
		return false
	end
end

function applyTextureReplaceToVehicle(texName,colorTex,...)
	assert(type(texName) == "string", "Expected string at argument 1 , got "..type(texName))
	assert(isElement(colorTex), "Expected element at argument 2, got "..type(colorTex))
	assert(getElementType(colorTex) == "texture", "Expected texture element at argument 2, got "..getElementType(colorTex))
	local optParam = {...}

	if isElement(optParam[1]) then
		assert(getElementType(theElement) == "vehicle", "Expected vehicle element at argument 4, got "..type(theElement))		
	else
		optParam[1] = nil
	end
	local thisEntity = unpack(optParam)	
	
	local texReplaceShader = dxCreateShader(unpack(shaderParams.SHVehPaintReplace))
	if texReplaceShader then
		functionTable.applyRTToTextureShader(texReplaceShader)
		dxSetShaderValue(texReplaceShader, "gTextureColor", colorTex) 
		engineApplyShaderToWorldTexture(texReplaceShader, texName, thisEntity or nil)
		return texReplaceShader
	else 
		return false
	end
end