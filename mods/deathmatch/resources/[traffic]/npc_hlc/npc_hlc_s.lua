all_npcs = {}

addEventHandler("onResourceStart", resourceRoot, function()
    initNPCControl()
    configureNPCFallbackCollision()
end, false)
addEventHandler("onResourceStop", resourceRoot, function()
    for npc in pairs(all_npcs) do
        disableHLCForNPC(npc)
    end
end, false)
