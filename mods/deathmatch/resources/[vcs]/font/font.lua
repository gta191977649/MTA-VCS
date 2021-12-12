loadstring(exports.dgs:dgsImportFunction())()

DX_FONT = {
    ["RADIO"] = dgsCreateFont( "vcs.ttf", 25 ),
    ["HUD"] = dgsCreateFont( "pricedown_ui.ttf", 25 ),
}

function getDxFont(font) 
    return DX_FONT[font]
end