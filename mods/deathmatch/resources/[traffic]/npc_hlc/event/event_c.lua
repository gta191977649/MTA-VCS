addEventHandler("onClientVehicleCollision",root,function(hit, damageImpulseMag, bodyPart, x, y, z, nx, ny, nz) 
    if hit ~= nil and source == getPedOccupiedVehicle(localPlayer) and getElementType(hit) == "ped" then
        if getElementHealth(hit) > 0 and isHLCEnabled(hit) then 
            if damageImpulseMag > 30 then 
                setTimer(function() 
                    setElementHealth(hit,0)
                    -- sync to server
                    triggerServerEvent("npc_hlc:onNPCKill",hit,localPlayer)
                end,200,1)
            end
        end
    end
end)
addEventHandler("onClientPedWeaponFire", root,function(weapon, ammo, ammoInClip, hitX, hitY, hitZ, hitElement)
    if not isHLCEnabled(source) then return end
    if ammo == 0 then 
        setPedWeaponSlot(source,0)
    end
end)
addEventHandler ( "onClientPedDamage",root,function(attacker,weapon,bodypart ) 
    if not attacker then return end
    if getElementType(attacker) ~= "vehicle" and weapon == nil or getElementType(attacker) ~= "vehicle" and weapon > 40 then return end -- ignore explored
    if not isHLCEnabled(source) then return end
    if isElement(attacker) then
        if bodypart == 9 then --head shot
            setElementHealth(source,0)
            triggerServerEvent("npc_hlc:onNPCKill",source,localPlayer)
            return
        end
        local attacker = getElementType(attacker) == "vehicle" and getVehicleOccupant (attacker) or attacker   
        if isElement(attacker) then
            AI[source].hited = true
            triggerServerEvent("npc_hlc:onClientNPCDamage",root,source,attacker)
        end
    end
end)

addEventHandler ( "onClientVehicleDamage",root,function(attacker,weapon,loss) 
    --print(weapon)
    if not attacker then return end
    --if getElementType(attacker) ~= "vehicle" and weapon == nil or getElementType(attacker) ~= "vehicle" and weapon > 40 then return end -- ignore explored
    --AI[npc].hited
    local ped = getVehicleOccupant (source)
    if ped and isHLCEnabled(ped) then 
        AI[ped].hited = true
        triggerServerEvent("npc_hlc:onClientNPCVehicleDamage",source,source,attacker,weapon,loss)
    end
end)
--onClientNPCVehicleJacked

function onNPCVehicleJacked(npc,jacker) 
    if not isHLCEnabled(npc) then return end
    triggerServerEvent("npc_hlc:onNPCVehicleJacked",npc,jacker)

    removeEventHandler("onClientPedVehicleExit", npc,onNPCVehicleJacked)
end

addEventHandler("onClientVehicleStartEnter", root, function(player,seat,door)
	local ped = getVehicleOccupant (source,seat)
    if isHLCEnabled(ped) then 
        addEventHandler("onClientPedVehicleExit", ped,function() 
            onNPCVehicleJacked(ped,player)
        end,false)
    end
end)

addEventHandler ( "onClientPlayerTarget",root,function(target) 
    if target and source == localPlayer and getElementType(target) == "ped" then 
        if isHLCEnabled(target) and isPlayerAimingTowardsPed(target,5) then 
            triggerServerEvent("npc_hlc:onNPCThreaten",target,source)
        end
    end
end)

function isPlayerAimingTowardsPed ( theElement, range )
    thePed = localPlayer
	if isElement(theElement) and type(range) == "number" then
		if (getElementType(thePed) == "player") then
			local x, y, z = getElementPosition(theElement)
			local px, py, pz = getElementPosition(thePed)
            local p_ped = theElement.matrix.forward 
            local p_player = thePed.matrix.forward 
            local dot = p_ped:dot(p_player)
            if dot < -0.65 then
                local col = createColTube(x, y, z-1, range, 2)
                attachElements(col, theElement)
                setElementParent(col, theElement)
                if getPedTask(thePed, "secondary", 0) == "TASK_SIMPLE_USE_GUN" and getPedTarget(thePed) == theElement and isElementWithinColShape(thePed, col) then
                    return true
                end
            end
		end
	end
	return false
end
--[[
addEventHandler("onClientPedVehicleExit", root, function(vehicle) 
    if isHLCEnabled(source) then
        local task = getNPCCurrentTask(source)
        triggerServerEvent("npc_hlc:onClientNPCVehicleJacked",root,source,localPlayer)
    end
end)
]]