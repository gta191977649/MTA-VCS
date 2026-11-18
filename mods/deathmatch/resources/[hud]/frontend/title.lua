function showTitle(title,caption,time)
    time = time or 3000
    local shown = showGameTextForPlayer(title,0,time)
    if caption then showCaptionForPlayer(caption,time) end
    return shown
end
addEvent("ui.client.showTitle",true)
addEventHandler("ui.client.showTitle",localPlayer,showTitle,false)
