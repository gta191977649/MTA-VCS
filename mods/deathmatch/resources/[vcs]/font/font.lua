loadstring(exports.dgs:dgsImportFunction())()

DX_FONT = {
    ["GAME_TEXT_NAME"] = dgsCreateFont( "vcs.ttf", 30 ),
    ["RADIO"] = dgsCreateFont( "vcs.ttf", 25 ),
    ["HUD"] = dgsCreateFont( "pricedown_ui.ttf", 25 ),
}

function getDxFont(font) 
    return DX_FONT[font]
end