local crash
-- SCM 005D tests a world-space sphere against the camera. Use the current
-- viewport rays so widescreen, zoom and rolled cameras keep the same margin.
local function sphereOnScreen(x,y,z,radius)
    local cx,cy,cz,tx,ty,tz=getCameraMatrix()
    x,y,z=x-cx,y-cy,z-cz
    local dx,dy,dz=tx-cx,ty-cy,tz-cz
    local depth=(x*dx+y*dy+z*dz)/math.sqrt(dx*dx+dy*dy+dz*dz)
    if depth+radius<getNearClipDistance() or depth-radius>getFarClipDistance() then return false end
    local width,height=guiGetScreenSize()
    local function ray(u,v)
        local rx,ry,rz=getWorldFromScreenPosition(u,v,20)
        return {rx-cx,ry-cy,rz-cz}
    end
    local corners={ray(0,0),ray(width,0),ray(width,height),ray(0,height)}
    for i=1,4 do
        local a,b,inside=corners[i],corners[i%4+1],corners[(i+1)%4+1]
        local nx,ny,nz=a[2]*b[3]-a[3]*b[2],a[3]*b[1]-a[1]*b[3],a[1]*b[2]-a[2]*b[1]
        local signed=x*nx+y*ny+z*nz
        if nx*inside[1]+ny*inside[2]+nz*inside[3]<0 then signed=-signed end
        if signed < -radius*math.sqrt(nx*nx+ny*ny+nz*nz) then return false end
    end
    return true
end

addEvent("mission:checkRivalRecovery",true)
addEventHandler("mission:checkRivalRecovery",resourceRoot,function(token,ped,car,x,y,z,check,radius)
    if token~=MissionRunToken or not isElement(ped) or isElementOnScreen(ped)
        or isElement(car) and isElementOnScreen(car) then return end
    local ground=getGroundPosition(x,y,z+1)
    if not ground or math.abs(ground-z)>=4 then ground=z end
    if sphereOnScreen(x,y,ground,radius or 6) then return end
    triggerServerEvent("mission:rivalRecoveryClear",resourceRoot,token,ped,check,ground)
end,false)
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
