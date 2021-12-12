UI = exports.ui
WANTED = exports.wanted
BOT = exports.slothbot
PLAYER = exports.player

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
        --createMarker ( x , y, z, "checkpoint", 5, 255, 0, 0, 170 )      -- check if the creation succeeded
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
    UI.showTextBox(_,playerid,"Teleport to SF",3000)
end )
addCommandHandler ( "ls",function(playerid,cmd) 
    setElementPosition(playerid,2490.385742,-1669.751953,13.335947)
    setElementDimension(playerid,0)
    setElementInterior(playerid,0)
    UI.showTextBox(_,playerid,"Teleport to LS",3000)
end )
addCommandHandler ( "lsair",function(playerid,cmd) 
    setElementPosition(playerid,2455.129883,-1660.992188,13.023550)
    UI.showTextBox(_,playerid,"Teleport to LS",3000)
end )
addCommandHandler ( "lv",function(playerid,cmd) 
    setElementPosition(playerid,1697.488281,1449.591797,10.764462)
    UI.showTextBox(_,playerid,"Teleport to LV",3000)
end )
addCommandHandler ( "a51",function(playerid,cmd) 
    setElementPosition(playerid,111.211914,1896.759766,18.477478)
    UI.showTextBox(_,playerid,"Teleport to Area 51",3000)
end )
addCommandHandler ( "hp",function(playerid,cmd,health) 
    setElementHealth(playerid,health)
    UI.showTextBox(_,playerid,"Health set.",3000)
end )
addCommandHandler ( "a",function(playerid,cmd,health) 
    setPedArmor(playerid,health)
    UI.showTextBox(_,playerid,"Armor set.",3000)
end )

addCommandHandler("w2",function(playerid,_,weapon_id) 
    giveWeapon(playerid,weapon_id)
    UI.showTextBox(_,playerid,"Cheat Activated",3000)
end)
addCommandHandler("t",function(playerid,_,hour) 
    setTime(hour,0)
    UI.showTextBox(_,playerid,"Cheat Activated",3000)
end)
addCommandHandler("pos",function(playerid,_,x,y,z) 
    setElementPosition(playerid,x,y,z)
    UI.showTextBox(_,playerid,"Teleported",3000)
end)
addCommandHandler("cash",function(playerid,_,x,y,z) 
    givePlayerMoney( playerid, 50 )

    UI.showTextBox(_,playerid,"Cheat Activated",3000)
end)

addCommandHandler("int",function(playerid,_,x,y,z) 
    local int = getElementInterior(playerid)
    local dim = getElementDimension(playerid)

    UI.showTextBox(_,playerid,"Interior is "..int.." Dimsion is "..dim,3000)
end)
addCommandHandler("camfix",function(playerid,_,x,y,z) 
    setCameraTarget(playerid) 
    UI.showTextBox(_,playerid,"Camera Fixed",3000)
end)

addCommandHandler("trash",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createObject(2858, x,y,z-1)
    UI.showTextBox(_,playerid,"Placed trash",3000)
end)

addCommandHandler("coll",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createObject(3090, x,y,z)
    UI.showTextBox(_,playerid,"Placed trash",3000)
end)

addCommandHandler("boom",function(playerid) 
    local x,y,z = getElementPosition(playerid)
    createExplosion ( x, y, z, 10, source )
    UI.showTextBox(_,playerid,"Bloom Created",3000)
end)

addCommandHandler("city",function(playerid) 
    UI.showTextBox(_,playerid,getElementZoneName ( playerid,true),3000)
end)
addCommandHandler("bot",function(playerid) 
    local x,y,z = 2495.610352,-1677.076172,13.337479
    local bot = BOT:spawnBot (x,y,z,0,0,0,0,nil,9)
    BOT:setBotWeapon(bot,9)
    UI.showTextBox(_,playerid,"BOT",3000)
    print("yes")
end)

addCommandHandler("wanted",function(playerid,_,level) 
    WANTED:setPlayerWanted(playerid,level)
    --UI.showTextBox(_,playerid,getElementZoneName ( playerid,true),3000)
end)

addCommandHandler("unlock",function(playerid,_,item) 
    print(item)
    PLAYER:setPlayerUnlockItem(playerid,item)
    UI:showTextBox(playerid,"unlock "..item,3000)
end) 

addCommandHandler("vid",function(playerid,_,id) 
   local x,y,z = getElementPosition(playerid)
   createVehicle(id,x+2,y+2,z)
end) 