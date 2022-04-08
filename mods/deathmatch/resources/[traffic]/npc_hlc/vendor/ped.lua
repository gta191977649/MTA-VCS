local MeleeWeapons = {
    [0] = true,
    [1] = true,
    [2] = true,
    [3] = true,
    [4] = true,
    [5] = true,
    [6] = true,
    [7] = true,
    [8] = true,
    [9] = true,
    [10] = true,
    [11] = true,
    [12] = true,
    [14] = true,
    [15] = true,
}
function getPedAvaiableWeaponSlot(npc)
    for i=1,12 do 
        local weapon = getPedWeapon (npc, i)
        local ammo = getPedTotalAmmo(npc,i)
        if weapon ~= 0 and ammo > 0 then return i end
    end
    return 0
end

function isNPCCurrentHoldingMeleeWeapon(npc) 
    local id = getPedWeapon(npc)
    return MeleeWeapons[id] ~= nil
end

function getNPCFromVechile(vehicle)
    if vehicle == nil or vehicle == false then return end
    if getElementType(vehicle) ~= "vehicle" then return false end
    local npc = getVehicleOccupant(vehicle)
    if npc ~= nil and isHLCEnabled(npc) then return npc end
    return false
end