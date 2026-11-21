-- 0092 at SLUS 0030C990 adds -COL.minZ before inserting each ramp into the world.
local offsets = {ndc_boatrampwide=0.78221953,ndc_boatrampnarrow=0.78221953,
    ndc_boatramphump=0.47153401,ndc_bikerampnarrow=-0.00044656}
TrialRamps = {}
local ramps, materials, owner = {}, {}, false

function TrialRamps.clear(token)
    if token and token~=owner then return end
    for _,object in ipairs(ramps) do if isElement(object) then destroyElement(object) end end
    for _,a in pairs(materials) do
        if a.model then engineRestoreCOL(a.model) engineRestoreModel(a.model) end
        for _,item in ipairs({"col","dff","txd"}) do if isElement(a[item]) then destroyElement(a[item]) end end
        if a.model then engineFreeModel(a.model) end
    end
    ramps,materials,owner={},{},false
end

local function rampModel(name)
    if materials[name] then return materials[name].model end
    local a={model=engineRequestModel("object",1218)}
    materials[name]=a
    if not a.model then return false end
    local base="assets/"..name
    a.txd=engineLoadTXD(base..".txd")
    if not a.txd or not engineImportTXD(a.txd,a.model) then return false end
    a.dff=engineLoadDFF(base..".dff")
    a.col=engineLoadCOL(base..".col")
    if not a.dff or not a.col or not engineReplaceModel(a.dff,a.model,true) or not engineReplaceCOL(a.col,a.model) then return false end
    engineSetModelLODDistance(a.model,250)
    return a.model
end

function TrialRamps.show(token,rows,interior,dimension)
    if not token or token~=MissionRunToken then return false end
    TrialRamps.clear()
    owner=token
    for _,row in ipairs(rows) do
        local name,x,y,z,yaw=unpack(row)
        local model=offsets[name] and rampModel(name)
        local obj=model and createObject(model,x,y,z+offsets[name],0,0,yaw)
        if not obj then TrialRamps.clear() return false end
        setElementDimension(obj,dimension)
        setElementInterior(obj,interior)
        setElementDoubleSided(obj,true)
        setElementFrozen(obj,true)
        ramps[#ramps+1]=obj
    end
    return true
end

addEvent("mission:trialRamps",true)
addEventHandler("mission:trialRamps",resourceRoot,function(token,rows,interior,dimension,id)
    if token==MissionRunToken and not TrialRamps.show(token,rows,interior,dimension) then
        triggerServerEvent("mission:trialRampFailure",resourceRoot,token,id)
    end
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token) TrialRamps.clear(token) end,false)
addEventHandler("onClientResourceStop",resourceRoot,function() TrialRamps.clear() end)

-- VCS 04E8/04E9 (003D9068/003D9140) require a wheelie/stoppie duration over 50ms.
local telemetry,telemetryOwner
local function stopTelemetry()
    if telemetry and isTimer(telemetry) then killTimer(telemetry) end
    telemetry,telemetryOwner=nil,nil
end
addEvent("mission:trialObserve",true)
addEventHandler("mission:trialObserve",resourceRoot,function(token,id,vehicle)
    if token~=MissionRunToken then return end
    stopTelemetry()
    telemetryOwner=token
    local lastContact,started,reportedPose,wasAirborne
    telemetry=setTimer(function()
        if token~=MissionRunToken or not isElement(vehicle) then stopTelemetry() return end
        if getPedOccupiedVehicle(localPlayer)~=vehicle then
            lastContact,started,reportedPose,wasAirborne=nil,nil,nil,nil
            return
        end
        local now=getTickCount()
        local pose=0
        if id=="mallbmx" then
            local front,rear=isVehicleWheelOnGround(vehicle,"front_left"),isVehicleWheelOnGround(vehicle,"rear_left")
            pose=front and not rear and 2 or rear and not front and 1 or 0
            if pose~=lastContact then lastContact,started=pose,now end
            if pose==0 or now-started<=50 then
                if reportedPose then
                    reportedPose=nil
                    triggerServerEvent("mission:trialSample",resourceRoot,token,id,0,0,true)
                end
                return
            end
            reportedPose=pose
            triggerServerEvent("mission:trialSample",resourceRoot,token,id,pose,0,true)
            return
        end
        local x,y,z=getElementPosition(vehicle)
        local landed=isVehicleOnGround(vehicle)
        local water
        if id=="watersports" then
            water=getWaterLevel(x,y,z,true)
            if type(water)=="number" then
                landed=landed or isElementInWater(vehicle) or z-water<=0.75
            end
        end
        if landed and not wasAirborne then return end
        wasAirborne=not landed
        local ground=getGroundPosition(x,y,z+0.5)
        if type(water)=="number" then ground=math.max(type(ground)=="number" and ground or water,water) end
        if type(ground)=="number" then
            triggerServerEvent("mission:trialSample",resourceRoot,token,id,pose,ground,landed)
        end
    end,100,0)
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if token==telemetryOwner then stopTelemetry() end
end,false)
addEventHandler("onClientResourceStop",resourceRoot,stopTelemetry)
