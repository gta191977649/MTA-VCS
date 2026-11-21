-- Local spring for each streamed helicopter attachment.
local length = 31 * 6 / 32
local function step(s, dt, x, y, z)
    local dx, dy, dz = s.x-x, s.y-y, s.z-z
    local distance = math.sqrt(dx*dx+dy*dy+dz*dz)
    local tension = 0
    if distance > length then
        local radial = (dx*(s.vx-s.ax)+dy*(s.vy-s.ay)+dz*(s.vz-s.az))/distance
        tension = math.max(0, 180*(distance-length)+15*radial)/distance
    end
    local drag = math.exp(-0.8*dt)
    s.vx = (s.vx-dx*tension*dt)*drag
    s.vy = (s.vy-dy*tension*dt)*drag
    s.vz = (s.vz-(9.81+dz*tension)*dt)*drag
    s.x, s.y, s.z = s.x+s.vx*dt, s.y+s.vy*dt, s.z+s.vz*dt
end

local ropes = {}
local function update(s,now)
    local heli=getElementAttachedTo(s.hook)
    if not isElement(heli) or not isElementStreamedIn(heli) then return end
    if s.vehicle~=heli then
        local x,y,z=getElementPosition(heli)
        s.vehicle,s.time,s.lastX,s.lastY,s.lastZ=heli,now,x,y,z
        s.x,s.y,s.z,s.vx,s.vy,s.vz=x,y,z-length,0,0,0
        s.ox,s.oy,s.oz=0,0,-length
        s.correction=nil
        s.sent=now-125
    end
    local m = getElementMatrix(s.vehicle)
    if not m then return end
    local x,y,z = unpack(m[4])
    local dt = (now-s.time)/1000
    if dt <= 0 then return end
    local dx,dy,dz = x-s.lastX,y-s.lastY,z-s.lastZ
    if dt > 0.5 or dx*dx+dy*dy+dz*dz > 400 then
        s.x,s.y,s.z,s.vx,s.vy,s.vz = x,y,z-length,0,0,0
        s.correction=nil
    else
        local count = math.ceil(dt*120)
        s.ax,s.ay,s.az = dx/dt,dy/dt,dz/dt
        for i=1,count do
            local t=i/count
            step(s,dt/count,s.lastX+dx*t,s.lastY+dy*t,s.lastZ+dz*t)
        end
    end
    -- A remote pilot reports an offset in helicopter space. Bleed the error
    -- into the locally simulated trajectory between network samples.
    if s.correction then
        local e=s.correction
        local blend=1-math.exp(-18*dt)
        s.x,s.y,s.z=s.x+e[1]*blend,s.y+e[2]*blend,s.z+e[3]*blend
        e[1],e[2],e[3]=e[1]*(1-blend),e[2]*(1-blend),e[3]*(1-blend)
    end
    s.lastX,s.lastY,s.lastZ,s.time = x,y,z,now
    dx,dy,dz = s.x-x,s.y-y,s.z-z
    local function localOffset(axis)
        return dx*axis[1]+dy*axis[2]+dz*axis[3]
    end
    local a,b,c = localOffset(m[1]),localOffset(m[2]),localOffset(m[3])
    if math.abs(a-s.ox)+math.abs(b-s.oy)+math.abs(c-s.oz)>0.001 then
        setElementAttachedOffsets(s.hook,a,b,c,0,0,0)
        s.ox,s.oy,s.oz = a,b,c
    end

    if MissionRunToken and now-s.sent>=125 and getVehicleOccupant(heli,0)==localPlayer
        and getElementData(s.hook,"mission:slingOwner",false)==localPlayer then
        s.sent=now
        triggerServerEvent("mission:slingSample",resourceRoot,MissionRunToken,s.hook,a,b,c)
    end
end

local function watch(hook)
    if getElementType(hook)~="object" then return end
    if getElementData(hook,"mission:airRescueCable",false) and isElementStreamedIn(hook) then
        ropes[hook]=ropes[hook] or {hook=hook}
    else ropes[hook]=nil end
end

addEventHandler("onClientElementStreamIn",resourceRoot,function() watch(source) end)
addEventHandler("onClientElementDataChange",resourceRoot,function(key)
    if key=="mission:airRescueCable" then watch(source) end
end)
addEventHandler("onClientElementStreamOut",resourceRoot,function() ropes[source]=nil end)
addEventHandler("onClientElementDestroy",resourceRoot,function() ropes[source]=nil end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,hook in ipairs(getElementsByType("object",resourceRoot,true)) do watch(hook) end
end)
addEventHandler("onClientPreRender",root,function()
    local now=getTickCount()
    for _,s in pairs(ropes) do update(s,now) end
end,true,"high")

addEvent("mission:slingSnapshot",true)
addEventHandler("mission:slingSnapshot",resourceRoot,function(hook,a,b,c)
    local s=ropes[hook]
    if not s or not isElement(s.vehicle) then return end
    local m=getElementMatrix(s.vehicle)
    if not m then return end
    local function worldPosition(i)
        return a*m[1][i]+b*m[2][i]+c*m[3][i]+m[4][i]
    end
    s.correction={worldPosition(1)-s.x,worldPosition(2)-s.y,worldPosition(3)-s.z}
end,false)
