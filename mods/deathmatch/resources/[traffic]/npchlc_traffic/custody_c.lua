addEvent("traffic:bustedText", true)
addEventHandler("traffic:bustedText", resourceRoot, function(visible, officer)
    if visible then TrafficCustodyCamera.begin(officer) else TrafficCustodyCamera.finish() end
    local frontend = getResourceFromName("frontend")
    if not frontend or getResourceState(frontend) ~= "running" then return end
    if visible then
        local text = exports.frontend:getVcsText("BUSTED") or "Busted"
        exports.frontend:showGameTextForPlayer(text, 2, 5000)
    else
        exports.frontend:hideGameText(2)
    end
end, false)
addEvent("traffic:bustedCameraEnd", true)
addEventHandler("traffic:bustedCameraEnd", resourceRoot, function() TrafficCustodyCamera.finish() end, false)

-- The seated driver can be well to one side of the server's chassis origin.
-- Aim the pistol at the actual streamed skeleton on each observer's client.
local aimKey="npchlc_traffic:seatedArrestAim"
local aiming={}
local aimTimer
local function stopAim(officer)
    if not aiming[officer] then return end
    aiming[officer]=nil
    if isElement(officer) then setPedControlState(officer,"aim_weapon",false) end
    if not next(aiming) and aimTimer then killTimer(aimTimer);aimTimer=nil end
end
local function updateAim()
    for officer,player in pairs(aiming) do
        if not isElement(officer) or not isElement(player) or isPedDead(officer) then
            stopAim(officer)
        elseif isElementStreamedIn(player) and getPedOccupiedVehicle(player) then
            local tx,ty,tz=getPedBonePosition(player,4)
            if tx then
                local x,y=getElementPosition(officer)
                setPedRotation(officer,-math.deg(math.atan2(tx-x,ty-y)))
                setPedAimTarget(officer,tx,ty,tz)
                setPedControlState(officer,"fire",false)
                setPedControlState(officer,"aim_weapon",true)
            end
        end
    end
end
local function trackAim(officer)
    local target=getElementData(officer,aimKey,false)
    if not isElement(target) or not isElementStreamedIn(officer) then stopAim(officer);return end
    aiming[officer]=target
    updateAim()
    if not aimTimer and next(aiming) then aimTimer=setTimer(updateAim,50,0) end
end
addEventHandler("onClientElementDataChange",root,function(key) if key==aimKey then trackAim(source) end end)
addEventHandler("onClientElementStreamIn",root,function() if getElementType(source)=="ped" then trackAim(source) end end)
addEventHandler("onClientElementStreamOut",root,function() stopAim(source) end)
addEventHandler("onClientElementDestroy",root,function() stopAim(source) end)
addEventHandler("onClientResourceStop",resourceRoot,function() for officer in pairs(aiming) do stopAim(officer) end end)
