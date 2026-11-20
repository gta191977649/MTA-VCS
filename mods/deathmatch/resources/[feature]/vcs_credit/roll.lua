-- SLUS-21590 0x273180 builds record offsets with a 478-unit measuring box.
-- 0x272E78 draws each record centered in a narrower 40..440 box.
VCSCreditRoll = {}
local scale = 0.6
local color = tocolor(220, 220, 220, 255)
local records, texture, lineStep
local width, height, sx, sy, left, top
local function readFace()
    local file = fileOpen(":frontend/ps2/manifest.json", true)
    if not file then return end
    local data = fromJSON(fileRead(file, fileGetSize(file)))
    fileClose(file)
    return data and data.fonts and data.fonts.gametext
end

local function layout(text, glyphs, limit)
    local lines = {}
    for paragraph in (text .. "~n~"):gmatch("(.-)~n~") do
        local line = {width=0}
        for word in paragraph:gmatch("%S+") do
            local run, width = {}, 0
            for char in word:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
                local glyph = glyphs[tostring(utf8.byte(char))]
                if glyph then
                    run[#run+1] = {glyph=glyph, x=width}
                    width = width + math.ceil(glyph[2]*scale)
                end
            end
            local space = #line > 0 and math.ceil(glyphs["32"][2]*scale) or 0
            if #line > 0 and line.width+space+width > limit then
                lines[#lines+1] = line
                line, space = {width=0}, 0
            end
            local pen = line.width+space
            for _, item in ipairs(run) do
                item.x = item.x+pen
                line[#line+1] = item
            end
            line.width = pen+width
        end
        lines[#lines+1] = line
    end
    return lines
end

function VCSCreditRoll.load()
    if records and isElement(texture) then return true end
    local face = readFace()
    texture = exports.frontend:getPs2HudTexture("gametext")
    if not face or not isElement(texture) then return false end
    lineStep = math.ceil(face.cellHeight*scale)
    local result, offset = {}, 0
    for group=1,9 do
        local index = 1
        while true do
            local key = ("CR%02d_%02d"):format(group, index)
            local text = exports.frontend:getVcsText(key, "CRED01")
            if not text then break end
            result[#result+1] = {offset=offset, lines=layout(text, face.glyphs, 400)}
            offset = offset + #layout(text, face.glyphs, 478)*lineStep
            index = index+1
        end
    end
    if #result ~= 118 then return false end
    records = result
    return true
end

function VCSCreditRoll.draw(scroll)
    local w,h = guiGetScreenSize()
    if w ~= width or h ~= height then
        local hudX,hudY = exports.frontend:getVcsHudViewport(w,h)
        width,height = w,h
        sx,sy = hudX*640/480,hudY*448/272
        left,top = (w-480*sx)/2,(h-272*sy)/2
    end
    for _, record in ipairs(records) do
        local y = record.offset+498-scroll
        if y >= 398 then break end
        if y > -206 then
            for i,line in ipairs(record.lines) do
                local lineY = y-1+(i-1)*lineStep
                if lineY >= 272 then break end
                if lineY+lineStep > 0 then
                    local x = 240-math.floor(line.width/2)
                    for _, item in ipairs(line) do
                        local g = item.glyph
                        local ink = g[1]+g[2]+g[3]
                        if ink > 0 and g[4] > 0 then
                            dxDrawImageSection(left+(x+item.x-g[1]*scale)*sx,top+lineY*sy,
                                ink*scale*sx,g[4]*scale*sy,g[5]+0.5,g[6],ink-1,g[4]-0.5,texture,0,0,0,color)
                        end
                    end
                end
            end
        end
    end
    return scroll > records[#records].offset+704
end
