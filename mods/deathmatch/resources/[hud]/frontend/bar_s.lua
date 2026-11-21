local targets = {}

local function slotNumber(slot)
    if slot == nil then return 1 end
    slot = tonumber(slot)
    if slot and slot >= 1 and slot <= 3 and slot % 1 == 0 then return slot end
end

local function ownerName()
    return "server:" .. getResourceName(sourceResource or getThisResource())
end

function showNpcHealthBar(player, ped, label, slot, maxHealth)
    slot = slotNumber(slot)
    maxHealth = maxHealth == nil and 100 or tonumber(maxHealth)
    if not slot or not maxHealth or maxHealth ~= maxHealth or maxHealth <= 0 or maxHealth == math.huge
        or not isElement(player) or getElementType(player) ~= "player"
        or not isElement(ped) or getElementType(ped) ~= "ped"
        or type(label) ~= "string" or label == "" then
        return false
    end
    local owner = ownerName()
    if not triggerClientEvent(player, "ui:npcHealthShow", resourceRoot, ped, label, slot, maxHealth, owner) then
        return false
    end
    local slots = targets[player] or {}
    slots[slot] = {owner = owner, ownerRoot = getResourceRootElement(sourceResource or getThisResource()), ped = ped}
    targets[player] = slots
    return true
end

local function clearTarget(player, slots, slot)
    local bar = slots[slot]
    slots[slot] = nil
    if not next(slots) then targets[player] = nil end
    return triggerClientEvent(player, "ui:npcHealthHide", resourceRoot, slot, bar.owner)
end

function hideNpcHealthBar(player, slot)
    slot = slotNumber(slot)
    local slots = targets[player]
    local bar = slots and slots[slot]
    if not bar or bar.owner ~= ownerName() then return false end
    return clearTarget(player, slots, slot)
end

local function clearPed()
    for player, slots in pairs(targets) do
        for slot, bar in pairs(slots) do
            if bar.ped == source then clearTarget(player, slots, slot) end
        end
    end
end

addEventHandler("onPedWasted", root, clearPed)
addEventHandler("onElementDestroy", root, clearPed)
addEventHandler("onPlayerQuit", root, function()
    targets[source] = nil
end)

addEventHandler("onResourceStop", root, function()
    for player, slots in pairs(targets) do
        for slot, bar in pairs(slots) do
            if bar.ownerRoot == source then clearTarget(player, slots, slot) end
        end
    end
end)
