local LibertyTexture = dxCreateTexture('radarvc.jpg')
local radar = {}
local Offset = {[1] = -120, [2] = -241}
local Size = 124
local myRenderTarget = {}
local tiles = {}
local enabled = false
local ROW_COUNT = 12






function handleTileLoading()
	local visibleTileNames = table.merge(engineGetVisibleTextureNames("radar??"), engineGetVisibleTextureNames("radar???"))
	
	for name, data in pairs(tiles) do
		if not table.find(visibleTileNames, name) then
			unloadTile(name)
		end
	end
	
	for index, name in ipairs (visibleTileNames) do
		loadTile(name)
	end
end

function table.merge ( ... )
	local ret = { }
	
	for index, tbl in ipairs ( {...} ) do
		for index, val in ipairs ( tbl ) do
			table.insert ( ret, val )
		end
	end
	
	return ret
end

function table.find ( tbl, val )
	for index, value in ipairs ( tbl ) do
		if value == val then
			return index
		end
	end
	
	return false
end


function loadTile(name)
	if type ( name ) ~= "string" then
		return false
	end
	
	if tiles[name] then
		return true
	end
	
	local id = tonumber(name:match("%d+"))
	
	if not id then
		return false
	end
	
	local row = math.floor(id/ROW_COUNT)
	local col = id-(row*ROW_COUNT)
	local texture = radar[col+1][row+1]
	local shader = dxCreateShader("shader/texreplace.fx")
	dxSetShaderValue(shader, "gTexture", texture)
	engineApplyShaderToWorldTexture(shader, name)
	tiles[name] = {shader = shader, texture = texture}
	
	return true
end

function unloadTile ( name )
	local tile = tiles[name]
	
	if not tile then
		return false
	end
	
	--if isElement(tile.shader)  then destroyElement(tile.shader)  end
	--if isElement(tile.texture) then destroyElement(tile.texture) end
	
	tiles[name] = nil
	
	-- We succeeded
	return true
end




function ViceRadar()
	--enabled = not enabled
	print("VC RADAR")
	enabled = true
	
	if enabled then
		for i1 = 1, 12 do
			if(not radar[i1]) then radar[i1] = {} end
			if(not myRenderTarget[i1]) then myRenderTarget[i1] = {} end
			for i2 = 1, 12 do
				myRenderTarget[i1][i2] = dxCreateRenderTarget(Size, Size, true) 
				dxSetRenderTarget(myRenderTarget[i1][i2], true)
				dxSetBlendMode("modulate_add")
				
				dxDrawImageSection(0,0, Size, Size, ((i1-1)*Size)+(Offset[1]),((i2-1)*Size)+(Offset[2]), Size, Size,LibertyTexture, 0)
				
				dxSetBlendMode("blend")
				dxSetRenderTarget()
				radar[i1][i2] = myRenderTarget[i1][i2]
			end
		end

	
		handleTileLoading()
		
		addEventHandler("onClientHUDRender", root, handleTileLoading)
	else
		removeEventHandler("onClientHUDRender", root, handleTileLoading)
		
		for name, data in pairs(tiles) do
			unloadTile(name)
		end
	end
end
addEvent("ViceRadar", true)
addEventHandler("ViceRadar", localPlayer, ViceRadar)




ViceRadar()
function CreateBlip(x, y, z, icon, size, r, g, b, a, ordering, visibleDistance, info)
	local bl = createBlip(x, y, z, icon, size, r, g, b, a, ordering, visibleDistance)
	--setElementDimension(bl, 2)
end

