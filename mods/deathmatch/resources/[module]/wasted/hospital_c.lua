addEvent("wasted:showMessage", true)
addEventHandler("wasted:showMessage", resourceRoot, function(visible)
    if visible then
        exports.frontend:showGameTextForPlayer(exports.frontend:getVcsText("DEAD"), 2, 4000)
    else
        exports.frontend:hideGameText(2)
    end
end, false)
