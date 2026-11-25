-- R5 DXUT font dimensions are positive D3DX cell heights in pixels.
-- MTA expands a custom font size by 1.75 before creating the D3DX font.
local fonts = {}
function getDialogFont(height)
    if not fonts[height] then
        local size = math.ceil(height / 1.75)
        local face = dxCreateFont("arial.ttf", size, true, "antialiased") or "default-bold"
        fonts[height] = {face=face, height=height, scale=height / dxGetFontHeight(1,face)}
    end
    return fonts[height]
end

function getDialogBodyFont(width)
    return getDialogFont(width<1024 and 12 or width<1400 and 14 or width<1600 and 16 or 18)
end

function dialogTextWidth(text,font)
    return dxGetTextWidth(text,font.scale,font.face)
end

-- Keep complete glyphs in a narrow cell. Let the font render its full ink
-- bounds (including descenders) instead of scissoring to the advance width.
function fitDialogText(text,width,font)
    if width<=0 then return "" end
    if dialogTextWidth(text,font)<=width then return text end
    local lo,hi=0,utf8.len(text)
    while lo<hi do
        local mid=math.ceil((lo+hi)/2)
        if dialogTextWidth(utf8.sub(text,1,mid),font)<=width then lo=mid else hi=mid-1 end
    end
    return utf8.sub(text,1,lo)
end

-- CDXUTDialog::InitDefaultElements, control 9, elements 0 through 3.
local barAtlas=dxCreateTexture("res/sampgui.png","argb",false,"clamp")
local regions={
    track={243,144,22,11}, back={243,124,22,20}, forward={243,155,22,21}, thumb={266,123,20,44}
}
function drawScrollPart(part,x,y,w,h,horizontal,disabled)
    if not barAtlas or w<=0 or h<=0 then return end
    local r=regions[part]
    local tint=tocolor(255,255,255)
    if part=="thumb" then tint=disabled and tocolor(149,176,208) or tocolor(185,34,40) end
    if horizontal then x,y,w,h=x+(w-h)/2,y+(h-w)/2,h,w end
    dxDrawImageSection(x,y,w,h,r[1],r[2],r[3],r[4],barAtlas,horizontal and -90 or 0,0,0,tint)
end

-- R5 dialog Draw/Close (6F890/6F860) select input modes 2/0.
-- Scoreboard Show/Hide (6F3D0/6E9E0) select modes 3/0.
-- Both visible modes expose the cursor. Share this resource's MTA request.
local cursorOwners={}
function setDialogCursorVisible(owner,visible)
    cursorOwners[owner]=visible and true or nil
    showCursor(next(cursorOwners)~=nil)
end
addEventHandler("onClientPreRender",root,function()
    if next(cursorOwners) and not isCursorShowing() then showCursor(true) end
end)
