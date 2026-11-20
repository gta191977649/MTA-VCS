-- US VCS pedestrian type 20. All money, health, occupancy and clocks belong
-- to the server. The vehicle syncer supplies only its streamed floor material.
PedCarService = {}
local sessions, claimed = {}, {}
local scriptReleased = setmetatable({}, {__mode="k"})
local byName, sequence = {}, 0
local hlc = exports.npc_hlc
local healthCaps = {}
-- MTA CPed::GetMaxHealth clamps writes against stat 24 * 0.176.
local serviceHealthStat = math.ceil(125 / 0.176)
local function grantHealth(player,health)
    local stat=getPedStat(player,24)
    if stat*0.176 < health then
        if not setPedStat(player,24,serviceHealthStat) then return end
        healthCaps[player]=stat
    end
    setElementHealth(player,health)
end
local function releaseHealthCap(player)
    local previous=healthCaps[player]
    if previous and isElement(player) and getPedStat(player,24)==serviceHealthStat then
        setPedStat(player,24,previous)
    end
    healthCaps[player]=nil
end
local function age(now,before) return (now-before)%4294967296 end
local function due(now,deadline) return now ~= deadline and age(now,deadline) < 2147483648 end
local function sameWorld(a,b)
    return isElement(a) and isElement(b) and getElementDimension(a)==getElementDimension(b)
        and getElementInterior(a)==getElementInterior(b)
end
local function stopped(car)
    local x,y,z=getElementVelocity(car)
    return x*x+y*y+z*z < 0.0001
end
local function carInfo(car)
    local id=getElementData(car,"npchlc_traffic:originalModel",false)
    if id then return TrafficServiceCars[id] end
    -- Unconverted player cars can match an exact original model label.
    if not next(byName) then
        for _, row in pairs(TrafficServiceCars) do byName[row[1]]=row end
    end
    return byName[string.upper(getVehicleName(car))]
end
local function available(car,player)
    if not sameWorld(car,player) or getElementType(player)~="player" or isPedDead(player)
        or isVehicleLocked(car) or isVehicleBlown(car) or getVehicleOccupant(car,0)~=player
        or getVehicleType(car)~="Automobile" or getVehicleMaxPassengers(car)<1 then return false end
    for seat in pairs(getVehicleOccupants(car)) do if seat~=0 then return false end end
    return carInfo(car)
end
local function doorPoint(car)
    local m=getElementMatrix(car)
    local _,_,low,side,front=exports.server_coldata:getModelBoundingBox(getElementModel(car))
    if not m or not side then return end
    local x,y,z=unpack(m[4])
    -- Passenger side standing position in the converted model's bounds.
    side,front=side+0.55,front*0.16
    return x+side*m[1][1]+front*m[2][1], y+side*m[1][2]+front*m[2][2], z+low+0.85
end
local function finish(s,now)
    sessions[s.ped],claimed[s.player]=nil,nil
    s.walk.serviceEnded=now
    if isElement(s.ped) and not isPedInVehicle(s.ped) then hlc:clearNPCTasks(s.ped) end
end
local function endRide(s,now,spoken)
    if s.phase=="exit" then return end
    s.phase,s.exitAt,s.pending="exit",nil,nil
    if spoken then PedVoice.emit(s.player,"serviceEnd") end
    -- Release the player-record actor reference before the native exit.
    s.referenced=false
end
local function settleExit(s,now)
    if s.boarded and sameWorld(s.car,s.player) and getVehicleOccupant(s.car,0)==s.player
        and not isPedDead(s.player) then
        if s.referenced then s.walk.cash=((s.walk.cash or 0)+100)%65536 end
        takePlayerMoney(s.player,math.min(100,math.max(0,getPlayerMoney(s.player))))
    end
    finish(s,now)
end
function PedCarService.scriptReleased(ped)
    scriptReleased[ped]=getTickCount()
end
function PedCarService.relinquish(ped)
    if sessions[ped] then finish(sessions[ped],getTickCount()) end
end
function PedCarService.cancel(ped)
    local s=sessions[ped]
    if not s then return end
    if s.boarded and getPedOccupiedVehicle(ped)==s.car then
        endRide(s,getTickCount(),false)
    else
        finish(s,getTickCount())
    end
end
local function payment(s,now)
    if not due(now,s.payAt) then return end
    if getPlayerMoney(s.player)<2 then s.interval=250
    elseif takePlayerMoney(s.player,1) and s.referenced then
        s.walk.cash=((s.walk.cash or 0)+1)%65536
    end
    s.payAt=now+1000
end
local function delayForStreet(s,now)
    s.actionAt=now+3000
    s.interval=s.interval>=251 and s.interval<=999 and 250 or 1200
end
local function perform(s,now)
    local car,player=s.car,s.player
    local a,b=getVehicleVariant(car)
    if s.info[2] and a and b and a~=0 and b~=0 then
        grantHealth(player,125)
        endRide(s,now,true)
        return
    end
    -- PS2 applies a passenger-side downward turning force. Translate the
    -- torque into MTA angular velocity using the car's handling turn mass.
    local m=getElementMatrix(car)
    local h=getVehicleHandling(car)
    if m and h and h.turnMass and h.turnMass>0 then
        local px,py=getElementPosition(s.ped)
        local x,y=unpack(m[4])
        local force=-(0.8+0.4*math.random())*70/h.turnMass
        local ax,ay,az=getElementAngularVelocity(car)
        setElementAngularVelocity(car,ax+(py-y)*force,ay-(px-x)*force,az)
    end
    local x,y,z=getElementPosition(car)
    local listeners=getElementsWithinRange(x,y,z,35,"player",getElementInterior(car),getElementDimension(car))
    if listeners and #listeners>0 then
        triggerClientEvent(listeners,"npchlc_traffic:serviceSuspension",resourceRoot,car,math.random(55,69)/127,
            1+math.random(-1499,1499)/12000)
    end
    PedVoice.emit(player,"serviceAction")
    PedVoice.emit(s.ped,"serviceAction")
    if getPlayerMoney(player)<10 or s.interval<251 then endRide(s,now,true) return end
    s.actionAt=now+s.interval
    s.interval=math.max(250,s.interval-(s.interval>=350 and 30 or 10))
    grantHealth(player,math.min(125,math.floor(getElementHealth(player)+1)))
    if s.interval==250 then s.actionAt=now+3000 end
end
local function ride(s,now)
    if getPedOccupiedVehicle(s.ped)~=s.car then settleExit(s,now) return end
    if not sameWorld(s.ped,s.player) or getVehicleOccupant(s.car,0)~=s.player or isPedDead(s.player) then
        if due(now,s.actionAt) or not sameWorld(s.ped,s.player) then endRide(s,now,false) end
        if isElement(s.player) and not isPedDead(s.player) then payment(s,now) end
        return
    end
    if due(now,s.actionAt) then
        if not stopped(s.car) then
            s.pending,s.surface=nil,nil
            delayForStreet(s,now)
        elseif s.surface~=nil then
            if s.surface then perform(s,now) else delayForStreet(s,now) end
            s.surface=nil
        elseif not s.pending then
            local peer=getElementSyncer(s.car)
            if sameWorld(peer,s.car) then
                sequence=sequence+1
                local x,y,z=getElementPosition(s.car)
                s.pending={peer=peer,id=sequence,at=now,x=x,y=y,z=z}
                triggerClientEvent(peer,"npchlc_traffic:serviceFloor",resourceRoot,s.ped,s.car,sequence)
            else delayForStreet(s,now) end
        elseif age(now,s.pending.at)>=800 then
            s.pending=nil
            delayForStreet(s,now)
        end
    end
    payment(s,now)
end

addEvent("npchlc_traffic:serviceFloorResult",true)
addEventHandler("npchlc_traffic:serviceFloorResult",resourceRoot,function(ped,car,id,material)
    local s=sessions[ped]
    local p=s and s.pending
    if not p or p.id~=id or p.peer~=client or s.car~=car or not sameWorld(client,car)
        or getElementSyncer(car)~=client or getVehicleOccupant(car,0)~=s.player
        or getPedOccupiedVehicle(ped)~=car or age(getTickCount(),p.at)>=800 then return end
    local x,y,z=getElementPosition(car)
    s.pending=nil
    s.surface=stopped(car) and (x-p.x)^2+(y-p.y)^2+(z-p.z)^2<0.25
        and type(material)=="number" and material>=0 and material<=178 and material%1==0
        and material~=0 and material~=1 and material~=89
end,false)

local function tickSession(s,now)
    local ped,car,player=s.ped,s.car,s.player
    if not isElement(ped) or not isElement(car) or isPedDead(ped) then finish(s,now) return end
    if s.phase=="ride" then ride(s,now) return end
    if s.phase=="exit" then
        if getPedOccupiedVehicle(ped)~=car then settleExit(s,now)
        elseif not s.exitAt or age(now,s.exitAt)>=1200 then
            s.exitAt=now
            TrafficPassengers.requestExit(ped,car,getPedOccupiedVehicleSeat(ped))
        end
        return
    end
    if s.phase=="board" and getPedOccupiedVehicle(ped)==car and getPedOccupiedVehicleSeat(ped)>0
        and getVehicleOccupant(car,0)==player then
        s.phase,s.boarded,s.referenced="ride",true,true
        s.interval,s.actionAt,s.payAt=1000,now+3000,now+1000
        return
    end
    if not sameWorld(ped,car) or not available(car,player) or age(now,s.start)>10000 then finish(s,now) return end
    local x,y,z=doorPoint(car)
    if not x then finish(s,now) return end
    local px,py,pz=getElementPosition(ped)
    local d=(x-px)^2+(y-py)^2+(z-pz)^2
    if s.phase=="approach" then
        if d<=1 then
            hlc:clearNPCTasks(ped)
            local cx,cy=getElementPosition(car)
            setPedRotation(ped,-math.deg(math.atan2(cx-px,cy-py)))
            s.phase,s.waitAt="offer",now
            PedVoice.emit(ped,"serviceOffer")
            PedVoice.emit(player,"serviceOffer")
        elseif not s.dest or (x-s.dest[1])^2+(y-s.dest[2])^2+(z-s.dest[3])^2>0.25 then
            if not hlc:setNPCTask(ped,{"walkTrafficToPoint",x,y,z,0.45}) then finish(s,now) return end
            s.dest={x,y,z}
        end
    elseif s.phase=="offer" then
        if d>1 then finish(s,now) return end
        if age(now,s.waitAt)>1000 then
            if getPlayerMoney(player)<101 then finish(s,now) return end
            s.phase="board"
        end
    elseif s.phase=="board" then
        local peer=getElementSyncer(ped)
        if isElement(peer) and (s.peer~=peer or age(now,s.sent)>=1500) then
            s.peer,s.sent=peer,now
            triggerClientEvent(peer,"npchlc_traffic:boardPassenger",resourceRoot,ped,car)
        end
    end
end

function PedCarService.update(ped,walk,now)
    if sessions[ped] then return true end
    local model=walk.originalModelId
    if model~=31 and model~=50 and model~=76 or isPedInVehicle(ped) or walk.leader or walk.partner
        or walk.wait or scriptReleased[ped] and age(now,scriptReleased[ped])<=30000
        or PedActivity.active(ped) or walk.serviceEnded and age(now,walk.serviceEnded)<=10000 then return false end
    local x,y,z=getElementPosition(ped)
    for _,car in ipairs(getElementsWithinRange(x,y,z,5,"vehicle",getElementInterior(ped),getElementDimension(ped)) or {}) do
        local player=getVehicleOccupant(car,0)
        local info=available(car,player)
        local cx,cy,cz=getElementPosition(car)
        if info and not claimed[player] and (x-cx)^2+(y-cy)^2+(z-cz)^2<25 then
            local s={ped=ped,car=car,player=player,info=info,walk=walk,phase="approach",start=now}
            sessions[ped],claimed[player]=s,s
            hlc:clearNPCTasks(ped)
            tickSession(s,now)
            return sessions[ped]~=nil
        end
    end
    return false
end

setTimer(function()
    local now=getTickCount()
    for _,s in pairs(sessions) do tickSession(s,now) end
    for player,previous in pairs(healthCaps) do
        if not isElement(player) or getPedStat(player,24)~=serviceHealthStat
            or getElementHealth(player)<=math.max(1,previous*0.176) then releaseHealthCap(player) end
    end
end,100,0)
addEventHandler("onPlayerWasted",root,function() releaseHealthCap(source) end)
addEventHandler("onPlayerQuit",root,function() releaseHealthCap(source) end)
addEventHandler("onResourceStop",resourceRoot,function()
    for player in pairs(healthCaps) do releaseHealthCap(player) end
end,false)
addEventHandler("onVehicleEnter",root,function(ped,seat)
    local s=sessions[ped]
    if s and s.car==source and s.phase=="board" and seat>0 then tickSession(s,getTickCount()) end
end)
addEventHandler("onVehicleExit",root,function(ped,seat)
    local s=sessions[ped]
    if s and s.car==source and s.boarded and seat>0 then settleExit(s,getTickCount()) end
end)
addEventHandler("onElementDestroy",root,function()
    if sessions[source] then finish(sessions[source],getTickCount()) end
    for _,s in pairs(sessions) do if s.car==source then finish(s,getTickCount()) end end
end)
