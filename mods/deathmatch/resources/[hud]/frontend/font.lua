local hudKinds = {tip = true, subtitle = true, header = true, title = true,
    menu_item_strong = true, menu_item = true, normal = true}

function getFont(kind)
    if hudKinds[kind] then return exports.font:getHudFont() or "default" end
    return "default"
end
