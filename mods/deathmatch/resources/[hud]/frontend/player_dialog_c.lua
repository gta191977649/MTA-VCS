-- DXUT default control rectangles in the SA-MP GUI atlas.
local atlas = dxCreateTexture("res/sampgui.png", "argb", false, "clamp")
local white = tocolor(255,255,255)
local font=getDialogFont(18)
local controlFont=getDialogFont(20)
local rowH=font.height
local bodyFont
local bodyColor = tocolor(169,196,228)
local dialog, layout, edit, inputMode
local first, selected, focus, dragging, pressedButton
local function clamp(n, low, high) return math.max(low, math.min(n, high)) end

local function sprite(x,y,w,h,u,v,uw,vh,color)
    if atlas and w > 0 and h > 0 then
        dxDrawImageSection(x,y,w,h,u,v,uw,vh,atlas,0,0,0,color or white)
    end
end

local function drawEditFrame(x,y,w,h)
    -- DXUT draws nine atlas sections into a five-pixel edit border.
    local xs,ys={x,x+5,x+w-5,x+w},{y,y+5,y+h-5,y+h}
    local us,vs={8,14,241,246},{82,90,113,121}
    for j=1,3 do
        for i=1,3 do
            sprite(xs[i],ys[j],xs[i+1]-xs[i],ys[j+1]-ys[j],us[i],vs[j],us[i+1]-us[i],vs[j+1]-vs[j])
        end
    end
end

local function panel(x,y,w,h)
    dxDrawRectangle(x,y,w,h,tocolor(0,0,0,205))

end

local function split(value, separator)
    local result = {}
    for part in (value .. separator):gmatch("(.-)" .. separator) do result[#result+1] = part end
    return result
end

local function plain(s) return (s:gsub("{%x%x%x%x%x%x}", "")) end
local function measure(s) return dialogTextWidth(plain(s),font) end
local function label(s,x,y,w,color,shadow,face)
    face=face or font
    -- DX color-coded mode disables clipping. Draw each run in the cell bounds.
    local right, start = x+w, 1
    while start <= #s and x < right do
        local a,b,rgb = s:find("{(%x%x%x%x%x%x)}",start)
        local part = fitDialogText(s:sub(start,(a or #s+1)-1),right-x,face)
        local function pass(dx,dy,tint)
            dxDrawText(part,x+dx,y+dy,right+dx,y+face.height+dy,tint,face.scale,face.face,"left","top",false)
        end
        local black=tocolor(0,0,0)
        if shadow=="outline" then
            pass(-1,0,black)
            pass(1,0,black)
            pass(0,-1,black)
            pass(0,1,black)
        elseif shadow then pass(1,1,black) end
        pass(0,0,color or white)
        x = x + dialogTextWidth(part,face)
        if not a or part~=s:sub(start,a-1) then break end
        color = tonumber("FF"..rgb,16)
        start = b+1
    end
end

local function cursor()
    local x,y = getCursorPosition()
    if not x then return -1,-1 end
    local sw,sh = guiGetScreenSize()
    return x*sw,y*sh
end
local function inside(x,y,l,t,w,h) return x>=l and x<l+w and y>=t and y<t+h end

local function arrange()
    local sw,sh = guiGetScreenSize()
    local d = dialog
    local rows, widths = {}, {}
    local lines = split(d.info:gsub("\r",""),"\n")
    if lines[#lines] == "" then table.remove(lines) end
    local list = d.style==2 or d.style>=4
    local input = d.style==1 or d.style==3
    bodyFont=getDialogBodyFont(sw)
    local pixels=bodyFont.height
    local function measureBody(value) return dialogTextWidth(plain(value),bodyFont) end
    if list then
        rows={}
        for i,cells in ipairs(d.items) do rows[i]=cells end
    else
        for _,line in ipairs(lines) do rows[#rows+1]={line} end
    end
    local columns=rows[1] and math.max(1,#rows[1]) or 1
    for _,cells in ipairs(rows) do
        for i,value in ipairs(cells) do
            local width=list and measure(value)+20 or measureBody(value)
            widths[i]=math.max(widths[i] or 0,width)
        end
    end
    local total=0
    for _,v in ipairs(widths) do total=total+v end
    local bw=100
    local buttons=d.button2~="" and 2 or 1
    local preferred=total+40
    if d.style==2 then preferred=clamp(preferred,400,800)
    elseif d.style>=4 then preferred=math.max(400,preferred+(4-columns)*20) end
    local w=math.min(sw-12,math.max(230,preferred))
    local available=w-40
    if d.style>=4 and total<available and columns>1 then
        local extra=math.max(0,math.floor((360-total-(4-columns)*20)/(columns-1)))
        for i=1,columns-1 do widths[i]=(widths[i] or 0)+extra end
    end
    if total>available then
        for i,v in ipairs(widths) do widths[i]=v*available/total end
    end
    if not list then
        rows={}
        local color=""
        for _,line in ipairs(lines) do
            local part=color
            local pos = 1
            while pos<=#line do
                local code=line:sub(pos,pos+7)
                if code:match("^{%x%x%x%x%x%x}$") then
                    color=code
                    part=part..code
                    pos=pos+8
                else
                    local byte=line:byte(pos)
                    local length=byte<128 and 1 or byte<224 and 2 or byte<240 and 3 or 4
                    local ch=line:sub(pos,pos+length-1)
                    if measureBody(part..ch)>available and plain(part)~="" then
                        rows[#rows+1]={part}
                        part=color
                    end
                    part=part..ch
                    pos=pos+length
                end
            end
            rows[#rows+1]={part}
        end
        widths={available}
    end
    local header = d.style==5 and table.remove(rows,1) or nil
    local captionH=d.caption~="" and pixels+6 or 0
    local headerH=header and pixels or 0
    local pitch=list and rowH or pixels
    local inputExtra=math.floor(rowH*1.6+14)
    local fixed=captionH+headerH+(list and 45 or 55)+(input and inputExtra or 0)
    local area=list and clamp(#rows*pitch+12,200,400) or math.max(pitch,#rows*pitch)
    area=math.min(area,math.max(pitch,sh-fixed-12))
    local count=math.max(1,math.floor((area-(list and 12 or 0))/pitch))
    local h=fixed+area
    local x,y=math.floor(sw/2)-math.floor(w/2),math.floor(sh/2)-math.floor(h/2)
    layout={sw=sw,sh=sh,x=x,y=y,w=w,h=h,rows=rows,widths=widths,header=header,captionH=captionH,
        top=y+captionH+headerH+(list and 11 or 5),area=area,pitch=pitch,count=count,list=list,input=input,
        bw=bw,buttons=buttons,editY=y+h-54-math.floor(controlFont.height*1.5),editH=14+math.floor(controlFont.height*1.5)}
    first=clamp(first,1,math.max(1,#rows-count+1))
    if edit then
        guiSetPosition(edit,x+5,layout.editY,false)
        guiSetSize(edit,w-10,layout.editH,false)
    end
end

local function close(replacing)
    if not dialog then return end
    if isElement(edit) then destroyElement(edit) end
    if not replacing then
        if inputMode then guiSetInputMode(inputMode) end
        inputMode=nil
        setDialogCursorVisible("dialog",false)
    end
    dialog,layout,edit,dragging,pressedButton=nil,nil,nil,nil,nil
end

function setPlayerDialog(data)
    local replacing=dialog and data
    close(replacing)
    if not data then return true end
    if not replacing then
        inputMode=guiGetInputMode()
        setDialogCursorVisible("dialog",true)
    end
    guiSetInputMode("no_binds")
    dialog=data
    dialog.caller=getResourceRootElement(sourceResource)
    first,selected,focus=1,1,1
    if data.style==1 or data.style==3 then
        edit=guiCreateEdit(0,0,100,24,"",false)
        guiEditSetMaxLength(edit,128)
        guiEditSetMasked(edit,data.style==3)
        guiSetAlpha(edit,0)
        guiBringToFront(edit)
        guiFocus(edit)
    end
    arrange()
    return true
end

function isPlayerDialogVisible() return dialog~=nil end
local function submit(response)
    local token,caller=dialog.token,dialog.caller
    local item=layout.list and layout.rows[selected] and selected-1 or -1
    local input=edit and guiGetText(edit) or ""
    close()
    triggerEvent("onClientDialogResponse",caller,token,response,item,input)
end

local function buttonX(l,i)
    return l.x+(l.w-l.bw*l.buttons-20*(l.buttons-1))/2+(i-1)*(l.bw+20)
end
local function drawCells(cells,y,isHeader)
    local outlined=isHeader or not layout.list
    local x=layout.x+(layout.list and 16 or 20)
    for i,w in ipairs(layout.widths) do
        label(cells[i] or "",x,y,layout.list and w-3 or w,outlined and bodyColor or white,outlined and "outline",outlined and bodyFont or font)
        x=x+w
    end
end

local function scrollMetrics()
    local l=layout
    local arrow=l.list and 16 or 0
    local y=l.list and l.top-6 or l.top
    local track=l.area-2*arrow
    local thumb=math.max(12,track*l.count/math.max(l.count,#l.rows))
    return y,arrow,track,thumb
end

local function moveThumb(pixel)
    local y,arrow,track,thumb=scrollMetrics()
    local fraction=clamp((pixel-y-arrow-dragging)/math.max(1,track-thumb),0,1)
    first=1+math.floor(fraction*(#layout.rows-layout.count)+0.5)
end

addEventHandler("onClientRender",root,function()
    if not dialog then return end
    local sw,sh=guiGetScreenSize()
    if layout.sw~=sw or layout.sh~=sh then arrange() end
    local l=layout
    panel(l.x,l.y,l.w,l.h)
    if l.captionH>0 then
        sprite(l.x,l.y,l.w,l.captionH,17,269,224,18,tocolor(10,10,10,200))
        label(dialog.caption,l.x+5,l.y+1,l.w-10,tocolor(210,210,210),true)
    end
    if l.header then drawCells(l.header,l.y+l.captionH+3,true) end
    if l.list then sprite(l.x+5,l.top-6,l.w-26,l.area,13,124,228,141) end
    for j=0,l.count-1 do
        local i=first+j
        if l.rows[i] then
            local y=l.top+j*l.pitch
            if l.list and selected==i then sprite(l.x+11,y,l.w-38,rowH,17,269,224,18,tocolor(185,34,40,255)) end
            drawCells(l.rows[i],y)
        end
    end
    local mx,my=cursor()
    if l.list or #l.rows>l.count then
        local y,arrow,track,thumb=scrollMetrics()
        local x=l.x+l.w-21
        drawScrollPart("track",x,y+arrow,16,track)
        if arrow>0 then
            drawScrollPart("back",x,y,16,arrow)
            drawScrollPart("forward",x,y+arrow+track,16,arrow)
        end
        if #l.rows>l.count then
            if dragging then moveThumb(my) end
            local pos=(track-thumb)*(first-1)/(#l.rows-l.count)
            drawScrollPart("thumb",x,y+arrow+pos,16,thumb)
        end
    end
    if edit then
        local y=l.editY
        drawEditFrame(l.x+5,y,l.w-10,l.editH)
        local value=guiGetText(edit)
        local caret=guiEditGetCaretIndex(edit) or utf8.len(value)
        if dialog.style==3 then value=string.rep("*",utf8.len(value)) end
        local prefix=utf8.sub(value,1,caret)
        local left=l.x+14
        while dialogTextWidth(prefix,controlFont)>l.w-28 do
            value=utf8.sub(value,2); prefix=utf8.sub(prefix,2)
        end
        dxDrawText(fitDialogText(value,l.w-28,controlFont),left,y,l.x+l.w-14,y+l.editH,white,controlFont.scale,controlFont.face,"left","center",false)
        if getTickCount()%1000<550 then dxDrawRectangle(left+dialogTextWidth(prefix,controlFont),y+(l.editH-controlFont.height)/2,1,controlFont.height,white) end
    end
    for i=1,l.buttons do
        local x,y=buttonX(l,i),l.y+l.h-35
        local hot=inside(mx,my,x,y,l.bw,30)
        local pressed=pressedButton==i and hot
        if pressed then x,y=x+1,y+2 elseif hot then x,y=x-1,y-2 end
        local tint=pressed and tocolor(149,176,208) or hot and tocolor(185,34,40) or tocolor(255,255,255,200)
        sprite(x,y,l.bw,30,0,0,136,54,tint)
        if focus==i and not hot then sprite(x,y,l.bw,30,0,0,136,54,tocolor(255,255,255,200)) end
        local caption=i==1 and dialog.button1 or dialog.button2
        local visible=fitDialogText(plain(caption),l.bw-6,controlFont)
        local width=dialogTextWidth(visible,controlFont)
        label(caption,x+(l.bw-width)/2,y+(30-controlFont.height)/2,l.bw-6,
            hot and white or tocolor(200,200,200),false,controlFont)
    end
end)

addEventHandler("onClientKey",root,function(key,down)
    if not dialog or not down or isConsoleActive() or isMainMenuActive() then return end
    local l=layout
    if key=="escape" then cancelEvent(); submit(0); return end
    if key=="enter" or key=="num_enter" then cancelEvent(); submit(focus==1 and 1 or 0); return end
    if key=="tab" then cancelEvent(); focus=focus%l.buttons+1; return end
    local step=({arrow_u=-1,arrow_d=1,pgup=-l.count,pgdn=l.count,home=-#l.rows,["end"]=#l.rows})[key]
    if step and l.list then
        selected=clamp(selected+step,1,#l.rows)
        first=clamp(first,selected-l.count+1,selected)
    elseif key=="mouse_wheel_up" or key=="mouse_wheel_down" then
        first=clamp(first+(key=="mouse_wheel_up" and -3 or 3),1,math.max(1,#l.rows-l.count+1))
    else return end
    cancelEvent()
end,true,"high")

addEventHandler("onClientClick",root,function(button,state,x,y)
    if not dialog or button~="left" then return end
    local l=layout
    if state=="up" then
        local i=pressedButton
        pressedButton,dragging=nil,false
        if i and inside(x,y,buttonX(l,i),l.y+l.h-35,l.bw,30) then submit(i==1 and 1 or 0) end
        return
    end
    for i=1,l.buttons do
        if inside(x,y,buttonX(l,i),l.y+l.h-35,l.bw,30) then pressedButton,focus=i,i; return end
    end
    local barY,arrow,track,thumb=scrollMetrics()
    if inside(x,y,l.x+l.w-21,barY,16,l.area) and (l.list or #l.rows>l.count) then
        local maxFirst=math.max(1,#l.rows-l.count+1)
        if maxFirst==1 then return end
        local offset=y-barY-arrow
        local pos=(track-thumb)*(first-1)/(maxFirst-1)
        if offset<0 then first=math.max(1,first-1)
        elseif offset>=track then first=math.min(maxFirst,first+1)
        elseif offset<pos then first=math.max(1,first-l.count)
        elseif offset>=pos+thumb then first=math.min(maxFirst,first+l.count)
        else dragging=offset-pos end
        return
    end
    if l.list and inside(x,y,l.x+8,l.top,l.w-32,math.min(l.count,#l.rows-first+1)*rowH) then
        selected=first+math.floor((y-l.top)/rowH)
    elseif edit then guiFocus(edit) end
end)

addEventHandler("onClientDoubleClick",root,function(button,x,y)
    local l=layout
    if l and l.list and button=="left" and inside(x,y,l.x+8,l.top,l.w-32,math.min(l.count,#l.rows)*rowH) then submit(1) end
end)
addEventHandler("onClientResourceStop",root,function()
    if dialog and (source==dialog.caller or source==resourceRoot) then close() end
end)

