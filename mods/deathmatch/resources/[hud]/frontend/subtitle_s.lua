function showCaptionForPlayer(playerid,msg,time)
    return triggerClientEvent (playerid,"showClientCaption", playerid,msg,time)
end
function hideCaptionForPlayer(playerid)
    return triggerClientEvent (playerid,"hideClientCaption", playerid)
end
function testCaption(source,_,msg,time)
    showCaptionForPlayer(source,msg,time)
end
addCommandHandler ( "cp", testCaption )
