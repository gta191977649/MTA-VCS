function showTextBox(playerid,msg,time)
    triggerClientEvent (playerid,"showClientTextBox", playerid,msg,time)
end
function testTextbox(source,_,msg,time)
    showTextBox(source,msg,time)
end
addCommandHandler ( "textbox", testTextbox )