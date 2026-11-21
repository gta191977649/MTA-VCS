local lastReport = setmetatable({}, {__mode="k"})
local spinReports = setmetatable({}, {__mode="k"})

-- Server MTA exposes angular velocity only for vehicles. The native
-- 001DC3E8 comparison is on the seated ped's turn speed, not the hull's.
function CJetSki.CheckRiderMotion(ped,vehicle)
    if not isElementSyncer(vehicle) or getVehicleOccupant(vehicle,0) ~= ped then return end
    local wx,wy,wz = getElementAngularVelocity(ped)
    if not wx or wx*wx+wy*wy+wz*wz <= 0.09 then return end
    local now = getTickCount()
    if spinReports[ped] and (now-spinReports[ped])%4294967296 < 200 then return end
    spinReports[ped] = now
    triggerServerEvent("vcs_vehicle:jetSkiRiderSpin",resourceRoot,vehicle,ped,wx,wy,wz)
end

addEvent("vcs_vehicle:testJetSkiOverturn",true)
addEventHandler("vcs_vehicle:testJetSkiOverturn",resourceRoot,function(vehicle,episode)
    if CVehicle.resolve(vehicle) == CJetSki and isElementSyncer(vehicle)
        and CJetSki.HasOverturnLift(vehicle) then
        triggerServerEvent("vcs_vehicle:jetSkiOverturned",resourceRoot,vehicle,episode)
    end
end,false)

addEventHandler("onClientVehicleCollision", root, function(other, impulse, _, x,y,z, nx,ny,nz)
    if not isElementSyncer(source) or CVehicle.resolve(source) ~= CJetSki
        or getVehicleType(source) ~= "Boat" or not getVehicleOccupant(source,0)
        or not nz or not impulse or impulse <= 0 then return end
    local matrix = getElementMatrix(source)
    local handling = getVehicleHandling(source)
    if not matrix or not handling or CJetSki.ImpactScore(impulse,handling.mass,matrix,nx,ny,nz,1) <= 0 then return end
    local now = getTickCount()
    local previous = lastReport[source]
    if previous and (now-previous.tick)%4294967296 < 150 and impulse <= previous.impulse then return end
    lastReport[source] = {tick=now,impulse=impulse}
    -- Static world geometry has no shared element ID. Only a synchronized
    -- vehicle contributes its own velocity to the server's impact calculation.
    local collider=isElement(other) and getElementType(other)=="vehicle" and not isElementLocal(other) and other or false
    triggerServerEvent("vcs_vehicle:jetSkiImpact",resourceRoot,source,collider,impulse,x,y,z,nx,ny,nz)
end)
