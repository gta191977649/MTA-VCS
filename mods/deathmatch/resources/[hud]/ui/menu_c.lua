DGS = exports.dgs

local Menu = {}
local MenuWidth = 433
local MenuMaxHeight = 450
local isMenuShown = false
local selectedItem = 1
local shownedMenu = nil

function appyColStyles(col,gridlist) 
	local font = dxCreateFont('ahronbd.ttf', 25, false, 'proof') or 'default'
	DGS:dgsGridListSetColumnFont(gridlist, col ,font)
	DGS:dgsSetProperty(gridlist,"font",font)
	DGS:dgsSetProperty(gridlist,"columnColor",tocolor(0,0,0,200))
	DGS:dgsSetProperty(gridlist,"bgColor",tocolor(0,0,0,200))
	DGS:dgsSetProperty(gridlist,"leading",5)
	--DGS:dgsSetProperty(gridlist,"rowTextColor",tocolor(67,80,95,255))
	DGS:dgsSetProperty(gridlist,"rowShadow",{3,3,tocolor(0,0,0,255)})
	DGS:dgsSetProperty(gridlist,"columnShadow",{3,3,tocolor(0,0,0,255)})
	DGS:dgsSetProperty(gridlist,"shadow",{2,2})
	DGS:dgsSetProperty(gridlist,"columnHeight",65)
	DGS:dgsSetProperty(gridlist,"columnTextPosOffset",{10,12})
	
	DGS:dgsSetProperty(gridlist,"rowTextColor",{tocolor(67,81,95,255),tocolor(150,176,209,255),tocolor(150,176,209,255)})
	DGS:dgsSetProperty(gridlist,"rowHeight",30)
	DGS:dgsSetProperty(gridlist,"clip",false)
end
function createMenu(header)
	
	-- Initialize the meta table
	local idx = #Menu + 1
	Menu[idx] = {}
	Menu[idx]["rows"] = {}
	Menu[idx]["header"] = nil
	Menu[idx]["gridList"] = DGS:dgsCreateGridList (100, 250, MenuWidth, 70 + (33 * #Menu[idx]["rows"]), false )  
	DGS:dgsSetProperty(Menu[idx]["gridList"],"colorcoded",true)

	Menu[idx]["colum_1"] = DGS:dgsGridListAddColumn( Menu[idx]["gridList"], "", 0.5)  
	Menu[idx]["colum_2"] = DGS:dgsGridListAddColumn( Menu[idx]["gridList"], "", 0.5)  

	-- Apply styles
	appyColStyles(Menu[idx]["colum_1"],Menu[idx]["gridList"]) 
	appyColStyles(Menu[idx]["colum_2"],Menu[idx]["gridList"]) 

	-- create title label
	Menu[idx]["title"] = DGS:dgsCreateLabel(0.05, -0.5, 1, 1,header, true)
	DGS:dgsSetProperty(Menu[idx]["title"],"font","beckett")
	DGS:dgsSetProperty(Menu[idx]["title"],"textSize",{2.5,2.5})
	DGS:dgsSetProperty(Menu[idx]["title"],"shadow",{2.5,2.5,tocolor(0,0,0,255),true})
	DGS:dgsSetProperty(Menu[idx]["title"],"alignment",{"left","center"})	-- default invisable window
	DGS:dgsSetVisible ( Menu[idx]["gridList"],false )
	--DGS:dgsSetVisible ( Menu[idx]["title"],false )

	-- atttach to custom element
	--dgsAttachToAutoDestroy (Menu[idx]["gridList"],menu) 
	--setElementParent (Menu[idx]["colum"], menu )  number is 1 anyways
	DGS:dgsSetParent (Menu[idx]["title"], Menu[idx]["gridList"] ) 
	
	DGS:dgsSetProperty(Menu[idx]["gridList"],"scrollBarState",{false,false})
	return Menu[idx]["gridList"] 
end
function getMenuHeight(menu)
	local row_count = DGS:dgsGridListGetRowCount(menu)
	local height = 90 + (33 * row_count) 
	return height > MenuMaxHeight and MenuMaxHeight or height
end

function processColorCode(str) 
	str = string.gsub(str,"~r~", "#d40000")
    str = string.gsub(str,"~y~", "#7F550B")
    str = string.gsub(str,"~l~", "#c8d7ee")
    str = string.gsub(str,"~b~", "#303a66")
    str = string.gsub(str,"~g~", "#2e6124")
    str = string.gsub(str,"~w~", "#BFC2C2")
	return str
end
function addMenuItem(menu,title_1,title_2) 
	-- for the god snake backwards compatibility support
	title_1 = title_1 and processColorCode(title_1) or processColorCode("")
	title_2 = title_2 and processColorCode(title_2) or processColorCode("")

	--local dgs_colum = 1
	--table.insert(Menu[menu_id]["rows"],title)
	local newItem = DGS:dgsGridListAddRow(menu)
	DGS:dgsGridListSetItemText(menu,newItem,1," "..title_1)
	DGS:dgsGridListSetItemText(menu,newItem,2," "..title_2)
	DGS:dgsGridListSetRowBackGroundColor(menu,newItem,tocolor(0,0,0,0),tocolor(0,0,0,0),tocolor(0,0,0,0))
	-- Update the menu height seems bugged

	DGS:dgsSetSize(menu,MenuWidth,getMenuHeight(menu))
end
function setMenuColumnHeader(menu,colum,text) 
	DGS:dgsGridListSetColumnTitle(menu,colum,text)
	DGS:dgsGridListAutoSizeColumn(menu,colum,0.6,true,true)

end
function showMenuForPlayer(menu)
	local label = nil 
	for _,c in ipairs( DGS:dgsGetChildren ( menu ) ) do 
		if getElementType(c) == "dgs-dxlabel" then 
			label = c
			break
		end
	end
	DGS:dgsSetVisible (menu,true )
	DGS:dgsSetVisible (label,true )
	DGS:dgsGridListSetSelectedItem (menu, 1)
	--DGS:dgsGridListAutoSizeColumn(menu,1)
	--DGS:dgsGridListAutoSizeColumn(menu,2)
	selectedItem = 1
	shownedMenu = menu
	toggleAllControls (false,true,false)  
end
function hideMenuForPlayer(menu)
	if DGS:dgsGetVisible(menu) == true then
		DGS:dgsSetVisible (menu,false)
	end
	--DGS:dgsSetVisible (menu,false )
	shownedMenu = nil
	toggleAllControls (true,true,false)  
end

function clearMenu(menu)
	DGS:dgsGridListClear (menu)
	local rowCount = DGS:dgsGridListGetRowCount(menu)
	DGS:dgsSetSize(menu,MenuWidth,getMenuHeight(menu))
end

function setMenuHeader(menu,newHeader)
	local label = nil 
	for _,c in ipairs( DGS:dgsGetChildren ( menu ) ) do 
		if getElementType(c) == "dgs-dxlabel" then 
			label = c
			break
		end
	end
	DGS:dgsSetProperty(label,"text",newHeader)
end
addEventHandler( "onClientKey", root, function(button,press) 
	if shownedMenu == nil then return end
	--dgsSetProperty(gridlist,"selectedColumn",selectedColumn)
	local menuItemCount = DGS:dgsGridListGetRowCount(shownedMenu)
	if button == "arrow_u" and press then
		local previousItem = selectedItem
		if selectedItem > 1 then 
			selectedItem = selectedItem - 1 
		else
			selectedItem = menuItemCount
		end
		DGS:dgsGridListSetSelectedItem (shownedMenu, selectedItem)
		DGS:dgsGridListScrollTo(shownedMenu,selectedItem,1)
		playSoundFrontEnd(3)
		triggerEvent( "onPlayerMenuItemChange", shownedMenu,shownedMenu, previousItem,selectedItem)
		return
	end
	if button == "arrow_d" and press then
		local previousItem = selectedItem
		if selectedItem >= 1 and selectedItem < menuItemCount then 
			selectedItem = selectedItem + 1 
		else
			selectedItem = 1
		end
		DGS:dgsGridListSetSelectedItem (shownedMenu, selectedItem)
		DGS:dgsGridListScrollTo(shownedMenu,selectedItem,1)
		playSoundFrontEnd(3)
		triggerEvent( "onPlayerMenuItemChange", shownedMenu,shownedMenu, previousItem,selectedItem)
		return
	end
	
	if button == "space" and press then
		triggerEvent ( "onPlayerSelectedMenuRow", shownedMenu,shownedMenu, selectedItem)
		playSoundFrontEnd(1)
		return
	end
	if button == "f" and press then
		triggerEvent ( "onPlayerMenuExit", shownedMenu,shownedMenu)
		--hideMenuForPlayer(shownedMenu)
		playSoundFrontEnd(2)
		return
	end
end )

addEvent ( "onPlayerSelectedMenuRow", true  )
addEvent ( "onPlayerMenuItemChange", true  )
addEvent ( "onPlayerMenuExit", true  )