local board, owner, drag, view
local offsetX, offsetY = 0, 0
local header, body, dirty
local lineHeight, barSize = 18, 16
local headingFont, headingHeight
local rowFont = getDialogFont(18)
local headingColor = tocolor(149,176,208)
local titleColor = tocolor(190,190,190)
local white = tocolor(255,255,255)
local texture = dxCreateTexture("res/sampgui.png","argb",false,"clamp")
local function section(x,y,w,h,u,v,uw,vh,color)
    if texture then dxDrawImageSection(x,y,w,h,u,v,uw,vh,texture,0,0,0,color or white) end
end
local function limit(n,maximum) return math.max(0,math.min(n,maximum)) end

local function bounds()
    local sw,sh=guiGetScreenSize()
    local w=math.min(sw,sw>800 and 800 or 640)
    local h=math.min(sh,sw>800 and 600 or 480)
    return math.floor((sw-w)/2),math.floor((sh-h)/2),w,h
end
function getScoreboardBounds()
    if not board or isPlayerDialogVisible() then return false end
    return bounds()
end

local function releaseTargets()
    if isElement(header) then destroyElement(header) end
    if isElement(body) then destroyElement(body) end
    header,body=nil,nil
end
local function arrange()
    local x,y,w,h=bounds()
    local screenWidth=guiGetScreenSize()
    -- CFontRender::MeasureText2 and RenderText use GetFontSize() minus two.
    headingFont=getDialogBodyFont(screenWidth)
    headingHeight=headingFont.height
    local widths,total={},0
    for i,c in ipairs(board.columns) do
        widths[i]=math.max(24,tonumber(c.width) or 70)
        total=total+widths[i]
    end
    local vw,vh=w-16-barSize,h-65
    local rows=#board.rows*lineHeight
    if total>vw then vh=vh-barSize end
    if total<vw then
        for i,width in ipairs(widths) do widths[i]=width*vw/total end
        total=vw
    end
    if not view or vw~=view.vw or vh~=view.vh then
        releaseTargets()
        header=dxCreateRenderTarget(vw,26,true)
        body=dxCreateRenderTarget(vw,vh,true)
    end
    view={x=x,y=y,w=w,h=h,vw=vw,vh=vh,widths=widths,maxX=math.max(0,total-vw),maxY=math.max(0,rows-vh)}
    offsetX,offsetY=limit(offsetX,view.maxX),limit(offsetY,view.maxY)
    dirty=true
end
function setScoreboardContent(data)
    board=data or nil
    setDialogCursorVisible("scoreboard",board~=nil)
    if board then
        owner=getResourceRootElement(sourceResource)
        arrange()
    else
        owner,view,drag=nil,nil,nil
        offsetX,offsetY=0,0
        releaseTargets()
    end
    return true
end

local function drawText(text,x,y,right,color,font)
    font=font or rowFont
    local visible=fitDialogText(text,right-x,font)
    dxDrawText(visible,x,y,right,y+lineHeight,color or white,font.scale,font.face,"left","center",false)
    return visible==text
end
-- The scoreboard uses CFontRender's four axial shadow passes. DXUT static
-- dialog controls use a different, single diagonal pass.
local function heading(text,x,y,right,color)
    text=fitDialogText(text,right-x,headingFont)
    local function pass(dx,dy,tint)
        dxDrawText(text,x+dx,y+dy,right+dx,y+headingHeight+4+dy,tint,headingFont.scale,headingFont.face,"left","top",false)
    end
    local black=tocolor(0,0,0)
    pass(0,-1,black)
    pass(0,1,black)
    pass(-1,0,black)
    pass(1,0,black)
    pass(0,0,color)
end
local function cell(value,column,row,x,y,w)
    local right=x+w-4
    if type(value)=="table" then
        local path=value[1]
        if type(path)=="string" and fileExists(path) then
            local iw,ih=math.min(w,column.imageW or 18),math.min(lineHeight,column.imageH or 12)
            dxDrawImage(x,y+(lineHeight-ih)/2,iw,ih,path)
            x=x+iw+3
        end
        value=value[2]
    end
    if not value or x>=right then return end
    local str=tostring(value)
    local color=row.color or white
    if column.name~="name" or not board.colorcodes then drawText(str,x,y,right,color); return end
    local start=1
    while x<right do
        local a,b,rgb=str:find("#(%x%x%x%x%x%x)",start)
        local part=str:sub(start,(a or #str+1)-1)
        if not drawText(part,x,y,right,color) or not a then break end
        x=x+dialogTextWidth(part,rowFont)
        color=tonumber("FF"..rgb,16)
        start=b+1
    end
end

local function repaint()
    if not header or not body then return end
    local x=-offsetX
    dxSetRenderTarget(header,true)
    dxSetBlendMode("modulate_add")
    for i,col in ipairs(board.columns) do
        local w=view.widths[i]
        if x+w>0 and x<view.vw then heading(col.friendlyName,x+2,1,x+w-4,headingColor) end
        x=x+w
    end
    dxSetRenderTarget(body,true)
    local first=1+math.floor(offsetY/lineHeight)
    for i=first,math.min(#board.rows,first+math.ceil(view.vh/lineHeight)) do
        local row=board.rows[i]
        local y=(i-1)*lineHeight-offsetY
        if row.highlight then dxDrawRectangle(0,y,view.vw,lineHeight,tocolor(150,7,14,255)) end
        x=-offsetX
        for j,col in ipairs(board.columns) do
            local w=view.widths[j]
            if x+w>0 and x<view.vw then cell(row.cells[j],col,row,x,y,w) end
            x=x+w
        end
    end
    dxSetBlendMode("blend")
    dxSetRenderTarget()
    dirty=false
end

local function scrollbar(horizontal)
    local v=view
    local length=horizontal and v.vw or v.vh
    local max=horizontal and v.maxX or v.maxY
    local x=v.x+8+(horizontal and 0 or v.vw)
    local y=v.y+60+(horizontal and v.vh or 0)
    if horizontal then x=x+barSize else y=y+barSize end
    length=length-2*barSize
    local thumb=math.max(18,length*length/(length+max))
    local offset=horizontal and offsetX or offsetY
    return x,y,length,thumb,max>0 and (length-thumb)*offset/max or 0,max
end
local function drawBar(horizontal)
    local x,y,length,thumb,pos,max=scrollbar(horizontal)
    if horizontal and max<=0 then return end
    local w,h=horizontal and length or barSize,horizontal and barSize or length
    drawScrollPart("track",x,y,w,h,horizontal)
    drawScrollPart("back",horizontal and x-barSize or x,horizontal and y or y-barSize,barSize,barSize,horizontal)
    drawScrollPart("forward",horizontal and x+w or x,horizontal and y or y+h,barSize,barSize,horizontal)
    if max>0 then
        drawScrollPart("thumb",x+(horizontal and pos or 0),y+(horizontal and 0 or pos),horizontal and thumb or w,horizontal and h or thumb,horizontal)
    end
end

addEventHandler("onClientRender",root,function()
    if not board or isPlayerDialogVisible() then return end
    local x,y,w,h=bounds()
    if x~=view.x or y~=view.y or w~=view.w or h~=view.h then arrange() end
    if dirty then repaint() end
    dxDrawRectangle(x,y,w,h,tocolor(0,0,0,195))
    section(x,y+58,w,h-58,13,124,228,141,tocolor(255,255,255,200))
    -- R5 CScoreBoard::Draw starts the hostname five pixels inside the frame.
    -- The count uses a left-aligned rectangle sized for "Players: 10000".
    local countX=x+w-dialogTextWidth("Players: 10000",headingFont)
    heading(board.title,x+5,y+5,countX-2,titleColor)
    heading(board.population,countX,y+5,x+w,titleColor)
    if header and body then
        dxDrawImage(x+8,y+60-headingHeight-4,view.vw,26,header)
        dxDrawImage(x+8,y+60,view.vw,view.vh,body)
        dxSetBlendMode("blend")
    end
    drawBar(true)
    drawBar(false)
end)
addEventHandler("onClientRestore",root,function() if board then arrange() end end)

local function scroll(horizontal,value)
    if horizontal then offsetX=limit(value,view.maxX) else offsetY=limit(value,view.maxY) end
    dirty=true
end
addEventHandler("onClientKey",root,function(key,down)
    if not down or not board or isPlayerDialogVisible() then return end
    local horizontal=key=="arrow_l" or key=="arrow_r" or getKeyState("lshift") or getKeyState("rshift")
    local sign
    if key=="arrow_l" or key=="arrow_u" or key=="mouse_wheel_up" then sign=-1
    elseif key=="arrow_r" or key=="arrow_d" or key=="mouse_wheel_down" then sign=1
    else return end
    scroll(horizontal,(horizontal and offsetX or offsetY)+sign*(horizontal and 40 or lineHeight*(board.step or 1)))
    cancelEvent()
end)

local function moveThumb(mx,my)
    local x,y,length,thumb,_,max=scrollbar(drag.horizontal)
    local pixel=(drag.horizontal and mx-x or my-y)-drag.grab
    scroll(drag.horizontal,pixel*max/math.max(1,length-thumb))
end
addEventHandler("onClientCursorMove",root,function(_,_,mx,my)
    if drag and board and not isPlayerDialogVisible() then moveThumb(mx,my) end
end)
addEventHandler("onClientClick",root,function(button,state,mx,my)
    if button~="left" then return end
    if state=="up" then drag=nil; return end
    if not board or isPlayerDialogVisible() then return end
    for _,horizontal in ipairs({true,false}) do
        local x,y,length,thumb,pos,max=scrollbar(horizontal)
        local along=horizontal and mx-x or my-y
        local across=horizontal and my-y or mx-x
        if across>=0 and across<barSize and max>0 then
            local offset=horizontal and offsetX or offsetY
            local step=horizontal and 40 or lineHeight
            if along>=-barSize and along<0 then scroll(horizontal,offset-step); return end
            if along>=length and along<length+barSize then scroll(horizontal,offset+step); return end
        end
        if max>0 and across>=0 and across<barSize and along>=0 and along<length then
            drag={horizontal=horizontal,grab=(along>=pos and along<pos+thumb) and along-pos or thumb/2}
            moveThumb(mx,my)
            return
        end
    end
    local x=mx-view.x-8
    if x<0 or x>=view.vw then return end
    x=x+offsetX
    for i,w in ipairs(view.widths) do
        if x<w then
            local y=my-view.y
            local row=board.rows[1+math.floor((y-60+offsetY)/lineHeight)]
            if y>=60-headingHeight-4 and y<60 then triggerEvent("onScoreboardCellClick",owner,false,board.columns[i].name,mx,my)
            elseif y>=60 and y<60+view.vh and row then triggerEvent("onScoreboardCellClick",owner,row.element,board.columns[i].name,mx,my) end
            return
        end
        x=x-w
    end
end)
addEventHandler("onClientResourceStop",root,function() if source==owner then setScoreboardContent(false) end end)
