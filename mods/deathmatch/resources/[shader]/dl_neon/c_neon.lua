--
-- c_meme.lua
--

local neonTable = {gui = {}, func = {}, image = {fileList = {}, name = nil, color = nil, isSet = false}, 
					render = {shader = {}, settings = {}, texture = {}}, isResourceLoaded = false, isGuiVisible = false}
local scx, scy = guiGetScreenSize()
renderTarget = {RTColor = nil, RTNormal = nil, isOn = false}
local shaderPath = nil

------------------------------------------------------------------------------------------------------------
-- Settings
------------------------------------------------------------------------------------------------------------
local toggleKey = "F4"
local toggleCmd = "neon"
local emissiveEffectEnabled = true

------------------------------------------------------------------------------------------------------------
-- Menu
------------------------------------------------------------------------------------------------------------
function neonTable.func.createGuiBox()
	local windowWidth, windowHeight = 432, 302
	local left = scx / 10 
	local top = scy / 10
	neonTable.gui.root = guiCreateWindow(left, top, windowWidth, windowHeight, "Neon v0.1 by Ren712", false)
	guiWindowSetSizable(neonTable.gui.root, false)
	
    neonTable.gui.name = guiCreateLabel(220, 170, 201, 21, "No image chosen.", false, neonTable.gui.root)
	guiLabelSetHorizontalAlign(neonTable.gui.name, "center", false)
	guiLabelSetVerticalAlign(neonTable.gui.name, "center")
	
	neonTable.gui.imageList = guiCreateGridList(10, 26, 201, 257, false, neonTable.gui.root)				
	if neonTable.func.imageList then
		addEventHandler("onClientGUIClick", neonTable.gui.imageList, neonTable.func.imageList, false)
	end
	
	guiSetText(neonTable.gui.name, "No image chosen.")

	neonTable.gui.toggleColor = guiCreateButton(220, 195, 101, 21, "Color", false, neonTable.gui.root)
	if neonTable.func.toggleColor then
		addEventHandler("onClientGUIClick", neonTable.gui.toggleColor, neonTable.func.toggleColor, false)
	end
	
	neonTable.gui.apply = guiCreateButton(220, 215, 101, 21, "Apply", false, neonTable.gui.root)
	if neonTable.func.apply then
		addEventHandler("onClientGUIClick", neonTable.gui.apply, neonTable.func.apply, false)
	end
	
	neonTable.gui.close = guiCreateButton(320, 215, 101, 21, "Close", false, neonTable.gui.root)
	if neonTable.func.close then
		addEventHandler("onClientGUIClick", neonTable.gui.close, neonTable.func.close, false)
	end
	
	neonTable.gui.scrollX =  guiCreateScrollBar(290,239,130,21,true, false, neonTable.gui.root)
	guiScrollBarSetScrollPosition ( neonTable.gui.scrollX, 50 )
	neonTable.gui.scrollXLabel = guiCreateLabel(220, 239, 101, 21, "SizeX: 0.5", false, neonTable.gui.root)
	if neonTable.func.scrollX then
		addEventHandler("onClientGUIScroll", neonTable.gui.scrollX, neonTable.func.scrollX, false)
	end	
	
	neonTable.gui.scrollY =  guiCreateScrollBar(290,263,130,21,true, false, neonTable.gui.root)
	guiScrollBarSetScrollPosition ( neonTable.gui.scrollY, 50 )
	neonTable.gui.scrollYLabel = guiCreateLabel(220, 263, 101, 21, "SizeY: 0.5", false, neonTable.gui.root)
	if neonTable.func.scrollY then
		addEventHandler("onClientGUIScroll", neonTable.gui.scrollY, neonTable.func.scrollY, false)
	end	
	
	neonTable.gui.clear = guiCreateButton(320, 195, 101, 21, "Clear", false, neonTable.gui.root)
	if neonTable.func.clear then
		addEventHandler("onClientGUIClick", neonTable.gui.clear, neonTable.func.clear, false)
	end
end

function neonTable.func.toggleMeme()
	if neonTable.isGuiVisible then 
		colorPicker.closeSelect()
		showCursor(false)
		neonTable.isGuiVisible = false
		guiSetVisible(neonTable.gui.root, false)
		return 
	else
		showCursor(true)
		neonTable.isGuiVisible = true
		guiSetVisible(neonTable.gui.root, true)
	end
end

------------------------------------------------------------------------------------------------------------
-- Menu buttons
------------------------------------------------------------------------------------------------------------
function neonTable.func.imageList()
	local chosenListItem = guiGridListGetSelectedItem (neonTable.gui.imageList)
	local chosenListText = guiGridListGetItemText (neonTable.gui.imageList, chosenListItem, 1)
	if chosenListText == "" then 
		local chosenID = getElementData(localPlayer, 'neonTexture')
		local chosenColor = getElementData(localPlayer, 'neonColor')
		local chosenSize = getElementData(localPlayer, 'neonSize')
		if not chosenName or not chosenColor or not chosenSize then 
			return false
		end
		neonTable.image.name = neonTable.image.fileList[chosenID]
		neonTable.image.id = chosenID
		neonTable.image.color = chosenColor 
		neonTable.image.size = chosenSize
		guiSetText(neonTable.gui.scrollXLabel, "SizeX: "..neonTable.image.size[1])
		guiSetText(neonTable.gui.scrollYLabel, "SizeY: "..neonTable.image.size[2])
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollX, math.abs(neonTable.image.size[1] * 100) )
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollY, math.abs(neonTable.image.size[2] * 100) )
		guiSetText(neonTable.gui.name, neonTable.image.name)
		guiGridListSetSelectedItem(neonTable.gui.imageList, tonumber(neonTable.image.id) - 1 ,  1)
	else
		local chosenColor = getElementData(localPlayer, 'neonColor')
		local chosenSize = getElementData(localPlayer, 'neonSize')
		neonTable.image.name = neonTable.image.fileList[chosenListItem + 1]
		neonTable.image.id = chosenListItem + 1
		neonTable.image.color = chosenColor or {255, 255, 255, 255}
		neonTable.image.size = chosenSize or {0.5, 0.5}
		neonTable.image.isSet = false
		guiSetText(neonTable.gui.scrollXLabel, "SizeX: "..neonTable.image.size[1])
		guiSetText(neonTable.gui.scrollYLabel, "SizeY: "..neonTable.image.size[2])
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollX, math.abs(neonTable.image.size[1] * 100) )
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollY, math.abs(neonTable.image.size[2] * 100) )
		guiSetText (neonTable.gui.name, neonTable.image.name)
	end
end

function neonTable.func.toggleColor(button, state, absoluteX, absoluteY)
	if (button ~= "left") or (state ~= "up") then
		return
	end
	colorPicker.openSelect()
end

function neonTable.func.scrollX(scrolled)
	if not neonTable.isGuiVisible then return end
	local scrollPosition = guiScrollBarGetScrollPosition(scrolled)
	if not neonTable.image.size then neonTable.image.size = {0.5, 0.5} return end
	neonTable.image.size[1] = scrollPosition / 100
	guiSetText(neonTable.gui.scrollXLabel, "SizeX: "..neonTable.image.size[1])
end

function neonTable.func.scrollY(scrolled)
	if not neonTable.isGuiVisible then return end
	local scrollPosition = guiScrollBarGetScrollPosition(scrolled)
	if not neonTable.image.size then neonTable.image.size = {0.5, 0.5} return end
	neonTable.image.size[2] = scrollPosition / 100
	guiSetText(neonTable.gui.scrollYLabel, "SizeY: "..neonTable.image.size[2])
end

function closedColorPicker (chR, chG, chB, chA)
	neonTable.image.color = {chR, chG, chB, chA}
end

local getLastTick = getTickCount()
function neonTable.func.apply(button, state, absoluteX, absoluteY)
	if (button ~= "left") or (state ~= "up") then
		return
	end
	if (getTickCount() - getLastTick < 500) then 
		outputChatBox("Meme: Don't spam the apply button.")
		return 
	end
	if not neonTable.image.name or not neonTable.image.color or not neonTable.image.id or not neonTable.image.size then 
		return 
	end
	setElementData(localPlayer, 'neonTexture', neonTable.image.id, true)
	setElementData(localPlayer, 'neonColor', neonTable.image.color, true)
	setElementData(localPlayer, 'neonSize', neonTable.image.size, true) 
	neonTable.image.isSet = true
	getLastTick = getTickCount()
end

function neonTable.func.close(button, state, absoluteX, absoluteY)
	if (button ~= "left") or (state ~= "up") then
		return
	end
	colorPicker.closeSelect()
	showCursor(false)
	guiSetVisible(neonTable.gui.root, false)
	neonTable.isGuiVisible = nil
end

function neonTable.func.clear(button, state, absoluteX, absoluteY)
	if (button ~= "left") or (state ~= "up") then
		return
	end
	if getElementData(localPlayer, 'neonTexture') then 
		neonTable.image.id = nil
		neonTable.image.name = nil
		neonTable.image.color = nil	
		neonTable.image.size = {0.5, 0.5}	
		setElementData(localPlayer, 'neonTexture', neonTable.image.id, true)
		setElementData(localPlayer, 'neonColor', neonTable.image.color, true)
		setElementData(localPlayer, 'neonSize', neonTable.image.size, true)
		neonTable.image.isSet = true	
		guiSetText(neonTable.gui.scrollXLabel, "SizeX: "..neonTable.image.size[1])
		guiSetText(neonTable.gui.scrollYLabel, "SizeY: "..neonTable.image.size[2])
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollX, math.abs(neonTable.image.size[1] * 100) )
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollY, math.abs(neonTable.image.size[2] * 100) )
		guiSetText(neonTable.gui.name, "No image chosen.")
	end	
end

------------------------------------------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------------------------------------------
addEventHandler("onClientHUDRender", root, function()  
	if not neonTable.isGuiVisible or not neonTable.isResourceLoaded or not neonTable.image.name then 
		return 
	end
	local posX, posY = guiGetPosition ( neonTable.gui.root, false )
	dxDrawImage ((posX + 244), (posY + 25), 145, 145, "img/"..neonTable.image.name, 0, 0, 0, tocolor(unpack(neonTable.image.color)), true )
end
)

addEventHandler('onClientPedsProcessed', root, function()
	if not neonTable.isResourceLoaded then 
		return 
	end
	local camX, camY, camZ = getCameraMatrix()
	for index,thisPed in ipairs(getElementsByType("player", root, true)) do	
		if isElementStreamedIn(thisPed) then
			local thisVehicle = getPedOccupiedVehicle ( thisPed )
			if thisVehicle and getVehicleOccupant(thisVehicle) == thisPed then
				if neonTable.render.shader[thisPed] and isElementStreamedIn(thisVehicle) then
					local hx, hy, hz = getElementPosition(thisVehicle)
					if (tonumber(getDistanceBetweenPoints3D(camX, camY, camZ, hx, hy, hz)) < 50) then
						if isEntityInFrontalSphere(Vector3(hx, hy, hz), 5) then	
							drawVehicleNeon(thisVehicle, neonTable.render.shader[thisPed])
						end
					end
				end	
			end
		end
	end
end
) 

function drawVehicleNeon(thisVehicle, thisShader)
	if thisVehicle and thisShader then
		local vehMatrix = getElementMatrix(thisVehicle)
		if not vehMatrix then return end
		local elFw = {vehMatrix[2][1], vehMatrix[2][2], vehMatrix[2][3]}
		local pos = {vehMatrix[4][1], vehMatrix[4][2], vehMatrix[4][3]}
		local elUp = {-vehMatrix[3][1], -vehMatrix[3][2], -vehMatrix[3][3]}
		dxSetShaderValue( thisShader,"sLightForward", elFw )	
		dxSetShaderValue( thisShader,"sLightUp", elUp )
		dxSetShaderValue( thisShader,"sLightPosition", pos )
		dxDrawMaterialPrimitive3D( "trianglelist", thisShader, false, unpack( trianglelist.cube ) )		
	end
end

function setShaderDefaults(myShader)
	dxSetShaderValue(myShader, "sPixelSize", 1 / scx, 1 / scy )
	dxSetShaderValue(myShader, "sHalfPixel", 1/(scx * 2), 1/(scy * 2) )
	dxSetShaderValue(myShader, "sPicSize", 2.5, 5 )
	dxSetShaderValue(myShader, "sLightColor", 0, 0, 0, 0)
	dxSetShaderValue(myShader, "sLightNearClip", 0 )
	dxSetShaderValue(myShader, "sLightPositionOffset", 0, 0, 0)
	dxSetShaderValue(myShader, "sLightAttenuation", 3 )
	dxSetShaderValue(myShader, "sLightAttenuationPowerFw", 0.25 )
	dxSetShaderValue(myShader, "sLightAttenuationPowerBk", 2 )
	dxSetShaderValue(myShader, "gDistFade", 50, 40 )
	dxSetShaderValue(myShader, "sLightBillboard", false )
end

function setChangesToShader(theKey, oldValue, newValue)
    if (getElementType(source) == "player") then
		if not neonTable.render.settings[source] then 
			neonTable.render.settings[source] = {}
			neonTable.render.settings[source].player = source
		end
		if ((theKey == "neonTexture") or (theKey == "neonColor") or (theKey == "neonSize")) and newValue ~= nil and not neonTable.render.shader[source] then
			if renderTarget.isOn then
				shaderPath = "fx/primitive3D_projectedTexture2vec_dl.fx"
			else
				shaderPath = "fx/primitive3D_projectedTexture2vec.fx"
			end
			neonTable.render.shader[source] = dxCreateShader(shaderPath)
			if not neonTable.render.shader[source] then return end
			setShaderDefaults(neonTable.render.shader[source])		
		end
		if (theKey == "neonTexture") and newValue == nil and neonTable.render.shader[source] then
			destroyElement(neonTable.render.shader[source])
			neonTable.render.shader[source] = nil
		end
		if not neonTable.render.shader[source] then return end
		
		if (theKey == "neonTexture") then
			dxSetShaderValue( neonTable.render.shader[source],"sTexture", neonTable.render.texture[newValue] )
			neonTable.render.settings[source].texName = newValue
			local pedColorValue = getElementData(source, 'neonColor')
			if not pedColorValue then pedColorValue = {255, 255, 255, 255} end
			dxSetShaderValue( neonTable.render.shader[source],"sLightColor", pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255 )
			neonTable.render.settings[source].lightColor = {pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255}
		end
		if (theKey == "neonColor") then
			dxSetShaderValue( neonTable.render.shader[source],"sLightColor", newValue[1]/255, newValue[2]/255, newValue[3]/255, newValue[4]/255 )
			neonTable.render.settings[source].lightColor = {newValue[1]/255, newValue[2]/255, newValue[3]/255, newValue[4]/255}
		end	
		if (theKey == "neonSize") then     
			local thisVehicle = getPedOccupiedVehicle ( source )
			if isElement(thisVehicle) then
				local boundingBox = {getElementBoundingBox(thisVehicle)}
				if boundingBox[1] then
					local pedSizeValue = getElementData(source, 'neonSize')
					pedSizeValue = pedSizeValue or {0.5, 0.5}
					dxSetShaderValue(neonTable.render.shader[source], "sPicSize", 4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2]))	-- to 4.3
					if renderTarget.isOn then
						dxSetShaderValue(neonTable.render.shader[source], "sLightPositionOffset", 0, 0, 0)
					else
						dxSetShaderValue(neonTable.render.shader[source], "sLightPositionOffset", 0, math.abs(boundingBox[3]) * 0.95 - 0.15, 0)
					end
					neonTable.render.settings[source].picSize = {4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2])}
					neonTable.render.settings[source].lightPosOffset = math.abs(boundingBox[3]) * 0.95 - 0.15	
				end
			end		
		end
    end
end
addEventHandler("onClientElementDataChange", root, setChangesToShader)


addEventHandler("onClientVehicleEnter", root,
	function(thePlayer, seat)
		if not neonTable.render.shader[thePlayer] or not (seat == 0) then return end
		local thisVehicle = getPedOccupiedVehicle ( thePlayer )
			local boundingBox = {getElementBoundingBox(thisVehicle)}
			if boundingBox[1] then
				local pedSizeValue = getElementData(thePlayer, 'neonSize')
				pedSizeValue = pedSizeValue or {0.5, 0.5}
				dxSetShaderValue(neonTable.render.shader[thePlayer], "sPicSize", 4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2]))	-- to 4.3
				if renderTarget.isOn then
					dxSetShaderValue(neonTable.render.shader[thePlayer], "sLightPositionOffset", 0, 0, 0)
				else
					dxSetShaderValue(neonTable.render.shader[thePlayer], "sLightPositionOffset", 0, math.abs(boundingBox[3]) * 0.95 - 0.15, 0)
				end
				if not neonTable.render.settings[thePlayer] then 
					neonTable.render.settings[thePlayer] = {}
					neonTable.render.settings[thePlayer].player = thePlayer
				end
				neonTable.render.settings[thePlayer].picSize = {4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2])}
				neonTable.render.settings[thePlayer].lightPosOffset = math.abs(boundingBox[3]) * 0.95 - 0.15	
			end
	end
)

addEventHandler( "onClientElementStreamIn", root,
    function ( )
        if getElementType(source) == "vehicle" then
			local thisPed = getVehicleOccupant(source)
			if not thisPed or not neonTable.render.shader[thisPed] then return end
			local boundingBox = {getElementBoundingBox(source)}
			if boundingBox[1] then
				local pedSizeValue = getElementData(thisPed, 'neonSize')
				pedSizeValue = pedSizeValue or {0.5, 0.5}
				dxSetShaderValue(neonTable.render.shader[thisPed], "sPicSize", 4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2]))	-- to 4.3
				if renderTarget.isOn then
					dxSetShaderValue(neonTable.render.shader[thisPed], "sLightPositionOffset", 0, 0, 0)
				else
					dxSetShaderValue(neonTable.render.shader[thisPed], "sLightPositionOffset", 0, math.abs(boundingBox[3]) * 0.95 - 0.15, 0)
				end
				if not neonTable.render.settings[thisPed] then 
					neonTable.render.settings[thisPed] = {} 
					neonTable.render.settings[thisPed].player = thisPed
				end
				neonTable.render.settings[thisPed].picSize = {4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2])}
				neonTable.render.settings[thisPed].lightPosOffset = math.abs(boundingBox[3]) * 0.95 - 0.15				
			end
        end
    end
)

function restartAllShaders()
	if not neonTable.isResourceLoaded then return end
	for i,thisEntity in pairs(neonTable.render.settings) do
		if neonTable.render.shader[thisEntity.player] then
			destroyElement(neonTable.render.shader[thisEntity.player])
			if renderTarget.isOn then
				shaderPath = "fx/primitive3D_projectedTexture2vec_dl.fx"
			else
				shaderPath = "fx/primitive3D_projectedTexture2vec.fx"
			end
			neonTable.render.shader[thisEntity.player] = dxCreateShader(shaderPath)
			if not neonTable.render.shader[thisEntity.player] then return end
			setShaderDefaults(neonTable.render.shader[thisEntity.player])
			if renderTarget.isOn then
				dxSetShaderValue( neonTable.render.shader[thisEntity.player], "ColorRT", renderTarget.RTColor )
				dxSetShaderValue( neonTable.render.shader[thisEntity.player], "NormalRT", renderTarget.RTNormal )
			end
			local pedHeadValue = getElementData(thisEntity.player, 'neonTexture')
			if pedHeadValue then
				neonTable.render.settings[thisEntity.player].texName = pedHeadValue
				dxSetShaderValue( neonTable.render.shader[thisEntity.player],"sTexture", neonTable.render.texture[pedHeadValue] )
			end		
			local pedColorValue = getElementData(thisEntity.player, 'neonColor')		
			if pedColorValue then
				neonTable.render.settings[thisEntity.player].lightColor = {pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255}
				dxSetShaderValue( neonTable.render.shader[thisEntity.player],"sLightColor", pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255 )	
			end			
			if neonTable.render.settings[thisEntity.player].picSize then
				dxSetShaderValue(neonTable.render.shader[thisEntity.player], "sPicSize", neonTable.render.settings[thisEntity.player].picSize)
			else
				neonTable.render.settings[thisEntity.player].picSize = {0,0}
				local thisVehicle = getPedOccupiedVehicle (thisEntity.player)
				if thisVehicle then 
					local boundingBox = {getElementBoundingBox(thisVehicle)}
					if boundingBox[1] then
						local pedSizeValue = getElementData(thisPed, 'neonSize')
						pedSizeValue = pedSizeValue or {0.5, 0.5}
						neonTable.render.settings[thisPed].picSize = {4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2])}				
					end
				end	
				dxSetShaderValue(neonTable.render.shader[thisEntity.player], "sPicSize", neonTable.render.settings[thisEntity.player].picSize)
			end
			if renderTarget.isOn then
				dxSetShaderValue(neonTable.render.shader[thisEntity.player], "sLightPositionOffset", 0, 0, 0)
			else
				dxSetShaderValue(neonTable.render.shader[thisEntity.player], "sLightPositionOffset", 0, neonTable.render.settings[thisEntity.player].lightPosOffset, 0)
			end
		end
	end
end


----------------------------------------------------------------------------------------------------------------------------
-- onClientResourceStart/Stop
----------------------------------------------------------------------------------------------------------------------------
addEventHandler ( "onClientResourceStart", root, function(startedRes)
	switchDREffect(getResourceName(startedRes), true)
end
)

addEventHandler ( "onClientResourceStop", root, function(stoppedRes)
	switchDREffect(getResourceName(stoppedRes), false)
end
)

function switchDREffect(resName, isStarted)
	if isStarted then
		if resName == "dl_core" then
			local isCoreOn = getElementData ( localPlayer, "dl_core.on", false )
			if renderTarget.isOn and isCoreOn then return end
			renderTarget.isOn = isCoreOn
			if renderTarget.isOn then
				renderTarget.RTColor, renderTarget.RTNormal = exports.dl_core:getRenderTargets()
				exports.dl_core:setEmissivePostEffectEnabled(emissiveEffectEnabled)
			end
			if renderTarget.RTColor and renderTarget.RTNormal then
				renderTarget.isOn = true
				restartAllShaders()
			end
		end	
	else
		if not renderTarget.isOn then return end
		if resName == "dl_core" then
			renderTarget.isOn = false
			restartAllShaders()
		end	
	end
end

addEvent( "switchDL_core", true )
addEventHandler( "switchDL_core", root, function(isOn) switchDREffect("dl_core", isOn) end)
------------------------------------------------------------------------------------------------------------
-- OnClientResourceStart / OnClientResourceStop
------------------------------------------------------------------------------------------------------------
addEventHandler("onClientResourceStart", resourceRoot, function()
	if not isFullDX9Supported then
		return
	end
	outputChatBox ("Type /"..toggleCmd.." or hit "..toggleKey.." to choose a vehicle neon!", 0, 255, 0, true)

	neonTable.func.createGuiBox()
	guiSetVisible (neonTable.gui.root, false)
	local imageColumn = guiGridListAddColumn ( neonTable.gui.imageList,"Choose your image",0.85)

	local meta = xmlLoadFile( "neons.xml" )  
	local children = xmlNodeGetChildren(meta)   
	for i,name in ipairs(children) do 
		neonTable.image.fileList[i] = xmlNodeGetAttribute(name, "file") 
		local imageName = xmlNodeGetAttribute(name, "name")
		local imageRow = guiGridListAddRow(neonTable.gui.imageList)
		neonTable.render.texture[i] = dxCreateTexture("img/"..neonTable.image.fileList[i], "dxt3", true, "clamp")
		if not neonTable.render.texture[i] then
			outputChatBox("dl_neon: Could not load textures")
			return
		end
		guiGridListSetItemText(neonTable.gui.imageList, imageRow, imageColumn, imageName, false, false )
	end
	xmlUnloadFile(meta)
	renderTarget.isOn = getElementData ( localPlayer, "dl_core.on", false )
	if renderTarget.isOn then 
		renderTarget.RTColor, renderTarget.RTNormal = exports.dl_core:getRenderTargets()
		exports.dl_core:setEmissivePostEffectEnabled(emissiveEffectEnabled)
		if renderTarget.RTColor and renderTarget.RTNormal then
			renderTarget.isOn = true
			shaderPath = "fx/primitive3D_projectedTexture2vec_dl.fx"
		else
			shaderPath = "fx/primitive3D_projectedTexture2vec.fx"
		end
	else
		shaderPath = "fx/primitive3D_projectedTexture2vec.fx"
	end
	
	for index,thisPed in ipairs(getElementsByType("player", root, true)) do	
		neonTable.render.shader[thisPed] = dxCreateShader(shaderPath)
		if not neonTable.render.shader[thisPed] then return end
		if renderTarget.isOn then
			dxSetShaderValue( neonTable.render.shader[thisPed], "ColorRT", renderTarget.RTColor )
			dxSetShaderValue( neonTable.render.shader[thisPed], "NormalRT", renderTarget.RTNormal )
		end
		
		setShaderDefaults(neonTable.render.shader[thisPed])

		neonTable.render.settings[thisPed] = {}
		neonTable.render.settings[thisPed].player = thisPed		
		local pedHeadValue = getElementData(thisPed, 'neonTexture')
		if pedHeadValue then
			neonTable.render.settings[thisPed].texName = pedHeadValue
			dxSetShaderValue( neonTable.render.shader[thisPed],"sTexture", neonTable.render.texture[pedHeadValue] )
		end		
		local pedColorValue = getElementData(thisPed, 'neonColor')
				
		if pedColorValue then
			neonTable.render.settings[thisPed].lightColor = {pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255}
			dxSetShaderValue( neonTable.render.shader[thisPed],"sLightColor", pedColorValue[1]/255, pedColorValue[2]/255, pedColorValue[3]/255, pedColorValue[4]/255 )
		end	

		local thisVehicle = getPedOccupiedVehicle(thisPed)
		if thisVehicle and getPedOccupiedVehicleSeat(thisPed) then
			local boundingBox = {getElementBoundingBox(thisVehicle)}
			if boundingBox[1] then
				local pedSizeValue = getElementData(thisPed, 'neonSize')
				pedSizeValue = pedSizeValue or {0.5, 0.5}
				dxSetShaderValue(neonTable.render.shader[thisPed], "sPicSize", 4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2]))	-- to 4.3
				if renderTarget.isOn then 
					dxSetShaderValue(neonTable.render.shader[thisPed], "sLightPositionOffset", 0, 0, 0)
				else
					dxSetShaderValue(neonTable.render.shader[thisPed], "sLightPositionOffset", 0, math.abs(boundingBox[3]) * 0.95 - 0.15, 0)
				end
				neonTable.render.settings[thisPed].picSize = {4 * pedSizeValue[1] * 2.3 *  math.abs(boundingBox[1]), 3 * pedSizeValue[2] * 2.1 * math.abs(boundingBox[2])}
				neonTable.render.settings[thisPed].lightPosOffset = math.abs(boundingBox[3]) * 0.95 - 0.15	
			end		
		end	
	end
	
	neonTable.image.id = getElementData(localPlayer, 'neonTexture')
	neonTable.image.color = getElementData(localPlayer, 'neonColor')
	neonTable.image.size = getElementData(localPlayer, 'neonSize')
	if neonTable.image.id and neonTable.image.color and neonTable.image.size then
		neonTable.image.name = neonTable.image.fileList[neonTable.image.id]
		guiSetText(neonTable.gui.name, neonTable.image.name)
		guiGridListSetSelectedItem(neonTable.gui.imageList, tonumber(neonTable.image.id) - 1 ,  1)
	else
		guiGridListSetSelectedItem(neonTable.gui.imageList, 0, 1)
		neonTable.image.name = neonTable.image.fileList[1]
		guiSetText(neonTable.gui.name, neonTable.image.name)
		neonTable.image.id = 1
		neonTable.image.color = {255, 255, 255, 255}
		neonTable.image.size = {0.5, 0.5}
	end
		guiSetText(neonTable.gui.scrollXLabel, "SizeX: "..neonTable.image.size[1])
		guiSetText(neonTable.gui.scrollYLabel, "SizeY: "..neonTable.image.size[2])
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollX, math.abs(neonTable.image.size[1] * 100) )
		guiScrollBarSetScrollPosition ( neonTable.gui.scrollY, math.abs(neonTable.image.size[1] * 100) )	

	bindKey(toggleKey, "down", neonTable.func.toggleMeme)
	addCommandHandler(toggleCmd, neonTable.func.toggleMeme)
	neonTable.func.imageList()
	neonTable.image.isSet = true
	neonTable.isResourceLoaded = true
end
)

addEventHandler("onClientResourceStop", getResourceRootElement( getThisResource()), function()
	for i,thisEntity in ipairs(neonTable.render.settings) do
		if neonTable.render.shader[thisEntity.player] then
			destroyElement(neonTable.render.shader[thisEntity.player])
			neonTable.render.shader[thisEntity.player] = nil
		end
	end
	for i,name in ipairs(neonTable.render.texture) do
		if neonTable.render.texture[i] then
			destroyElement(neonTable.render.texture[i])
			neonTable.render.texture[i] = nil
		end
	end
end
)
