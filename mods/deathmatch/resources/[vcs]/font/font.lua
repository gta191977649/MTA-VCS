local hudFont
local legacySizes = {GAME_TEXT_NAME = 30, RADIO = 25, HUD = 25}
local legacyFonts = {}
local fontPath = "NotoSansSC-Regular.ttf"

function getHudFont()
    if hudFont == nil then
        hudFont = dxCreateFont(fontPath, 20, false, "proof") or "default"
    end
    return hudFont
end

function getDxFont(role)
    local size = legacySizes[role]
    if not size then return nil end
    if legacyFonts[role] == nil then
        legacyFonts[role] = exports.dgs:dgsCreateFont(fontPath, size) or "default"
    end
    return legacyFonts[role]
end
