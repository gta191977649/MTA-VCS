-- Different runs can occupy the same starting grid or approach the same gate.
-- Record only the directed collision pairs this resource actually changes.
local racers, overrides = {}, {}
local key = "mission:raceOwner"

local function suppress(a,b)
    if not isElementCollidableWith(a,b) then return end
    if setElementCollidableWith(a,b,false) then
        overrides[a]=overrides[a] or {}
        overrides[a][b]=true
    end
end

local function restore(a,b)
    if not overrides[a] or not overrides[a][b] then return end
    if isElement(a) and isElement(b) then setElementCollidableWith(a,b,true) end
    overrides[a][b]=nil
    if not next(overrides[a]) then overrides[a]=nil end
end

local function update(vehicle, owner)
    if racers[vehicle]==owner then return end
    for other, otherOwner in pairs(racers) do
        if other~=vehicle then
            if owner and owner~=otherOwner then
                suppress(vehicle,other)
                suppress(other,vehicle)
            else
                restore(vehicle,other)
                restore(other,vehicle)
            end
        end
    end
    racers[vehicle]=owner
end

local function streamIn(vehicle)
    if getElementType(vehicle)=="vehicle" then
        update(vehicle,getElementData(vehicle,key,false) or nil)
    end
end
addEventHandler("onClientElementStreamIn",root,function() streamIn(source) end)
addEventHandler("onClientElementDataChange",root,function(name)
    if name==key and isElementStreamedIn(source) then streamIn(source) end
end)
local function streamOut()
    if racers[source] then update(source,nil) end
end
addEventHandler("onClientElementStreamOut",root,streamOut)
addEventHandler("onClientElementDestroy",root,streamOut)
addEventHandler("onClientResourceStart",resourceRoot,function()
    for _,car in ipairs(getElementsByType("vehicle",root,true)) do streamIn(car) end
end,false)
addEventHandler("onClientResourceStop",resourceRoot,function()
    for car in pairs(racers) do update(car,nil) end
end,false)
