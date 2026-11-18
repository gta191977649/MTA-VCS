local npc, heli
local uiTargets = {}

addCommandHandler("hudnpc", function(player, _, action, slotArg, value)
    if not isElement(player) then return end
    local slot = tonumber(slotArg) or 1
    if slot < 1 or slot > 3 or slot % 1 ~= 0 then return end
    local targets = uiTargets[player] or {}
    uiTargets[player] = targets
    local ped = targets[slot]
    if action == "show" then
        if not isElement(ped) or isPedDead(ped) then
            if isElement(ped) then destroyElement(ped) end
            local x, y, z = getElementPosition(player)
            ped = createPed(7, x + 2 + slot, y, z)
            if not ped then return end
            setElementInterior(ped, getElementInterior(player))
            setElementDimension(ped, getElementDimension(player))
            targets[slot] = ped
        end
        exports.frontend:showNpcHealthBar(player, ped, "Test NPC " .. slot, slot)
    elseif action == "hide" then
        exports.frontend:hideNpcHealthBar(player, slot)
    elseif isElement(ped) and action == "health" and tonumber(value) then
        local health = math.max(0, math.min(100, tonumber(value)))
        if health == 0 then killPed(ped) else setElementHealth(ped, health) end
    elseif isElement(ped) and action == "dimension" and tonumber(value) then
        setElementDimension(ped, tonumber(value))
    elseif isElement(ped) and action == "destroy" then
        destroyElement(ped)
        targets[slot] = nil
    else
        outputChatBox("Usage: /hudnpc <show|hide|health|dimension|destroy> [slot 1-3] [value]", player)
    end
end, true)

addEventHandler("onPlayerQuit", root, function()
    for _, ped in pairs(uiTargets[source] or {}) do
        if isElement(ped) then destroyElement(ped) end
    end
    uiTargets[source] = nil
end)

addCommandHandler("npc", function(player)
    local resource = getResourceFromName("npc_hlc")
    if not resource or getResourceState(resource) ~= "running" then
        outputChatBox("npc_hlc is unavailable.", player)
        return
    end
    local AI = exports.npc_hlc
    if not isElement(npc) then npc = createPed(7, 1, 1, 3) end
    if not isElement(heli) then heli = createVehicle(497, 0, 5, 5) end
    warpPedIntoVehicle(npc,heli)

    AI:enableHLCForNPC(npc)
    --AI:setNPCWalkSpeed(npc,"sprintfast")
    AI:addNPCTask(npc,{"driveToPos", 1451.496094,-620.940430,99.804688, 5}) 
end)
