local block="vcs_service"
local key="mission:servicePose"
local durations={oj_swim_wave=1200,oj_heli_wave=1200,oj_rescue_ped=1500,
    amb_ls_thw_float=1267,amb_ls_thw_floatl=1433}
local active={}
local library,clock,bestLatency

function MissionVisualElapsed(start)
    if not clock then return end
    local elapsed=(getTickCount()+clock-start)%4294967296
    return elapsed<=2147483647 and elapsed or 0
end

local function play(ped)
    if getElementType(ped)~="ped" or not library or not isElementStreamedIn(ped) then return end
    local pose=getElementData(ped,key,false)
    if type(pose)~="table" or type(pose[2])~="number" then
        if active[ped] then setPedAnimation(ped); active[ped]=nil end
        return
    end
    local clip,start=pose[1],pose[2]
    local duration=durations[clip]
    if not duration then return end
    local elapsed=MissionVisualElapsed(start) or 0
    local loop=clip:sub(1,3)=="oj_"
    if not loop and elapsed>=duration then
        if active[ped] then setPedAnimation(ped); active[ped]=nil end
        return
    end
    if setPedAnimation(ped,block,clip,loop and -1 or duration-elapsed,loop,false,false,false) then
        active[ped]=true
        if elapsed>0 then setPedAnimationProgress(ped,clip,(elapsed%duration)/duration) end
    end
end

local function observe()
    if getElementType(source)=="ped" and getElementData(source,key,false) then play(source) end
end
addEventHandler("onClientElementStreamIn",root,observe)
addEventHandler("onClientElementDataChange",root,function(name)
    if name==key then play(source) end
end)
addEventHandler("onClientElementStreamOut",root,function() active[source]=nil end)
addEventHandler("onClientElementDestroy",root,function() active[source]=nil end)
addEvent("mission:poseClockReply",true)
addEventHandler("mission:poseClockReply",resourceRoot,function(sent,server)
    local now=getTickCount()
    local latency=(now-sent)%4294967296
    if bestLatency and latency>=bestLatency then return end
    local first=not clock
    bestLatency,clock=latency,server+latency/2-now
    if not first then return end
    for _,ped in ipairs(getElementsByType("ped",root,true)) do
        if getElementData(ped,key,false) then play(ped) end
    end
end,false)
addEventHandler("onClientResourceStart",resourceRoot,function()
    library=engineLoadIFP("assets/service_animations.ifp",block)
    if library then
        local function sample() triggerServerEvent("mission:poseClock",resourceRoot,getTickCount()) end
        sample()
        -- Initial resource streaming can delay the first reply.
        setTimer(sample,2000,4)
    end
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for ped in pairs(active) do if isElement(ped) then setPedAnimation(ped) end end
end)
