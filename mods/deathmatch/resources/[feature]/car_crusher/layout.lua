-- Harwood turned onto the eastern hardstand, with the loading side facing the yard.
local pickupX, pickupY = 1142.75, 51.15625
local function crusherWorld(x, y, z)
    return -1267.255 + (y-pickupY), 130.228 - (x-pickupX), z + 11.36
end

Crusher = {
    rotation = 270,
    pickupMin = {crusherWorld(1149.75, 46.25, -0.951)},
    pickupMax = {crusherWorld(1135.75, 56.0625, -0.951)},
    drop = {crusherWorld(1143, 59.875, 5)},
    missionHelp = {crusherWorld(1140.25, 50.0625, 0)},
    info = {crusherWorld(1130.375, 52.75, 0.375)},
    parts = {
        doc_crane_leggs = {crusherWorld(1118.29, 52.4406, 2.35756)},
        doc_crane_cab = {crusherWorld(1118.98, 52.4167, 10.2705)},
        back_box = {crusherWorld(1136.7, 58.4806, 3.26552)},
        crushercrush = {crusherWorld(1139.73, 60.3852, 1.09806)},
        crushertop = {crusherWorld(1139.55, 65.0512, 4.59026)}
    }
}
