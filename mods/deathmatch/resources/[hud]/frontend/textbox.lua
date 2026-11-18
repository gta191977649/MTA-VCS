function showTextBox(playerid,msg,time,playCue)
    return triggerClientEvent (playerid,"showClientTextBox", playerid,msg,time,playCue)
end
function testTextbox(source,_,msg,time)
    showTextBox(source,msg,time)
end
addCommandHandler ( "textbox", testTextbox )
