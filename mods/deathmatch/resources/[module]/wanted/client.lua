-- Presentation cache for the local HUD. Only the server changes gameplay state.
local stars, parole = getPlayerWantedLevel(), 0
function getLocalWantedSnapshot()
    return stars, parole
end
addEvent("onClientPlayerWanted", false)
addEvent("onClientWantedSnapshot", false)
addEvent("wanted:change", true)
addEventHandler("wanted:change", resourceRoot, function(oldLevel, level, reason)
    stars = level
    if reason == "respray" then parole = oldLevel end
    triggerEvent("onClientPlayerWanted", localPlayer, oldLevel, level, reason)
end, false)
addEvent("wanted:snapshot", true)
addEventHandler("wanted:snapshot", resourceRoot, function(level, suspended, reason)
    stars, parole = level, suspended
    triggerEvent("onClientWantedSnapshot", localPlayer, level, suspended, reason)
end, false)
