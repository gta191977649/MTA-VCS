local active, ready = {}, {}
local serial = 0

-- R5 uses 256-byte line buffers, four tab stops and 128-byte response strings.
-- Keep UTF-8 code points intact when applying the native byte limits in MTA.
local function bytePrefix(value,limit)
    if #value<=limit then return value end
    local nextByte=value:byte(limit+1)
    while limit>0 and nextByte>=128 and nextByte<192 do
        limit=limit-1
        nextByte=value:byte(limit+1)
    end
    return value:sub(1,limit)
end

local function listRows(info,style)
    local rows,columns={},nil
    for line in (info:gsub("\r","").."\n"):gmatch("(.-)\n") do
        while #line>0 do
            local part=bytePrefix(line,256)
            line=line:sub(#part+1)
            local cells={}
            if style==2 then cells[1]=part
            else
                for value in part:gmatch("[^\t]+") do
                    if #cells==(columns or 4) then break end
                    cells[#cells+1]=bytePrefix(value,128)
                end
                columns=columns or math.max(1,#cells)
            end
            rows[#rows+1]=cells
        end
    end
    return rows
end

function GetPlayerDialogID(player)
    return active[player] and active[player].id or -1
end

function IsPlayerUsingDialog(player)
    return active[player] ~= nil
end

function GetPlayerDialogData(player)
    local d = active[player]
    if not d then return false end
    return d.id, d.style, d.caption, d.info, d.button1, d.button2
end

function HidePlayerDialog(player)
    if not active[player] then return false end
    active[player] = nil
    if ready[player] then triggerClientEvent(player, "samp:display", resourceRoot, false) end
    return true
end

function ShowPlayerDialog(player, id, style, caption, info, button1, button2)
    if not isElement(player) or getElementType(player) ~= "player" then return false end
    if type(id)=="number" and id<0 and id==math.floor(id) then return HidePlayerDialog(player) end
    if type(id) ~= "number" or id ~= math.floor(id) or id < 0 or id > 32767 then return false end
    if type(style) ~= "number" or style ~= math.floor(style) or style < 0 or style > 5 then return false end
    button2 = button2 or ""
    if type(caption) ~= "string" or type(info) ~= "string" or type(button1) ~= "string" or type(button2) ~= "string" then return false end
    serial = serial + 1
    local d = {id=id, style=style, caption=bytePrefix(caption,64), info=info, button1=button1, button2=button2, token=serial}
    if style==2 or style>=4 then d.items=listRows(info,style) end
    active[player] = d
    d.owner = getResourceRootElement(sourceResource or getThisResource())
    if ready[player] then triggerClientEvent(player, "samp:display", resourceRoot, d) end
    return true
end

addEvent("samp:ready", true)
addEventHandler("samp:ready", resourceRoot, function()
    if not client or ready[client] then return end
    ready[client] = true
    if active[client] then triggerClientEvent(client, "samp:display", resourceRoot, active[client]) end
end, false)

addEvent("onPlayerDialogResponse", false)
addEvent("samp:submit", true)
addEventHandler("samp:submit", resourceRoot, function(token, response, item, input)
    local d = active[client]
    if not d or token ~= d.token or (response ~= 0 and response ~= 1) then return end
    if d.style == 2 or d.style >= 4 then
        if type(item) ~= "number" or item ~= math.floor(item) or item < -1 then return end
        local first=d.style==5 and 2 or 1
        local selected=item>=0 and d.items[first+item]
        if item==-1 and #d.items>=first or item>=0 and not selected then return end
        input=bytePrefix(selected and selected[1] or "",128):gsub("{%x%x%x%x%x%x}","")
    else
        item = -1
        if d.style == 1 or d.style == 3 then
            if type(input) ~= "string" or #input > 512 then return end
            input=bytePrefix(input,128)
        else input = "" end
    end
    active[client] = nil
    triggerEvent("onPlayerDialogResponse", d.owner, client, d.id, response, item, input)
end, false)

addEventHandler("onPlayerQuit", root, function() active[source], ready[source] = nil, nil end)
addEventHandler("onResourceStop", root, function()
    for player, d in pairs(active) do
        if source == d.owner then HidePlayerDialog(player) end
    end
end)
