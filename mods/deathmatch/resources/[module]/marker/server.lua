-- shared.lua defines the exported setters, so capture builtins before it loads (see meta.xml).
MarkerHideNative=function(element) return MarkerNativeColor(element,0,0,0,0) end
local ready={}

local function visibleTo(state,player)
    local current=player
    while isElement(current) do
        if state.visibility[current]~=nil then return state.visibility[current] end
        current=getElementParent(current)
    end
    return false
end

local function publicState(element,player)
    local state=MarkerRecords[element]
    if not state then return false end
    return {style=state.style,color=state.color,animation=state.animation,target=state.target,
        blipVisible=state.blipVisible==true,blip=state.blip,visible=visibleTo(state,player)}
end

function MarkerChanged(element)
    local state=MarkerRecords[element]
    if state.blipVisible then
        if not isElement(state.blip) then
            state.blip=createBlipAttachedTo(element,0,2,unpack(state.color))
            if state.blip then setElementParent(state.blip,element) end
        end
        if isElement(state.blip) then
            setBlipColor(state.blip,unpack(state.color))
            setElementVisibleTo(state.blip,root,false)
            for _,player in ipairs(getElementsByType("player")) do
                setElementVisibleTo(state.blip,player,visibleTo(state,player))
            end
        end
    elseif isElement(state.blip) then
        destroyElement(state.blip)
        state.blip=nil
    end
    MarkerSyncBlip(element)
    for player in pairs(ready) do
        if isElement(player) then triggerClientEvent(player,"marker:update",resourceRoot,element,publicState(element,player)) end
    end
end

function createMarker(x,y,z,style,size,r,g,b,a,visibleTo,ignoreAlphaLimits)
    return MarkerCreate(x,y,z,style,size,r,g,b,a,visibleTo,ignoreAlphaLimits)
end

function setMarkerVisibleTo(element,visibleTo,visible)
    if not MarkerRecords[element] or not isElement(visibleTo) or type(visible)~="boolean" then return false end
    MarkerRecords[element].visibility[visibleTo]=visible
    MarkerChanged(element)
    return true
end

function isMarkerVisibleTo(element,player)
    local state=MarkerRecords[element]
    return state and isElement(player) and visibleTo(state,player) or false
end

addEvent("marker:ready",true)
addEventHandler("marker:ready",resourceRoot,function()
    if not client or source~=resourceRoot or ready[client] then return end
    ready[client]=true
    local snapshot={}
    for element in pairs(MarkerRecords) do
        if isElement(MarkerRecords[element].blip) then
            setElementVisibleTo(MarkerRecords[element].blip,client,visibleTo(MarkerRecords[element],client))
        end
        snapshot[#snapshot+1]={element,publicState(element,client)}
    end
    triggerClientEvent(client,"marker:snapshot",resourceRoot,snapshot)
end)
addEventHandler("onPlayerQuit",root,function() ready[source]=nil end)
addEventHandler("onResourceStop",root,function(stopped)
    for element,state in pairs(MarkerRecords) do
        if state.owner==stopped and isElement(element) then destroyElement(element) end
    end
end)
