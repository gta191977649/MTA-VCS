----------------------------------------------
--Resource: dl_vehicles                     --
--Author: Ren712                            --
--Contact: knoblauch700@o2.pl               --
----------------------------------------------

---------------------------------------------------------------------------------------------------
-- editable variables
---------------------------------------------------------------------------------------------------
local vehLiTable = { leftEN ={}, rightEN ={}, left={},right={}, color ={}, isBlown={}, vehType={}, strOut={} }

local gLightTheta = math.rad(6) -- Theta is the inner cone angle (6)
local gLightPhi = math.rad(20) -- Phi is the outer cone angle (18)
local gLightFalloff = 1.5 -- light intensity attenuation between the phi and theta areas
local gLightAttenuation = 18 -- 15
local gLightAttenuationPower = 1.5
local flTimerUpdate = 200 -- the effect update time interval
local lightMaxDistance = 180

local excludeVehicleId = {441,464,501,465,564,571,594,606,607,610,611,584,608,450,591}

function getPositionFromElementOffset(element,offX,offY,offZ)
	local m = getElementMatrix ( element )  -- Get the matrix
	local x = offX * m[1][1] + offY * m[2][1] + offZ * m[3][1] + m[4][1]  -- Apply transform
	local y = offX * m[1][2] + offY * m[2][2] + offZ * m[3][2] + m[4][2]
	local z = offX * m[1][3] + offY * m[2][3] + offZ * m[3][3] + m[4][3]
	return x, y, z                               -- Return the transformed point
end

addEventHandler("onClientPreRender", root, function()
	for index,this in ipairs(getElementsByType("vehicle")) do
		if vehLiTable.leftEN[this] or vehLiTable.rightEN[this] then
			local rx, ry, rz = getElementRotation(this, "ZXY")
			rx = rx - 4
			local x1,y1,z1,x2,y2,z2
			local col = vehLiTable.color[this]
			local vehType = vehLiTable.vehType[this]
			local dumPos = {getVehicleModelDummyPosition(getElementModel(this), "light_front_main")}
			if vehType == "Bike" or vehType == "Quad" then
				x1,y1,z1 = getPositionFromElementOffset(this,dumPos[1],dumPos[2] - 0.5,dumPos[3]) -- (left,front,above)	0,0.8,0.1)		
			elseif vehType == "Train" then
				x1,y1,z1 = getPositionFromElementOffset(this,-dumPos[1],dumPos[2] - 0.5,dumPos[3]) -- (left,front,above) -0.7,5.0,-0.9
				x2,y2,z2 = getPositionFromElementOffset(this,dumPos[1],dumPos[2] - 0.5,dumPos[3]) -- (left,front,above) 0.7,5.0,-0.9)
			else
				x1,y1,z1 = getPositionFromElementOffset(this,-dumPos[1],dumPos[2] - 0.5,dumPos[3]) -- (left,front,above) -0.7,0.8,-0.1)
				x2,y2,z2 = getPositionFromElementOffset(this,dumPos[1],dumPos[2] - 0.5,dumPos[3]) -- (left,front,above) 0.7,0.8,-0.1)
			end
			
			if vehLiTable.leftEN[this] then
				exports.dl_lightmanager:setLightRotation(vehLiTable.left[this],rx,ry,rz,true)
				exports.dl_lightmanager:setLightPosition(vehLiTable.left[this],x1,y1,z1)
				exports.dl_lightmanager:setLightColor(vehLiTable.left[this],col[1],col[2],col[3],255) 
			end
			if vehLiTable.rightEN[this] and vehType~="Bike" and vehType~="Quad" then
				exports.dl_lightmanager:setLightRotation(vehLiTable.right[this],rx,ry,rz,true)
				exports.dl_lightmanager:setLightPosition(vehLiTable.right[this],x2,y2,z2)
				exports.dl_lightmanager:setLightColor(vehLiTable.right[this],col[1],col[2],col[3],255)  
			end
		end
	end
end
, true, "high+10")

function createWorldLight()
	local camX, camY, camZ = getCameraMatrix()
	local thisLight = exports.dl_lightmanager:createSpotLight(camX, camY, camZ,0,0,0,0,0,0,0,gLightFalloff,gLightTheta,gLightPhi,gLightAttenuation)
	exports.dl_lightmanager:setLightAttenuationPower(thisLight, gLightAttenuationPower)
	exports.dl_lightmanager:setLightDistFade(thisLight, lightMaxDistance, lightMaxDistance * 0.7)
	return thisLight
end

function destroyWorldLight(this)
	return exports.dl_lightmanager:destroyLight(this)
end

function lightEffectStop(thisVeh)
	if vehLiTable.leftEN[thisVeh] then
		destroyWorldLight(vehLiTable.left[thisVeh])
		vehLiTable.leftEN[thisVeh]=false
	end
	if vehLiTable.rightEN[thisVeh] then
		destroyWorldLight(vehLiTable.right[thisVeh])
		vehLiTable.rightEN[thisVeh]=false
	end
end

function lightEffectManage(thisVeh,vehType)
	if vehLiTable.isBlown[thisVeh] then return end
	local posX,posY,posZ = getElementPosition(thisVeh)
	local camX,camY,camZ = getCameraMatrix()
	local camDist = getDistanceBetweenPoints3D ( posX,posY,posZ,camX,camY,camZ )
	local lightSwitched = false
	local ispastDist = lightMaxDistance < camDist
	if ispastDist then
		if vehLiTable.leftEN[thisVeh] then
			destroyWorldLight(vehLiTable.left[thisVeh])
			vehLiTable.leftEN[thisVeh]=false		
		end
		if vehLiTable.rightEN[thisVeh] then
			destroyWorldLight(vehLiTable.right[thisVeh])
			vehLiTable.rightEN[thisVeh]=false			
		end
		return
	end
	if ((getVehicleLightState ( thisVeh, 0 )==1) or (areVehicleLightsOn(thisVeh)==false)) and vehLiTable.leftEN[thisVeh] then 
		destroyWorldLight(vehLiTable.left[thisVeh])
		vehLiTable.leftEN[thisVeh]=false		
	end

	if ((getVehicleLightState ( thisVeh, 1 )==1) or (areVehicleLightsOn(thisVeh)==false)) and vehLiTable.rightEN[thisVeh] then 
		destroyWorldLight(vehLiTable.right[thisVeh])
		vehLiTable.rightEN[thisVeh]=false	
	end	
	
	if getVehicleEngineState(thisVeh) then
		if (getVehicleLightState ( thisVeh, 0 )==0) then 
			if (areVehicleLightsOn(thisVeh)==true) then
				if vehLiTable.leftEN[thisVeh]~=true and (getVehicleOccupant( thisVeh ,0 ) or not vehLiTable.strOut[thisVeh]) then
					if not ispastDist then
						vehLiTable.left[thisVeh] = createWorldLight()
						vehLiTable.leftEN[thisVeh]=true
						lightSwitched=true
					end
				end
			else
				if vehLiTable.leftEN[thisVeh]==true then
					destroyWorldLight(vehLiTable.left[thisVeh])
					vehLiTable.leftEN[thisVeh]=false
				end
			end
		end
		
		if (getVehicleLightState ( thisVeh, 1 )==0 and vehType~="Bike")  then
			if (areVehicleLightsOn(thisVeh)==true) then 
				if vehLiTable.rightEN[thisVeh]~=true and (getVehicleOccupant( thisVeh ,0 ) or not vehLiTable.strOut[thisVeh]) then
					if not ispastDist then
						vehLiTable.right[thisVeh] = createWorldLight()
						vehLiTable.rightEN[thisVeh]=true
						lightSwitched=true
					end
				end
			else
				if vehLiTable.rightEN[thisVeh]==true then
					destroyWorldLight(vehLiTable.right[thisVeh])
					vehLiTable.rightEN[thisVeh]=false
				end
			end
		end
	end

	if (getVehicleLightState ( thisVeh, 0 )==0 and (areVehicleLightsOn(thisVeh)==true)) and vehLiTable.leftEN[thisVeh]~=true then
		if not ispastDist then
			vehLiTable.left[thisVeh] = createWorldLight()
			vehLiTable.leftEN[thisVeh]=true
		end
	end
	
	if (getVehicleLightState ( thisVeh, 1 )==0 and (areVehicleLightsOn(thisVeh)==true)) and vehLiTable.rightEN[thisVeh]~=true and vehType~="Bike" then
		if not ispastDist then
			vehLiTable.right[thisVeh] = createWorldLight()
			vehLiTable.rightEN[thisVeh]=true
		end
	end
	if lightSwitched then vehLiTable.strOut[thisVeh]=false end
	if vehLiTable.rightEN[thisVeh] or vehLiTable.leftEN[thisVeh] then
		local r,g,b = getVehicleHeadLightColor(thisVeh)
		vehLiTable.color[thisVeh] = {r,g,b}
	end
end

addEventHandler( "onClientElementStreamOut", getRootElement( ),function ()
	if getElementType( source ) == "vehicle" then
		vehLiTable.strOut[source] = true
	end
end
)

addEventHandler( "onClientElementStreamIn", getRootElement( ),function ()
	if getElementType( source ) == "vehicle" then
		--vehLiTable.strOut[source] = false
	end
end
)

addEventHandler("onClientResourceStart", getResourceRootElement( getThisResource()), function()
	if FLenTimer then return end
	local shTeNul = dxCreateShader ( "shaders/null.fx",0,0,false )
	engineApplyShaderToWorldTexture(shTeNul, "headlight*" )
	for index,thisVeh in ipairs(getElementsByType("vehicle")) do
		vehLiTable.isBlown[thisVeh] = isVehicleBlown(thisVeh)
		vehLiTable.strOut[thisVeh] = not isElementStreamedIn(thisVeh)
	end
	FLenTimer = setTimer(	function()
		for index,thisVeh in ipairs(getElementsByType("vehicle")) do
			if isElementStreamedIn(thisVeh) then
				local vehType = getVehicleType(thisVeh)
				local vehID = getElementModel(thisVeh)
				local isMatch = true
				for index,name in ipairs(excludeVehicleId) do
					if vehID==name then isMatch = false end
				end
				vehLiTable.vehType[thisVeh] = vehType
				if isMatch and ((vehType == "Automobile") or (vehType == "Monster Truck") or 
					(vehType == "Bike") or (vehType == "Quad") or (vehType == "Train")) then
					if isElementStreamedIn(thisVeh) then
						lightEffectManage(thisVeh,vehType)
					elseif not isElementStreamedIn(thisVeh) then
						lightEffectStop(thisVeh)
					end
				end
			end
		end
	end
	,flTimerUpdate,0 )
end
)

addEventHandler("onClientResourceStop", getResourceRootElement( getThisResource()), function()
	if not FLenTimer then return end
	killTimer(FLenTimer)
	for index,thisVeh in ipairs(getElementsByType("vehicle")) do
		lightEffectStop(thisVeh)
	end	
end
)

addEventHandler("onClientVehicleExplode", getRootElement(), function()
	if getElementType(source) == "vehicle"  then
		vehLiTable.isBlown[source] = true
		lightEffectStop(source)
	end
end
)

addEventHandler("onClientElementDestroy", getRootElement(), function ()
	if getElementType(source) == "vehicle"  then
		lightEffectStop(source)
	end
end
)
