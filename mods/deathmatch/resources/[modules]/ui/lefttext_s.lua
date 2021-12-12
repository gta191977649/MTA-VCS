function showLeftTextForPlayer(player,text,place)
    --print(getPlayerName(player))
    triggerClientEvent(player,"showClientLeftTextForPlayer",player,text,place)
end
function hideLeftTextForPlayer(player,place)
    triggerClientEvent(player,"hideClientLeftTextForPlayer",player,place)
end
