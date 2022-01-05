--
-- s_neon.lua
--

local fileList = {}
local isNeonForced = get("ForcePlayer")

addEventHandler ("onPlayerJoin", getRootElement(), function()
	if isNeonForced=="true" then
		if getElementType ( source ) == "player" then
			if not getElementData(source, 'neonTexture') or not getElementData(source, 'neonColor') then
				local chosenImgId = math.random(1, #fileList)
				local chosenColor = { math.random ( 150, 255 ),  math.random ( 150, 255 ),  math.random ( 150, 255 ), 255 }
				setElementData(source, 'neonTexture', chosenImgId, true)
				setElementData(source, 'neonColor', chosenColor, true) 
				setElementData(source, 'neonSize', {0.5, 0.5}, true) 
			end
		end
	end
end
)

addEventHandler("onResourceStart", getResourceRootElement( getThisResource()) ,function()
	if isNeonForced=="true" then
		local meta = xmlLoadFile("neons.xml")  
		local children = xmlNodeGetChildren(meta)
		for i,name in ipairs(children) do 
			fileList[i] = xmlNodeGetAttribute(name, "file")
		end
		for index,thisPed in ipairs(getElementsByType("player")) do
			if not getElementData(thisPed, 'neonTexture') or not getElementData(thisPed, 'neonColor') then
				local chosenImgId = math.random(1, #fileList)
				local chosenColor = { math.random ( 150, 255 ) ,  math.random ( 150, 255 ) ,  math.random ( 150, 255 ) , 255 }
				setElementData(thisPed, 'neonTexture', chosenImgId, true)
				setElementData(thisPed, 'neonColor', chosenColor, true) 
				setElementData(thisPed, 'neonSize', {0.5, 0.5}, true) 
			end
		end
	end
end
)
