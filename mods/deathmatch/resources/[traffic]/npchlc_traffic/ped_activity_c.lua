local block = TrafficAnimationBanks.activity
local motion = "npchlc_traffic:activityMotion"
local turn = "npchlc_traffic:activityHeading"
local turning, reports = {}, {}
local ifp
local chatClips = {idle_chat="IDLE_chat", xpressscratch="XPRESSscratch"}
local playingChat = {}
local clips = {
    idle_chat=true, idle_hbhb=true, xpressscratch=true, roadcross=true, fucku=true, atm=true, seat_down=true, seat_idle=true, seat_up=true, emp_bar_clean=true,
    emp_bar_idle=true, emp_bar_look=true, sunbathe=true, sunbathe_sit=true,
    sunbathe_to_sit=true, sunbathe_stand=true, beach_lower=true, beach_recline=true,
}

local function apply(ped, catchUp)
    local data = getElementData(ped, motion, false)
    local chat = type(data) == "table" and data[6] == "PED" and chatClips[data[1]]
    if chat or (ifp and type(data) == "table" and clips[data[1]]) then
        playingChat[ped] = chat or nil
        setPedAnimation(ped, chat and "PED" or block, chat or data[1], chat and data[4] or -1,
            data[2], false, false, not chat, 160)
        if catchUp then triggerServerEvent("npchlc_traffic:activityClock",resourceRoot,ped,data[3]) end
    else
        local current, clip = getPedAnimation(ped)
        if current == block or (playingChat[ped] and current and current:lower()=="ped"
            and clip and clip:lower()==playingChat[ped]:lower()) then setPedAnimation(ped) end
        playingChat[ped] = nil
    end
end

addEvent("npchlc_traffic:activityElapsed", true)
addEventHandler("npchlc_traffic:activityElapsed", resourceRoot, function(ped, revision, elapsed)
    if not isElement(ped) or not isElementStreamedIn(ped) then return end
    local data = getElementData(ped,motion,false)
    if data and data[3] == revision and data[4] > 0 then
        local progress = elapsed / data[4]
        if data[2] then progress = progress % 1 end
        setPedAnimationProgress(ped,data[1],math.min(progress,0.9999))
    end
end, false)

addEvent("npchlc_traffic:mugPunch",true)
addEventHandler("npchlc_traffic:mugPunch",resourceRoot,function(ped)
    if ifp and isElement(ped) and isElementStreamedIn(ped) then
        setPedAnimation(ped,block,"punchr",500,false,false,false,false,80)
    end
end,false)

-- Keep the world-space root where walking stopped. The original seat tracks
-- lower and retract bone 0 and restore it on standing, without relocating the ped.
addEventHandler("onClientPreRender", root, function(frameMs)
    for ped, command in pairs(turning) do
        local target = command[1]
        local _,_,facing = getElementRotation(ped)
        local delta = (target - facing + 180) % 360 - 180
        local step = math.min(frameMs,50) * 0.16
        if math.abs(delta) > 0.05 then
            setElementRotation(ped,0,0,facing + math.max(-step,math.min(step,delta)),"default",true)
        end
        if reports[ped] == command[2] and math.abs(delta) <= 1 then
            reports[ped] = nil
            triggerServerEvent("npchlc_traffic:activityTurned",resourceRoot,ped,command[2],facing)
        end
    end
end)

addEvent("npchlc_traffic:activityObserveTurn",true)
addEventHandler("npchlc_traffic:activityObserveTurn",resourceRoot,function(ped,revision)
    if isElement(ped) then reports[ped] = revision end
end,false)

addEventHandler("onClientResourceStart", resourceRoot, function()
    ifp = TrafficAnimationBanks.load(block, "ped_activity/activities.ifp")
    for _, ped in ipairs(getElementsByType("ped", root, true)) do
        turning[ped] = getElementData(ped,turn,false) or nil
        if getElementData(ped, motion, false) then apply(ped,true) end
    end
end)
addEventHandler("onClientElementDataChange", root, function(key)
    if key ~= motion and key ~= turn or getElementType(source) ~= "ped" or not isElementStreamedIn(source) then return end
    if key == turn then turning[source] = getElementData(source,turn,false) or nil
    else apply(source,false) end
end)
addEventHandler("onClientElementStreamIn", root, function()
    if getElementType(source) ~= "ped" then return end
    turning[source] = getElementData(source,turn,false) or nil
    if getElementData(source, motion, false) then apply(source,true) end
end)
addEventHandler("onClientElementStreamOut", root, function() turning[source],reports[source],playingChat[source] = nil,nil,nil end)
addEventHandler("onClientElementDestroy", root, function() turning[source],reports[source],playingChat[source] = nil,nil,nil end)

local function expectedProp(site)
    for _, kind in ipairs({"building","object"}) do
        for _, obj in ipairs(getElementsWithinRange(site[3],site[4],site[5], 0.5,kind) or {}) do
            local id = getElementID(obj)
            if id and id:lower() == site[2] then
                -- createBuilding is a world placement. It has no streaming-compatible
                -- MTA entity; Eagle destroys its element when the map cell unloads.
                if kind == "building" then return obj end
                if isElementStreamedIn(obj) and getElementInterior(obj) == 0 and getElementDimension(obj) == 0
                    and getElementCollisionsEnabled(obj) and (getElementAlpha(obj) or 0) > 0 then return obj end
            end
        end
    end
    return false
end

local function probe(ped, site, initial)
    if not ifp then return false end
    if not isElement(ped) or not isElementStreamedIn(ped) then return "streaming" end
    local x,y,z = site[6],site[7],site[8]
    local beach = site[1] == "beach"
    if not beach and not expectedProp(site) then return false end
    local angle = math.rad(site[9])
    local ahead = site[1] == "seat" and 0.85 or 0
    x,y = x - ahead*math.sin(angle), y + ahead*math.cos(angle)
    local hit,_,_,ground,_,_,_,nz,material = processLineOfSight(x,y,z+1.9,x,y,z-2.0,true,false,false,true,false)
    if not hit or nz < 0.65 then return false end
    if beach then
        local water = getWaterLevel(x,y,ground,true)
        if type(water) == "number" and water >= ground then return false end
        -- The shipped map's modeldata.SURFACES converts PS2 0x12 to SA 33
        -- and PS2 0x22 to SA 12. Other sand-like SA surfaces have other origins.
        if material ~= 33 and material ~= 12 then return false end
    end
    if initial then
        local px,py,pz = getElementPosition(ped)
        if not isLineOfSightClear(px,py,pz+0.5,x,y,ground+1.15,true,true,false,true,false,false,false,ped) then
            return false
        end
        for _, kind in ipairs({"ped","player","vehicle"}) do
            local radius = beach and 3 or 0.6
            for _, occupant in ipairs(getElementsWithinRange(x,y,ground+0.85,radius,kind,0,0) or {}) do
                if occupant ~= ped then return false end
            end
        end
    end
    return ground
end

addEvent("npchlc_traffic:activityProbe", true)
addEventHandler("npchlc_traffic:activityProbe", resourceRoot, function(ped, token, site, initial)
    triggerServerEvent("npchlc_traffic:activityReply", resourceRoot, ped, token, probe(ped,site,initial))
end, false)
