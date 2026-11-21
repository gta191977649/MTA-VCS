local watched, waitingForRoad = {}, {}

local function observe(ped)
    local owner = getElementData(ped,"mission:vigilanteTarget",false)
    watched[ped] = owner==localPlayer or nil
end
addEventHandler("onClientElementStreamIn",root,function()
    if getElementType(source)=="ped" then observe(source) end
    if getElementType(source)=="vehicle" and getElementData(source,"mission:vigilanteRoad",false)==localPlayer then
        waitingForRoad[source]=true
    end
end)
addEventHandler("onClientElementDataChange",root,function(key)
    if key=="mission:vigilanteTarget" and isElementStreamedIn(source) then observe(source) end
    if key=="mission:vigilanteRoad" then
        waitingForRoad[source]=isElementStreamedIn(source) and getElementData(source,key,false)==localPlayer or nil
    end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,ped in ipairs(getElementsByType("ped",root,true)) do observe(ped) end
    for _,car in ipairs(getElementsByType("vehicle",root,true)) do
        if getElementData(car,"mission:vigilanteRoad",false)==localPlayer then waitingForRoad[car]=true end
    end
end)
local function forget() watched[source],waitingForRoad[source]=nil,nil end
addEventHandler("onClientElementStreamOut",root,forget)
addEventHandler("onClientElementDestroy",root,forget)
addEventHandler("onClientPedWasted",root,forget)

-- The syncer applies damage from the dispatch owner, including that player's vehicle.
addEventHandler("onClientPedDamage",root,function(attacker)
    local owner=getElementData(source,"mission:vigilanteTarget",false)
    if not owner then return end
    if isElement(attacker) and getElementType(attacker)=="vehicle" then attacker=getVehicleController(attacker) end
    if attacker~=owner then cancelEvent() end
end,true,"high")

setTimer(function()
    local x,y,z=getElementPosition(localPlayer)
    for car in pairs(waitingForRoad) do
        local cx,cy,cz=getElementPosition(car)
        if getDistanceBetweenPoints3D(x,y,z,cx,cy,cz)<200 then
            local hit,_,_,height,_,_,_,nz=processLineOfSight(cx,cy,cz+5,cx,cy,cz-7,true,false,false,true,false)
            if hit and nz and nz>0.55 then triggerServerEvent("mission:vigilanteRoadReady",resourceRoot,car,height,MissionRunToken) end
        end
    end
    for ped in pairs(watched) do
        if isElement(ped) and not isPedDead(ped) and not isPedInVehicle(ped) then
            local px,py,pz=getElementPosition(ped)
            if getDistanceBetweenPoints3D(px,py,pz,x,y,z)<100 and
                isLineOfSightClear(px,py,pz+0.6,x,y,z+0.5,true,false,false,true,false,false,false,ped) then
                triggerServerEvent("mission:vigilanteSpotted",resourceRoot,ped,MissionRunToken)
            end
        end
    end
end,900,0)
