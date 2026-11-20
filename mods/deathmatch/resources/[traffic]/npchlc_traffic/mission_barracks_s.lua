-- PHI_A3_4981 attaches three mission-owned actors to the bed, outside the seat pool.
local offsets={{.75,-1.5,1.7},{-.75,-2.2,1.7},{0,-4,1.7}}
local crews={}

local function releaseCrew(truck)
    local crew=crews[truck]
    if not crew then return false end
    crews[truck]=nil
    for _,ped in ipairs(crew) do
        if isElement(ped) and getElementAttachedTo(ped)==truck then detachElements(ped,truck) end
    end
    return true
end

function unmountPhilBarracksRiders(truck)
    return crews[truck] and crews[truck].owner==sourceResource and releaseCrew(truck) or false
end

function mountPhilBarracksRiders(truck,front,left,tail)
    if not isElement(truck) or getElementType(truck)~="vehicle" or getElementModel(truck)~=433
        or isVehicleBlown(truck) then return false end
    local model=getElementData(truck,"npchlc_traffic:originalModel",false)
    if model and model~=218 then return false end
    local riders={front,left,tail}
    local current=crews[truck]
    if current and current.owner~=sourceResource then return false end
    if front==left or front==tail or left==tail then return false end
    for i=1,3 do
        local ped=riders[i]
        if not isElement(ped) or getElementType(ped)~="ped" or isPedDead(ped)
            or isPedInVehicle(ped) or getElementInterior(ped)~=getElementInterior(truck)
            or getElementDimension(ped)~=getElementDimension(truck) then return false end
        local brain=PedAI.brain(ped)
        if brain and brain.scriptOwner~=sourceResource then return false end
        if current then
            if current[i]~=ped or getElementAttachedTo(ped)~=truck then return false end
        elseif getElementAttachedTo(ped) then return false end
    end
    if current then return true end
    local previous={}
    for i,ped in ipairs(riders) do
        previous[i]={position={getElementPosition(ped)},rotation={getElementRotation(ped)}}
        local point=offsets[i]
        if not attachElements(ped,truck,point[1],point[2],point[3],0,0,180) then
            for j=1,i-1 do
                detachElements(riders[j],truck)
                setElementPosition(riders[j],unpack(previous[j].position))
                setElementRotation(riders[j],unpack(previous[j].rotation))
            end
            return false
        end
    end
    riders.owner=sourceResource
    crews[truck]=riders
    return true
end

addEventHandler("onElementDestroy",root,function()
    if crews[source] then releaseCrew(source) end
end)
addEventHandler("onVehicleExplode",root,function()
    if crews[source] then releaseCrew(source) end
end)
addEventHandler("onResourceStop",root,function(stopped)
    for truck,crew in pairs(crews) do
        if stopped==getThisResource() or stopped==crew.owner then releaseCrew(truck) end
    end
end)
