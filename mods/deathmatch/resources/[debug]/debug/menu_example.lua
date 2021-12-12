UI = exports.ui

local menu_id = UI:createMenu("Header")
UI:addMenuItem(menu_id,"Item A") 
UI:addMenuItem(menu_id,"Item B") 
UI:addMenuItem(menu_id,"Item C") 
UI:showMenuForPlayer(menu_id)
addEventHandler( "onPlayerSelectedMenuRow",root,function(showedMenu,Item) 
    outputChatBox(string.format("Menu %d & Row %d selected",showedMenu,Item))
end)
addEventHandler( "onPlayerMenuExit",root,function(showedMenu) 
    outputChatBox(string.format("Menu %d exit",showedMenu))
end)