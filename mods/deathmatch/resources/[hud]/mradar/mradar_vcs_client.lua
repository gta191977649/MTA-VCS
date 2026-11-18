-- Preserve MTA blip IDs for existing scripts and use VCS art for their equivalents.
MRADAR_VCS_ICONS = {
    radar_balloon = "Red balloon",
    radar_usj = "Unique stunt jump",
    radar_rampage = "Rampage",
    radar_empire_con = "Business under construction",
    radar_gunshop = "Ammu-Nation",
    radar_umberto = "Umberto Robina",
    radar_mendez = "Mendez brothers",
    radar_diaz = "Ricardo Diaz",
    radar_reni = "Reni Wassulmaier",
    radar_phil = "Phil Cassidy",
    radar_marty = "Marty Jay Williams",
    radar_louise = "Louise Cassidy-Williams",
    radar_lance = "Lance Vance",
    radar_gonz = "Gonzalez",
    radar_bryan = "Bryan Forbes",
    radar_jerry = "Jerry Martinez",
    radar_empire_dam = "Damaged business",
    radar_plane = "Airport",
    radar_empire = "Empire business",
    radar_powerup = "Power-up",
    radar_cshop = "Clothes shop",
    radar_save = "Safe house",
    radar_bomb = "Bomb",
    property = "Property",
    phone = "Telephone",
    mp_targetplayer = "Target player",
    mp_carlockup = "Vehicle lockup",
    mp_tank = "Tank",
    mp_car = "Vehicle",
    mp_objective = "Objective",
    mp_player = "Player",
    mp_checkpoint = "Checkpoint",
    mp_base = "Base",
}

RADAR_SPRITE_TEXTURE_NAMES = {
    [RADAR_SPRITE.CENTRE] = "radar_centre",
    [RADAR_SPRITE.MAP_HERE] = "arrow",
    [RADAR_SPRITE.NORTH] = "radar_north",
    [RADAR_SPRITE.AIRYARD] = "radar_plane",
    [RADAR_SPRITE.AMMUGUN] = "radar_gunshop",
    [RADAR_SPRITE.PROPERTYG] = "property",
    [RADAR_SPRITE.PROPERTYR] = "radar_empire_dam",
    [RADAR_SPRITE.SAVEGAME] = "radar_save",
    [RADAR_SPRITE.WAYPOINT] = "arrow",
    [RADAR_SPRITE.TSHIRT] = "radar_cshop",
    [RADAR_SPRITE.RUNWAY] = "radar_plane",
    [RADAR_SPRITE.SPRAY] = "spray",
}

HUD_SPRITE_TEXTURE_NAMES = {
    [HUD_SPRITE.RADAR_DISC] = "radardisc",
    [HUD_SPRITE.RADAR_RING_PLANE] = "radar_plane",
}

MRADAR_VCS_WEAPONS = {
    [WEAPON_ID.BRASSKNUCKLE] = "brassknuckle",
    [WEAPON_ID.GOLFCLUB] = "golfclub",
    [WEAPON_ID.NIGHTSTICK] = "nitestick",
    [WEAPON_ID.KNIFE] = "knifecur",
    [WEAPON_ID.BASEBALLBAT] = "bat",
    [WEAPON_ID.KATANA] = "katana",
    [WEAPON_ID.CHAINSAW] = "chnsaw",
    [WEAPON_ID.GRENADE] = "grenade",
    [WEAPON_ID.TEARGAS] = "teargas",
    [WEAPON_ID.MOLOTOV] = "molotov",
    [WEAPON_ID.PISTOL] = "beretta",
    [WEAPON_ID.DESERT_EAGLE] = "python",
    [WEAPON_ID.SHOTGUN] = "chromegun",
    [WEAPON_ID.SPAS12_SHOTGUN] = "shotgspa",
    [WEAPON_ID.MICRO_UZI] = "uzi",
    [WEAPON_ID.MP5] = "mplng",
    [WEAPON_ID.AK47] = "ak47",
    [WEAPON_ID.M4] = "m16",
    [WEAPON_ID.TEC9] = "skorpion",
    [WEAPON_ID.SNIPERRIFLE] = "sniper",
    [WEAPON_ID.RLAUNCHER] = "rocketla",
    [WEAPON_ID.RLAUNCHER_HS] = "rocketla",
    [WEAPON_ID.FLAMETHROWER] = "flame",
    [WEAPON_ID.MINIGUN] = "minigun",
    [WEAPON_ID.DETONATOR] = "bomb",
    [WEAPON_ID.CAMERA] = "camera",
}
function getVcsRadarRect(width, height)
    local scaleX, scaleY = exports.frontend:getVcsHudViewport(width, height)
    -- CRadar::DrawRadarCircle and the default 8-unit safe zone from Frontend.cpp.
    local safeZone = -8
    local left = (41.6 + safeZone * 1.95) * scaleX
    local top = height - (119.6 + safeZone * 1.15) * scaleY
    local referenceWidth, referenceHeight = 99.2 * scaleX, 92 * scaleY

    -- The original radar atlas has a circular alpha footprint in square pixels.
    -- Keep VCSPC's horizontal size and center the square in its reference rect.
    local diameter = math.floor(referenceWidth + 0.5)
    return math.floor(left + 0.5), math.floor(top + (referenceHeight - diameter) / 2 + 0.5), diameter, diameter
end

