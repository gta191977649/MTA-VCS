function showCaptionForPlayer(playerid,msg,time)
    triggerClientEvent (playerid,"showClientCaption", playerid,msg,time)
end
function hideCaptionForPlayer(playerid)
    triggerClientEvent (playerid,"hideClientCaption", playerid)
end
function testCaption(source,_,msg,time)
    showCaptionForPlayer(source,msg,time)
end
addCommandHandler ( "cp", testCaption )