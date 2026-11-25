local function cell(column, element, isTeam)
    local value
    if column.name=="name" then
        if isTeam then value=getTeamName(element).." ("..#getPlayersInTeam(element)..")"
        else value=getPlayerName(element) end
    elseif column.name=="ping" then
        if not isTeam then value=getPlayerPing(element)+(tonumber(getElementData(element,"customping")) or 0) end
    elseif column.name=="id" then value=getElementData(element,"scoreboard:sessionID")
    else
        value=getElementData(element,column.name)
        if column.name=="score" and not isTeam and not value then value=0 end
    end
    if value and type(value)~="table" then value=tostring(value) end
    if column.textFunction then value=column.textFunction(value,element) end
    if column.isImage and type(value)=="string" then return {value} end
    return value or false
end

function buildScoreboardRows(columns,selected,sortBy,teams)
    local function row(element,isTeam)
        local r,g,b
        if isTeam then r,g,b=getTeamColor(element) else r,g,b=getPlayerNametagColor(element) end
        local cells={}
        for i,c in ipairs(columns) do cells[i]=cell(c,element,isTeam) end
        return {element=element,cells=cells,color=tocolor(r,g,b),highlight=selected[element] or element==localPlayer}
    end
    local index
    for i,c in ipairs(columns) do if c.name==sortBy.what then index=i end end
    local function sorted(elements,isTeam)
        local rows={}
        for _,element in ipairs(elements) do rows[#rows+1]=row(element,isTeam) end
        if index then
            local function key(r)
                local v=r.cells[index]
                if type(v)=="table" then v=v[2] or v[1] end
                return tostring(v or ""):lower()
            end
            table.sort(rows,function(a,b)
                local av,bv=key(a),key(b)
                local an,bn=tonumber(av),tonumber(bv)
                if (an~=nil)~=(bn~=nil) then
                    if sortBy.dir==1 then return bn~=nil end
                    return an~=nil
                end
                if an then av,bv=an,bn end
                if sortBy.dir==1 then return av>bv end
                return av<bv
            end)
        elseif not isTeam then
            table.sort(rows,function(a,b)
                if a.element==b.element then return false end
                if a.element==localPlayer then return true end
                if b.element==localPlayer then return false end
                return (tonumber(getElementData(a.element,"scoreboard:sessionID")) or 0) <
                       (tonumber(getElementData(b.element,"scoreboard:sessionID")) or 0)
            end)
        end
        return rows
    end
    local players={}
    for _,p in ipairs(getElementsByType("player")) do
        if not teams or not getPlayerTeam(p) then players[#players+1]=p end
    end
    local rows=sorted(players,false)
    if teams then
        for _,team in ipairs(sorted(getElementsByType("team"),true)) do
            rows[#rows+1]=team
            for _,r in ipairs(sorted(getPlayersInTeam(team.element),false)) do rows[#rows+1]=r end
        end
    end
    return rows
end
