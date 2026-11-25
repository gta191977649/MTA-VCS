local range=DrivingRange
local scene,waiting
local models={}
local function track(element)
    if element then setElementParent(element,scene.root) end
    return element
end

local function playCue(name,pos)
    local sound=track(playSound3D("assets/golf_"..name..".wav",pos[1],pos[2],pos[3],false,false))
    if sound then setSoundMinDistance(sound,5) setSoundMaxDistance(sound,90) end
end
local function model(name)
    local id=engineRequestModel("object")
    if not id then return end
    models[name]=id
    local txd=track(engineLoadTXD("assets/"..name..".txd"))
    local dff=track(engineLoadDFF("assets/"..name..".dff"))
    if txd and dff then engineImportTXD(txd,id) engineReplaceModel(dff,id) end
    return id
end

local function prop(name,pos,heading)
    local obj=track(createObject(models[name] or model(name),pos[1],pos[2],pos[3],0,0,heading))
    if obj then setElementCollisionsEnabled(obj,false) setElementDoubleSided(obj,true) end
    return obj
end

local function frontend()
    local res=getResourceFromName("frontend")
    return res and getResourceState(res)=="running"
end

local function clear(token)
    if not token or waiting==token then waiting=nil end
    if not scene or (token and token~=scene.token) then return end
    if isElement(scene.root) then destroyElement(scene.root) end
    for _,id in pairs(models) do engineFreeModel(id) end
    models={}
    if isElement(scene.target) then setCameraTarget(scene.target) else setCameraMatrix(unpack(scene.camera)) end
    for control,enabled in pairs(scene.controls) do toggleControl(control,enabled) end
    for player,alpha in pairs(scene.hidden) do if isElement(player) then setElementAlpha(player,alpha) end end
    if frontend() then exports.frontend:showGolfMeter(false) exports.frontend:showTextBox(false) end
    scene=nil
end

local function pose(clip,loop)
    if isElement(scene.actor) then setPedAnimation(scene.actor,"vcs_golf",clip,-1,loop,false,false,true) end
end
local function elapsed()
    return MissionVisualElapsed(scene.start) or math.max(0,getTickCount()-scene.received)
end

addEvent("mission:golfPrompt",true)
addEventHandler("mission:golfPrompt",resourceRoot,function(name)
    if MissionRunToken or not frontend() then return end
    exports.frontend:showTextBox(name and (name.." challenges you. Press E to respond at the range.") or
        "Press E to play Swinger's Club.",6000)
end,false)

addEvent("mission:golfTurn",true)
addEventHandler("mission:golfTurn",resourceRoot,function(token,turn,player,shot,scores,target)
    if token~=MissionRunToken or not isElement(player) then return end
    waiting=nil
    if not scene then
        scene={root=createElement("golf-round"),token=token,camera={getCameraMatrix()},target=getCameraTarget(),controls={},hidden={}}
        for _,control in ipairs({"fire","aim_weapon","enter_exit","jump","sprint","forwards","backwards","left","right","crouch","action","next_weapon","previous_weapon"}) do
            scene.controls[control]=isControlEnabled(control)
            toggleControl(control,false)
        end
        setElementParent(scene.root,resourceRoot)
        track(engineLoadIFP("assets/golf.ifp","vcs_golf"))
        scene.club=prop("golfclub",range.tee,20)
        scene.buoy=prop("bouy",range.buoy,110)
        scene.ball=prop("ndc_golfball",range.ball,110)
    end
    for _,ped in ipairs({localPlayer,player}) do
        if scene.hidden[ped]==nil then scene.hidden[ped]=getElementAlpha(ped) setElementAlpha(ped,0) end
    end
    if isElement(scene.actor) then destroyElement(scene.actor) end
    local tee=range.tee
    local ground=getGroundPosition(tee[1],tee[2],tee[3]+3) or tee[3]
    scene.actor=track(createPed(getElementModel(player),tee[1],tee[2],math.max(ground,tee[3])+0.95,20))
    if scene.actor then
        setElementCollisionsEnabled(scene.actor,false)
        setElementFrozen(scene.actor,true)
    end
    pose("golf_idle",true)
    scene.turn,scene.phase,scene.player=turn,"ready",player
    if isElement(scene.ball) then setElementPosition(scene.ball,unpack(range.ball)) end
    setCameraMatrix(76.7,592.01,14.62,75.74,591.7,14.61)
    exports.frontend:showGolfMeter(false)
    local hint=player==localPlayer and "Space to begin. Backspace to leave." or ("Watching "..getPlayerName(player)..".")
    exports.frontend:showTextBox(("Shot %d/5. Beat %d.~n~%s~n~%s"):format(shot,target,scores,hint),0,false)
end,false)

addEvent("mission:golfPhase",true)
addEventHandler("mission:golfPhase",resourceRoot,function(token,turn,phase,start,power,angle)
    if not scene or scene.token~=token or scene.turn~=turn then return end
    if phase=="aim" or phase=="swing" then
        exports.frontend:playVcsFrontendSound("race_gate")
        exports.frontend:playVcsFrontendSound("race_gate_center")
    end
    scene.phase,scene.start,scene.power,scene.received=phase,start,power,getTickCount()
    local active=scene.player==localPlayer
    if phase=="power" or phase=="aim" then
        local label=phase=="power" and "power" or "accuracy"
        exports.frontend:showTextBox(active and ("Press Space in the green section to set "..label..".") or
            (getPlayerName(scene.player).." is setting "..label.."."),0,false)
    else
        exports.frontend:showGolfMeter(false)
        exports.frontend:showTextBox(false)
        if phase=="swing" then
            pose("golf_swing",false)
            playCue("swing",range.tee)
        elseif phase=="flight" then
            local points,distance,bonus=range.flight(power,angle)
            scene.points,scene.contact,scene.hit=points,bonus,false
            playCue("strike",range.ball)
            scene.base,scene.fast=0,false
            if active then exports.frontend:showTextBox("Hold Space to fast forward your shot.",3500) end
        elseif phase=="result" then
            local last=scene.points and scene.points[#scene.points]
            if last and isElement(scene.ball) then setElementPosition(scene.ball,unpack(last)) end
            if last then
                if scene.contact and not scene.hit then playCue("buoy",scene.points[scene.contact]) end
                fxAddWaterSplash(last[1],last[2],last[3])
                playCue("water",last)
            end
            pose("golf_wait",true)
        end
    end
end,false)

addEvent("mission:golfSpeed",true)
addEventHandler("mission:golfSpeed",resourceRoot,function(token,turn,start,base,fast)
    if scene and scene.token==token and scene.turn==turn and scene.phase=="flight" then
        scene.start,scene.base,scene.fast,scene.received=start,base,fast,getTickCount()
    end
end,false)

-- CVisibilityPlugins::RenderWeaponPedsForPC binds the weapon frame to BONE_R_HAND.
addEventHandler("onClientPedsProcessed",root,function()
    if not scene or not isElement(scene.actor) or not isElement(scene.club) then return end
    local hand=getElementBoneMatrix(scene.actor,24)
    if hand then setElementMatrix(scene.club,hand) end
end)

addEventHandler("onClientPreRender",root,function()
    if not scene then return end
    local phase=scene.phase
    if phase=="aim" or phase=="power" then
        exports.frontend:showGolfMeter(phase,range.meter(phase,elapsed(),scene.power))
    elseif phase=="flight" and scene.points and isElement(scene.ball) then
        local t=(scene.base+elapsed()*(scene.fast and 0.8 or 0.4))/20
        local i=math.min(#scene.points,math.floor(t)+1)
        if scene.contact and i>=scene.contact and not scene.hit then
            scene.hit=true
            playCue("buoy",scene.points[scene.contact])
        end
        local a,b=scene.points[i],scene.points[math.min(i+1,#scene.points)]
        local k=t-math.floor(t)
        local x,y,z=a[1]+(b[1]-a[1])*k,a[2]+(b[2]-a[2])*k,a[3]+(b[3]-a[3])*k
        setElementPosition(scene.ball,x,y,z)
        if range.ball[1]-x>28 then setCameraMatrix(x+6.58,y+2.39,z+1,x,y,z) end
    end
end)

local function input(action)
    if scene then triggerServerEvent("mission:golfInput",resourceRoot,scene.token,scene.turn,scene.phase,action) end
end
local function swing()
    if not scene or scene.player~=localPlayer then return end
    if scene.phase=="flight" then input(true)
    elseif scene.phase=="ready" or scene.phase=="power" or scene.phase=="aim" then input("strike") end
end
local function enter()
    if MissionRunToken or isPedInVehicle(localPlayer) or isChatBoxInputActive() or isConsoleActive() then return end
    local x,y,z=getElementPosition(localPlayer)
    if getDistanceBetweenPoints3D(x,y,z,unpack(range.entry))<=4 then
        triggerServerEvent("mission:golfEnter",resourceRoot)
    end
end
addCommandHandler("golf",enter)
addCommandHandler("golfswing",swing)
bindKey("e","down",enter)
bindKey("space","down",swing)
bindKey("space","up",function() if scene and scene.phase=="flight" and scene.player==localPlayer then input(false) end end)
addEvent("mission:golfWaiting",true)
addEventHandler("mission:golfWaiting",resourceRoot,function(token)
    if token==MissionRunToken then waiting=token end
end,false)
bindKey("backspace","down",function()
    if isChatBoxInputActive() or isConsoleActive() then return end
    if scene then input("leave")
    elseif waiting==MissionRunToken and waiting then triggerServerEvent("mission:golfInput",resourceRoot,waiting,0,"waiting","leave") end
end)
addEvent("mission:golfDepart",true)
addEventHandler("mission:golfDepart",resourceRoot,function(token,player)
    if scene and token==scene.token and isElement(player) and scene.hidden[player]~=nil then
        setElementAlpha(player,scene.hidden[player])
        scene.hidden[player]=nil
    end
end,false)
addEvent("mission:golfStop",true)
addEventHandler("mission:golfStop",resourceRoot,clear,false)
addEventHandler("onClientResourceStop",resourceRoot,function() clear() end)
