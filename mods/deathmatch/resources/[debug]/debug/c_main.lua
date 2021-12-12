--
-- c_main.lua
--
local orderPriority = "-2.7"	-- The lower this number, the later the effect is applied
local scx, scy = guiGetScreenSize()
Settings = {}
Settings.var = {}

local shaders = {
	{ file ="blobs.fx", mouse = false, sm = 3 },
	{ file ="blobsMod.fx", mouse = false, sm = 3 },
	{ file ="colCircle.fx", mouse = false, sm = 3 },
	{ file ="colDonut.fx", mouse = false, sm = 3 },
	{ file ="colFractals.fx", mouse = true, sm = 3 },
	{ file ="colNeckl.fx", mouse = true, sm = 3 },
	{ file ="colorDrops.fx", mouse = true, sm = 3 },
	{ file ="coolWaves.fx", mouse = false, sm = 2 },
	{ file ="energyField.fx", mouse = false, sm = 3 },
	{ file ="grayWaves.fx", mouse = false, sm = 2 },
	{ file ="greenCircle.fx", mouse = false, sm = 3 },
	{ file ="gridWalk.fx", mouse = false, sm = 2 },
	{ file ="hypnoCircles.fx", mouse = false, sm = 2 },
	{ file ="hypnoWheel.fx", mouse = false, sm = 2 },
	{ file ="merryXMass.fx", mouse = false, sm = 3 },
	{ file ="mixPaint.fx", mouse = true, sm = 3 },
	{ file ="mouseVioletCircle.fx", mouse = true, sm = 3 },
	{ file ="noise.fx", mouse = false, sm = 2 },
	{ file ="purpleSine.fx", mouse = false, sm = 2 },
	{ file ="redFlower.fx", mouse = true, sm = 3 },
	{ file ="redPlanet.fx", mouse = false, sm = 3 },
	{ file ="screenFlare.fx", mouse = true, sm = 3 },
	{ file ="sineColors.fx", mouse = false, sm = 3 },
	{ file ="sineWeb.fx", mouse = false, sm = 3 },
	{ file ="spin.fx", mouse = false, sm = 3 },
	{ file ="spinNeckl.fx", mouse = false, sm = 3 },
	{ file ="spinx.fx", mouse = true, sm = 3 },
	{ file ="starTravel.fx", mouse = false, sm = 3 },
	{ file ="tunnel.fx", mouse = false, sm = 3 },
	{ file ="verticalStrobes.fx", mouse = false, sm = 3 },
	{ file ="violetExplosion.fx", mouse = false, sm = 3 },
	{ file ="warpedSiveWave.fx", mouse = false, sm = 2 },
	{ file ="weirdFlower.fx", mouse = false, sm = 2 },
	{ file ="whiteCircles.fx", mouse = false, sm = 2 }
				}
---------------------------------
-- shader model version
---------------------------------
function vCardPSVer()
	local smVersion = tostring(dxGetStatus().VideoCardPSVersion)
	return smVersion
end

---------------------------------
-- DepthBuffer access
---------------------------------
function isDepthBufferAccessible()
	local depthStatus = tostring(dxGetStatus().DepthBufferFormat)
	outputDebugString("DepthBufferFormat: "..depthStatus)
	if depthStatus=='unknown' then depthStatus=false end
	return depthStatus
end

----------------------------------------------------------------
-- enableShaders
----------------------------------------------------------------
function enableShaders(fxnr)
	if bEffectEnabled then return end
	-- Create things
	myScreenSource = dxCreateScreenSource( scx, scy )
	
	effectNo = fxnr
	thisShader, tecName = dxCreateShader( "fx/"..shaders[fxnr].file )
	outputDebugString( tostring(shaders[fxnr].file).." is using technique "..tostring(tecName) )
	
	-- Get list of all elements used
	effectParts = {
						myScreenSource,
						thisShader,
					}

	-- Check list of all elements used
	bAllValid = true
	for _,part in ipairs(effectParts) do
		bAllValid = part and bAllValid
	end

	bEffectEnabled = true
	
	if not bAllValid then
		outputChatBox( "GLSLSandbox_pack: Could not create some things. Please use debugscript 3" )
		disableShaders()
	else
		if shaders[fxnr].mouse == true then showCursor(true) end	
	end
end

----------------------------------------------------------------
-- disableShaders
----------------------------------------------------------------
function disableShaders()
	if not bEffectEnabled then return end
	
	if isCursorShowing() then showCursor(false) end
	
	-- Destroy all shaders
	for _,part in ipairs(effectParts) do
		if part then
			destroyElement( part )
		end
	end
	effectParts = {}

	bAllValid = false
	
	-- Flag effect as stopped
	bEffectEnabled = false
end

-----------------------------------------------------------------------------------
-- onClientRender
-----------------------------------------------------------------------------------
local scaleXY = 0.5
addEventHandler( "onClientRender", root, function()
	if not bAllValid then return end
	-- Update screen
	dxUpdateScreenSource(myScreenSource, true)
	-- Start with screen
	dxSetShaderValue(thisShader, "sTexColor", myScreenSource)
	dxSetShaderValue(thisShader, "sTexSize", scx, scy)
	if isCursorShowing() then
		local cpX,cpY = getCursorPosition()
		dxSetShaderValue(thisShader, "sMouse", cpX, cpY)
	end
	dxSetShaderValue(thisShader, "sScale", scaleXY, scaleXY)
	if thisShader then 
		dxDrawImage(0, 0, scx, scy, thisShader, 0, 0, 0, tocolor(255,255,255,255))
		dxDrawText ("Effect: "..shaders[effectNo].file.." Effect nr: "..tostring(effectNo).." PS required: "..tostring(shaders[effectNo].sm)..
			" Mouse use: "..tostring(shaders[effectNo].mouse).." Scale: "..tostring(scaleXY), 0, scy - 15)	
	end
end
)

--------------------------------
-- Control the effect
--------------------------------
bindKey ( "mouse_wheel_up", "down", function( key, keyState )
	if not bAllValid then return end
	if ( keyState == "down" ) then
		scaleXY = scaleXY + 0.05
	end
end
)

bindKey ( "mouse_wheel_down", "down", function( key, keyState )
	if not bAllValid then return end
	if ( keyState == "down" ) then
		scaleXY = scaleXY - 0.05
	end
end
)

addEventHandler("onClientRender", root, function()
	if not bAllValid then return end
	if getKeyState("lalt") then
		if not isCursorShowing() then showCursor(true) end
		local cpX,cpY = getCursorPosition()
		dxSetShaderValue(thisShader, "sCenter", cpX, cpY)
	else
		if not shaders[effectNo].mouse then
			showCursor(false)
		end
	end
end
)

--------------------------------
-- Switching the effects
--------------------------------
local efxNr = 0
addEventHandler( "onClientResourceStart", getResourceRootElement( getThisResource()), function()
	if (vCardPSVer()~="3") then 
		outputChatBox('GLSLSandbox_pack: Shader Model 3 not supported',255,0,0)
		outputChatBox('GLSLSandbox_pack: Limited set of effects available',255,0,0)
		return 
	end
	outputDebugString("VideoCardPSVersion: "..vCardPSVer())
	outputChatBox("GLSLSandbox_pack: Hit '=' and '-' to browse effects, mouse scroll to zoom in and out, left_alt to change position")
	bindKey ( "-", "down", function( key, keyState )
		if ( keyState == "down" ) then
			efxNr = efxNr - 1
			if efxNr > 0 then
				switchShaderExamples(efxNr)
			else
				efxNr = 1
			end
		end
	end)	
  
	bindKey ( "=", "down", function( key, keyState )
		if ( keyState == "down" ) then
			efxNr = efxNr + 1
			if efxNr <= #shaders then
				switchShaderExamples(efxNr)
			else
				efxNr = #shaders
			end
		end
	end)  
end
)

function switchShaderExamples( fxnr )
	if bEffectEnabled then disableShaders() end
	if fxnr > 0 then
		enableShaders(fxnr)
	else
		disableShaders()
	end
end
