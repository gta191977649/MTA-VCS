-- Police bribe pickups recover weapons confiscated after Busted only.
local sites = {
    busted = {
        {-865.1029, -669.1772, 11.2617}, {-651.5514, 758.763, 11.2463},
        {512.5314, 508.5707, 11.3028}, {402.7107, -464.5605, 10.1144},
    },
}
local price = 2000
local recoveries, offers, introduced = {}, {}, {}
local nextOffer = 0

-- US PS2 0x255DE0 overwrites the previous list, including for an empty loadout.
function StorePedsWeapons(player)
    local weapons = {slot = getPedWeaponSlot(player)}
    for slot = 0, 12 do
        local id, ammo = getPedWeapon(player, slot), getPedTotalAmmo(player, slot)
        if id and id > 0 and ammo and ammo > 0 then
            weapons[#weapons + 1] = {id, ammo}
        end
    end
    return weapons
end

-- 0x255E70 gives each confiscated weapon and its stored total ammunition.
function RestorePedsWeapons(player, weapons)
    for _, weapon in ipairs(weapons) do
        if not giveWeapon(player, weapon[1], weapon[2], false) then return false end
    end
    if weapons.slot then setPedWeaponSlot(player, weapons.slot) end
    return true
end

local function closeOffer(player)
    if not offers[player] then return end
    offers[player] = nil
    triggerClientEvent(player, "wasted:help", resourceRoot, false)
end

local function sendSites(player)
    local recovery = recoveries[player]
    if recovery then
        triggerClientEvent(player, "wasted:sites", resourceRoot, sites[recovery.reason], recovery.dimension)
    end
end

function ActivateWeaponBuyback(player, reason)
    if not isElement(player) or getElementType(player) ~= "player" or not sites[reason] then return false end
    closeOffer(player)
    local recovery = recoveries[player] or {weapons = {}}
    recovery.reason, recovery.dimension = reason, getElementDimension(player)
    recoveries[player] = recovery
    sendSites(player)
    if not introduced[player] then
        introduced[player] = true
        triggerClientEvent(player, "wasted:help", resourceRoot, "H_WBBW1")
    end
    return true
end

function ConfiscatePlayerWeapons(player, reason, snapshot)
    if not isElement(player) or getElementType(player) ~= "player" or not sites[reason] then return false end
    local weapons = snapshot or StorePedsWeapons(player)
    if not takeAllWeapons(player) then return false end
    recoveries[player] = {weapons = weapons}
    return ActivateWeaponBuyback(player, reason)
end

local function atSite(player, index)
    local recovery = recoveries[player]
    local site = recovery and sites[recovery.reason][index]
    if not site or isPedDead(player) or getElementInterior(player) ~= 0 or
        getElementDimension(player) ~= recovery.dimension then return false end
    local x, y, z = getElementPosition(player)
    return getDistanceBetweenPoints3D(x, y, z, site[1], site[2], site[3]) <= 2.5
end

addEvent("wasted:collect", true)
addEventHandler("wasted:collect", resourceRoot, function(index)
    if not client or type(index) ~= "number" or offers[client] or
        not atSite(client, index) or isElementFrozen(client) then return end
    local key = "RE_WEP"
    if #recoveries[client].weapons == 0 then
        key = "RE_WEPE"
    elseif getPlayerMoney(client) < price then
        key = "RE_WEPN"
    else
        nextOffer = nextOffer + 1
        offers[client] = {site = index, token = nextOffer}
    end
    triggerClientEvent(client, "wasted:help", resourceRoot, key, offers[client] and nextOffer, index)
end, false)

addEvent("wasted:answer", true)
addEventHandler("wasted:answer", resourceRoot, function(token, buy)
    local player = client
    local offer = offers[player]
    if not offer or offer.token ~= token then return end
    closeOffer(player)
    if buy ~= true or not atSite(player, offer.site) or isElementFrozen(player) then return end
    if getPlayerMoney(player) < price then
        triggerClientEvent(player, "wasted:help", resourceRoot, "RE_WEPN")
        return
    end
    local recovery = recoveries[player]
    local before = StorePedsWeapons(player)
    if not RestorePedsWeapons(player, recovery.weapons) or not takePlayerMoney(player, price) then
        takeAllWeapons(player)
        RestorePedsWeapons(player, before)
        return
    end
    recovery.weapons = {}
end, false)

addEventHandler("onPlayerResourceStart", root, function(started)
    if started == getThisResource() then sendSites(source) end
end)
local function interrupt()
    closeOffer(source)
end
addEventHandler("onPlayerWasted", root, interrupt)
addEventHandler("onPlayerSpawn", root, interrupt)
addEventHandler("onElementInteriorChange", root, interrupt)
addEventHandler("onElementDimensionChange", root, interrupt)
addEvent("traffic:onPlayerBusted", false)
addEventHandler("traffic:onPlayerBusted", root, interrupt)
addEventHandler("onPlayerQuit", root, function()
    recoveries[source], offers[source], introduced[source] = nil, nil, nil
end)
