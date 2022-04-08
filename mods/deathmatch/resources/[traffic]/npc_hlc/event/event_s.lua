addEvent("npc_hlc:onNPCKill",true)
addEventHandler("npc_hlc:onNPCKill",root,function(killer)
    --print("server kill sync")
    killPed(source)
end)


addEvent("npc_hlc:onNPCDamage",true)
addEvent("npc_hlc:onClientNPCDamage",true)
addEventHandler("npc_hlc:onClientNPCDamage",root,function(npc,attacker)
    if isElement(attacker) and isElement(npc) then
        triggerEvent("npc_hlc:onNPCDamage",npc,attacker)
    end
end)

addEvent("npc_hlc:onNPCVehicleDamage",true)
addEvent("npc_hlc:onClientNPCVehicleDamage",true)
addEventHandler("npc_hlc:onClientNPCVehicleDamage",root,function(veh,attacker,theWeapon,loss)
    triggerEvent("npc_hlc:onNPCVehicleDamage",veh,attacker,theWeapon,loss)
end)

addEvent("npc_hlc:onNPCVehicleJacked",true)

--[[
addEvent("npc_hlc:onClientNPCVehicleJacked",true)
addEventHandler("npc_hlc:onClientNPCVehicleJacked",root,function(npc,jacker)
    if isElement(jacker) and isElement(npc) then
        triggerEvent("npc_hlc:onNPCVehicleJacked",npc,jacker)
    end
end)
-]]

addEvent("npc_hlc:onNPCThreaten",true)