function showLeftTextForPlayer(player, title, value, place)
    return triggerClientEvent(player, "showClientLeftTextForPlayer", player, title, value, place)
end

function hideLeftTextForPlayer(player, place)
    return triggerClientEvent(player, "hideClientLeftTextForPlayer", player, place)
end
