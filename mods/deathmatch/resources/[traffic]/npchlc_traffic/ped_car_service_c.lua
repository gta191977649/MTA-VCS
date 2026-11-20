addEvent("npchlc_traffic:serviceSuspension",true)
addEventHandler("npchlc_traffic:serviceSuspension",resourceRoot,function(car,volume,speed)
    if not isElement(car) or not isElementStreamedIn(car) then return end
    local x,y,z=getElementPosition(car)
    local sound=playSound3D("sfx_service_suspension.wav",x,y,z)
    if not sound then return end
    setElementInterior(sound,getElementInterior(car))
    setElementDimension(sound,getElementDimension(car))
    attachElements(sound,car)
    setSoundMaxDistance(sound,35)
    setSoundVolume(sound,volume)
    setSoundSpeed(sound,speed)
end,false)

addEvent("npchlc_traffic:serviceFloor",true)
addEventHandler("npchlc_traffic:serviceFloor",resourceRoot,function(ped,car,id)
    if not isElement(car) or not isElementSyncer(car) or not isElementStreamedIn(car)
        or not isElement(ped) or getPedOccupiedVehicle(ped)~=car then return end
    local x,y,z=getElementPosition(car)
    local hit,_,_,_,_,_,_,_,material=processLineOfSight(x,y,z,x,y,z-100,true,false,false,true,false)
    triggerServerEvent("npchlc_traffic:serviceFloorResult",resourceRoot,ped,car,id,hit and material or false)
end,false)
