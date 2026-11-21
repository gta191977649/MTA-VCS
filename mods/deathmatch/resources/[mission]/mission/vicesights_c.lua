local tour
local photos
local flashes={
    {250,0.8,0,0}, {500,-0.8,0.3,0.2}, {900,0.8,0.3,0.2}, {1300,-0.8,0,0.2},
    {1800,0.8,0.3,0.2}, {2300,-0.8,0,0.2}, {3000,0.8,0.3,0.2}, {3400,-0.8,0.2,0.2}, {3800,0.8,0,0.2},
}
local effects={}
local nextGround=0

local function clearPhotos()
    photos=nil
    for fx in pairs(effects) do
        effects[fx]=nil
        if isElement(fx) then destroyElement(fx) end
    end
end

local function drawPhotos(now)
    for fx,expiry in pairs(effects) do
        if now>=expiry or not isElement(fx) then
            effects[fx]=nil
            if isElement(fx) then destroyElement(fx) end
        end
    end
    if not photos then return end
    local heli=photos.heli
    if not isElement(heli) or getPedOccupiedVehicle(localPlayer)~=heli then clearPhotos() return end
    local f=flashes[photos.index]
    if now-photos.at<f[1] then return end
    local m=getElementMatrix(heli)
    if m then
        local function axis(i) return m[4][i]+m[1][i]*f[2]+m[2][i]*f[3]+m[3][i]*f[4] end
        local fx=createEffect("camflash",axis(1),axis(2),axis(3))
        if fx then
            setElementInterior(fx,getElementInterior(heli))
            setElementDimension(fx,getElementDimension(heli))
            effects[fx]=now+450
        end
    end
    photos.index=photos.index+1
    if not flashes[photos.index] then photos=nil end
end
addEventHandler("onClientPedDamage",root,function(attacker)
    local owner=getElementData(source,"mission:tourOwner",false)
    if not owner or not isElement(attacker) then return end
    if getElementType(attacker)=="vehicle" then attacker=getVehicleController(attacker) end
    if isElement(attacker) and getElementType(attacker)=="player" and attacker~=owner then cancelEvent() end
end,true,"high")

local function updateTour()
    if tour~=MissionRunToken then return end
    local now=getTickCount()
    drawPhotos(now)
    if now<nextGround then return end
    nextGround=now+1000
    local heli=getPedOccupiedVehicle(localPlayer)
    if not heli or getVehicleOccupant(heli,0)~=localPlayer then return end
    local x,y,z=getElementPosition(heli)
    local hit,_,_,ground=processLineOfSight(x,y,z,x,y,-30,true,false,false,true,true,false,false,false,heli)
    local water=getWaterLevel(x,y,z)
    if hit or water then
        triggerServerEvent("mission:tourGround",resourceRoot,tour,heli,math.max(hit and ground or -30,water or -30))
    end
end

local function stopTour()
    if tour then removeEventHandler("onClientPreRender",root,updateTour) end
    tour=nil
    clearPhotos()
end

addEventHandler("mission:start",resourceRoot,function(title,token)
    if title=="Vice Sights" and token==tour then return end
    stopTour()
    if title=="Vice Sights" and token then
        tour,nextGround=token,0
        addEventHandler("onClientPreRender",root,updateTour)
    end
end,false)
addEventHandler("mission:end",resourceRoot,function(_,_,token)
    if token==tour then stopTour() end
end,false)
addEventHandler("onClientPlayerWasted",localPlayer,stopTour,false)
addEventHandler("onClientResourceStop",resourceRoot,stopTour,false)
addEvent("mission:tourPhotos",true)
addEventHandler("mission:tourPhotos",resourceRoot,function(token,heli)
    if not tour or token~=tour then return end
    clearPhotos()
    if isElement(heli) then photos={heli=heli,at=getTickCount(),index=1} end
end,false)
