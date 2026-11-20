addEventHandler("onClientPedDamage", root, function(attacker, weapon, _, loss)
    if not isElement(attacker) or not getElementData(source, "npchlc_traffic:visibility") then return end
    if attacker == localPlayer or getElementType(attacker) == "ped" and isElementSyncer(attacker) then
        triggerServerEvent("npchlc_traffic:pedHit", resourceRoot, source, attacker, weapon, loss)
    elseif isElementSyncer(source) and (getElementType(attacker) == "player" or getElementType(attacker) == "ped") then
        triggerServerEvent("npchlc_traffic:pedHitSeen", resourceRoot, source, attacker, weapon, loss)
    end
end)

addEventHandler("onClientPedWeaponFire", root, function(weapon, _, _, ex, ey, ez)
    if isElementSyncer(source) and getElementData(source, "npchlc_traffic:visibility") then
        triggerServerEvent("npchlc_traffic:pedGunfire", resourceRoot, source, weapon, ex, ey, ez)
    end
end)

-- MTA's native server bullet event covers slots 2 through 6. The minigun
-- reports locally from slot 7. Coalesce its very high rate of fire.
local lastMinigun
addEventHandler("onClientPlayerWeaponFire", localPlayer, function(weapon, _, _, ex, ey, ez, _, sx, sy, sz)
    if weapon ~= 38 then return end
    local now = getTickCount()
    if lastMinigun and (now - lastMinigun) % 4294967296 < 120 then return end
    lastMinigun = now
    triggerServerEvent("npchlc_traffic:minigun", resourceRoot, ex, ey, ez, sx, sy, sz)
end, false)

addEvent("npchlc_traffic:pedObserve", true)
addEventHandler("npchlc_traffic:pedObserve", resourceRoot, function(id, victim, observers)
    if not isElement(victim) or not isElementStreamedIn(victim) then return end
    local x, y, z = getElementPosition(victim)
    local seen = {}
    for _, ped in ipairs(observers) do
        if isElement(ped) and isElementStreamedIn(ped) then
            local px, py, pz = getElementPosition(ped)
            if isLineOfSightClear(px, py, pz + 0.65, x, y, z + 0.65, true, false, false, true, false) then
                seen[#seen + 1] = ped
            end
        end
    end
    if #seen > 0 then triggerServerEvent("npchlc_traffic:pedSight", resourceRoot, id, seen) end
end)
