local progress, npcBars = {}, {}
local theme = getHudTheme()
local barLabel = {size = 24, align = "right", maxLines = 1}

function showProgressBarForPlayer(text, amount, place)
    local slot, percent = Hud.slot(place), Hud.number(amount)
    if not slot or not percent or type(text) ~= "string" then return false end
    progress[slot] = {label = {text = text, style = barLabel}, amount = percent / 100, owner = Hud.owner()}
    return true
end

function hideProgressBarForPlayer(place)
    local slot = Hud.slot(place)
    if not slot or not progress[slot] then return false end
    progress[slot] = nil
    return true
end

local function setNpcBar(ped, label, slot, maxHealth, owner)
    slot = Hud.slot(slot)
    maxHealth = maxHealth == nil and 100 or Hud.number(maxHealth)
    if not slot or not maxHealth or maxHealth <= 0 or not isElement(ped) or getElementType(ped) ~= "ped"
        or type(label) ~= "string" or label == "" then
        return false
    end
    npcBars[slot] = {
        ped = ped, label = {text = label, style = barLabel}, maxHealth = maxHealth, owner = owner,
    }
    return true
end

local function clearNpcBar(slot, owner)
    slot = Hud.slot(slot)
    local bar = npcBars[slot]
    if not bar or bar.owner ~= owner then return false end
    npcBars[slot] = nil
    return true
end

function showNpcHealthBar(ped, label, slot, maxHealth)
    return setNpcBar(ped, label, slot, maxHealth, Hud.owner())
end

function hideNpcHealthBar(slot)
    return clearNpcBar(slot, Hud.owner())
end

addEvent("ui:npcHealthShow", true)
addEventHandler("ui:npcHealthShow", resourceRoot, setNpcBar, false)
addEvent("ui:npcHealthHide", true)
addEventHandler("ui:npcHealthHide", resourceRoot, clearNpcBar, false)

local function clearPed()
    for slot, bar in pairs(npcBars) do
        if bar.ped == source then npcBars[slot] = nil end
    end
end

addEventHandler("onClientElementDestroy", root, clearPed)
addEventHandler("onClientPedWasted", root, clearPed)

addEventHandler("onClientResourceStop", root, function(resource)
    local owner = getResourceName(resource)
    for slot, bar in pairs(npcBars) do
        if bar.owner == owner then npcBars[slot] = nil end
    end
    for slot, bar in pairs(progress) do
        if bar.owner == owner then progress[slot] = nil end
    end
end)

-- CHud's script counter draws a black border and separate back/fill quads.
function COnscreenTimer:drawMeter(screen, bar, row, amount, ink)
    local screenWidth, sx, sy = CWidescreenSupport:playerHud()
    local scale = screen.scale
    local x = (screenWidth - 66 * sx) / scale
    local y = row * sy / scale
    local width, height = 41 * sx / scale, 11 * sy / scale
    local borderX, borderY = sx / scale, sy / scale
    Hud.rect(screen, x - borderX, y - borderY, width + 2 * borderX, height + 2 * borderY, theme.track)
    Hud.rect(screen, x, y, width, height, {55, 55, 55})
    if amount > 0 then Hud.rect(screen, x, y, width * Hud.clamp(amount), height, ink or theme.accent) end
    Hud.text(screen, bar.label, x - 7 * sx / scale, y - borderY, 380, 1)
end

Hud.onRender(function(screen, now)
    if Hud.message("garage", now) then return end
    local viewportWidth, sx, sy = CWidescreenSupport:playerHud()
    local right = (viewportWidth - 25 * sx) / screen.scale
    local y = (Hud.message("timer", now) and 122 or 101)
    for slot = 1, 3 do
        if Hud.drawTaskText(screen, slot, right - 312, right, y * sy / screen.scale, 312) then y = y + 20 end
        local bar = progress[slot]
        if bar then
            COnscreenTimer:drawMeter(screen, bar, y, bar.amount)
            y = y + 31
        end
    end

    local dimension, interior = getElementDimension(localPlayer), getElementInterior(localPlayer)
    for slot = 1, 3 do
        local bar = npcBars[slot]
        if bar then
            local ped = bar.ped
            if not isElement(ped) then
                npcBars[slot] = nil
            elseif isElementStreamedIn(ped) and getElementDimension(ped) == dimension
                and getElementInterior(ped) == interior then
                local health = getElementHealth(ped) or 0
                if health > 0 then
                    local ratio = Hud.clamp(health / bar.maxHealth)
                    COnscreenTimer:drawMeter(screen, bar, y, ratio, theme.danger)
                    y = y + 31
                else
                    npcBars[slot] = nil
                end
            end
        end
    end
end)
