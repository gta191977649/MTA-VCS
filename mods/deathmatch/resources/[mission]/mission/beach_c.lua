local patrol
local roads={}
local roadTimer
addEventHandler("onClientVehicleCollision",root,function(other,impulse,_,x,y,z,nx,ny,nz,otherImpulse)
    if not patrol or patrol~=MissionRunToken then return end
    local car=getPedOccupiedVehicle(localPlayer)
    if not car or getVehicleController(car)~=localPlayer then return end
    local bike
    if source==car then bike,impulse=other,otherImpulse or impulse
    elseif other==car then bike=source end
    if isElement(bike) and impulse and impulse>10 and getElementData(bike,"mission:actorOwner",false)==localPlayer
        and getElementData(bike,"vcs_vehicle:originalModel",false)==205 then
        triggerServerEvent("mission:beachBikeHit",resourceRoot,patrol,bike)
    end
end)
local function watch(car)
    if patrol and getElementType(car)=="vehicle" then
        roads[car]=getElementData(car,"mission:beachRoad",false)==localPlayer and isElementStreamedIn(car) or nil
    end
end
addEventHandler("onClientElementStreamIn",root,function() watch(source) end)
addEventHandler("onClientElementDataChange",root,function(key)
    if key=="mission:beachRoad" then watch(source) end
end)
addEventHandler("onClientElementStreamOut",root,function() roads[source]=nil end)
addEventHandler("onClientElementDestroy",root,function() roads[source]=nil end)
local function checkRoads()
    if not patrol or patrol~=MissionRunToken then return end
    for car in pairs(roads) do
        local x,y,z=getElementPosition(car)
        local hit,_,_,gz,_,_,_,nz=processLineOfSight(x,y,z+6,x,y,z-8,true,false,false,true,false)
        if hit and nz>0.5 then triggerServerEvent("mission:beachRoad",resourceRoot,patrol,car,gz) end
    end
end

local function throwPreserver()
    if not patrol or patrol~=MissionRunToken then return end
    local side=getPedControlState(localPlayer,"vehicle_look_left") and -1 or getPedControlState(localPlayer,"vehicle_look_right") and 1
    if side then triggerServerEvent("mission:throwPreserver",resourceRoot,patrol,side) end
end

local function stopPatrol()
    if patrol then unbindKey("vehicle_fire","down",throwPreserver) end
    if roadTimer and isTimer(roadTimer) then killTimer(roadTimer) end
    patrol,roadTimer,roads=nil,nil,{}
end
addEventHandler("mission:start",resourceRoot,function(title,token)
    if title=="Beach Patrol" and token==patrol then return end
    stopPatrol()
    if title=="Beach Patrol" and token then
        patrol=token
        for _,car in ipairs(getElementsByType("vehicle",root,true)) do watch(car) end
        roadTimer=setTimer(checkRoads,850,0)
        bindKey("vehicle_fire","down",throwPreserver)
    end
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if token==patrol then stopPatrol() end
end,false)
addEventHandler("onClientPlayerWasted",localPlayer,stopPatrol,false)
addEventHandler("onClientResourceStop",resourceRoot,stopPatrol,false)
addEventHandler("onClientPedDamage",root,function(attacker)
    local owner=getElementData(source,"mission:beachOwner",false)
    if not owner then return end
    if isElement(attacker) and getElementType(attacker)=="vehicle" then attacker=getVehicleController(attacker) end
    if attacker~=owner then cancelEvent() end
end,true,"high")
