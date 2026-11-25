local style = {size = 18, align = "right", panel = true, accent = true, maxLines = 1}

function showRacePos(position, total, time)
    if position == nil or total == nil or time == nil then return false end
    return Hud.set("race", ("%s / %s  ·  %s"):format(tostring(position), tostring(total), tostring(time)), nil, style)
end

function hideRacePos()
    return Hud.clear("race")
end

Hud.onRender(function(screen, now)
    local entry, opacity = Hud.message("race", now)
    if entry then
        Hud.text(screen, entry, screen.width - screen.margin - 10, screen.height * 0.265, 225, opacity)
    end
end)

-- RACEHUB_14643 replaces the route mesh on a fixed, one-by-two metre map board.
-- The images retain the original board texture and the selected model's triangles.
local boards = {
    mainla={x=-1050.625,y=-794.385,z=12.421},
    beach={x=248.529+0.05*math.cos(math.rad(-15)),y=-304.109+0.05*math.sin(math.rad(-15)),z=12.421},
}
local preview

local function releaseBoard(board)
    if isElement(board.object) then destroyElement(board.object) end
    if board.model then engineFreeModel(board.model) end
    if isElement(board.dff) then destroyElement(board.dff) end
    if isElement(board.txd) then destroyElement(board.txd) end
end

local function createBoard(board)
    local model=engineRequestModel("object")
    if not model then return end
    board.model=model
    board.txd=engineLoadTXD("res/race/route.txd")
    board.dff=engineLoadDFF("res/race/"..board.original..".dff")
    if not board.txd or not engineImportTXD(board.txd,model)
        or not board.dff or not engineReplaceModel(board.dff,model,true) then return end
    local p=boards[board.board]
    local mainland=board.board=="mainla"
    local angle=math.rad(75)
    local normalX,normalY=mainland and -1 or math.sin(angle),mainland and 0 or -math.cos(angle)
    local position={p.x+0.08*normalX,p.y+0.08*normalY,p.z,1}
    board.object=createObject(model,position[1],position[2],position[3])
    if board.object then
        -- The converted mainland mesh stores vertical along local Y, beach along Z.
        local matrix=mainland and {{-1,0,0,0},{0,0,1,0},{0,1,0,0},position}
            or {{math.cos(angle),math.sin(angle),0,0},{-math.sin(angle),math.cos(angle),0,0},{0,0,1,0},position}
        setElementMatrix(board.object,matrix)
    end
    if board.object then
        setElementCollisionsEnabled(board.object,false)
        setElementDoubleSided(board.object,true)
        setElementDimension(board.object,getElementDimension(localPlayer))
        setElementInterior(board.object,getElementInterior(localPlayer))
    end
end
local positions={"1st","2nd","3rd","4th"}

function Hud.racePreviewActive() return preview~=nil end

local function releasePreview()
    if not preview then return end
    if preview.restoreAreaName then setPlayerHudComponentVisible("area_name",true) end
    releaseBoard(preview)
    if isElement(preview.map) then destroyElement(preview.map) end
    if isElement(preview.route) then destroyElement(preview.route) end
    preview=nil
end

function showRaceCoursePreview(course)
    local owner=Hud.owner()
    if preview and preview.owner~=owner then return false end
    if course==false then releasePreview() return true end
    if type(course)~="table" or not boards[course.board] or type(course.key)~="string"
        or type(course.model)~="number" or course.model%1~=0 or course.model<7473 or course.model>7489
        or not course.key:match("^RACTIT[1-8BC]$") or type(course.name)~="string" or type(course.kind)~="string"
        or type(course.number)~="number" or type(course.fee)~="number" or type(course.prize)~="number"
        or type(course.laps)~="number" or (course.time and type(course.time)~="number") then return false end
    local map=preview and preview.board==course.board and preview.map
    if not map then map=dxCreateTexture("res/race/racemap_"..course.board..".png","argb",false,"clamp") end
    local route=dxCreateTexture("res/race/route_"..course.key..".png","argb",false,"clamp")
    if not map or not route then
        if isElement(route) then destroyElement(route) end
        if isElement(map) and (not preview or map~=preview.map) then destroyElement(map) end
        releasePreview()
        return false
    end
    if preview then
        releaseBoard(preview)
        if preview.map~=map then destroyElement(preview.map) end
        destroyElement(preview.route)
    end
    local best=course.time and ("%d:%02d"):format(math.floor(course.time/60000),math.floor(course.time/1000)%60) or "N/A"
    local lines={
        {75,0.8,"Race "..course.number}, {93,0.5,"Entrance Fee: $"..course.fee},
        {105,0.5,"Reward: $"..course.prize}, {130,0.5,"Race type: "..course.kind},
        {142,0.5,"Laps: "..course.laps}, {180,0.6,"Best Result: "..(positions[course.position] or "N/A")},
        {195,0.6,"Best Time: "..best},{230,0.8,course.name},
    }
    for _,line in ipairs(lines) do line.entry={text=line[3],style={nativeScale=line[2]}} end
    local restoreAreaName=preview and preview.restoreAreaName or isPlayerHudComponentVisible("area_name")
    if restoreAreaName then setPlayerHudComponentVisible("area_name",false) end
    preview={owner=owner,map=map,route=route,board=course.board,original=course.model,lines=lines,restoreAreaName=restoreAreaName}
    createBoard(preview)
    return true
end

-- Draw the board beneath frontend help, at the perspective size of the SCM prop.
addEventHandler("onClientRender",root,function()
    if not preview or not Hud.baseUiVisible() then return end
    local p=boards[preview.board]
    if isElement(preview.object) then
        -- Keep the board backing just behind the selected mesh.
        local cx,cy=getCameraMatrix()
        local dx,dy=cx-p.x,cy-p.y
        local length=math.max(0.01,math.sqrt(dx*dx+dy*dy))
        local bx,by=p.x-0.06*dx/length,p.y-0.06*dy/length
        dxDrawMaterialLine3D(bx,by,p.z+1,bx,by,p.z-1,preview.map,1,tocolor(255,255,255),false,cx,cy,p.z)
        return
    end
    local x,top=getScreenFromWorldPosition(p.x,p.y,p.z+1,1)
    local _,bottom=getScreenFromWorldPosition(p.x,p.y,p.z-1,1)
    if not x or not bottom or bottom<=top then return end
    local height=bottom-top
    local width=height/2
    dxDrawImage(x-width/2,top,width,height,preview.map)
    dxDrawImage(x-width/2,top,width,height,preview.route)
end,true,"high")

Hud.onRender(function(screen)
    if not preview then return end
    local _,sx,sy=CWidescreenSupport:playerHud()
    for _,line in ipairs(preview.lines) do
        Hud.text(screen,line.entry,20*sx/screen.scale,line[1]*sy/screen.scale,
            screen.width*0.42,1)
    end
end,"racePreview")

addEventHandler("onClientResourceStop",root,function(resource)
    if preview and (resource==getThisResource() or preview.owner==getResourceName(resource)) then releasePreview() end
end)
