function showPayoutGameText(cash)
    if cash ~= nil then
        cash = Hud.number(cash)
        if not cash then return false end
    end
    local language = getResourceFromName("language")
    local title = language and getResourceState(language) == "running"
        and exports.language:translateText("MISSION_PAYOUT")
    local message = cash and (getVcsText("M_PASS") or "~Y~MISSION PASSED! ~n~$~1~")
        or (getVcsText("M_PASSN") or "~Y~MISSION PASSED!")
    if title then message = "~Y~" .. title .. (cash and "~n~$~1~" or "") end
    if cash then message = message:gsub("~1~",string.format("%d",cash)) end
    showGameText(message,"missionPassed",2000)
    if not CAudioEngine:reportFrontendAudioEvent("mission_passed") then
        CAudioEngine:reportFrontendAudioEvent("money")
    end
    return true
end
addEvent("ui.mission.showpayout",true)
addEventHandler("ui.mission.showpayout",localPlayer,showPayoutGameText,false)
