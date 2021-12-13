LANG = exports.language
function showPayoutGameText(cash)
    print("yes")
    showGameTextForPlayer(string.format("~y~%s\n\r~w~$%d",LANG:translateText("MISSION_PAYOUT"),cash), 0, 3000)
    playSoundFrontEnd(12)
end
addEvent("ui.mission.showpayout",true)
addEventHandler("ui.mission.showpayout",root,showPayoutGameText)