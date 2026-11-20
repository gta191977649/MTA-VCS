local hlc = exports.npc_hlc
local viewers = {}
local requestTime = {}

local function nearby(ped, viewer)
    return isElement(ped) and getElementType(ped) == "ped"
        and TrafficNPCDebugRange.alpha(ped, viewer, getElementPosition(viewer)) > 0
end

local function describe(ped,brain)
    if isPedDead(ped) then return "dead" end
    if brain and (brain.wait==0x11 or brain.wait==0x12) then
        return "gunpoint",brain.wait==0x11 and "handsup" or "handscower"
    end
    local event = brain and (brain.objectives.current or brain.event)
    if event and event.intent=="flee" and event.probe and not event.task then
        return "flee","Awaiting route"
    end
    if event and (event.intent or event.order) then return event.intent or event.order,event.task end
    local kind,phase = PedActivity.debugTask(ped)
    if kind then return kind,phase end
    if isPedInVehicle(ped) then return getPedOccupiedVehicleSeat(ped)==0 and "driver" or "passenger" end
    return TrafficAmbient.debugTask(ped)
end

addEvent("npchlc_traffic:npcDebugWatch",true)
addEventHandler("npchlc_traffic:npcDebugWatch",resourceRoot,function(generation,peds)
    if not client or type(generation)~="number" then return end
    if peds==false then viewers[client]=nil return end
    if type(peds)~="table" then return end
    local now=getTickCount()
    if requestTime[client] and (now-requestTime[client])%4294967296<150 then return end
    requestTime[client]=now
    local watch,rows,owners={},{},{}
    viewers[client]={generation=generation,watch=watch}
    for i=1,math.min(#peds,1024) do
        local ped=peds[i]
        if nearby(ped,client) and not watch[ped] then
            local brain=PedAI.brain(ped)
            if brain or getElementParent(ped)==getResourceDynamicElementRoot(getThisResource()) then
                local task,revision,owner,fallback=hlc:getNPCDebugAssignment(ped)
                local kind,phase=describe(ped,brain)
                local profile=brain and brain.profile or PedAIRules.profile(getElementData(ped,"npchlc_traffic:originalModel",false))
                local entry={ped,revision or 0}
                watch[ped]=entry
                rows[#rows+1]={ped,revision or 0,profile.temper,profile.fear,kind or "idle",
                    type(phase)=="string" and phase or false,task or false,owner or false,
                    getElementData(ped,"npchlc_traffic:spawnHealth",false) or 100,fallback or false}
                if owner and owner~=client then
                    owners[owner]=owners[owner] or {}
                    table.insert(owners[owner],entry)
                end
            end
        end
    end
    triggerClientEvent(client,"npchlc_traffic:npcDebugRows",resourceRoot,generation,rows)
    for owner,entries in pairs(owners) do
        triggerClientEvent(owner,"npchlc_traffic:npcDebugSample",resourceRoot,client,generation,entries)
    end
end,false)

local function validDetail(detail)
    if type(detail)~="table" or type(detail[1])~="string" or #detail[1]>60 then return false end
    if detail[2]~=false and (type(detail[2])~="string" or #detail[2]>64) then return false end
    for i=3,8 do
        local n=detail[i]
        if n~=false and (type(n)~="number" or not (math.abs(n)<100000)) then return false end
    end
    return (detail[3]==false)==(detail[4]==false) and (detail[6]==false)==(detail[7]==false)
end

addEvent("npchlc_traffic:npcDebugReport",true)
addEventHandler("npchlc_traffic:npcDebugReport",resourceRoot,function(viewer,generation,rows)
    local sub=viewers[viewer]
    if not client or not sub or generation~=sub.generation or type(rows)~="table" then return end
    local accepted={}
    for i=1,math.min(#rows,1024) do
        local row=rows[i]
        local entry=type(row)=="table" and sub.watch[row[1]]
        if entry and not entry.sent and row[2]==entry[2] and nearby(row[1],viewer) then
            local _,revision,owner=hlc:getNPCDebugAssignment(row[1])
            if owner==client and revision==row[2] and (row[3]==false or validDetail(row[3])) then
                entry.sent=true
                local detail=row[3]
                accepted[#accepted+1]={row[1],revision,detail and {unpack(detail,1,8)} or false}
            end
        end
    end
    if #accepted>0 then triggerClientEvent(viewer,"npchlc_traffic:npcDebugDetails",resourceRoot,generation,accepted) end
end,false)

addEventHandler("npc_hlc:debugAssignmentChanged",root,function(revision,task,owner)
    for viewer,sub in pairs(viewers) do
        if (getTickCount()-requestTime[viewer])%4294967296>1500 then
            viewers[viewer]=nil
        elseif sub.watch[source] and nearby(source,viewer) then
            sub.watch[source]={source,revision}
            triggerClientEvent(viewer,"npchlc_traffic:npcDebugRevision",resourceRoot,sub.generation,source,revision,task,owner)
        end
    end
end)

addEventHandler("onPlayerQuit",root,function() viewers[source],requestTime[source]=nil,nil end)
