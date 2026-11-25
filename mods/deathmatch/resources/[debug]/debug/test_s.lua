UI = exports.frontend

local godPlayers = {}

function isPlayerInGodMode(player)
    return godPlayers[player] == true
end

addCommandHandler("god", function(player)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    godPlayers[player] = true
    setElementData(player, "god", true, "broadcast", "deny")
    setElementOnFire(player, false)
    UI:showTextBox(player, "Godmode", 3000)
end)

addEventHandler("onPlayerQuit", root, function()
    godPlayers[source] = nil
end)

addEventHandler("onResourceStop", resourceRoot, function()
    for player in pairs(godPlayers) do
        if isElement(player) then removeElementData(player, "god") end
    end
end)

addCommandHandler("wanted", function(player, _, value, extra)
    if not isElement(player) or getElementType(player) ~= "player" then return end
    if extra or not value or not value:match("^[1-6]$") then
        UI:showTextBox(player, "Usage: /wanted [1-6]", 3000)
        return
    end
    local resource = getResourceFromName("wanted")
    if not resource or getResourceState(resource) ~= "running" then
        UI:showTextBox(player, "Wanted resource is unavailable.", 3000)
        return
    end
    if exports.wanted:setPlayerWanted(player, tonumber(value), "debug") then
        local level = exports.wanted:getPlayerWanted(player)
        UI:showTextBox(player, ("Wanted level set to %d %s."):format(level, level == 1 and "star" or "stars"), 3000)
    else
        UI:showTextBox(player, "Could not set wanted level.", 3000)
    end
end)

local function optionalExports(player, name)
    local resource = getResourceFromName(name)
    if resource and getResourceState(resource) == "running" then
        return exports[name]
    end
    outputChatBox(name .. " is unavailable.", player)
end

function getPositionInFrontOfElement(element)
	local matrix = getElementMatrix ( element )
	local offX = 0 * matrix[1][1] + 5 * matrix[2][1] + 0 * matrix[3][1] + matrix[4][1]
	local offY = 0 * matrix[1][2] + 5 * matrix[2][2] + 0 * matrix[3][2] + matrix[4][2]
	local offZ = 0 * matrix[1][3] + 5 * matrix[2][3] + 0 * matrix[3][3] + matrix[4][3]
	return offX, offY, offZ
end


addCommandHandler("setdim",function(player,cmd,id) 
    setElementDimension(player,id)
end)


addCommandHandler ( "save",function(source,cmd) 
    local fileHandle = fileCreate("pos.txt")             -- attempt to create a new file
    if fileHandle then                          
        local x,y,z = getElementPosition(source)    
        --exports.marker:createMarker(x, y, z, "checkpoint", 5, 255, 0, 0, 170)
        local rx,ry,rz = getElementRotation ( source )
        fileWrite(fileHandle,string.format("%f,%f,%f,%f",x,y,z,rz))     -- write a text line
        fileClose(fileHandle)                             -- close the file once you're done with it
    end

end )
addCommandHandler ( "csave",function(source,cmd) 
    local fileHandle = fileCreate("cpos.txt")             -- attempt to create a new file
    if fileHandle then                          
        local x, y, z, lx, ly, lz = getCameraMatrix (source)
        fileWrite(fileHandle,string.format("%f,%f,%f,%f,%f,%f",x, y, z, lx, ly, lz))     -- write a text line
        fileClose(fileHandle)                             -- close the file once you're done with it
    end

end )
addCommandHandler ( "sf",function(playerid,cmd) 
    setElementPosition(playerid,-2654.248047,633.406250,14.453125)
    UI:showTextBox(playerid,"Teleport to SF",3000)
end )
addCommandHandler ( "ls",function(playerid,cmd) 
    setElementPosition(playerid,2490.385742,-1669.751953,13.335947)
    setElementDimension(playerid,0)
    setElementInterior(playerid,0)
    UI:showTextBox(playerid,"Teleport to LS",3000)
end )
addCommandHandler ( "lsair",function(playerid,cmd) 
    setElementPosition(playerid,2455.129883,-1660.992188,13.023550)
    UI:showTextBox(playerid,"Teleport to LS",3000)
end )
addCommandHandler ( "lv",function(playerid,cmd) 
    setElementPosition(playerid,1697.488281,1449.591797,10.764462)
    UI:showTextBox(playerid,"Teleport to LV",3000)
end )
addCommandHandler ( "a51",function(playerid,cmd) 
    setElementPosition(playerid,111.211914,1896.759766,18.477478)
    UI:showTextBox(playerid,"Teleport to Area 51",3000)
end )
addCommandHandler ( "hp",function(playerid,cmd,health) 
    setElementHealth(playerid,health)
    UI:showTextBox(playerid,"Health set.",3000)
end )
addCommandHandler ( "a",function(playerid,cmd,health) 
    setPedArmor(playerid,health)
    UI:showTextBox(playerid,"Armor set.",3000)
end )

addCommandHandler("w2",function(playerid,_,weapon_id) 
    giveWeapon(playerid,weapon_id)
    UI:showTextBox(playerid,"Cheat Activated",3000)
end)
addCommandHandler("t",function(playerid,_,hour) 
    setTime(hour,0)
    UI:showTextBox(playerid,"Cheat Activated",3000)
end)
addCommandHandler("pos",function(playerid,_,x,y,z) 
    setElementPosition(playerid,x,y,z)
    UI:showTextBox(playerid,"Teleported",3000)
end)
addCommandHandler("cash",function(playerid,_,x,y,z) 
    givePlayerMoney( playerid, 50 )

    UI:showTextBox(playerid,"Cheat Activated",3000)
end)

addCommandHandler("cashmax", function(player)
    if not isElement(player) then return end
    if setPlayerMoney(player, 999999999, true) then
        UI:showTextBox(player, "Test balance set to $999,999,999.", 3000)
    end
end)

addCommandHandler("int",function(playerid,_,x,y,z) 
    local int = getElementInterior(playerid)
    local dim = getElementDimension(playerid)

    UI:showTextBox(playerid,"Interior is "..int.." Dimsion is "..dim,3000)
end)
addCommandHandler("camfix",function(playerid,_,x,y,z) 
    setCameraTarget(playerid) 
    UI:showTextBox(playerid,"Camera Fixed",3000)
end)

addCommandHandler("trash",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createObject(2858, x,y,z-1)
    UI:showTextBox(playerid,"Placed trash",3000)
end)

addCommandHandler("coll",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createObject(3090, x,y,z)
    UI:showTextBox(playerid,"Placed trash",3000)
end)

addCommandHandler("boom",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createExplosion ( x, y, z, 10, source )
    UI:showTextBox(playerid,"Bloom Created",3000)
end)

addCommandHandler("city",function(playerid) 
    UI:showTextBox(playerid,getElementZoneName ( playerid,true),3000)
end)
addCommandHandler("bot",function(playerid) 
    local BOT = optionalExports(playerid, "slothbot")
    if not BOT then return end
    local x,y,z = 2495.610352,-1677.076172,13.337479
    local bot = BOT:spawnBot (x,y,z,0,0,0,0,nil,9)
    BOT:setBotWeapon(bot,9)
    UI:showTextBox(playerid,"BOT",3000)
    print("yes")
end)

addCommandHandler("wanted",function(playerid,_,level) 
    local WANTED = optionalExports(playerid, "wanted")
    if not WANTED then return end
    WANTED:setPlayerWanted(playerid,level)
    --UI:showTextBox(playerid,getElementZoneName ( playerid,true),3000)
end)

addCommandHandler("unlock",function(playerid,_,item) 
    local PLAYER = optionalExports(playerid, "player")
    if not PLAYER then return end
    print(item)
    PLAYER:setPlayerUnlockItem(playerid,item)
    UI:showTextBox(playerid,"unlock "..item,3000)
end) 

addCommandHandler("vid",function(playerid,_,id) 
   local x,y,z = getElementPosition(playerid)
   createVehicle(id,x+2,y+2,z)
end)
