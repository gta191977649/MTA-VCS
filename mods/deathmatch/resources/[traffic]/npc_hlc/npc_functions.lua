function isHLCEnabled(npc)
    return isElement(npc) and getElementData(npc, "npc_hlc", false) == true
end

local function getProfileValue(npc, key)
    if not isHLCEnabled(npc) then return false end
    local profile = getElementData(npc, "npc_hlc:profile", false)
    return profile and profile[key]
end

function getNPCWalkSpeed(npc)
    return getProfileValue(npc, 1)
end

function getNPCWeaponAccuracy(npc)
    return getProfileValue(npc, 2)
end

function getNPCDriveSpeed(npc)
    return getProfileValue(npc, 3)
end
