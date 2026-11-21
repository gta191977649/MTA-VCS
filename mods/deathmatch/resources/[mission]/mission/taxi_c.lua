local target, tailNumber, targetToken
addEvent("mission:tailTarget",true)
addEventHandler("mission:tailTarget",resourceRoot,function(vehicle,number,token)
    if not MissionRunToken or token~=MissionRunToken then return end
    target,tailNumber,targetToken=vehicle or nil,number,token
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if token==targetToken then target,tailNumber,targetToken=nil,nil,nil end
end,false)

-- onClientVehicleCollision supplies the other vehicle even at low impact speeds.
addEventHandler("onClientVehicleCollision",root,function(hit)
    if target and hit==target and source==getPedOccupiedVehicle(localPlayer)
        and getVehicleController(source)==localPlayer then
        triggerServerEvent("mission:tailCollision",resourceRoot,target,MissionRunToken,tailNumber)
    end
end)
