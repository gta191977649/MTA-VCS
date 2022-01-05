--
-- c_main.lua
--

local enablePedVS = true
local emissiveSettings = {add = 0.1, mult = 2, cutoff = 0.08, power = 1.88, blur = 1.0, bloom = 1.5, scale = 0.5}

local scx, scy = guiGetScreenSize()
isFXSupported = (tonumber(dxGetStatus().VideoCardNumRenderTargets) > 1 and tonumber(dxGetStatus().VideoCardPSVersion) > 2 
	and tostring(dxGetStatus().DepthBufferFormat) ~= "unknown")
shaderTable = {}
shaderTable.RToutput = {}
shaderTable.RTinput = {}
	
---------------------------------------------------------------------------------------------------
-- shader lists
---------------------------------------------------------------------------------------------------
if enablePedVS then pedShader = "fx/RTinput_ped.fx" else pedShader = "fx/RTinput_ped_noVS.fx" end
shaderParams = { 
	SHWorldReplace = {"fx/RTinput_world_texReplace.fx", 5, 0, false, "world,object"}, 
	SHPedReplace = {"fx/RTinput_ped_texReplace.fx", 5, 0, false, "ped"}, 
	SHVehPaintReplace = {"fx/RTinput_car_paint_texReplace.fx", 5, 0, false, "vehicle"}, 
	SHWorld = {"fx/RTinput_world_vcs.fx", 0, 0, false, "world,object"},
	SHWorldNormal = {"fx/RTinput_world_normal.fx", 3, 0, false, "world,object"},
	SHWorldRefAnim = {"fx/RTinput_world_refAnim.fx", 1, 0, false, "world,object"}, 
	SHWorldEmissiveAdd = {"fx/RTinput_world_emissiveAdd.fx", 4, 0, false, "world,object"},
	SHWorldEmissive = {"fx/RTinput_world_emissive.fx", 4, 0, false, "world,object"},
	SHGrass = {"fx/RTinput_grass.fx", 0, 0, false, "world"},
	SHWorldNoZWrite = {"fx/RTinput_world_noZWrite.fx", 2, 0, false, "world,object,vehicle"},
	SHWaterWake = {"fx/RTinput_water_detail.fx", 3, 0, false, "world,object"},
	SHWaterDetail = {"fx/RTinput_water_detail.fx", 3, 0, false, "world,object"},
	SHWater = {"fx/RTinput_water.fx", 0, 0, false, "world,object"},
	SHVehPaint = {"fx/RTinput_car_paint.fx", 0, 0, false, "vehicle"},
	SHPedNormal = {"fx/RTinput_ped_normal.fx", 3, 0, false, "ped"},
	SHPed = {pedShader, 0, 0, false, "ped"}
				}

isDRShValid, isDRRtValid, isDREValid, isDREnabled, isDREEnabled = false,  false, false, false, false
		
----------------------------------------------------------------------------------------------------------------------------
-- onClientResourceStart/Stop
----------------------------------------------------------------------------------------------------------------------------
function switchDLOn()
	functionTable.enableCore()
	CPrmFixZ.create()
	setElementData(localPlayer, "dl_core.on", true, false)
end


function switchDLOff()
	functionTable.disableCore()
	CPrmFixZ.destroy()
	setElementData(localPlayer, "dl_core.on", false, false)
end

addEventHandler( "onClientPreRender", root,
    function()
		if not isDREnabled then return end
		CPrmFixZ.draw()
		dxSetRenderTarget(targetTable.RTColor, true)
		dxSetRenderTarget(targetTable.RTNormal, true)
		dxSetRenderTarget()
    end
, true, "high+20" )

addEventHandler( "onClientHUDRender", root,
    function()
		if not isDREEnabled then return end
		dxSetRenderTarget(targetTable.RTOut1, true)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHBrightPass) 
		dxSetRenderTarget(targetTable.RTOut2, true)
		dxSetShaderValue(shaderTable.RToutput.SHBlurH, "sTex0", targetTable.RTOut1)
		dxSetShaderValue(shaderTable.RToutput.SHBlurH, "sBlur", emissiveSettings.blur * 4)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHBlurH) 
		dxSetRenderTarget(targetTable.RTOut1, true)
		dxSetShaderValue(shaderTable.RToutput.SHBlurV, "sTex0", targetTable.RTOut2)
		dxSetShaderValue(shaderTable.RToutput.SHBlurV, "sBlur", emissiveSettings.blur * 4)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHBlurV)
		dxSetRenderTarget(targetTable.RTOut2, true)
		dxSetShaderValue(shaderTable.RToutput.SHBlurH, "sTex0", targetTable.RTOut1)
		dxSetShaderValue(shaderTable.RToutput.SHBlurH, "sBlur", emissiveSettings.blur)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHBlurH) 
		dxSetRenderTarget(targetTable.RTOut1, true)
		dxSetShaderValue(shaderTable.RToutput.SHBlurV, "sTex0", targetTable.RTOut2)
		dxSetShaderValue(shaderTable.RToutput.SHBlurV, "sBlur", emissiveSettings.blur)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHBlurV)
		dxSetRenderTarget(targetTable.RTOut2, true)
		dxSetShaderValue(shaderTable.RToutput.SHAddBlend, "sTex0", targetTable.RTOut1)
		dxDrawImage(0, 0, scx * emissiveSettings.scale, scy * emissiveSettings.scale, shaderTable.RToutput.SHAddBlend)
		dxSetRenderTarget()
		dxDrawImage(0, 0, scx , scy, shaderTable.RToutput.SHAddBlend, 0, 0, 0, tocolor(204,153,130,190))
		dxSetBlendMode()
    end
, true, "high+1" )

---------------------------------------------------------------------------------------------------
-- manage render targets
---------------------------------------------------------------------------------------------------
functionTable = {}

function functionTable.enableCore()
	if isDREnabled then return end
	if functionTable.createWorldShaders() and functionTable.createRenderTargets() then
		for i, thisPart in pairs(shaderTable.RTinput) do
			functionTable.applyRTToTextureShader(thisPart)
		end

		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHWorld, "*")
		functionTable.removeShaderFromList(shaderTable.RTinput.SHWorld, textureListTable.RemoveList)
		functionTable.removeShaderFromList(shaderTable.RTinput.SHWorld, textureListTable.ZDisable)
		functionTable.applyShaderToList(shaderTable.RTinput.SHWorld, textureListTable.ApplyList)
		engineRemoveShaderFromWorldTexture(shaderTable.RTinput.SHWorld, "unnamed")
		
		functionTable.applyShaderToList(shaderTable.RTinput.SHWorldRefAnim, textureListTable.ApplySpecial)
		functionTable.applyShaderToList(shaderTable.RTinput.SHWorldNoZWrite, textureListTable.ZDisableApply)
		dxSetShaderValue(shaderTable.RTinput.SHWorldNoZWrite, "sWorldZBias", 0.005)		

	
		functionTable.applyShaderToList(shaderTable.RTinput.SHVehPaint, textureListTable.TextureGrun)		
		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHVehPaint, "vehiclegeneric256")
		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHVehPaint, "*")
		engineRemoveShaderFromWorldTexture(shaderTable.RTinput.SHVehPaint, "unnamed")


		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHPed, "*")	
		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHGrass, "tx*")
		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHWater, "water*")
		engineRemoveShaderFromWorldTexture(shaderTable.RTinput.SHWater, "waterwake")

		engineApplyShaderToWorldTexture(shaderTable.RTinput.SHWaterWake, "waterwake")
		dxSetShaderValue(shaderTable.RTinput.SHWaterWake, "sWorldZBias", 0.45)
		
		functionTable.applyShaderToList(shaderTable.RTinput.SHWaterDetail, textureListTable.Detail)
		dxSetShaderValue(shaderTable.RTinput.SHWaterDetail, "sWorldZBias", 0.01)
		
		isDREnabled = true

		local f = fileOpen("txd_exclude.txt")
		local lines = fileRead(f, fileGetSize(f))
		lines = split(lines,"\n")
		for k,txd in ipairs(lines) do 
			txd = string.gsub(txd,"\r","")
			engineRemoveShaderFromWorldTexture(shaderTable.RTinput.SHWorld, txd)
		end
		fileClose(f)
	end
end


function functionTable.disableCore()
	if isDREnabled then
		local isDisabled = not functionTable.destroyWorldShaders()
		isDREnabled = not isDisabled
	end
end

addEventHandler( "onClientResourceStop", resourceRoot, function()
	functionTable.destroyRenderTargets()
end)


function functionTable.createWorldShaders()
	if not isDRShValid then
		shaderTable.RTinput = {}
		shaderTable.RTinput.SHWorld = dxCreateShader(unpack(shaderParams.SHWorld))
		shaderTable.RTinput.SHWorldRefAnim = dxCreateShader(unpack(shaderParams.SHWorldRefAnim))
		shaderTable.RTinput.SHGrass = dxCreateShader(unpack(shaderParams.SHGrass))
		shaderTable.RTinput.SHWorldNoZWrite = dxCreateShader(unpack(shaderParams.SHWorldNoZWrite))
		shaderTable.RTinput.SHWaterWake = dxCreateShader(unpack(shaderParams.SHWaterWake))
		shaderTable.RTinput.SHWaterDetail = dxCreateShader(unpack(shaderParams.SHWaterDetail))
		shaderTable.RTinput.SHWater = dxCreateShader(unpack(shaderParams.SHWater))
		shaderTable.RTinput.SHPed = dxCreateShader(unpack(shaderParams.SHPed))
		shaderTable.RTinput.SHVehPaint = dxCreateShader(unpack(shaderParams.SHVehPaint))

		isDRShValid = true
			
			for i,thisPart in pairs(shaderTable.RTinput) do
				isDRShValid = thisPart and isDRShValid
			end
	end
	return isDRShValid
end

function functionTable.destroyWorldShaders()
	if isDRShValid then
		for _,thisPart in pairs(shaderTable.RTinput) do
			engineRemoveShaderFromWorldTexture(thisPart, "*")
			destroyElement(thisPart)
			thisPart = nil
		end
		isDRShValid = false 
		return true
	end
	return false
end

targetTable = {}
function functionTable.createRenderTargets()
	if not isDRRtValid then
		targetTable.RTColor = dxCreateRenderTarget( scx , scy, false )
		targetTable.RTNormal = dxCreateRenderTarget( scx , scy, false )
		targetTable.RTOut1 = dxCreateRenderTarget( scx * emissiveSettings.scale , scy * emissiveSettings.scale , true )
		targetTable.RTOut2 = dxCreateRenderTarget( scx * emissiveSettings.scale , scy * emissiveSettings.scale , true )
		isDRRtValid = true
		for _,thisPart in pairs(targetTable) do
			isDRRtValid = thisPart and isDRRtValid
		end
	end
	return isDRRtValid
end

function functionTable.disableNormals(isDisableNormals)
	if shaderTable.RTinput.SHWorld and shaderTable.RTinput.SHWorldNoZWrite and shaderTable.RTinput.SHWorldRefAnim then
		dxSetShaderValue( shaderTable.RTinput.SHWorld, "sDisableNormals", isDisableNormals )
		dxSetShaderValue( shaderTable.RTinput.SHWorldRefAnim, "sDisableNormals", isDisableNormals )
		dxSetShaderValue( shaderTable.RTinput.SHWorldNoZWrite, "sDisableNormals", isDisableNormals )
		return true
	end
	return false
end

function functionTable.destroyRenderTargets()
	if isDRRtValid then
		for _,thisPart in pairs(targetTable) do
			destroyElement(thisPart)
			thisPart = nil
		end
		isDRRtValid = false 
		return false
	end
	return false
end

function functionTable.createEmissivePostEffect()
	if isDREEnabled then
		return true
	end
	if not isDREValid then
		shaderTable.RToutput.SHBlurH = dxCreateShader( "fx/RTOutput_blurH.fx" )
		shaderTable.RToutput.SHBlurV = dxCreateShader( "fx/RTOutput_blurV.fx" )
		shaderTable.RToutput.SHBrightPass = dxCreateShader( "fx/RTOutput_brightPass.fx" )
		shaderTable.RToutput.SHAddBlend = dxCreateShader( "fx/RTOutput_addBlend.fx" )
	end
	isDREValid = true
			
	for i,thisPart in pairs(shaderTable.RToutput) do
		isDREValid = thisPart and isDREValid
	end
	isDREEnabled = isDREValid and isDRRtValid and functionTable.applyRTToTextureShader(shaderTable.RToutput.SHBrightPass)
	if isDREEnabled then
		dxSetShaderValue( shaderTable.RToutput.SHBrightPass, "sPower", emissiveSettings.power )
		dxSetShaderValue( shaderTable.RToutput.SHBrightPass, "sCutoff", emissiveSettings.cutoff )
		dxSetShaderValue( shaderTable.RToutput.SHBrightPass, "sPower", emissiveSettings.power )	
		dxSetShaderValue( shaderTable.RToutput.SHBrightPass, "sAdd", emissiveSettings.add )	
		dxSetShaderValue( shaderTable.RToutput.SHBrightPass, "sMult", emissiveSettings.mult )
		dxSetShaderValue( shaderTable.RToutput.SHBlurH, "sTex0Size", scx * emissiveSettings.scale, scy * emissiveSettings.scale )
		dxSetShaderValue( shaderTable.RToutput.SHBlurH, "sBloom", emissiveSettings.bloom )
		dxSetShaderValue( shaderTable.RToutput.SHBlurH, "sBlur", emissiveSettings.blur )
		dxSetShaderValue( shaderTable.RToutput.SHBlurV, "sTex0Size", scx * emissiveSettings.scale, scy * emissiveSettings.scale )
		dxSetShaderValue( shaderTable.RToutput.SHBlurV, "sBloom", emissiveSettings.bloom )
		dxSetShaderValue( shaderTable.RToutput.SHBlurV, "sBlur", emissiveSettings.blur )		
	end
	return isDREEnabled
end

function functionTable.destroyEmissivePostEffect()
	if isDREValid then
		for _,thisPart in pairs(shaderTable.RToutput) do
			destroyElement(thisPart)
			thisPart = nil
		end
		isDREValid = false 
		isDREEnabled = false
		return false
	end
	return false
end

function functionTable.applyRTToTextureShader(myShader)
	if myShader and isDRRtValid then
		dxSetShaderValue( myShader, "ColorRT", targetTable.RTColor )
		dxSetShaderValue( myShader, "NormalRT", targetTable.RTNormal )
		return true
	else
		return false
	end
end

function functionTable.applyShaderToList(myShader, myList)
	for _,applyMatch in ipairs(myList) do
		engineApplyShaderToWorldTexture(myShader, applyMatch)	
	end
end

function functionTable.removeShaderFromList(myShader, myList)
	for _,removeMatch in ipairs(myList) do
		engineRemoveShaderFromWorldTexture(myShader, removeMatch)	
	end
end


