CFont = {textures = {}, fonts = {}}

local function readJson(path)
    local file = fileOpen(path, true)
    if not file then return nil end
    local data = fromJSON(fileRead(file, fileGetSize(file)))
    fileClose(file)
    return data
end

local function loadManifest()
    local manifest = readJson("ps2/manifest.json")
    if not manifest or not manifest.fonts or not manifest.textures then return false end
    CFont.fonts = manifest.fonts
    CFont.availableTextures = manifest.textures
    CFont.sounds = manifest.sounds or {}
    return true
end

function getVcsText(key, tableName)
    if type(key) ~= "string" then return false end
    if CFont.text == nil then CFont.text = readJson("ps2/gxt.json") or false end
    local section = CFont.text and CFont.text[tableName or "MAIN"]
    return section and section[key] or false
end

function CFont:texture(name)
    if not self.availableTextures or not self.availableTextures[name] then return false end
    if self.textures[name] == nil then
        self.textures[name] = dxCreateTexture("ps2/" .. name .. ".png", "argb", false, "clamp") or false
    end
    return self.textures[name]
end

function getPs2HudTexture(name)
    if type(name) ~= "string" then return false end
    return CFont:texture(name)
end

local function glyph(face, char)
    local code = utf8.byte(char)
    if not code then return face.glyphs["63"] end
    if code >= 0xE000 and code <= 0xE0FF then
        return face.buttons[tostring(code - 0xE000)], true
    end
    local key = tostring(code)
    local item = face.glyphs[key]
    if not item and code >= 97 and code <= 122 then item = face.glyphs[tostring(code - 32)] end
    return item or face.glyphs["63"] or face.glyphs["32"]
end

function CFont:button(token, name)
    local face = self.fonts[name]
    local code = token:byte()
    if face and face.buttons[tostring(code)] then
        return utf8.char(code + 0xE000)
    end
end

function CFont:face(name)
    if self:texture(name) then return self.fonts[name] end
end

function CFont:width(text, size, name)
    local face = self:face(name)
    if not face then return nil end
    local width = 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local item = glyph(face, char)
        if item then width = width + item[2] end
    end
    return width * size / face.cellHeight
end

function CFont:draw(text, name, x, y, size, color, shadow, horizontalScale, white)
    local face = self:face(name)
    if not face then return false end
    local texture = self.textures[name]
    local scaleY = size / face.cellHeight
    local scaleX = scaleY * (horizontalScale or 1)
    local function drawRun(ink, offset, shadowOnly)
        local pen = x + offset * scaleX
        for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
            local item, button = glyph(face, char)
            if item then
                local inkWidth = item[1] + item[2] + item[3]
                if char ~= " " and inkWidth > 0 and item[4] > 0 and not (shadowOnly and button) then
                    -- SLUS 0x3B8EA0 samples from u+0.5 to u+width-0.5, and v to v+height-0.5.
                    local sourceWidth = inkWidth / (button and 1.33 or 1)
                    dxDrawImageSection(pen - item[1] * scaleX, y + offset * scaleY, inkWidth * scaleX,
                        item[4] * scaleY, item[5] + 0.5, item[6], math.max(0.5, sourceWidth - 1), item[4] - 0.5,
                        texture, 0, 0, 0, button and white or ink)
                end
                pen = pen + item[2] * scaleX
            end
        end
    end
    -- The SLUS FancyText shadow is two logical pixels at unit scale.
    if shadow and name ~= "gametext" then drawRun(shadow, name == "fancytext" and 2 or 3, true) end
    drawRun(color, 0, false)
    return true
end

CAudioEngine = {}
function CAudioEngine:reportFrontendAudioEvent(name)
    if not CFont.sounds or not CFont.sounds[name] then return false end
    return playSound("ps2/sfx_" .. name .. ".wav", false)
end

function playVcsFrontendSound(name)
    return type(name) == "string" and CAudioEngine:reportFrontendAudioEvent(name) or false
end

addEventHandler("onClientResourceStart", resourceRoot, function()
    if not loadManifest() then
        outputDebugString("frontend: import the SLUS-21590 HUD assets with tools/import_vcs_frontend.py", 2)
    end
end, false)
