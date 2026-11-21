local wheel=Ferris.new()
local riders,spectators,visits,requests,ready={},{},{},{},{}
local playerSeats={}
local seatInputUntil={}
local exitDwellUntil=0
local active=false
local accumulator,lastTick=0,getTickCount()
local populationClock,snapshotClock=0,0
local dependencies={"vcs","eagleLoader","npchlc_traffic","frontend","marker"}
local function dependenciesRunning()
    for _,name in ipairs(dependencies) do
        local resource=getResourceFromName(name)
        if not resource or getResourceState(resource)~="running" then return false end
    end
    return true
end
local function validPlayer(p)
    return isElement(p) and getElementType(p)=="player" and not isPedDead(p)
        and getElementInterior(p)==0 and getElementDimension(p)==0 and not isPedInVehicle(p)
end
local function carriage(p)
    if not validPlayer(p) then return end
    if playerSeats[p] then return playerSeats[p].index end
    return Ferris.rider(wheel,getElementPosition(p))
end

function getFerrisWheelState()
    local state={}
    for k,v in pairs(wheel) do state[k]=v end
    state.active=active
    state.riders={}
    for ped,record in pairs(riders) do
        if isElement(ped) then
            state.riders[#state.riders+1]={ped=ped,index=record.index,seat=record.seat,lookTarget=record.lookTarget,
                greetingAt=record.greetingAt,greetingUntil=record.greetingUntil}
        end
    end
    state.spectators={}
    for ped,record in pairs(spectators) do
        if isElement(ped) then state.spectators[#state.spectators+1]={ped=ped,target=record.target} end
    end
    state.players={}
    for player,record in pairs(playerSeats) do
        if isElement(player) then state.players[#state.players+1]={ped=player,index=record.index,seat=record.seat,
            greetingAt=record.greetingAt,greetingUntil=record.greetingUntil} end
    end
    return state
end

local function snapshot(target)
    local state=getFerrisWheelState()
    if target then triggerClientEvent(target,"funfield:state",resourceRoot,state)
    else
        for player in pairs(ready) do
            if isElement(player) then triggerClientEvent(player,"funfield:state",resourceRoot,state) end
        end
    end
end

local function releaseSpectator(ped)
    local resource=getResourceFromName("npchlc_traffic")
    if isElement(ped) and resource and getResourceState(resource)=="running" then exports.npchlc_traffic:releaseTrafficPed(ped) end
    spectators[ped]=nil
end

local function clearPopulation()
    for ped in pairs(spectators) do releaseSpectator(ped) end
    for ped in pairs(riders) do
        if isElement(ped) then destroyElement(ped) end
    end
    riders={}
end

local function releaseSeat(player,place,notify)
    local record=playerSeats[player]
    if not record then return end
    playerSeats[player]=nil
    if isElement(player) then
        setElementData(player,"funfield:seated",false,"broadcast","deny")
        setElementFrozen(player,record.frozen)
        setElementCollisionsEnabled(player,record.collisions)
        if place and validPlayer(player) then
            local x,y,z=Ferris.position(wheel,record.index)
            setElementPosition(player,x,y,z-2.15,false)
            -- Carry the wheel's tangential velocity into a voluntary jump/fall.
            local angle=wheel.angle+record.index*Ferris.spacing
            setElementVelocity(player,0,math.cos(angle)*Ferris.radius*wheel.speed/50,
                -math.sin(angle)*Ferris.radius*wheel.speed/50)
        end
        if notify~=false and ready[player] and getResourceState(getThisResource())=="running" then
            triggerClientEvent(player,"funfield:stood",resourceRoot)
        end
    end
end

local function seatOccupied(index,seat)
    for ped,r in pairs(riders) do
        if isElement(ped) and not isPedDead(ped) and r.index==index and r.seat==seat then return true end
    end
    for _,r in pairs(playerSeats) do if r.index==index and r.seat==seat then return true end end
    return false
end

local function spawnPopulation()
    local count=0
    for index=0,11 do
        local group=math.random(0,2)
        local candidates=group==0 and {1,2} or group==1 and {3,4} or {math.random(1,2),math.random(3,4)}
        for _,seat in ipairs(candidates) do
            if count<20 and math.random(0,1)==1 then
                local sample=exports.npchlc_traffic:getTrafficPopulationAt(337.69,-243.22,11.06,getTime(),math.random(0,15))
                if sample and sample.originalModelId then
                    local x,y,z=Ferris.position(wheel,index)
                    local ped,reason=exports.npchlc_traffic:createTrafficScriptPed(sample.originalModelId,x,y,z-1.1,0,0)
                    if ped then
                        setElementFrozen(ped,true)
                        setElementCollisionsEnabled(ped,false)
                        setElementSyncer(ped,false)
                        setElementData(ped,"funfield:rider",{index=index,seat=seat})
                        riders[ped]={index=index,seat=seat,gestureUntil=0}
                        count=count+1
                    else
                        outputDebugString("[funfield] Rider model "..sample.originalModelId..": "..tostring(reason),2)
                    end
                end
            end
        end
    end
    outputDebugString("[funfield] Activated 12 carriages with "..count.." original civilian riders.")
end

local function updatePopulation(now)
    local alive={}
    for ped,r in pairs(riders) do
        if not isElement(ped) or isPedDead(ped) then
            if isElement(ped) then destroyElement(ped) end
            riders[ped]=nil
        else
            setElementMatrix(ped,Ferris.seatMatrix(wheel,r.index,r.seat))
            if now>=r.gestureUntil and math.random()<1-0.99^3 then
                r.gestureUntil=now+1200
                setElementData(ped,"funfield:gestureUntil",r.gestureUntil)
            end
            alive[#alive+1]=ped
        end
    end
    local count=0
    for ped,r in pairs(spectators) do
        if not isElement(ped) or isPedDead(ped) or now>=r.untilTick or not isElement(r.target) then
            releaseSpectator(ped)
        else count=count+1 end
    end
    -- SCM FERRIS_517: borrow ambient actors, never generate spectator doubles.
    if count<5 and #alive>0 and math.random(0,4)==0 then
        local ped=exports.npchlc_traffic:acquireTrafficPedInArea(316.8525,-268.58,346.5,-215.2524,11.06,0,0,true,true,true)
        if ped then
            local target=alive[math.random(#alive)]
            exports.npchlc_traffic:assignTrafficPedObjective(ped,"clear")
            local x,y=getElementPosition(ped)
            local tx,ty=getElementPosition(target)
            setPedRotation(ped,-math.deg(math.atan2(tx-x,ty-y)))
            spectators[ped]={target=target,untilTick=now+math.random(13000,17999)}
        end
    end
    if count>0 and count<5 then
        local watching={}
        for ped in pairs(spectators) do if isElement(ped) then watching[#watching+1]=ped end end
        for _,record in pairs(riders) do
            if #watching>0 and math.random()<1-0.99^3 then record.lookTarget=watching[math.random(#watching)] end
        end
    end
end

local function chooseStop()
    local target
    for _,r in pairs(requests) do
        local angle=Ferris.nextStop(wheel,r.index)
        if not target or angle<target then target=angle end
    end
    for _,visit in pairs(visits) do
        if visit.pending then
            local angle=Ferris.nextStop(wheel)
            if not target or angle<target then target=angle end
        end
    end
    if target then Ferris.stop(wheel,target) end
end

local function updatePlayers()
    if not dependenciesRunning() then return end
    local near,boarding=false,false
    for _,player in ipairs(getElementsByType("player")) do
        local seat=playerSeats[player]
        if seat then
            local expected=Ferris.seatMatrix(wheel,seat.index,seat.seat)[4]
            local px,py,pz=getElementPosition(player)
            local displaced=(px-expected[1])^2+(py-expected[2])^2+(pz-expected[3])^2>25
            if not validPlayer(player) or getElementHealth(player)<seat.health or displaced then
                releaseSeat(player,false)
                requests[player]=nil
            else
                setElementMatrix(player,Ferris.seatMatrix(wheel,seat.index,seat.seat))
            end
        end
        if validPlayer(player) then
            local x,y,z=getElementPosition(player)
            local distance=(x-Ferris.x)^2+(y-Ferris.y)^2+(z-Ferris.z)^2
            local index=carriage(player)
            if distance<275^2 or index then near=true end
            local inside=not index and Ferris.atEntrance(x,y,z)
            if inside then
                boarding=true
                if not visits[player] then visits[player]={pending=wheel.phase~="stopped"} end
            else visits[player]=nil end
            local request=requests[player]
            if request and index~=request.index then requests[player]=nil end
        else visits[player],requests[player]=nil,nil end
    end
    if not near and active then
        local retain=false
        for _,p in ipairs(getElementsByType("player")) do
            if getElementInterior(p)==0 and getElementDimension(p)==0 then
                local x,y,z=getElementPosition(p)
                if (x-Ferris.x)^2+(y-Ferris.y)^2+(z-Ferris.z)^2<300^2 then retain=true break end
            end
        end
        if not retain then active=false clearPopulation() end
    elseif near and not active then active=true spawnPopulation() end
    if wheel.phase=="stopped" then
        for _,visit in pairs(visits) do visit.pending=false end
        for p,r in pairs(requests) do
            local _,_,z=Ferris.position(wheel,r.index)
            if z<Ferris.z-Ferris.radius+0.05 then
                triggerClientEvent(p,"funfield:exitReady",resourceRoot)
                if playerSeats[p] then exitDwellUntil=math.max(exitDwellUntil,wheel.time+12000) end
                requests[p]=nil
            end
        end
        if not boarding and wheel.time>=exitDwellUntil and wheel.time-(wheel.stoppedAt or 0)>=Ferris.grace then
            wheel.phase="starting"
        end
    elseif wheel.phase~="stopping" then chooseStop()
    else
        local needed=next(requests)~=nil
        for _,visit in pairs(visits) do needed=needed or visit.pending end
        if not needed then
            wheel.phase=wheel.speed>=0.05 and "running" or "starting"
            wheel.target=nil
        end
    end
end

addEvent("funfield:ready",true)
addEventHandler("funfield:ready",resourceRoot,function()
    if client and source==resourceRoot then ready[client]=true snapshot(client) end
end)
addEvent("funfield:exit",true)
addEventHandler("funfield:exit",resourceRoot,function()
    if not client or source~=resourceRoot or requests[client] then return end
    local index=carriage(client)
    if index then
        requests[client]={index=index}
        triggerClientEvent(client,"funfield:exitQueued",resourceRoot)
        chooseStop()
        snapshot()
    end
end)
addEvent("funfield:greeting",true)
addEventHandler("funfield:greeting",resourceRoot,function(neighbor)
    if not client or source~=resourceRoot or not validPlayer(client) then return end
    local record=playerSeats[client]
    if not record or record.lastGreeting and wheel.time-record.lastGreeting<45000 then return end
    record.lastGreeting=wheel.time
    record.greetingAt,record.greetingUntil=wheel.time+1000,wheel.time+2200
    local other=riders[neighbor]
    if other and isElement(neighbor) and not isPedDead(neighbor) then
        local apart=math.abs(other.index-record.index)
        apart=math.min(apart,12-apart)
        if apart>0 and (not other.greetingUntil or wheel.time>other.greetingUntil) then
            other.greetingAt,other.greetingUntil=wheel.time+2400,wheel.time+3600
            other.lookTarget=client
        end
    end
    snapshot()
end)
addEvent("funfield:seat",true)
addEventHandler("funfield:seat",resourceRoot,function()
    if not client or source~=resourceRoot or not validPlayer(client) then return end
    if playerSeats[client] then
        seatInputUntil[client]=getTickCount()+700
        releaseSeat(client,true)
        snapshot()
        return
    end
    if isElementFrozen(client) then return end
    local index=carriage(client)
    if index==nil then return end
    seatInputUntil[client]=getTickCount()+700
    local x,y,z=getElementPosition(client)
    local chosen,distance
    for seat=1,4 do
        if not seatOccupied(index,seat) then
            local p=Ferris.seatMatrix(wheel,index,seat)[4]
            local d=(x-p[1])^2+(y-p[2])^2+(z-p[3])^2
            if not distance or d<distance then chosen,distance=seat,d end
        end
    end
    if not chosen then triggerClientEvent(client,"funfield:seatFull",resourceRoot) return end
    playerSeats[client]={index=index,seat=chosen,frozen=isElementFrozen(client),
        collisions=getElementCollisionsEnabled(client),health=getElementHealth(client)}
    setElementData(client,"funfield:seated",true,"broadcast","deny")
    -- Keep the player task live. Seat ownership supplies the transform and
    -- controls/collision; the client applies the final original bone pose.
    setElementVelocity(client,0,0,0)
    setElementCollisionsEnabled(client,false)
    setElementMatrix(client,Ferris.seatMatrix(wheel,index,chosen))
    snapshot()
end)
addEventHandler("onVehicleStartEnter",root,function(player)
    if playerSeats[player] or getTickCount()<(seatInputUntil[player] or 0) then cancelEvent() end
end)

setTimer(function()
    local now=getTickCount()
    accumulator=accumulator+(now-lastTick)/1000
    lastTick=now
    while accumulator>=Ferris.step do
        Ferris.advance(wheel,Ferris.step)
        accumulator=accumulator-Ferris.step
    end
    updatePlayers()
    if active and now-populationClock>=100 then populationClock=now updatePopulation(now) end
    if now-snapshotClock>=250 then snapshotClock=now snapshot() end
end,33,0)

addEventHandler("onPlayerQuit",root,function()
    releaseSeat(source,false,false)
    visits[source],requests[source],ready[source]=nil,nil,nil
    seatInputUntil[source]=nil
end)
addEventHandler("onPlayerWasted",root,function()
    releaseSeat(source,false)
    visits[source],requests[source]=nil,nil
end)
addEventHandler("onPlayerSpawn",root,function()
    releaseSeat(source,false)
    visits[source],requests[source]=nil,nil
end)
addEventHandler("onResourceStart",resourceRoot,function()
    local p=Ferris.entrance
    local marker=exports.marker:createMarker(p[1],p[2],p[3]-1,"cylinder",1.1,255,96,180,100)
    if marker then setElementParent(marker,resourceRoot) end
end)
local function recoverPlayers()
    for _,player in ipairs(getElementsByType("player")) do
        local riding=carriage(player)
        releaseSeat(player,false,false)
        if riding then setElementPosition(player,unpack(Ferris.exit)) end
    end
end
addEventHandler("onResourceStop",resourceRoot,function()
    recoverPlayers()
    clearPopulation()
end)
addEventHandler("onResourceStop",root,function(stopped)
    local name=getResourceName(stopped)
    for _,dependency in ipairs(dependencies) do
        if name==dependency then
            recoverPlayers()
            active=false
            clearPopulation()
            visits,requests={},{}
            snapshot()
            break
        end
    end
end)
