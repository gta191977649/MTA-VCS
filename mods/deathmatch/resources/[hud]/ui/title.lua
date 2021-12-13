function showTitle(title,caption,time)
    time = time or 3000
    showGameTextForPlayer(title,0,time) 
    showCaptionForPlayer(caption,time) 
end
addEvent("ui.client.showTitle",true)
addEventHandler("ui.client.showTitle",root,showTitle)