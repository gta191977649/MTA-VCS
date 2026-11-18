CHud = {}
Hud = CHud

local theme = {
    panel = {0, 0, 0}, foreground = {255, 255, 255}, muted = {160, 160, 160},
    accent = {237, 130, 180}, track = {0, 0, 0}, danger = {174, 0, 0},
    shadow = {0, 0, 0},
}

local colorCodes = {
    r = theme.danger, y = theme.accent, l = theme.shadow, b = {0, 0, 255},
    g = {0, 255, 0}, p = {128, 0, 128}, w = theme.foreground, h = {30, 255, 255}, t = {30, 255, 255},
}

local messages, renderers, hiddenBy = {}, {}, {}
CMessages = {}

function getHudTheme()
    return theme
end

function Hud.color(color, alpha)
    return tocolor(color[1], color[2], color[3], math.floor(alpha or 255))
end

function Hud.owner()
    return getResourceName(sourceResource or getThisResource())
end

function Hud.number(value, fallback)
    value = tonumber(value)
    if value and value > -math.huge and value < math.huge then return value end
    return fallback
end

function Hud.slot(value)
    if value == nil then return 1 end
    value = Hud.number(value)
    if value and value >= 1 and value <= 3 and value % 1 == 0 then return value end
end

function Hud.clamp(value)
    return math.max(0, math.min(1, value))
end

function Hud.onRender(callback)
    renderers[#renderers + 1] = callback
end

function setGameplayUiVisible(visible)
    local owner = Hud.owner()
    hiddenBy[owner] = visible == false and true or nil
    return true
end

function isGameplayUiVisible()
    return not next(hiddenBy) and not isMainMenuActive() and not isPlayerMapVisible()
end

function CMessages:set(slot, text, duration, style, owner)
    if type(text) ~= "string" or text == "" then return false end
    messages[slot] = {
        text = text, style = style, started = getTickCount(), duration = duration,
        owner = owner or Hud.owner(),
    }
    return true
end

function CMessages:clear(slot, owner)
    local entry = messages[slot]
    if not entry or (owner and entry.owner ~= owner) then return false end
    messages[slot] = nil
    return true
end

function CMessages:get(slot, now)
    local entry = messages[slot]
    if not entry then return end
    local elapsed = (now - entry.started) % 4294967296
    local fadeIn, fadeOut = entry.style.fadeIn or 0, entry.style.fadeOut or 0
    local fadeAt = entry.duration and (entry.style.fadeDelay or fadeIn) + entry.duration
    if fadeAt and elapsed >= fadeAt + fadeOut then
        messages[slot] = nil
        return
    end
    local opacity = fadeIn > 0 and Hud.clamp(elapsed / fadeIn) or 1
    if fadeAt and elapsed > fadeAt and fadeOut > 0 then
        opacity = math.min(opacity, 1 - Hud.clamp((elapsed - fadeAt) / fadeOut))
    end
    return entry, opacity
end

function Hud.set(...)
    return CMessages:set(...)
end

function Hud.clear(...)
    return CMessages:clear(...)
end

function Hud.message(...)
    return CMessages:get(...)
end

local function measure(text, size, face)
    return CFont:width(text, size, face or "gametext") or 0
end

function Hud.measureText(text, size)
    return measure(text:gsub("~%a~", ""):gsub("#%x%x%x%x%x%x", ""), size)
end

local function wrapText(text, size, maxWidth, defaultColor, face)
    local lines, line = {}, {width = 0}
    local color, word, wordWidth, gap = defaultColor, {}, 0, ""
    local spaceWidth = measure(" ", size, face)

    local function finishLine()
        lines[#lines + 1] = line
        line = {width = 0}
    end

    local function append(text, width, ink)
        local last = line[#line]
        if last and last.color == ink then
            last.text = last.text .. text
            last.width = last.width + width
        else
            line[#line + 1] = {text = text, width = width, color = ink}
        end
        line.width = line.width + width
    end

    local function flushWord()
        if #word == 0 then return end
        local gapWidth = #gap * spaceWidth
        if line.width + gapWidth + wordWidth > maxWidth and line.width > 0 then
            finishLine()
        end
        if gapWidth > 0 and line.width > 0 then append(gap, gapWidth, word[1].color) end
        for _, glyph in ipairs(word) do
            if line.width > 0 and line.width + glyph.width > maxWidth then finishLine() end
            append(glyph.text, glyph.width, glyph.color)
        end
        word, wordWidth, gap = {}, 0, ""
    end

    text = text:gsub("~k~%s*~([%w_]+)~", function(action)
        return getVcsText("C0" .. action) or action
    end)
    text = text:gsub("\r\n", "\n"):gsub("\n\r", "\n"):gsub("\r", "\n")
    local index = 1
    while index <= #text do
        local token = text:sub(index, index + 2):match("^~(%a)~$")
        local button = token and CFont:button(token, face)
        token = token and token:lower()
        local hex = text:sub(index, index + 6):match("^#(%x%x%x%x%x%x)$")
        if button then
            local width = measure(button, size, face)
            word[#word + 1] = {text = button, width = width, color = theme.foreground}
            wordWidth, index = wordWidth + width, index + 3
        elseif token == "n" then
            flushWord()
            finishLine()
            gap, index = "", index + 3
        elseif token and colorCodes[token] then
            color, index = colorCodes[token], index + 3
        elseif hex then
            color = {tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16)}
            index = index + 7
        else
            local nextIndex = index + 1
            while nextIndex <= #text and text:byte(nextIndex) >= 128 and text:byte(nextIndex) < 192 do
                nextIndex = nextIndex + 1
            end
            local char = text:sub(index, nextIndex - 1)
            if char == "\n" then
                flushWord()
                finishLine()
                gap = ""
            elseif char == " " or char == "\t" then
                flushWord()
                gap = gap .. (char == "\t" and "    " or " ")
            else
                local width = measure(char, size, face)
                word[#word + 1] = {text = char, width = width, color = color}
                wordWidth = wordWidth + width
            end
            index = nextIndex
        end
    end
    flushWord()
    finishLine()
    return lines
end

local function limitLines(lines, limit, size, maxWidth, face)
    if not limit or #lines <= limit then return end
    for index = #lines, limit + 1, -1 do lines[index] = nil end
    local line = lines[limit]
    local ellipsisWidth = measure("...", size, face)
    while #line > 0 and line.width + ellipsisWidth > maxWidth do
        local last = line[#line]
        local prefix, char = last.text:match("^(.*)([%z\1-\127\194-\244][\128-\191]*)$")
        if not prefix or prefix == "" then
            line.width = line.width - last.width
            line[#line] = nil
        else
            local removed = measure(char, size, face)
            last.text, last.width = prefix, last.width - removed
            line.width = line.width - removed
        end
    end
    line[#line + 1] = {text = "...", width = ellipsisWidth, color = theme.foreground}
    line.width = line.width + ellipsisWidth
end

function Hud.rect(screen, x, y, width, height, color, opacity)
    local scale = screen.scale
    dxDrawRectangle(x * scale, y * scale, width * scale, height * scale, Hud.color(color, opacity))
end

function Hud.text(screen, entry, x, y, maxWidth, opacity)
    local style = entry.style
    local align = style.align or "left"
    local face = style.face or "gametext"
    local font = CFont:face(face)
    if not font then return 0 end
    local scale = screen.scale
    -- CSimpleFont uses atlas pixels in the PS2's logical viewport. Its scale
    -- applies to both axes before the horizontal and vertical screen projection.
    local size = style.nativeScale and font.cellHeight * style.nativeScale * screen.fontScaleY or style.size
    local aspect = screen.textAspect or 1
    maxWidth = maxWidth / aspect
    if entry.width ~= maxWidth or entry.font ~= font then
        entry.lines = wrapText(entry.text, size, maxWidth, style.color or theme.foreground, face)
        limitLines(entry.lines, style.maxLines, size, maxWidth, face)
        entry.width, entry.font = maxWidth, font
    end
    local lineHeight = size * font.lineHeight / font.cellHeight
    local height, width = (#entry.lines - 1) * lineHeight + size, 0
    for _, line in ipairs(entry.lines) do width = math.max(width, line.width * aspect) end
    if style.valign == "center" then y = y - height / 2 end
    if style.valign == "bottom" then y = y - height end
    local left = x - (align == "center" and width / 2 or align == "right" and width or 0)
    if style.panel then
        Hud.rect(screen, left - 7, y - 4, width + 14, height + 8, theme.panel, 128 * opacity)
    end
    local shadow = style.shadow ~= false and Hud.color(theme.shadow, 255 * opacity) or nil
    local white = Hud.color(theme.foreground, 255 * opacity)
    for _, line in ipairs(entry.lines) do
        local lineWidth = line.width * aspect
        local lineX = x - (align == "center" and lineWidth / 2 or align == "right" and lineWidth or 0)
        for _, run in ipairs(line) do
            local px, py = scale * lineX, scale * y
            CFont:draw(run.text, face, px, py, size * scale, Hud.color(run.color, 255 * opacity), shadow, aspect, white)
            lineX = lineX + run.width * aspect
        end
        y = y + lineHeight
    end
    return height
end

addEventHandler("onClientResourceStop", root, function(resource)
    local owner = getResourceName(resource)
    hiddenBy[owner] = nil
    for slot, entry in pairs(messages) do
        if entry.owner == owner then messages[slot] = nil end
    end
end)

addEventHandler("onClientRender", root, function()
    if not isGameplayUiVisible() then return end
    local width, height = guiGetScreenSize()
    local _, sx, sy = CWidescreenSupport:playerHud()
    local scale = sy * 272 / 720
    local screen = {width = width / scale, height = height / scale, scale = scale, margin = 32,
        fontScaleY = sy / scale, textAspect = sx / sy}
    local now = getTickCount()
    for _, render in ipairs(renderers) do render(screen, now) end
end)
