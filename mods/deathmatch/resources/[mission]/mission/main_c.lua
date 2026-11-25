local active = false
local entryPrompt, enteredDriverVehicle
local lastGateCue
local courseMenu

local function frontendRunning()
    local resource=getResourceFromName("frontend")
    return resource and getResourceState(resource)=="running"
end

-- RACEHUB_27311 / 27455 frame the route board from its front face.
local cameras = {
    mainla={-1053,-794.385,12.421, -1050.625,-794.385,12.421},
    beach={248.529+2.5*math.cos(math.rad(-15)),-304.109+2.5*math.sin(math.rad(-15)),12.421,
        248.529,-304.109,12.421},
}
local previewCamera

local function closeCourseChoice(frontendStopped)
    local canDraw=not frontendStopped and frontendRunning()
    courseMenu=nil
    if previewCamera then
        if isElement(previewCamera.target) then setCameraTarget(previewCamera.target)
        else setCameraMatrix(unpack(previewCamera.matrix)) end
        previewCamera=nil
        if canDraw then exports.frontend:showRaceCoursePreview(false) end
    end
    if canDraw then exports.frontend:showTextBox(false) end
end

local function clearHud(preserveResult)
    entryPrompt=nil
    closeCourseChoice()
    lastGateCue=nil
    active=false
    MissionRunToken=nil
    if not frontendRunning() then return end
    exports.frontend:hideVehicleMissionHud()
    exports.frontend:hideCaptionForPlayer(true)
    exports.frontend:hideGameText(1)
    exports.frontend:hideGameText("raceCountdown")
    exports.frontend:hideGameText("missionPassed")
    if preserveResult~=true then exports.frontend:hideGameText("missionResult") end
end

addEventHandler("onClientVehicleEnter",root,function(player,seat)
    if player==localPlayer and seat==0 then
        enteredDriverVehicle=source
        triggerServerEvent("mission:driverEntered",resourceRoot,source)
    end
end)
addEvent("mission:prompt",true)
addEventHandler("mission:prompt",resourceRoot,function(title,vehicle)
    if vehicle~=enteredDriverVehicle or not vehicle or getPedOccupiedVehicle(localPlayer)~=vehicle
        or getPedOccupiedVehicleSeat(localPlayer)~=0 or not frontendRunning() then return end
    entryPrompt=title
    if not title then exports.frontend:showTextBox(false) return end
    local keys = getBoundKeys("sub_mission") or {}
    local key = keys["2"] and "2" or next(keys)
    local message = key and ("Press %s to start %s"):format(key:upper(),title)
        or ("Use /vehiclemission to start %s"):format(title)
    exports.frontend:showTextBox(message,5000)
end,false)
addEventHandler("onClientVehicleExit",root,function(player,seat)
    if player~=localPlayer or seat~=0 then return end
    enteredDriverVehicle=nil
    if entryPrompt and frontendRunning() then exports.frontend:showTextBox(false) end
    entryPrompt=nil
end)
addEvent("mission:start",true)
addEventHandler("mission:start",resourceRoot,function(title,token)
    clearHud(true)
    active = true
    MissionRunToken = token
    if frontendRunning() then exports.frontend:showGameTextForPlayer(title,1,3000) end
end,false)
addEvent("mission:message",true)
addEventHandler("mission:message",resourceRoot,function(message,token)
    if not active or token~=MissionRunToken or not frontendRunning() then return end
    if message==false then exports.frontend:hideCaptionForPlayer(true)
    else exports.frontend:showCaptionForPlayer(message,4000) end
end,false)
addEvent("mission:end",true)
addEventHandler("mission:end",resourceRoot,function(message,passed,token)
    if token~=MissionRunToken then return end
    clearHud()
    if message and frontendRunning() then exports.frontend:showVehicleMissionResult(passed,message) end
end,false)
addEvent("mission:help",true)
addEventHandler("mission:help",resourceRoot,function(token,text,duration)
    if not active or token~=MissionRunToken or not frontendRunning() then return end
    exports.frontend:showTextBox(text,duration)
end,false)
addEvent("mission:payout",true)
addEventHandler("mission:payout",resourceRoot,function(token,amount)
    if active and token==MissionRunToken and frontendRunning() then exports.frontend:showPayoutGameText(amount) end
end,false)
addEvent("mission:raceCue",true)
addEventHandler("mission:raceCue",resourceRoot,function(token,value)
    if not active or token~=MissionRunToken or not frontendRunning() then return end
    local go=value==0 or value=="GO" or value=="GO!"
    if value~="checkpoint" and value~="lap" then
        exports.frontend:showGameText(go and "GO!" or tostring(value),"raceCountdown",go and 1500 or 1000)
    end
    local sample=(go or value=="lap") and "race_go" or "race_gate"
    if sample=="race_gate" then
        -- SLUS 001C5844 suppresses rapid repeats for five PS2 frames.
        local now=getTickCount()
        if lastGateCue and (now-lastGateCue)%4294967296<1000*5/30 then return end
        lastGateCue=now
    end
    exports.frontend:playVcsFrontendSound(sample)
    exports.frontend:playVcsFrontendSound(sample.."_center")
end,false)

local function showCourseChoice()
    local menu = courseMenu
    if menu and frontendRunning() then
        local option=menu.options[menu.index]
        if type(option)=="table" and cameras[option.board] then
            if not previewCamera then
                previewCamera={target=getCameraTarget(), matrix={getCameraMatrix()}}
                setCameraMatrix(unpack(cameras[option.board]))
            end
            exports.frontend:showRaceCoursePreview(option)
            exports.frontend:showTextBox("Left / Right to browse.~n~Enter to race.~n~Backspace to exit.",0,false)
        else
            exports.frontend:showTextBox(("%s (%d/%d)~n~Left / Right to browse. Enter to select."):format(
                option,menu.index,#menu.options),0,false)
        end
    end
end

addEvent("mission:courseMenu",true)
addEventHandler("mission:courseMenu",resourceRoot,function(token,id,options,serial,initialIndex)
    if token ~= MissionRunToken or #options == 0 then return end
    courseMenu = {id=id,index=initialIndex or 1,options=options,serial=serial}
    showCourseChoice()
end,false)

addEvent("mission:courseSelected",true)
addEventHandler("mission:courseSelected",resourceRoot,function(token,serial)
    if token==MissionRunToken and courseMenu and courseMenu.serial==serial then
        closeCourseChoice()
    end
end,false)

addEventHandler("onClientKey",root,function(key,pressed)
    local menu = courseMenu
    if not menu or not pressed or isChatBoxInputActive() or isConsoleActive() then return end
    if key == "arrow_l" or key == "arrow_r" then
        local step=key=="arrow_l" and -1 or 1
        if menu.id=="turismo" then menu.index=math.max(1,math.min(#menu.options,menu.index+step))
        else menu.index=(menu.index-1+step)%#menu.options+1 end
        showCourseChoice()
    elseif key == "enter" or key == "num_enter" or (key=="backspace" and (menu.id=="turismo" or menu.id=="golf")) then
        closeCourseChoice()
        local choice=menu.index
        if key=="backspace" then choice=false end
        triggerServerEvent("mission:courseChoice",resourceRoot,MissionRunToken,menu.id,choice,menu.serial)
    else return end
    cancelEvent()
end)

addEvent("mission:clearUi",true)
addEventHandler("mission:clearUi",resourceRoot,function() clearHud() end,false)
addEvent("mission:hud",true)
addEventHandler("mission:hud",resourceRoot,function(id,level,seconds,label,value,bar,percent,token,countdown,secondCounter)
    if not active or token~=MissionRunToken or not frontendRunning() then return end
    local showLevel = id == "vigilante" or id == "paramedic" or id == "airrescue" or id == "beachpatrol" or id == "firefighter"
    exports.frontend:showVehicleMissionHud(seconds, showLevel and level or false, label, value, bar, percent, countdown, secondCounter)
end,false)
addEventHandler("onClientResourceStart",root,function(started)
    if source==resourceRoot or started==getResourceFromName("frontend") then
        triggerServerEvent("mission:ready",resourceRoot)
    end
end)
addEventHandler("onClientResourceStop",resourceRoot,clearHud)
addEventHandler("onClientResourceStop",root,function(stopped)
    if stopped==getResourceFromName("frontend") and courseMenu and courseMenu.id=="turismo" then
        local menu=courseMenu
        closeCourseChoice(true)
        triggerServerEvent("mission:courseChoice",resourceRoot,MissionRunToken,menu.id,false,menu.serial)
    end
end)

local function protectMissionActor(attacker,weapon,_,_,_,_,tyre)
    local owner=getElementData(source,"mission:actorOwner",false)
    if not owner then return end
    local vehicleHit=isElement(attacker) and getElementType(attacker)=="vehicle"
    if vehicleHit then attacker=getVehicleController(attacker) end
    local rival=getElementData(source,"mission:turismoRival",false)
    if rival and rival~="recovering" then
        if rival=="driver" then
            local armed=type(weapon)=="number" and (weapon>=1 and weapon<=18 or weapon>=22 and weapon<=42)
            if vehicleHit or attacker~=owner or not armed then
                cancelEvent()
            elseif attacker==localPlayer and MissionRunToken then
                triggerServerEvent("mission:turismoWeaponHit",resourceRoot,MissionRunToken,source,weapon)
            end
            return
        end
        local protectedCar=rival=="racing" and (weapon==18 or weapon==37 or tyre and tyre>=0)
        if attacker~=owner or protectedCar then
            cancelEvent()
        end
    elseif isElement(attacker) and getElementType(attacker)=="player" and attacker~=owner then
        cancelEvent()
    end
end
addEventHandler("onClientPedDamage",root,protectMissionActor,true,"high")
addEventHandler("onClientVehicleDamage",root,protectMissionActor,true,"high")

-- MTA sets DoesNotGetTired at client startup. Restore the VCS sprint budget
-- until Paramedic grants opcode 01FB. SLUS 0022F9F4, 00232A40 and 0023A870.
local energy, capacity, practice = 150,150,0
local exhausted = false
local swimEnergy, swimExhausted = 1,false
local swimDisplay
local function showSwimEnergy(value)
    if value == swimDisplay then return end
    swimDisplay = value
    setElementData(localPlayer,"mission:swimEnergy",value,false)
end

-- SLUS 002D6058 sets player-info +0x164. 001F3060 reads it before deducting
-- swimming endurance using horizontal velocity and the 50 Hz game time step.
local function swimming(step)
    local vx,vy = getElementVelocity(localPlayer)
    local multiplier = getPedControlState(localPlayer,"sprint") and 3 or 1
    if getElementData(localPlayer,"mission:unlimitedSwim",false) then
        swimEnergy=1
    else
        local spent=(math.sqrt(vx*vx+vy*vy)*0.005+0.00005)*multiplier*step
        swimEnergy=math.max(0,swimEnergy-spent)
    end
    showSwimEnergy(math.floor(swimEnergy*100))
    if swimEnergy==0 and isControlEnabled("sprint") then
        toggleControl("sprint",false)
        swimExhausted=true
    end
end

local function releaseSprint()
    if exhausted or swimExhausted then
        toggleControl("sprint",true)
        exhausted,swimExhausted=false,false
    end
end
addEventHandler("onClientPreRender",root,function(elapsed)
    local step=math.min(3,elapsed/20)
    if not isPedDead(localPlayer) and not isPedInVehicle(localPlayer) and isElementInWater(localPlayer) then
        if exhausted or (swimExhausted and getElementData(localPlayer,"mission:unlimitedSwim",false)) then releaseSprint() end
        swimming(step)
        return
    end
    if swimExhausted then releaseSprint() end
    if swimDisplay~=nil then showSwimEnergy(false) end
    swimEnergy = isPedDead(localPlayer) and 1 or math.min(1,swimEnergy+step*0.002)
    if getElementData(localPlayer,"mission:unlimitedSprint",false) or isPedDead(localPlayer) then
        energy=capacity
        releaseSprint()
        return
    end
    if not isPedInVehicle(localPlayer) and getPedMoveState(localPlayer)=="sprint" then
        local spent=step*0.5
        energy=math.max(-100,energy-spent)
        practice=practice+spent
        if practice>=500 then
            capacity=math.min(2000,capacity+10)
            practice=0
        end
        if energy<=-100 and isControlEnabled("sprint") then
            toggleControl("sprint",false)
            exhausted=true
        end
    else
        energy=math.min(capacity,energy+step*0.5)
        if exhausted and energy>=0 then releaseSprint() end
    end
end)
addEventHandler("onClientResourceStop",resourceRoot,releaseSprint)
addEventHandler("onClientResourceStop",resourceRoot,function()
    if swimDisplay~=nil then setElementData(localPlayer,"mission:swimEnergy",false,false) end
end)

-- Fireproofing belongs to the saved player. Direct explosion and bullet
-- damage retain their own MTA damage types.
addEventHandler("onClientPlayerDamage",localPlayer,function(_,weapon)
    if (weapon==37 or weapon==18) and getElementData(localPlayer,"mission:fireproof",false) then
        cancelEvent()
        if isPedOnFire(localPlayer) then setPedOnFire(localPlayer,false) end
    end
end)
