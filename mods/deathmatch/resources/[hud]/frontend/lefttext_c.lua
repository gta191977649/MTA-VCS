local rows = {}
local theme = getHudTheme()
local labelStyle = {size = 17, color = theme.muted, maxLines = 1}
local valueStyle = {size = 17, color = theme.foreground, align = "right", maxLines = 1}

function showLeftTextForPlayer(title, value, place)
    local single = value == nil or (type(value) == "number" and place == nil)
    local slot = Hud.slot(single and value or place)
    if not slot or type(title) ~= "string" then return false end
    if not single and type(value) ~= "string" and type(value) ~= "number" then return false end
    rows[slot] = {
        owner = Hud.owner(),
        label = not single and {text = title, style = labelStyle} or nil,
        value = {text = single and title or tostring(value), style = valueStyle},
    }
    return true
end

function hideLeftTextForPlayer(place)
    local slot = Hud.slot(place)
    if not slot or not rows[slot] then return false end
    rows[slot] = nil
    return true
end

addEvent("showClientLeftTextForPlayer", true)
addEventHandler("showClientLeftTextForPlayer", localPlayer, showLeftTextForPlayer, false)
addEvent("hideClientLeftTextForPlayer", true)
addEventHandler("hideClientLeftTextForPlayer", localPlayer, hideLeftTextForPlayer, false)

addEventHandler("onClientResourceStop", root, function(resource)
    local owner = getResourceName(resource)
    for slot, row in pairs(rows) do
        if row.owner == owner then rows[slot] = nil end
    end
end)

function Hud.drawTaskText(screen, slot, left, right, y, width)
    local row = rows[slot]
    if not row then return false end
    local valueWidth = width
    if row.label then
        valueWidth = math.min(width * 0.45, Hud.measureText(row.value.text, valueStyle.size) + 4)
        Hud.text(screen, row.label, left, y, width - valueWidth - 12, 1)
    end
    Hud.text(screen, row.value, right, y, valueWidth, 1)
    return true
end
