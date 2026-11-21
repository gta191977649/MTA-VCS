-- Shared presentation only. Camera ownership and movement belong to the scene.
local owners={}
local from,target,changed=0,0,getTickCount()
local chatBefore,radarBefore
local duration=350

function Hud.cinematicActive() return next(owners)~=nil end

local function progress(now)
    local t=math.min(1,math.max(0,(now-changed)/duration))
    t=t*t*(3-2*t)
    return from+(target-from)*t
end

function Hud.cinematicInset(width,height)
    return math.max(0,(height-width/2.20)/2)*progress(getTickCount())
end

local function transition()
    local active=Hud.cinematicActive()
    local nextTarget=active and 1 or 0
    if nextTarget~=target then
        local now=getTickCount()
        from,changed=progress(now),now
        target=nextTarget
    end
    if active and chatBefore==nil then
        chatBefore=isChatVisible()
        radarBefore=isPlayerHudComponentVisible("radar")
        showChat(false)
        setPlayerHudComponentVisible("radar",false)
    elseif not active and chatBefore~=nil then
        showChat(chatBefore)
        setPlayerHudComponentVisible("radar",radarBefore)
        chatBefore=nil
        radarBefore=nil
    end
end

function setCinematicPresentation(enabled)
    if type(enabled)~="boolean" then return false end
    owners[Hud.owner()]=enabled and true or nil
    transition()
    return true
end

function getCinematicPresentation()
    local width,height=guiGetScreenSize()
    return {active=Hud.cinematicActive(),aspect=2.20,inset=Hud.cinematicInset(width,height)}
end

addEventHandler("onClientResourceStop",root,function(resource)
    owners[getResourceName(resource)]=nil
    transition()
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    if chatBefore~=nil then
        showChat(chatBefore)
        setPlayerHudComponentVisible("radar",radarBefore)
    end
end,false)
addEventHandler("onClientRender",root,function()
    if not Hud.baseUiVisible() then return end
    local width,height=guiGetScreenSize()
    local inset=Hud.cinematicInset(width,height)
    if inset<0.1 then return end
    dxDrawRectangle(0,0,width,inset,tocolor(0,0,0,255))
    dxDrawRectangle(0,height-inset,width,inset,tocolor(0,0,0,255))
end,true,"high")
