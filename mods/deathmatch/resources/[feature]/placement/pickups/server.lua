-- SA weapon equivalents for the VCS pickups with compatible native weapons.
-- VCS-only weapons are retained in weapons.lua and reported until implemented.
local weaponIds = {
    UZI=28, AK47=30, BERETTA=22, BRASSKNUCKLE=1, BAT=5,
    CHROMEGUN=25, GRENADE=16, MACHETE=8, NITESTICK=3,
    MOLOTOV=18, M16=31, KATANA=8, FLAME=37, PYTHON=24,
    GOLFCLUB=2, ROCKETLA=35, SNIPER=34, CHNSAW=9,
}

addEventHandler("onResourceStart", resourceRoot, function()
    local unsupported, count = {}, 0
    for _, row in ipairs(WEAPON_PICKUPS) do
        local id = weaponIds[row[2]]
        if id then
            local pickup = createPickup(row[4], row[5], row[6], 2, id, 30000, row[3])
            if pickup then count = count + 1 else outputDebugString("[placement] Pickup failed at MAIN.txt:" .. row[1], 2) end
        else
            unsupported[row[2]] = (unsupported[row[2]] or 0) + 1
        end
    end
    outputDebugString("[placement] Spawned " .. count .. " weapon pickups using SA weapon equivalents.")
    for name, n in pairs(unsupported) do
        outputDebugString("[placement] Unsupported weapon " .. name .. " (" .. n .. " locations)", 2)
    end
end)
