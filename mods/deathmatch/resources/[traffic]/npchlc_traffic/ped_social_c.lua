addEvent("npchlc_traffic:socialLook",true)
addEventHandler("npchlc_traffic:socialLook",resourceRoot,function(ped,target,duration)
    if isElement(ped) and isElementStreamedIn(ped) and isElement(target) then
        local x,y,z = getElementPosition(target)
        setPedLookAt(ped,x,y,z+0.6,duration,500,target)
    end
end,false)

addEvent("npchlc_traffic:boardPassenger",true)
addEventHandler("npchlc_traffic:boardPassenger",resourceRoot,function(ped,car)
    if isElement(ped) and isElementSyncer(ped) and not isPedInVehicle(ped)
        and isElement(car) and isElementStreamedIn(car) and not isVehicleLocked(car) then
        setPedEnterVehicle(ped,car,true)
    end
end,false)
local facingKey = "npchlc_traffic:socialFacing"
local partners = {}

local function track(ped)
    partners[ped] = getElementData(ped,facingKey,false) or nil
end

addEventHandler("onClientElementDataChange",root,function(key)
    if key == facingKey and isElementStreamedIn(source) then track(source) end
end)
addEventHandler("onClientElementStreamIn",root,function()
    if getElementType(source) == "ped" then track(source) end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,ped in ipairs(getElementsByType("ped",root,true)) do track(ped) end
end,false)
addEventHandler("onClientElementStreamOut",root,function() partners[source] = nil end)
addEventHandler("onClientElementDestroy",root,function() partners[source] = nil end)

addEventHandler("onClientPreRender",root,function(elapsed)
    for ped,partner in pairs(partners) do
        if not isElement(partner) then
            partners[ped] = nil
        elseif isElementStreamedIn(partner) and not isPedDead(ped) and not isPedInVehicle(ped)
            and not isPedDead(partner) and not isPedInVehicle(partner)
            and getElementDimension(ped)==getElementDimension(partner)
            and getElementInterior(ped)==getElementInterior(partner) then
            local x,y = getElementPosition(ped)
            local tx,ty = getElementPosition(partner)
            local matrix = getElementMatrix(ped)
            if matrix and (tx-x)^2+(ty-y)^2 > 0.0001 then
                local current = math.deg(math.atan2(-matrix[2][1],matrix[2][2]))
                local desired = math.deg(math.atan2(x-tx,ty-y))
                local delta = (desired-current+180)%360-180
                if math.abs(delta)>0.5 then
                    local step = math.min(elapsed,100)*0.24
                    setPedRotation(ped,current+math.max(-step,math.min(step,delta)),true)
                end
            end
        end
    end
end)
