addEvent("samp:display", true)
addEventHandler("samp:display", resourceRoot, function(data)
    exports.frontend:setPlayerDialog(data)
end, false)

addEvent("onClientDialogResponse", false)
addEventHandler("onClientDialogResponse", resourceRoot, function(...)
    triggerServerEvent("samp:submit", resourceRoot, ...)
end, false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    triggerServerEvent("samp:ready", resourceRoot)
end)
