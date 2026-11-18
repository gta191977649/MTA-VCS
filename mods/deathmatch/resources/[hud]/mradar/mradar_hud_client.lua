local function getFrontend()
    local resource = getResourceFromName("frontend")
    if resource and getResourceState(resource) == "running" then return exports.frontend end
end

function getMHudVisible()
    local frontend = getFrontend()
    return frontend and frontend:getVcsPlayerHudVisible() or false
end

function setMHudVisible(visible)
    local frontend = getFrontend()
    return frontend and frontend:setVcsPlayerHudVisible(visible) or false
end

function getVcsWeaponHudInfo(weapon)
    return {name = MRADAR_VCS_WEAPONS[weapon], clipped = WEAPON_AMMO_CLIPPED[weapon] == true}
end
