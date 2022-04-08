npc_hlc = exports.npc_hlc
addEventHandler("onClientPedDamage", root,function(attacker) 
    if attacker and getElementData(source,"npc_hlc") then -- only with nphlc_peds
        if getElementType(attacker) == "player" and attacker == localPlayer then 
            --print("attacker is ",getPlayerName(attacker))
            setElementData(source,"npchlc:attacker",attacker)
        end
        if getElementType(attacker) == "ped" then 
            --print("attacker is ped")
            setElementData(source,"npchlc:attacker",attacker)
        end
    end
end)

addEventHandler("onClientPedWasted",root,function() 
    if getElementData(source,"npc_hlc") then -- only with nphlc_peds
        triggerServerEvent("onTrafficPedWasted",source)
    end
end)

addEventHandler ( "onClientPlayerWeaponFire",localPlayer, function(weapon, ammo, ammoInClip, hitX, hitY, hitZ, hitElement) 
    if source == localPlayer and hitElement and getElementType(hitElement) == "ped" and getElementData(hitElement,"npc_hlc") then
        local hp = getElementHealth(hitElement)
        setElementHealth(hitElement,hp - getWeaponProperty(weapon,"std","damage"))
    end
end)


addEventHandler ( "onClientPlayerDamage", localPlayer, function( attacker, weapon, bodypart )
    if attacker and isElement(attacker) then 
        triggerServerEvent("onTrafficPlayerWasted",source,attacker)
    end
end)

