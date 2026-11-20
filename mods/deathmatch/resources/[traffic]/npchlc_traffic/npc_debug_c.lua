TrafficNPCDebug = {}
local hlc = exports.npc_hlc
local timer, generation, rows, details = nil, 0, {}, {}
local drivingStyles={
    [0]="Stop for cars", "Slow down for cars", "Avoid cars", "Plough through",
    "Stop for cars, ignore lights", "Avoid cars, obey lights", "Avoid cars, stop for peds, obey lights"
}
local palettes = {}
local function palette(alpha)
    if not palettes[alpha] then
        local function tint(r,g,b,opacity)
            return tocolor(r,g,b,math.floor(alpha*(opacity or 255)/255))
        end
        palettes[alpha] = {
            white=tint(255,255,255), dark=tint(14,10,10,235), red=tint(255,80,80), green=tint(117,233,136),
            blood=tint(175,25,30), empty=tint(55,26,26), route=tint(60,235,255,230),
            continuation=tint(165,240,245,165)
        }
    end
    return palettes[alpha]
end

local function update()
    local px,py,pz=getElementPosition(localPlayer)
    local visible={}
    for _,ped in ipairs(getElementsByType("ped",resourceRoot,true)) do
        if isElementOnScreen(ped) and TrafficNPCDebugRange.alpha(ped,localPlayer,px,py,pz)>0 then
            visible[#visible+1]=ped
        end
    end
    triggerServerEvent("npchlc_traffic:npcDebugWatch",resourceRoot,generation,visible)
end

function TrafficNPCDebug.start()
    generation=generation+1
    timer=setTimer(update,200,0)
    update()
end

function TrafficNPCDebug.stop()
    if timer then killTimer(timer) end
    timer,rows,details=nil,{},{}
    triggerServerEvent("npchlc_traffic:npcDebugWatch",resourceRoot,generation,false)
end

addEvent("npchlc_traffic:npcDebugRows",true)
addEventHandler("npchlc_traffic:npcDebugRows",resourceRoot,function(epoch,nextRows)
    if not timer or epoch~=generation then return end
    local current={}
    for _,row in ipairs(nextRows) do
        local ped=row[1]
        current[ped]=row
        if not rows[ped] or rows[ped][2]~=row[2] or rows[ped][8]~=row[8] then details[ped]=nil end
    end
    for ped in pairs(rows) do if not current[ped] then details[ped]=nil end end
    rows=current
end,false)

addEvent("npchlc_traffic:npcDebugRevision",true)
addEventHandler("npchlc_traffic:npcDebugRevision",resourceRoot,function(epoch,ped,revision,task,owner,style,vehicle)
    local row=rows[ped]
    if timer and epoch==generation and row and revision>row[2] then
        row[2],row[7],row[8],row[10]=revision,task,owner,false
        row[11],row[12]=style,vehicle
        details[ped]=nil
    end
end,false)

local function forget() rows[source],details[source]=nil,nil end
addEventHandler("onClientElementStreamOut",root,forget)
addEventHandler("onClientElementDestroy",root,forget)

addEvent("npchlc_traffic:npcDebugSample",true)
addEventHandler("npchlc_traffic:npcDebugSample",resourceRoot,function(viewer,epoch,entries)
    local result={}
    for _,entry in ipairs(entries) do
        local sample=hlc:getNPCDebugExecution(entry[1],entry[2])
        result[#result+1]={entry[1],entry[2],sample or false}
    end
    -- Include stopped executors so observers can immediately drop old targets.
    if isElement(viewer) then triggerServerEvent("npchlc_traffic:npcDebugReport",resourceRoot,viewer,epoch,result) end
end,false)

addEvent("npchlc_traffic:npcDebugDetails",true)
addEventHandler("npchlc_traffic:npcDebugDetails",resourceRoot,function(epoch,entries)
    if not timer or epoch~=generation then return end
    for _,entry in ipairs(entries) do
        local row=rows[entry[1]]
        if row and row[2]==entry[2] then details[entry[1]]={entry[3],getTickCount()} end
    end
end,false)

local function target(ped,sample,colors)
    if not sample or not sample[3] then return end
    local x,y,z=getElementPosition(ped)
    local a,b,c=sample[3],sample[4],sample[5] or z
    c=c+0.15
    dxDrawLine3D(x,y,z-0.45,a,b,c,colors.route,2)
    dxDrawLine3D(a-0.24,b,c,a+0.24,b,c,colors.route,2)
    dxDrawLine3D(a,b-0.24,c,a,b+0.24,c,colors.route,2)
    if sample[6] then
        local dx,dy,dz=sample[6]-a,sample[7]-b,(sample[8] or z)+0.15-c
        local count=math.min(32,math.max(1,math.ceil(math.sqrt(dx*dx+dy*dy+dz*dz))))
        for i=0,count-1 do
            local u,v=i/count,(i+0.55)/count
            dxDrawLine3D(a+dx*u,b+dy*u,c+dz*u,a+dx*v,b+dy*v,c+dz*v,colors.continuation,1)
        end
    end
end

local function bar(x,y,value,maximum,color,colors)
    dxDrawRectangle(x-26,y,52,7,colors.dark)
    dxDrawRectangle(x-25,y+1,50,5,colors.empty)
    dxDrawRectangle(x-25,y+1,50*math.max(0,math.min(1,value/maximum)),5,color)
end

local function syncStatus(row,sample)
    if row[14]=="active" then return "Sync: native executor",true end
    if row[14]=="blocked" then return "Sync: waiting for server retry",false end
    if row[14]=="pending" then return "Sync: waiting for executor",false end
    if row[5]=="dead" or not row[7] then return "Sync: idle",true end
    if sample then
        if sample[9] then return "Sync: waiting for server",false end
        if not row[8] then return "Sync: server",true end
        return "Sync: synchronized",true
    end
    if row[8] then return "Sync: waiting for executor",false end
    return "Sync: waiting for server",false
end

local function drawLabel(labels,ped,row,x,bottom,caption,sample,colors)
    local style,vehicle=row[11],row[12]
    local driver=type(style)=="number" and isElement(vehicle) and getPedOccupiedVehicle(ped)==vehicle
        and getVehicleOccupant(vehicle,0)==ped
    local top=bottom-(driver and 89 or 75)
    labels[#labels+1]={"["..(row[13] or "UNKNOWN").."]",x,top,colors.white,"center",1,colors.dark}
    top=top+14
    local hot=row[3]>row[4]
    local temper=(hot and "Hot temper " or "Temper ")..row[3]
    local fear="  Fear "..row[4]
    local w1,w2=dxGetTextWidth(temper,1,"default-bold"),dxGetTextWidth(fear,1,"default-bold")
    labels[#labels+1]={temper,x-w2/2,top,hot and colors.red or colors.white,"center",1,colors.dark}
    labels[#labels+1]={fear,x+w1/2,top,colors.white,"center",1,colors.dark}
    if driver then
        top=top+14
        local label="Driving style "..style
        if drivingStyles[style] then label=label.." - "..drivingStyles[style] end
        labels[#labels+1]={label,x,top,colors.white,"center",1,colors.dark}
    end
    labels[#labels+1]={caption,x,top+14,colors.white,"center",1,colors.dark}
    local status,ready=syncStatus(row,sample)
    labels[#labels+1]={status,x,top+28,ready and colors.green or colors.red,"center",1,colors.dark}
    local armor=getPedArmor(ped) or 0
    if armor>0 then bar(x,bottom-15,armor,100,colors.white,colors) end
    bar(x,bottom-7,getElementHealth(ped) or 0,row[9],colors.blood,colors)
end

function TrafficNPCDebug.draw()
    local labels={}
    local px,py,pz=getElementPosition(localPlayer)
    for ped,row in pairs(rows) do
        local alpha = isElement(ped) and isElementStreamedIn(ped) and TrafficNPCDebugRange.alpha(ped,localPlayer,px,py,pz) or 0
        if alpha>0 and isElementOnScreen(ped) then
            local colors=palette(alpha)
            local hx,hy,hz=getPedBonePosition(ped,8)
            local x,y
            if hx then x,y=getScreenFromWorldPosition(hx,hy,hz+0.2) end
            if x then
                local sample=row[10]
                if row[8]==localPlayer then sample=hlc:getNPCDebugExecution(ped,row[2])
                elseif details[ped] and (getTickCount()-details[ped][2])%4294967296<650 then sample=details[ped][1] end
                local task=sample and sample[1] or row[7]
                local phase=sample and sample[2] or row[6]
                if row[5]=="Road rage" and row[6] then phase=row[6] end
                local caption=row[5]
                if task then caption=caption.." > "..task end
                if phase then caption=caption.." > "..phase end
                target(ped,sample,colors)
                drawLabel(labels,ped,row,x,y,caption,sample,colors)
            end
        end
    end
    if #labels>0 then exports.frontend:drawDebugLabels(labels) end
end
