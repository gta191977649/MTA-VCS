local key = "npchlc_traffic:threatPose"
local poses,revision = {},{}
local streetBlock = TrafficAnimationBanks.street
local allowed = {handsup=true,handscower=true,idle_tired=true,roadcross=true}
local gunpoint = {handsup="handsup_wait",handscower="handscower_wait"}

local function stopPose(ped)
    local owned = poses[ped]
    if not owned then return end
    poses[ped],revision[ped] = nil,nil
    local block,clip = getPedAnimation(ped)
    -- A finished named task can leave its frozen association on the skeleton.
    -- Clear it even when MTA no longer reports a named animation.
    if not block or (block:lower()==streetBlock and clip and clip:lower()==owned) then
        setPedAnimation(ped)
    end
end

local function refresh(ped)
    local data = getElementData(ped,key,false)
    if data and isElementStreamedIn(ped) then
        local clip = data[1]
        if not allowed[clip] then return end
        local waitClip = gunpoint[clip]
        if setPedAnimation(ped,streetBlock,waitClip or clip,data[3] or -1,not waitClip,false,false,not waitClip,120) then
            poses[ped],revision[ped] = waitClip or clip,waitClip and data[2]
        end
    else
        stopPose(ped)
    end
end
addEventHandler("onClientElementDataChange",root,function(name) if name == key then refresh(source) end end)
addEventHandler("onClientElementStreamIn",root,function() if getElementType(source) == "ped" then refresh(source) end end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,ped in ipairs(getElementsByType("ped",root,true)) do refresh(ped) end
end)
addEventHandler("onClientElementDestroy",root,function() poses[source],revision[source]=nil,nil end)
addEventHandler("onClientElementStreamOut",root,function() stopPose(source) end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for ped in pairs(poses) do stopPose(ped) end
end)
addEvent("npchlc_traffic:cashGround",true)
addEventHandler("npchlc_traffic:cashGround",resourceRoot,function(ped,id,points)
    if not isElement(ped) or not isElementStreamedIn(ped) then return end
    local heights = {}
    for i,p in ipairs(points) do
        local hit,_,_,z=processLineOfSight(p[1],p[2],p[3]+1.5,p[1],p[2],p[3]-2,true,false,false,true,false)
        heights[i] = hit and z or false
    end
    triggerServerEvent("npchlc_traffic:cashGroundReply",resourceRoot,ped,id,heights)
end)

setTimer(function()
    for ped,clip in pairs(poses) do
        if not isElementStreamedIn(ped) then
            stopPose(ped)
        elseif revision[ped] and isElementSyncer(ped) then
            local block,name = getPedAnimation(ped)
            if not name or name:lower()~=clip or not block or block:lower()~=streetBlock then
                triggerServerEvent("npchlc_traffic:threatPoseEnded",resourceRoot,ped,revision[ped])
                revision[ped] = nil
            end
        end
    end
end,350,0)
