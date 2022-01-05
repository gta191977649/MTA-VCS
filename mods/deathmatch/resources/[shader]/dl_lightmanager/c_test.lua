--[[

local lightMatrix = {}

bindKey("1", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))

	lightMatrix[#lightMatrix + 1] = createPointLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,lightAttenuation, false)
end
)

bindKey("2", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))
	local forwardVec = getCamera().matrix.forward
	local lightTheta = (math.rad(math.random(5,20))) -- Theta is the inner cone angle
	local lightPhi = (math.rad(math.random(30,50))) -- Phi is the outer cone angle
	local lightFalloff = (0.5 + math.random()) -- light intensity attenuation between the phi and theta areas
	lightMatrix[#lightMatrix + 1] = createSpotLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,forwardVec.x,forwardVec.y,forwardVec.z,lightFalloff,lightTheta,lightPhi,lightAttenuation, false)
end
)

bindKey("3", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))

	lightMatrix[#lightMatrix + 1] = createPointLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,lightAttenuation, true)
end
)

bindKey("4", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))
	local forwardVec = getCamera().matrix.forward
	local lightTheta = (math.rad(math.random(5,20))) -- Theta is the inner cone angle
	local lightPhi = (math.rad(math.random(30,50))) -- Phi is the outer cone angle
	local lightFalloff = (0.5 + math.random()) -- light intensity attenuation between the phi and theta areas
	lightMatrix[#lightMatrix + 1] = createSpotLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,forwardVec.x,forwardVec.y,forwardVec.z,lightFalloff,lightTheta,lightPhi,lightAttenuation, true)
end
)

bindKey("5", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))

	lightMatrix[#lightMatrix + 1] = createPointLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,lightAttenuation, false, true)
end
)

bindKey("6", "down", function()
    local camPos = getCamera().matrix.position + getCamera().matrix.forward * 5
	local lightAttenuation = math.random(1,10)
	local lightColor = Vector4(math.random(100,255), math.random(100,255), math.random(100,255), math.random(200,255))
	local forwardVec = getCamera().matrix.forward
	local lightTheta = (math.rad(math.random(5,20))) -- Theta is the inner cone angle
	local lightPhi = (math.rad(math.random(30,50))) -- Phi is the outer cone angle
	local lightFalloff = (0.5 + math.random()) -- light intensity attenuation between the phi and theta areas
	lightMatrix[#lightMatrix + 1] = createSpotLight(camPos.x,camPos.y,camPos.z,lightColor.x,lightColor.y,lightColor.z,lightColor.w,forwardVec.x,forwardVec.y,forwardVec.z,lightFalloff,lightTheta,lightPhi,lightAttenuation, false, true)
end
)

local myLastLight = nil
bindKey("7", "down", function()
	myLastLight = lightMatrix[#lightMatrix]
	if myLastLight then
		local lightType = getLightType(myLastLight)
		attachLightToElement(myLastLight,localPlayer,0,2,0,30,0,30)
	end
end
)

bindKey("8", "down", function()
	if myLastLight then
		local lightType = getLightType(myLastLight)
		detachFromElement(localPlayer)
	end
end
)

bindKey("0", "down", function()
	for i,v in ipairs(lightMatrix) do
		destroyLight(v)
		lightMatrix[i] = nil
	end
end
)


addEventHandler( "onClientResourceStart", getResourceRootElement( getThisResource()), function()
	outputChatBox("dl_lightmanager test:")
	outputChatBox("hit'1' for point light,'2' for spot light")
	outputChatBox("hit'3' for point light (normalGen),'4' for spot light (normalGen)")
	outputChatBox("hit'5' for point light (skipNormal),'6' for spot light (skipNormal)")	
	outputChatBox("hit'7' to attach last light to ped, 8 detach")
	outputChatBox("hit'0' to clear lights")
end
)

]]--