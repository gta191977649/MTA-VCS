function showGameTextForPlayer(source,msg,type,time)
    triggerClientEvent(source,"showClientGameText",source,msg,type,time)
end

function testTextbox(source,_,msg,time)
    
    showGameTextForPlayer(source,msg,3,time)
end
addCommandHandler ( "gt", testTextbox )