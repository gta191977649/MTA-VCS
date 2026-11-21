local winches={}
local cableColor=tocolor(56,58,60,255)

function setRescueWinchVisible(hook,visible)
    if not isElement(hook) or getElementType(hook)~="object" or type(visible)~="boolean" then return false end
    if winches[hook] and winches[hook]~=sourceResource then return false end
    winches[hook]=visible and sourceResource or nil
    return true
end

local function drawWinch(hook)
    local heli=getElementAttachedTo(hook)
    if not isElement(heli) or not isElementStreamedIn(heli) or not isElementStreamedIn(hook) then return end
    local m=getElementMatrix(heli)
    if not m then return end
    local x,y,z=getElementPosition(hook)
    dxDrawLine3D(m[4][1],m[4][2],m[4][3],x,y,z,cableColor,2.5)
end

addEventHandler("onClientRender",root,function()
    for hook in pairs(winches) do
        if isElement(hook) then drawWinch(hook) else winches[hook]=nil end
    end
end)

addEventHandler("onClientResourceStop",root,function(resource)
    for hook,owner in pairs(winches) do if owner==resource then winches[hook]=nil end end
end)
