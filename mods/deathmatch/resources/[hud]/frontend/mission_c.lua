function showPayoutGameText(cash)
    cash = Hud.number(cash)
    if not cash then return false end
    local language = getResourceFromName("language")
    local title = language and getResourceState(language) == "running"
        and exports.language:translateText("MISSION_PAYOUT")
    local message = getVcsText("M_PASS") or "~Y~MISSION PASSED! ~n~$~1~"
    if title then message = "~Y~" .. title .. "~n~$~1~" end
    showGameTextForPlayer((message:gsub("~1~", string.format("%d", cash))), 0, 3000)
    CAudioEngine:reportFrontendAudioEvent("money")
    return true
end
addEvent("ui.mission.showpayout",true)
addEventHandler("ui.mission.showpayout",localPlayer,showPayoutGameText,false)
