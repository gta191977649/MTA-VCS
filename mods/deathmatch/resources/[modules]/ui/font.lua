-- This file deal with locales
LANG = exports.language
FontFace = {
    ahronbd = dxCreateFont('ahronbd.ttf', 22, false, 'proof') or 'default',
    ahronbd_25 = dxCreateFont('ahronbd.ttf', 25, false, 'proof') or 'default',
    default_normal = dxCreateFont('ahronbd.ttf',10) or 'default',
    jp_tip = dxCreateFont('jp_normal.ttf', 20, false, 'proof') or 'default',
    jp_header = dxCreateFont('jp_normal.ttf', 30, false, 'proof') or 'default',
    jp_normal = dxCreateFont('jp_normal.ttf') or 'default',
    jp_menuItem = dxCreateFont('jp_normal.ttf',25) or 'default',
}
FontLocale = {
    ["en-US"] = { -- en-US 
        header = "diploma",
        title = "beckett",
        menu_item_strong = "bankgothic",
        menu_item = FontFace.ahronbd,
        tip = FontFace.ahronbd,
        subtitle = FontFace.ahronbd_25,
        normal = FontFace.default_normal,
    },
    ["ja-JP"] = { -- en-US 
        header = jp_header,
        title = "beckett",
        menu_item_strong = jp_menuItem,
        menu_item = jp_menuItem,
        tip = FontFace.jp_tip,
        subtitle = FontFace.jp_tip,
        normal = FontFace.jp_normal,
    },
}
function getFont(type) 
    locale = LANG:getLanguage() or "en-US"
    if FontLocale[locale][type] ~= nil then 
        return FontLocale[locale][type]
    end
    return "arial"
end

