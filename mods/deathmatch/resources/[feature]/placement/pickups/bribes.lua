-- US MAIN.SCM type-11 bribes. SLUS_215.90 schedules their respawn after 300000 ms.
local locations = {
    {-1241.8, -692.6, 18.0},
    {-1089.5, -233.8, 11.4},
    {-882.2, -989.9, 12.6},
    {-820.6, 519.3, 10.9},
    {-580.4, 956.6, 11.0},
    {-778.9, 1436.0, 11.9},
    {416.9, 991.5, 18.3},
    {547.7, -1.5, 14.0},
    {103.7, 245.3, 21.7},
    {-9.1, -962.1, 8.4},
    {193.4, -1580.9, 10.8},
    {282.1, -697.2, 10.1},
}

addEventHandler("onResourceStart", resourceRoot, function()
    for _, position in ipairs(locations) do
        local pickup = createPickup(position[1], position[2], position[3], 3, 1247, 300000)
        if pickup then
            addEventHandler("onPickupHit", pickup, function(player)
                local level = exports.wanted:getPlayerWanted(player)
                if not level or level == 0 or not exports.wanted:setPlayerWanted(player, level - 1, "bribe") then
                    cancelEvent()
                end
            end, false)
        end
    end
end, false)
