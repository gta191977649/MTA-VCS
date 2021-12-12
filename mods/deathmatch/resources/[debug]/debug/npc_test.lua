AI = exports.npc_hlc

local npc = createPed(7,1,1,3)
local heli = createVehicle(497, 0 , 5 ,5)


--giveWeapon ( npc, 31, 999999 )
addCommandHandler("npc",function(src) 
    warpPedIntoVehicle(npc,heli)

    AI:enableHLCForNPC(npc)
    --AI:setNPCWalkSpeed(npc,"sprintfast")
    AI:addNPCTask(npc,{"driveToPos", 1451.496094,-620.940430,99.804688, 5}) 
end)
