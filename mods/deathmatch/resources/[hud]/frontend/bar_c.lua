local progress, leftProgress, npcBars = {}, {}, {}
local theme = getHudTheme()
local barLabel = {size = 24, align = "right", maxLines = 1}
local missionRows, missionOwner, lastCountdownSecond = {}, nil, nil
local golfMeter
function showGolfMeter(phase, position)
    local owner=Hud.owner()
    if golfMeter and golfMeter.owner~=owner then return false end
    if phase==false then golfMeter=nil return true end
    if (phase~="power" and phase~="aim") or not Hud.number(position) then return false end
    golfMeter={owner=owner,phase=phase,position=Hud.clamp(position/100)}
    return true
end
local counterSilver = {200, 200, 200}

function showVehicleMissionHud(seconds, level, label, value, bar, percent, countdown, secondCounter)
    local owner = Hud.owner()
    if missionOwner and missionOwner ~= owner then return false end
    if seconds then
        seconds = Hud.number(seconds)
        if not seconds or seconds < 0 then return false end
        seconds = math.floor(seconds)
    end
    if level and not Hud.number(level) then return false end
    if label and (type(label) ~= "string" or (type(value) ~= "string" and not Hud.number(value))) then return false end
    if secondCounter and (type(secondCounter) ~= "table" or type(secondCounter.label) ~= "string"
        or not Hud.number(secondCounter.value)) then return false end
    if bar then
        percent = Hud.number(percent)
        if type(bar) ~= "string" or not percent then return false end
    end
    missionOwner = owner
    lastCountdownSecond = COnscreenTimer:warnAtSecond(countdown ~= false and seconds, lastCountdownSecond)
    local rows = {}
    if seconds then
        local clock = ("%d:%02d"):format(math.floor(seconds / 60) % 100, seconds % 60)
        rows[#rows+1] = {label = "Time", value = clock, color = theme.accent}
    end
    if level then rows[#rows+1] = {label = "Level", value = tostring(level), color = counterSilver} end
    if label then rows[#rows+1] = {label = label, value = tostring(value), color = counterSilver} end
    if secondCounter then
        rows[#rows+1] = {label = secondCounter.label, value = tostring(secondCounter.value), color = counterSilver}
    end
    if bar then rows[#rows+1] = {label = bar, amount = Hud.clamp(percent / 100), color = counterSilver} end
    missionRows = rows
    return true
end

function hideVehicleMissionHud()
    if missionOwner ~= Hud.owner() then return false end
    missionRows, missionOwner, lastCountdownSecond = {}, nil, nil
    return true
end

local function drawRun(run, right, top, sx, sy, size, ink)
    local left = right - run.width * sx
    for _, glyph in ipairs(run) do
        CFont:draw(glyph[1], "gametext", left + glyph[2] * sx, top, size, ink, nil, sx / sy)
    end
end

-- SLUS 00320C08 / 00320F28, HUD coordinates in the 480 x 272 reference viewport.
function COnscreenTimer:drawVehicleMissionRows(screen, width, sx, sy, y)
    if #missionRows == 0 then return y end
    local font = CFont:face("gametext")
    if not font then return y end
    local size = font.cellHeight * 0.6 * sy
    for _, row in ipairs(missionRows) do
        local ink = Hud.color(row.color)
        local labelInset = 75
        if row.value then
            row.valueRun = row.valueRun or CFont:scriptCounterRun(row.value, true)
            drawRun(row.valueRun, width - 24 * sx, y * sy, sx, sy, size, ink)
            labelInset = math.max(labelInset, 24 + row.valueRun.width + 4)
        else
            local scale = screen.scale
            Hud.rect(screen, (width - 67*sx)/scale, y*sy/scale, 43*sx/scale, 13*sy/scale, theme.track)
            if row.amount > 0 then
                Hud.rect(screen, (width - 66*sx)/scale, (y+1)*sy/scale,
                    41*row.amount*sx/scale, 11*sy/scale, row.color)
            end
        end
        row.labelRun = row.labelRun or CFont:scriptCounterRun(row.label, false)
        drawRun(row.labelRun, width - labelInset * sx, y * sy, sx, sy, size, ink)
        y = y + 20
    end
    return y
end

function showProgressBarForPlayer(text, amount, place, side)
    local slots = side == "left" and leftProgress or progress
    local slot, percent = Hud.slot(place), Hud.number(amount)
    if not slot or not percent or type(text) ~= "string" then return false end
    slots[slot] = {label = {text = text, style = barLabel}, amount = percent / 100, owner = Hud.owner()}
    return true
end

function hideProgressBarForPlayer(place, side)
    local slots = side == "left" and leftProgress or progress
    local slot = Hud.slot(place)
    if not slot or not slots[slot] or (side == "left" and slots[slot].owner ~= Hud.owner()) then return false end
    slots[slot] = nil
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
    if golfMeter and golfMeter.owner==owner then golfMeter=nil end
    if missionOwner == owner then missionRows, missionOwner, lastCountdownSecond = {}, nil, nil end
    for slot, bar in pairs(npcBars) do
        if bar.owner == owner then npcBars[slot] = nil end
    end
    for _,slots in ipairs({progress,leftProgress}) do
        for slot,bar in pairs(slots) do
            if bar.owner == owner then slots[slot] = nil end
        end
    end
end)

-- CHud's script counter draws a black border and separate back/fill quads.
function COnscreenTimer:drawMeter(screen, bar, row, amount, ink, leftX)
    local screenWidth, sx, sy = CWidescreenSupport:playerHud()
    local scale = screen.scale
    local x = leftX or (screenWidth - 66 * sx) / scale
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
    if golfMeter then
        -- DRIVERA_3717, _3828 and _3910 use the 480 x 272 script viewport.
        local width,height=guiGetScreenSize()
        local gx,gy=width/480,height/272
        local power=golfMeter.phase=="power"
        local texture=CFont:texture(power and "pwrbar" or "aimbar")
        local face=CFont:face("gametext")
        if texture and face then
            dxDrawRectangle(138*gx,198*gy,204*gx,20*gy,tocolor(0,0,0,128))
            dxDrawImage(140*gx,200*gy,200*gx,16*gy,texture)
            CFont:draw(power and "Power" or "Aim","gametext",140*gx,180*gy,
                face.cellHeight*0.75*gy,tocolor(255,255,255),nil,gx/gy)
            local pointerX=137+190*golfMeter.position
            CFont:draw("!","gametext",pointerX*gx,188*gy,face.cellHeight*1.75*gy,
                tocolor(255,255,0),nil,gx/(1.75*gy))
        end
    end
    local right = (viewportWidth - 25 * sx) / screen.scale
    local countdown = Hud.message("timer", now)
    local y = countdown and 122 or 101
    if #missionRows > 0 then
        y = COnscreenTimer:drawVehicleMissionRows(screen, viewportWidth, sx, sy, countdown and 120 or 100)
    end
    for slot = 1, 3 do
        if Hud.drawTaskText(screen, slot, right - 312, right, y * sy / screen.scale, 312) then y = y + 20 end
        local bar = progress[slot]
        if bar then
            COnscreenTimer:drawMeter(screen, bar, y, bar.amount)
            y = y + 31
        end
    end

    local left, width = 20*sx/screen.scale, 112*sx/screen.scale
    local leftY = 101
    for slot=1,3 do
        if Hud.drawTaskText(screen,slot,left,left+width,leftY*sy/screen.scale,width,"left") then leftY=leftY+20 end
        local meter = leftProgress[slot]
        if meter then
            COnscreenTimer:drawMeter(screen,meter,leftY,meter.amount,nil,left+width-41*sx/screen.scale)
            leftY=leftY+31
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
