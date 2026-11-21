local function frontendReady()
    local resource=getResourceFromName("frontend")
    return resource and getResourceState(resource)=="running"
end

local function present(element,state)
    if not isElement(element) then return end
    if state then
        MarkerRecords[element]=state
        MarkerHideNative(element)
        local definition=state
        if state.visible==false then definition=false end
        if frontendReady() then exports.frontend:setWorldMarker(element,definition) end
    else
        MarkerRecords[element]=nil
        if frontendReady() then exports.frontend:setWorldMarker(element,false) end
    end
end

function MarkerHideNative(element) return MarkerNativeColor(element,0,0,0,0) end
function MarkerChanged(element)
    local state=MarkerRecords[element]
    if state.blipVisible then
        if not isElement(state.blip) then
            state.blip=createBlipAttachedTo(element,0,2,unpack(state.color))
            if state.blip then setElementParent(state.blip,element) end
        end
        if isElement(state.blip) then setBlipColor(state.blip,unpack(state.color)) end
    elseif isElement(state.blip) then
        destroyElement(state.blip)
        state.blip=nil
    end
    MarkerSyncBlip(element)
    if frontendReady() then exports.frontend:setWorldMarker(element,MarkerRecords[element]) end
end
function createMarker(x,y,z,style,size,r,g,b,a,ignoreAlphaLimits)
    return MarkerCreate(x,y,z,style,size,r,g,b,a,nil,ignoreAlphaLimits)
end

-- Server-owned visuals are changed on the server; local setters cannot accidentally desync them.
for _,name in ipairs({"setMarkerType","setMarkerColor","setMarkerTarget","setMarkerAnimation","setMarkerBlipVisible"}) do
    local setter=_G[name]
    _G[name]=function(element,...)
        if not isElement(element) or not isElementLocal(element) then return false end
        return setter(element,...)
    end
end

addEvent("marker:update",true)
addEventHandler("marker:update",resourceRoot,present)
addEvent("marker:snapshot",true)
addEventHandler("marker:snapshot",resourceRoot,function(snapshot)
    for _,entry in ipairs(snapshot) do present(entry[1],entry[2]) end
end)

local function initialize()
    if not frontendReady() then return end
    exports.frontend:registerWorldMarkerAssets(VCSMarkerMeshes,MarkerStyles)
    for element,state in pairs(MarkerRecords) do
        local definition=state
        if state.visible==false then definition=false end
        exports.frontend:setWorldMarker(element,definition)
    end
end
addEventHandler("onClientResourceStart",resourceRoot,function()
    initialize()
    triggerServerEvent("marker:ready",resourceRoot)
end)
addEventHandler("onClientResourceStart",root,function(started)
    if started==getResourceFromName("frontend") or started==getResourceFromName("skygfx") then initialize() end
end)
addEventHandler("onClientResourceStop",root,function(stopped)
    for element,state in pairs(MarkerRecords) do
        if state.owner==stopped and isElement(element) then destroyElement(element) end
    end
end)
