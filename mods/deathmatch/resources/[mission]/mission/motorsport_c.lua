local crash
addEvent("mission:crashWatch",true)
addEventHandler("mission:crashWatch",resourceRoot,function(token,id,vehicle)
    if token==MissionRunToken then crash={vehicle=vehicle,id=id,token=token,contacts={}} end
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if crash and crash.token==token then crash=nil end
end,false)
-- The native 03A4 handler consumes a vehicle's most recent contact. Report the
-- contact identities only. All scored stunt states and timing are server-side.
addEventHandler("onClientVehicleCollision",root,function(hit)
    if not crash or crash.token~=MissionRunToken or not isElement(hit) or getElementType(hit)~="vehicle"
        or getPedOccupiedVehicle(localPlayer)~=crash.vehicle then return end
    local now=getTickCount()
    for e,expires in pairs(crash.contacts) do
        if expires<=now or not isElement(e) then crash.contacts[e]=nil end
    end
    local from,to=source,hit
    if to==crash.vehicle or crash.contacts[to] and not crash.contacts[from] then from,to=to,from end
    if from~=crash.vehicle and not crash.contacts[from] or to==crash.vehicle or crash.contacts[to] then return end
    crash.contacts[to]=now+5000
    triggerServerEvent("mission:crashContact",resourceRoot,crash.token,crash.id,from,to)
end)
