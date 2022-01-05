--
-- c_main.lua
--

lightFuncTable = {}
lightTable = { inputLights = {}, entity = {}, isInNrChanged = false, thisLight = 0 }

lightEntity = {}
lightEntity[1] = { start = function() return dxCreateShader( "fx/primitive3D_pointLight.fx" ) end }
lightEntity[2] = { start = function() return dxCreateShader( "fx/primitive3D_spotLight.fx" ) end }
lightEntity[3] = { start = function() return dxCreateShader( "fx/primitive3D_pointLight_normalGen.fx" ) end }
lightEntity[4] = { start = function() return dxCreateShader( "fx/primitive3D_spotLight_normalGen.fx" ) end }

local scx, scy = guiGetScreenSize()

---------------------------------------------------------------------------------------------------
-- main light functions
---------------------------------------------------------------------------------------------------
function lightFuncTable.create(lType,posX,posY,posZ,colorR,colorG,colorB,colorA,dirX,dirY,dirZ,falloff,theta,phi,attenuation,genNormals,skipNormals,dimension,interior)
	local w = findEmptyEntry(lightTable.inputLights)
	if not lightTable.inputLights[w] then lightTable.inputLights[w] = {} end
	if not lightTable.entity[w] then lightTable.entity[w] = {} end
	local lightType = lType;
	if genNormals then lightType = lType + 2
	lightTable.entity[w] = lightEntity[lightType].start()
		else lightTable.entity[w] = lightEntity[lType].start()
	end
	
	if renderTarget.isOn then 
		dxSetShaderValue(lightTable.entity[w], "ColorRT", renderTarget.RTColor )
		dxSetShaderValue(lightTable.entity[w], "NormalRT", renderTarget.RTNormal )
	end
	dxSetShaderValue(lightTable.entity[w], "sPixelSize", 1 / scx, 1 / scy )
	dxSetShaderValue(lightTable.entity[w], "sHalfPixel", 1/(scx * 2), 1/(scy * 2) )
			
	dxSetShaderValue(lightTable.entity[w], "sLightPosition", posX,posY,posZ)
	dxSetShaderValue(lightTable.entity[w], "sLightAttenuation", attenuation)
	dxSetShaderValue(lightTable.entity[w], "sLightColor", colorR / 255,colorG / 255,colorB / 255,colorA / 255)
	dxSetShaderValue(lightTable.entity[w], "sLightAttenuationPower", 1)	

	lightTable.inputLights[w].enabled = true
	lightTable.inputLights[w].tickCount = 0
	lightTable.inputLights[w].id = w
	lightTable.inputLights[w].lType = lightType
	lightTable.inputLights[w].pos = {posX,posY,posZ}
	lightTable.inputLights[w].color = {colorR,colorG,colorB,colorA}	
	lightTable.inputLights[w].lightBlend = 1
	lightTable.inputLights[w].attenuation = attenuation
	lightTable.inputLights[w].attenuationPower = 1
	lightTable.inputLights[w].skipNormals = skipNormals 
	lightTable.inputLights[w].dimension = dimension
	lightTable.inputLights[w].interior = interior
	lightTable.inputLights[w].distFade = {5000, 4900}
	
	dxSetShaderValue(lightTable.entity[w], "gDistFade", 5000, 4900)
	dxSetShaderValue(lightTable.entity[w], "gUseNormals", not skipNormals)

	if ((lightType == 2) or (lightType == 4)) then 
		lightTable.inputLights[w].dir = {dirX,dirY,dirZ}
		lightTable.inputLights[w].falloff = falloff
		lightTable.inputLights[w].theta = theta
		lightTable.inputLights[w].phi = phi

		dxSetShaderValue(lightTable.entity[w], "sLightDir", dirX,dirY,dirZ )
		dxSetShaderValue(lightTable.entity[w], "sLightPhi", phi )
		dxSetShaderValue(lightTable.entity[w], "sLightTheta", theta )
		dxSetShaderValue(lightTable.entity[w], "sLightFalloff", falloff )
	end
	
	local distFromCam = ( Vector3(posX,posY,posZ) - getCamera().matrix.position ).length
	if ( distFromCam < 8 * attenuation ) then 
		if ((lightType == 2) or (lightType == 4)) then
			lightTable.inputLights[w].trianglelist = trianglelist.cone
		else
			lightTable.inputLights[w].trianglelist = trianglelist.sphere		
		end
		dxSetShaderValue(lightTable.entity[w], "sLightBillboard", false )
		lightTable.inputLights[w].tessSwitch = true
	else
		lightTable.inputLights[w].trianglelist = trianglelist.plane
		dxSetShaderValue(lightTable.entity[w], "sLightBillboard",  true )
		lightTable.inputLights[w].tessSwitch = false
	end
	
	
	------outputDebugString('Created Light TYPE: '..lightType..' ID:'..w)
	lightTable.isInNrChanged = true
	return w
end

function lightFuncTable.destroy(w)
	if lightTable.inputLights[w] then
		lightTable.inputLights[w].enabled = false
		lightTable.isInNrChanged = true
		destroyElement(lightTable.entity[w])
		----outputDebugString('Destroyed Light ID:'..w)
		return true
	else
		----outputDebugString('Have Not Destroyed Light ID:'..w)
		return false 
	end
end

---------------------------------------------------------------------------------------------------
-- draw lights
---------------------------------------------------------------------------------------------------
local thisPos, distFromCam

addEventHandler("onClientRender", root, function()
	if #lightTable.inputLights == 0 then return end
	lightTable.thisLight = 0
	
	
for index,this in ipairs(lightTable.inputLights) do
	if this.enabled then
		thisPos = Vector3(unpack(this.pos))
		if isEntityInFrontalSphere(thisPos, this.attenuation) then
			lightTable.inputLights[this.id].tickCount = this.tickCount + lastFrameTickCount + math.random(500)
			if this.tickCount > LODSwitchDelta then            
				distFromCam = ( thisPos - localCamera.pos ).length
				if ( distFromCam < 8 * this.attenuation ) then 
					if not lightTable.inputLights[this.id].tessSwitch then
						if ((lightTable.inputLights[this.id].lType == 2) or (lightTable.inputLights[this.id].lType == 4)) then
							lightTable.inputLights[this.id].trianglelist = trianglelist.cone
						else
							lightTable.inputLights[this.id].trianglelist = trianglelist.sphere
						end
						dxSetShaderValue(lightTable.entity[this.id], "sLightBillboard", false )
						lightTable.inputLights[this.id].tessSwitch = true
					end
				else
					if lightTable.inputLights[this.id].tessSwitch then
						lightTable.inputLights[this.id].trianglelist = trianglelist.plane
						dxSetShaderValue(lightTable.entity[this.id], "sLightBillboard", true )
						lightTable.inputLights[this.id].tessSwitch = false
					end
				end					

				lightTable.inputLights[this.id].tickCount = 0
			end
			-- draw the outcome
			lightTable.thisLight = lightTable.thisLight + 1
			dxDrawMaterialPrimitive3D( "trianglelist", lightTable.entity[this.id], false, unpack( this.trianglelist ) )		
		end
	end
end

end
,true ,"high+5")

---------------------------------------------------------------------------------------------------
-- debug
---------------------------------------------------------------------------------------------------
local lightDebugSwitch = false

addCommandHandler( "debuglights",
function()
	if isDebugViewActive() then 
		lightDebugSwitch = switchDebugLights(not lightDebugSwitch)
	end
end
)

function switchDebugLights(switch)
	if switch then
		addEventHandler("onClientRender", root, renderDebugLights)
	else
		----outputDebugString('LightDebug mode: OFF')
		removeEventHandler("onClientRender", root, renderDebugLights)
	end
	return switch
end

local scx, scy = guiGetScreenSize()
local vcRam, vcRenTar = dxGetStatus().VideoCardRAM, dxGetStatus().VideoMemoryUsedByRenderTargets 
function renderDebugLights()
	if renderTarget.isOn then
		if renderTarget.RTColor then
			dxDrawImage(0, 0, scx/4, scy/4, renderTarget.RTColor, 0, 0, 0, tocolor(255,255,255,255))
			dxDrawImage(scx/4, 0, scx/4, scy/4, renderTarget.RTNormal, 0, 0, 0, tocolor(255,255,255,255))
			--dxDrawImage(0, 0, scx, scy, renderTarget.RTNormal, 0, 0, 0, tocolor(255,255,255,255))
		end
	end
    dxDrawText ("Light sources: "..lightTable.thisLight, 4, scy * 0.5 - 100)
    dxDrawText ("Is dl_core on: "..tostring(renderTarget.isOn), 4, scy * 0.5 - 85)	
    dxDrawText ("VideoCardRAM: "..vcRam.." MB VideoMemoryFreeForMTA: "..dxGetStatus().VideoMemoryFreeForMTA.." MB", 4, scy * 0.5 - 70)
    dxDrawText ("VideoMemoryUsedByRenderTargets: "..vcRenTar.." MB FramesPerSecond: "..math.floor(currentFPS), 4, scy * 0.5 - 55)
	
	if lightTable.thisLight == 0 then return end
	local camPos = getCamera().position
	local farClip = getFarClipDistance()
	for index,this in ipairs(lightTable.inputLights) do
		if this.enabled then
			local dPos = Vector3(this.pos[1] - camPos.x, this.pos[2] - camPos.y, this.pos[3] - camPos.z)
			if (dPos.length < ( math.min(80, farClip + this.attenuation))) then
				local scPosX, scPosY  = getScreenFromWorldPosition(this.pos[1], this.pos[2], this.pos[3])
				if scPosX and scPosY then
					dxDrawText ("Light TYPE: "..this.lType.." ID: "..this.id, scPosX, scPosY, 0, 0, tocolor(0,0,0))
					dxDrawText ("Light TYPE: "..this.lType.." ID: "..this.id, scPosX + 1, scPosY + 1, 0, 0, tocolor(this.color[1],this.color[2],this.color[3]))
					if ((this.lType == 2) or (this.lType == 4)) then
						dxDrawLine3D(this.pos[1], this.pos[2], this.pos[3], this.pos[1] + this.dir[1], this.pos[2] + this.dir[2], this.pos[3] + this.dir[3] , tocolor(this.color[1],this.color[2], this.color[3]), 1.0, true)
					end
				end
			end
		end
	end
end
 