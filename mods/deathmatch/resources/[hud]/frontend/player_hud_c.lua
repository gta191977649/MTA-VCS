local components = {"ammo", "armour", "breath", "clock", "health", "money", "weapon", "wanted"}
local original = {}
local reloadSnapshot = "leeds_engine:playerHud"
local visible, ready = true, false
local lastHealth, lastArmour, lastWanted
local healthChanged, armourChanged, wantedChanged

-- VCSPC CHud::Draw uses one right-edge anchor and a shared safe zone.
local hudOffsetX, hudOffsetY = -8 * 2.30, -8 * 0.9
local weaponLeft, weaponWidth = 104, 76
local white = tocolor(255, 255, 255)
-- VCSPC PrintStaminaBar uses RGB (0, 30, 117), with half intensity for the empty portion.
-- The original cyan sprite already contains (9, 255, 250), so compensate for its blue channel.
local oxygenFill, oxygenEmpty = tocolor(0, 30, 119), tocolor(0, 15, 59)

function getVcsPlayerHudVisible()
    return visible
end

function setVcsPlayerHudVisible(value)
    value = not not value
    local changed = visible ~= value
    visible = value
    return changed
end

local function updateFlashes(now, health, armour, wanted)
    if lastHealth and health < lastHealth then healthChanged = now end
    if lastArmour and armour < lastArmour then armourChanged = now end
    if lastWanted and wanted ~= lastWanted then wantedChanged = now end
    lastHealth, lastArmour, lastWanted = health, armour, wanted
end

local function canDraw(now, changed, interval)
    return not changed or (now - changed) % 4294967296 >= interval or now % 300 < 150
end

local function drawDigits(text, x, y, sx, sy, clock)
    local atlas = CFont:texture("hudnumbers")
    local fontX = sx * (clock and 0.954 or 0.968)
    local fontY = sy * (clock and 0.748 or 0.742)
    for char in text:gmatch(".") do
        local digit = tonumber(char)
        local cell
        local width = char == ":" and 8 or 13
        if digit then
            cell = clock and digit or digit + 11
        elseif char == ":" then
            cell = 10
        elseif char == "$" then
            cell = 21
        end
        if cell then
            dxDrawImageSection(x, y, width * fontX, 20 * fontY, cell % 8 * 16, math.floor(cell / 8) * 17,
                width, 16, atlas)
        elseif char == "-" then
            CFont:draw(char, "gametext", x, y, 20 * fontY, tocolor(255, 255, 255), nil, fontX / fontY)
        end
        x = x + (width + 0.25) * fontX
    end
end

local function bar(x, y, width, height, fraction, interior, fillTint, emptyTint)
    local progress = Hud.clamp(fraction)
    local remaining = 1 - progress
    local empty = emptyTint and interior or interior .. "dark"
    if remaining > 0 then
        dxDrawImageSection(x + width * progress, y, width * remaining, height, 16 + progress * 48,
            0, remaining * 48, 16, CFont:texture(empty), 0, 0, 0, emptyTint or white)
    end
    if progress > 0 then
        dxDrawImageSection(x, y, width * progress, height, 16, 0, progress * 48, 16, CFont:texture(interior),
            0, 0, 0, fillTint or white)
    end
    dxDrawImageSection(x, y, width, height, 16, 0, 48, 16, CFont:texture("bar_outline"))
end

local function drawWeapon(weapon, name, x, sx, sy, clipped)
    local texture = CFont:texture(weapon == 0 and "fist" or name and "weapon_" .. name or "")
    if not texture then return end
    dxDrawImage(x(weaponLeft), (24.5 + hudOffsetY) * sy, weaponWidth * sx, 72 * sy, texture)
    local slot = getPedWeaponSlot(localPlayer)
    if slot <= 1 or slot >= 10 or weapon == 40 then return end
    local total, clip = getPedTotalAmmo(localPlayer), getPedAmmoInClip(localPlayer)
    local reserve = math.max(0, total - clip)
    if reserve >= 9999 then return end
    local text = tostring(total)
    if clipped and weapon ~= 43 then
        local divisor = weapon == 37 and 10 or 1
        text = ("%d-%d"):format(math.floor(reserve / divisor), math.floor(clip / divisor))
    end
    local size, face = 10, "pagertext"
    local ammoScaleX = sx * 0.8
    local textWidth = CFont:width(text, size, face) or 0
    -- The PS2 64x64 weapon textures have their visible frame at U=1..46.
    local center = x(weaponLeft) + weaponWidth * sx * 23.5 / 64
    CFont:draw(text, face, center - textWidth * ammoScaleX / 2, (68.75 + hudOffsetY) * sy, size * sy,
        tocolor(248, 248, 248), nil, ammoScaleX / sy)
end

function CHud:drawPlayer(now)
    if not visible or not ready then return end
    local width, height = guiGetScreenSize()
    local sx, sy = getVcsHudViewport(width, height)
    local function x(offset) return width - (offset + hudOffsetX) * sx end
    local health, armour, wanted = getElementHealth(localPlayer), getPedArmor(localPlayer), getPlayerWantedLevel()
    updateFlashes(now, health, armour, wanted)
    local hour, minute = getTime()
    local cash = getPlayerMoney(localPlayer)
    drawDigits(("%02d:%02d"):format(hour, minute), x(163.5), (26.5 + hudOffsetY) * sy, sx, sy, true)
    drawDigits((cash < 0 and "-$%07d" or "$%08d"):format(math.abs(cash)), x(163.5), (85.5 + hudOffsetY) * sy,
        sx, sy, false)

    local barX, barWidth, barHeight = x(162.2), 56.2 * sx, 16.8 * sy
    local maxHealth = math.max(1, 100 + (getPedStat(localPlayer, 24) - 569) / 4.31)
    if (health >= 10 or now % 600 < 300) and canDraw(now, healthChanged, 650) then
        bar(barX, (65.5 + hudOffsetY) * sy, barWidth, barHeight, health / maxHealth, "bar_inside2")
    end
    local maxAir = 1000 + (getPedStat(localPlayer, 22) + getPedStat(localPlayer, 225)) * 1.5
    local air = getPedOxygenLevel(localPlayer) or maxAir
    local vehicle = getPedOccupiedVehicle(localPlayer)
    if (vehicle and isElementInWater(vehicle)) or (isElementInWater(localPlayer) and air < maxAir - 1) then
        bar(barX, (45.5 + hudOffsetY) * sy, barWidth, barHeight, air / maxAir, "bar_inside1", oxygenFill, oxygenEmpty)
    elseif armour > 0 and canDraw(now, armourChanged, 650) then
        bar(barX, (45.5 + hudOffsetY) * sy, barWidth, barHeight, armour / 100, "bar_inside1")
    end

    local weapon = getPedWeapon(localPlayer)
    local radar = getResourceFromName("mradar")
    local name, clipped
    if radar and getResourceState(radar) == "running" then
        local entry = exports.mradar:getVcsWeaponHudInfo(weapon)
        if entry then name, clipped = entry.name, entry.clipped end
    end
    drawWeapon(weapon, name, x, sx, sy, clipped)

    local parole = tonumber(getElementData(localPlayer, "nspray:paroleStars", false)) or 0
    local shown = canDraw(now, wantedChanged, 2000) and wanted or 0
    local atlas = CFont:texture("hudnumbers")
    for i = 1, math.min(6, math.max(wanted, parole)) do
        if i <= shown or (i <= parole and now % 300 < 150) then
            local tint = i <= shown and tocolor(207, 149, 54) or tocolor(0, 100, 150)
            dxDrawImageSection(x(66.59 + (i - 1) * 19.4), (103 + hudOffsetY) * sy, 20.904 * sx, 26 * sy,
                96, 34, 16, 16, atlas, 0, 0, 0, tint)
        end
    end
end

Hud.onRender(function(_, now) CHud:drawPlayer(now) end)

addEventHandler("onClientResourceStart", resourceRoot, function()
    for _, name in ipairs({"hudnumbers", "bar_inside1", "bar_inside1dark", "bar_inside2", "bar_inside2dark", "bar_outline"}) do
        if not CFont:texture(name) then return end
    end
    local previous = getElementData(localPlayer, reloadSnapshot, false)
    if previous then
        original = previous
        setElementData(localPlayer, reloadSnapshot, nil, false)
    end
    for _, name in ipairs(components) do
        if original[name] == nil then
            original[name] = isPlayerHudComponentVisible(name)
        end
        setPlayerHudComponentVisible(name, false)
    end
    ready = true
end, false)

addEventHandler("onClientPlayerSpawn", localPlayer, function()
    lastHealth, lastArmour, lastWanted = nil, nil, nil
    healthChanged, armourChanged, wantedChanged = nil, nil, nil
end, false)

addEventHandler("onClientResourceStop", resourceRoot, function()
    if getElementData(root, "leeds_engine:reloading", false) then
        if ready then setElementData(localPlayer, reloadSnapshot, original, false) end
        return
    end
    for name, previous in pairs(original) do setPlayerHudComponentVisible(name, previous) end
end, false)
