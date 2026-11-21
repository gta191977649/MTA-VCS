local snapshot
local wheel=Ferris.new()
local carriages,models,assets={},{},{}
local hub,hubMatrix,hubCollisions
local ifp,modelId
local seatPose,greetingPose
local greetingBones={}
local npcRecords,spectatorRecords,gestures={},{},{}
local playerRecords={}
local posedPlayers=setmetatable({},{__mode="k"})
local localSeat
local savedControls={}
local seatControls={"forwards","backwards","left","right","jump","sprint","crouch","fire","aim_weapon","enter_exit"}
local exitQueued,exitReady=false,false
local ownHelp,lastHelp=false,nil
local block="funfield.riders"
local accumulator=0
local currentCarriage
local lastContactIndex,lastContactAt=nil,0
local seatInputUntil=0
local seats=Ferris.seats

local function restoreControls()
    for name,enabled in pairs(savedControls) do toggleControl(name,enabled) end
    savedControls={}
end

local function clearSeatPose(ped)
    local playingBlock=getPedAnimation(ped)
    if playingBlock==block then setPedAnimation(ped) end
end

local function help(text)
    local frontend=getResourceFromName("frontend")
    if not frontend or getResourceState(frontend)~="running" then ownHelp,lastHelp=false,nil return end
    if text==lastHelp then return end
    if text then
        exports.frontend:showTextBox(text,0,not ownHelp)
        ownHelp=true
    elseif ownHelp then
        exports.frontend:showTextBox(false)
        ownHelp=false
    end
    lastHelp=text
end

local function validWorld()
    return getElementInterior(localPlayer)==0 and getElementDimension(localPlayer)==0 and not isPedDead(localPlayer)
end

local function restoreHub()
    if isElement(hub) then
        if hubMatrix then setElementMatrix(hub,hubMatrix) end
        setElementCollisionsEnabled(hub,hubCollisions)
    end
    hub,hubMatrix=nil,nil
end

local function clearCarriages()
    for _,object in pairs(carriages) do if isElement(object) then destroyElement(object) end end
    carriages={}
    currentCarriage=nil
    lastContactIndex,lastContactAt=nil,0
    restoreHub()
end

local function loadAssets()
    local file=fileOpen("assets/seat_pose.json",true)
    if file then seatPose=fromJSON(fileRead(file,fileGetSize(file))) fileClose(file) end
    if not seatPose then return false end
    file=fileOpen("assets/greeting_pose.json",true)
    if file then greetingPose=fromJSON(fileRead(file,fileGetSize(file))) fileClose(file) end
    if not greetingPose then return false end
    for index,bone in ipairs(greetingPose.bones) do greetingBones[bone]=index*4-3 end
    modelId=engineRequestModel("object",1218)
    if not modelId then return false end
    models[#models+1]=modelId
    local txd=engineLoadTXD("assets/carriage.txd")
    local dff=engineLoadDFF("assets/carriage.dff")
    local col=engineLoadCOL("assets/carriage.col")
    ifp=engineLoadIFP("assets/riders.ifp",block)
    for _,asset in ipairs({txd,dff,col,ifp}) do assets[#assets+1]=asset end
    if not txd or not dff or not col or not ifp then return false end
    engineImportTXD(txd,modelId)
    engineReplaceModel(dff,modelId,true)
    engineReplaceCOL(col,modelId)
    engineSetModelLODDistance(modelId,300)
    return true
end

local function findHub()
    if isElement(hub) then return true end
    for _,object in ipairs(getElementsByType("object")) do
        if getElementID(object)=="ferris_wheel" and getElementInterior(object)==0
            and getElementDimension(object)==0 then
            local x,y,z=getElementPosition(object)
            if (x-Ferris.x)^2+(y-Ferris.y)^2+(z-Ferris.z)^2<1 then
                hub,hubMatrix,hubCollisions=object,getElementMatrix(object),getElementCollisionsEnabled(object)
                setElementCollisionsEnabled(hub,false)
                return true
            end
        end
    end
    return false
end

local function ensureCarriages()
    if not modelId or not findHub() then return false end
    if not next(carriages) then
        for index=0,11 do
            local x,y,z=Ferris.position(wheel,index)
            local object=createObject(modelId,x,y,z,0,0,180)
            if not object then clearCarriages() return false end
            setElementID(object,"funfield:carriage:"..index)
            setElementFrozen(object,true)
            setObjectBreakable(object,false)
            setElementStreamable(object,false)
            carriages[index]=object
        end
    end
    return true
end

function getFerrisWheelState()
    local state={}
    for k,v in pairs(wheel) do state[k]=v end
    state.carriages=carriages
    state.riding=currentCarriage
    state.exitQueued=exitQueued
    state.exitReady=exitReady
    state.ready=next(carriages)~=nil
    state.hub=hub
    state.lod=isElement(hub) and getLowLODElement(hub) or false
    state.npcCount=#npcRecords
    state.spectatorCount=#spectatorRecords
    state.seated=localSeat and localSeat.seat or false
    state.riders=npcRecords
    state.players=playerRecords
    state.cinematic=FerrisCinema.state()
    return state
end

addEvent("funfield:state",true)
addEventHandler("funfield:state",resourceRoot,function(state)
    if source~=resourceRoot or type(state)~="table" then return end
    snapshot=state
    npcRecords,spectatorRecords=state.riders or {},state.spectators or {}
    playerRecords=state.players or {}
    wheel={}
    for k,v in pairs(state) do if type(v)~="table" then wheel[k]=v end end
    accumulator=0
end)

-- Apply player body poses after native ped processing, as the shared jet-ski
-- rider does. Native player facial animation remains untouched.
local skeleton={0,1,2,3,4,5,6,7,8,21,22,23,24,25,26,31,32,33,34,35,36,41,42,43,44,51,52,53,54,201,301,302}
addEventHandler("onClientPedsProcessed",root,function()
    if not seatPose or not snapshot or not snapshot.active then return end
    local phase=(wheel.time%4000)/1000*seatPose.rate
    local first=math.min(#seatPose.frames,math.floor(phase)+1)
    local second=math.min(#seatPose.frames,first+1)
    local fraction=phase-math.floor(phase)
    local a,b=seatPose.frames[first],seatPose.frames[second]
    for _,record in ipairs(playerRecords) do
        local ped,car=record.ped,carriages[record.index]
        if isElement(ped) and isElement(car) and not isPedDead(ped) and getElementData(ped,"funfield:seated") then
            local greeting=record.greetingAt and wheel.time>=record.greetingAt and wheel.time<record.greetingUntil
            local ga,gb,gf,weight
            if greeting then
                local age=wheel.time-record.greetingAt
                local p=math.min(#greetingPose.frames-1,age/1000*greetingPose.rate)
                local index=math.floor(p)+1
                ga,gb=greetingPose.frames[index],greetingPose.frames[math.min(#greetingPose.frames,index+1)]
                gf=p-math.floor(p)
                weight=math.max(0,math.min(1,age/180,(record.greetingUntil-wheel.time)/180))
                weight=weight*weight*(3-2*weight)
            end
            for n,bone in ipairs(seatPose.bones) do
                local k=n*4-3
                local sign=a[k]*b[k]+a[k+1]*b[k+1]+a[k+2]*b[k+2]+a[k+3]*b[k+3]<0 and -1 or 1
                local x=a[k]*(1-fraction)+b[k]*fraction*sign
                local y=a[k+1]*(1-fraction)+b[k+1]*fraction*sign
                local z=a[k+2]*(1-fraction)+b[k+2]*fraction*sign
                local w=a[k+3]*(1-fraction)+b[k+3]*fraction*sign
                local norm=math.sqrt(x*x+y*y+z*z+w*w)
                x,y,z,w=x/norm,y/norm,z/norm,w/norm
                local gk=greetingBones[bone]
                if greeting and gk then
                    local gs=ga[gk]*gb[gk]+ga[gk+1]*gb[gk+1]+ga[gk+2]*gb[gk+2]+ga[gk+3]*gb[gk+3]<0 and -1 or 1
                    local gx=ga[gk]*(1-gf)+gb[gk]*gf*gs
                    local gy=ga[gk+1]*(1-gf)+gb[gk+1]*gf*gs
                    local gz=ga[gk+2]*(1-gf)+gb[gk+2]*gf*gs
                    local gw=ga[gk+3]*(1-gf)+gb[gk+3]*gf*gs
                    local gn=math.sqrt(gx*gx+gy*gy+gz*gz+gw*gw)
                    gx,gy,gz,gw=gx/gn,gy/gn,gz/gn,gw/gn
                    local direction=x*gx+y*gy+z*gz+w*gw<0 and -1 or 1
                    x,y,z,w=x*(1-weight)+gx*weight*direction,y*(1-weight)+gy*weight*direction,
                        z*(1-weight)+gz*weight*direction,w*(1-weight)+gw*weight*direction
                    norm=math.sqrt(x*x+y*y+z*z+w*w)
                    x,y,z,w=x/norm,y/norm,z/norm,w/norm
                end
                -- Player skins retain their own facial bind/animation basis.
                -- VCS's jaw track distorts native SA mouths on more than CJ.
                if bone~=8 then setElementBoneQuaternion(ped,bone,x,y,z,w) end
            end
            updateElementRpHAnim(ped)
            local pelvis=getElementBoneMatrix(ped,1)
            local m=getElementMatrix(car)
            local seat=seats[record.seat]
            local direction=seat[4]==0 and 1 or -1
            local r1,r2=seatPose.root[first],seatPose.root[second]
            local x=seat[1]+(r1[1]+(r2[1]-r1[1])*fraction)*direction
            local y=seat[2]+(r1[2]+(r2[2]-r1[2])*fraction)*direction
            local z=seat[3]+r1[3]+(r2[3]-r1[3])*fraction
            if pelvis then
                local dx=m[4][1]+x*m[1][1]+y*m[2][1]+z*m[3][1]-pelvis[4][1]
                local dy=m[4][2]+x*m[1][2]+y*m[2][2]+z*m[3][2]-pelvis[4][2]
                local dz=m[4][3]+x*m[1][3]+y*m[2][3]+z*m[3][3]-pelvis[4][3]
                for _,bone in ipairs(skeleton) do
                    local bm=getElementBoneMatrix(ped,bone)
                    if bm then
                        bm[4][1],bm[4][2],bm[4][3]=bm[4][1]+dx,bm[4][2]+dy,bm[4][3]+dz
                        setElementBoneMatrix(ped,bone,bm)
                    end
                end
                if ped==localPlayer then
                    local head=getElementBoneMatrix(ped,5)
                    if head then FerrisCinema.setPlayerFocus(head[4][1],head[4][2],head[4][3]+.15) end
                end
            end
        end
    end
end,true,"low")
addEvent("funfield:exitQueued",true)
addEventHandler("funfield:exitQueued",resourceRoot,function() exitQueued=true exitReady=false end)
addEvent("funfield:exitReady",true)
addEventHandler("funfield:exitReady",resourceRoot,function() exitQueued=false exitReady=true end)
addEvent("funfield:stood",true)
addEventHandler("funfield:stood",resourceRoot,function()
    FerrisCinema.stop("stand")
    localSeat=nil
    clearSeatPose(localPlayer)
    restoreControls()
end)
addEvent("funfield:seatFull",true)
addEventHandler("funfield:seatFull",resourceRoot,function()
    exports.frontend:showTextBox("This carriage has no free seats.",2500)
    lastHelp=nil
end)

local function requestExit()
    if validWorld() and currentCarriage and not exitQueued and not isChatBoxInputActive()
        and not isConsoleActive() and not isMainMenuActive() then
        triggerServerEvent("funfield:exit",resourceRoot)
    end
end
addCommandHandler("exitferris",requestExit)
bindKey("e","down",requestExit)

local function seatInputAllowed()
    return validWorld() and currentCarriage~=nil and not isPedInVehicle(localPlayer)
        and not isChatBoxInputActive() and not isConsoleActive() and not isMainMenuActive()
end
local function seatContact()
    return currentCarriage~=nil and (getPedContactElement(localPlayer)==carriages[currentCarriage]
        or lastContactIndex==currentCarriage and getTickCount()-lastContactAt<250 and isPedOnGround(localPlayer))
end
local function toggleSeat()
    if seatInputAllowed() and (localSeat or seatContact()) then
        seatInputUntil=getTickCount()+700
        if localSeat then FerrisCinema.stop("stand") end
        triggerServerEvent("funfield:seat",resourceRoot)
    end
end
addCommandHandler("sitferris",toggleSeat)
bindKey("f","down",toggleSeat)
addEventHandler("onClientVehicleStartEnter",root,function(player)
    if player~=localPlayer then return end
    local consumingF=getKeyState("f") and seatInputAllowed()
        and (localSeat or seatContact())
    if localSeat or getTickCount()<seatInputUntil or consumingF then cancelEvent() end
end)

local function placeSeatedPed(ped,r)
    local object=carriages[r.index]
    if not isElement(object) or not isElement(ped) or isPedDead(ped) then return false end
    local m=getElementMatrix(object)
    local seat=seats[r.seat]
    local x,y,z=seat[1],seat[2],seat[3]
    local d=seat[4]==0 and 1 or -1
    -- 00213FB8 multiplies the entire ped matrix by the carriage transform.
    -- Both rows face the centre aisle; attachment Z is applied directly.
    setElementMatrix(ped,{{m[1][1]*d,m[1][2]*d,m[1][3]*d,0},
        {m[2][1]*d,m[2][2]*d,m[2][3]*d,0},{m[3][1],m[3][2],m[3][3],0},
        {m[4][1]+x*m[1][1]+y*m[2][1]+z*m[3][1],
         m[4][2]+x*m[1][2]+y*m[2][2]+z*m[3][2],
         m[4][3]+x*m[1][3]+y*m[2][3]+z*m[3][3],1}})
    return true
end

local function updateRiders(now)
    for _,r in ipairs(npcRecords) do
        local object,ped=carriages[r.index],r.ped
        if isElement(object) and isElement(ped) and not isPedDead(ped) then
            placeSeatedPed(ped,r)
            local px,py,pz=getElementPosition(localPlayer)
            local nx,ny,nz=getElementPosition(ped)
            -- 04B5 -> 0041DA30 toggles entity collision, including bullet traces.
            -- The SCM enables it near the player or when observed through a scope.
            local scope=getPedWeapon(localPlayer)==34 and getPedControlState(localPlayer,"aim_weapon")
            local collide=(px-nx)^2+(py-ny)^2+(pz-nz)^2<4 or scope and isElementOnScreen(ped)
            if getElementCollisionsEnabled(ped)~=collide then setElementCollisionsEnabled(ped,collide) end
            local untilTick=getElementData(ped,"funfield:gestureUntil") or 0
            local gesture=gestures[ped]
            if not gesture or gesture.tick~=untilTick then
                gesture={tick=untilTick,ends=now+1200}
                gestures[ped]=gesture
            end
            local replying=r.greetingAt and wheel.time>=r.greetingAt and wheel.time<r.greetingUntil
            local clip=(replying or gesture.ends>now and untilTick>0) and "seat_handsup" or "seat_idle"
            local _,playing=getPedAnimation(ped)
            if playing~=clip then setPedAnimation(ped,block,clip,-1,true,false,false,false,150) end
            if isElement(r.lookTarget) then
                local tx,ty,tz=getPedBonePosition(r.lookTarget,8)
                setPedLookAt(ped,tx,ty,tz,350,100,r.lookTarget)
            end
        end
    end
    local previousSeat=localSeat
    localSeat=nil
    local seatedNow={}
    for _,r in ipairs(playerRecords) do
        if isElement(r.ped) and getElementData(r.ped,"funfield:seated") and placeSeatedPed(r.ped,r) then
            setElementVelocity(r.ped,0,0,0)
            seatedNow[r.ped]=true
            posedPlayers[r.ped]=true
            -- Body/greeting bones are supplied after native ped processing.
            -- Do not also run the VCS IFP on players: its jaw channel would
            -- overwrite the native face even when the manual pose skips it.
            clearSeatPose(r.ped)
            if r.ped==localPlayer then
                localSeat=r
                for _,name in ipairs(seatControls) do
                    if savedControls[name]==nil then savedControls[name]=isControlEnabled(name) end
                    toggleControl(name,false)
                end
            end
        elseif isElement(r.ped) then clearSeatPose(r.ped) end
    end
    for ped in pairs(posedPlayers) do
        if not seatedNow[ped] then
            if isElement(ped) then clearSeatPose(ped) end
            posedPlayers[ped]=nil
        end
    end
    if not localSeat then
        restoreControls()
        if previousSeat then clearSeatPose(localPlayer) end
    end
    for _,r in ipairs(spectatorRecords) do
        if isElement(r.ped) and isElement(r.target) then
            local x,y,z=getPedBonePosition(r.target,8)
            setPedLookAt(r.ped,x,y,z,350,100,r.target)
        end
    end
    -- Released spectators expire their short look request without retaining script control.
end

addEventHandler("onClientPreRender",root,function(delta)
    local now=getTickCount()
    if not snapshot then return end
    accumulator=accumulator+delta/1000
    while accumulator>=Ferris.step do Ferris.advance(wheel,Ferris.step) accumulator=accumulator-Ferris.step end
    local x,y,z=getElementPosition(localPlayer)
    local nearby=validWorld() and (x-Ferris.x)^2+(y-Ferris.y)^2+(z-Ferris.z)^2<300^2
    if not snapshot.active or not nearby then
        FerrisCinema.stop("world changed")
        clearCarriages()
        help(nil)
        exitQueued,exitReady=false,false
        localSeat=nil
        restoreControls()
        clearSeatPose(localPlayer)
        return
    end
    if not ensureCarriages() then FerrisCinema.stop("wheel unavailable") return end
    local visual={}
    for k,v in pairs(wheel) do visual[k]=v end
    visual.angle=wheel.angle+wheel.speed*accumulator
    local contact=getPedContactElement(localPlayer)
    local oldIndex
    for index,object in pairs(carriages) do if contact==object then oldIndex=index break end end
    if oldIndex~=nil then lastContactIndex,lastContactAt=oldIndex,now end
    setElementRotation(hub,math.deg(visual.angle)%360,0,180,"ZXY")
    for index,object in pairs(carriages) do
        local cx,cy,cz=Ferris.position(visual,index)
        setElementPosition(object,cx,cy,cz)
        setElementRotation(object,math.deg(visual.swing),0,180,"ZXY")
        -- MTA carries a grounded ped using the contact object's matrix delta.
        -- Adding that displacement to the ped again doubles its travel and
        -- pushes it into the carriage wall. Leave walking and jumping native.
    end
    updateRiders(now)
    FerrisCinema.update(localSeat,localSeat and carriages[localSeat.index],exitReady,wheel.phase,delta,npcRecords,carriages,hub,visual)
    x,y,z=getElementPosition(localPlayer)
    currentCarriage=oldIndex
    if localSeat then currentCarriage=localSeat.index end
    if currentCarriage==nil then
        -- Contact may be absent for a frame during object movement; geometry alone
        -- must not carry airborne players or prevent jumping out.
        currentCarriage=Ferris.rider(visual,x,y,z)
    end
    if currentCarriage~=nil then
        if exitReady and wheel.phase=="stopped" then
            help(localSeat and "Press ~h~F~w~ again to stand up from seat. The wheel has stopped; walk onto the platform to leave."
                or "The Ferris Wheel has stopped. Walk onto the platform to leave.")
        elseif exitQueued then help(localSeat and "Press ~h~F~w~ again to stand up from seat. Exit stop requested; wait for the platform."
            or "Exit stop requested. Wait for your carriage to reach the platform.")
        elseif localSeat then help("Press ~h~F~w~ again to stand up from seat. Press ~h~E~w~ to request an exit stop.")
        else help("Press ~h~F~w~ to sit. Press ~h~E~w~ to request an exit stop. You can also jump out.") end
    else
        exitQueued,exitReady=false,false
        if Ferris.atEntrance(x,y,z) then
            help(wheel.phase=="stopped" and "The Ferris Wheel has stopped. Walk into a carriage to board."
                or "Wait for the ~h~Ferris Wheel~w~ to stop.")
        else help(nil) end
    end
end)

addEventHandler("onClientResourceStart",resourceRoot,function()
    if not loadAssets() then outputDebugString("[funfield] Original carriage assets failed to load.",1) return end
    triggerServerEvent("funfield:ready",resourceRoot)
end)
addEventHandler("onClientResourceStop",resourceRoot,function()
    if currentCarriage~=nil and validWorld() then setElementPosition(localPlayer,unpack(Ferris.exit)) end
    help(nil)
    restoreControls()
    clearSeatPose(localPlayer)
    clearCarriages()
    for _,r in ipairs(npcRecords) do if isElement(r.ped) then setPedAnimation(r.ped) end end
    for ped in pairs(posedPlayers) do if isElement(ped) then clearSeatPose(ped) end end
    for _,asset in ipairs(assets) do if isElement(asset) then destroyElement(asset) end end
    for _,id in ipairs(models) do engineFreeModel(id) end
end)
