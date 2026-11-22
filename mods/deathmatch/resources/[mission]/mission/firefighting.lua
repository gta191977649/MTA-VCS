local cars = {200,195,224,176,171}
local crews = {{0},{1},{2},{3},{3,1},{2,3},{2,4},{4,4,1},{4,4,1},{4,4,1},{4,4,2}}
local firstSite, lastSite = {1,13,30,49,68},{12,29,48,67,79}
local pad = {-742.272,858.7609,11.781}
local blue, pink = {0,0,255,225},{237,130,180,150}

local function discard(e)
    if isElement(e) then destroyElement(e) end
end

local function putInWorld(r,e)
    Mission.track(r,e)
    setElementInterior(e,r.interior)
    setElementDimension(e,r.dimension)
end

local function fire(r,x,y,z,entity,kind)
    local marker = Mission.marker(r,x,y,z,entity and "arrow" or "arrow2",0.65,kind=="roof" and pink or blue,true)
    if not marker then return false end
    if entity then attachElements(marker,entity,0,0,1.5) end
    setElementData(marker,"mission:fireTarget",{r.token,entity or false},"broadcast","deny")
    local f = {x=x,y=y,z=z,entity=entity,marker=marker,kind=kind,crew={}}
    r.fires[#r.fires+1]=f
    return f
end

local function dispatch(r)
    local x,y,z=getElementPosition(r.vehicle)
    local low = r.level<=5 and 150 or r.level<=10 and 300 or 500
    local high = r.level<=5 and 400 or r.level<=10 and 600 or 800
    for attempt=1,50 do
        local angle,range=math.random()*math.pi*2,math.random(low,high)
        local px,py,pz,yaw=exports.npchlc_traffic:getMissionTrafficRoad(x+math.cos(angle)*range,y+math.sin(angle)*range,z)
        if px then
            local distance=getDistanceBetweenPoints2D(x,y,px,py)
            local key=("fire:%d:%d"):format(math.floor(px/24),math.floor(py/24))
            if distance>=low and distance<=high and Mission.claimSite(r,key) then return px,py,pz,yaw,distance end
        end
    end
end

local function startGroundWave(r,now)
    Mission.releaseSites(r)
    local x,y,z,yaw,distance=dispatch(r)
    if not x then
        r.nextWave=now+3000
        if not r.noDispatch then Mission.message(r,"There are no fires in this part of the city, try another district.") end
        r.noDispatch=true
        return
    end
    r.noDispatch,r.nextWave=nil,nil
    local level=r.level
    local tier=level<=4 and level or level<=7 and 5 or level<=10 and 6 or math.min(level-4,11)
    local layout=crews[tier]
    r.fires,r.actors,r.saved,r.perfect={}, {}, 0, true
    for i,crewSize in ipairs(layout) do
        local offset=#layout==1 and 0 or #layout==2 and (i==1 and -5 or 5) or ({0,-7,7})[i]
        local px,py=x-math.sin(math.rad(yaw))*offset,y+math.cos(math.rad(yaw))*offset
        local model=cars[math.random(#cars)]
        local vehicle=exports.vcs_vehicle:createVcsVehicle(model,px,py,z+0.6,0,0,yaw+(i==2 and 180 or 0))
        if not vehicle then return Mission.fail(r,"The emergency vehicle could not be located.") end
        putInWorld(r,vehicle)
        r.actors[#r.actors+1]=vehicle
        setElementFrozen(vehicle,true)
        setVehicleEngineState(vehicle,false)
        setElementData(vehicle,"mission:fireRoad",r.token,"broadcast","deny")
        local f=fire(r,px,py,z,vehicle,"car")
        if not f then return Mission.fail(r,"The fire could not be located.") end
        for seat=0,crewSize-1 do
            local population=exports.npchlc_traffic:getTrafficPopulationAt(px,py,z,getTime(),math.random(0,15))
            local skin=population and population.originalModelId or 55
            local ped=exports.npchlc_traffic:createTrafficScriptPed(skin,px,py,z+1,r.interior,r.dimension)
            if not ped then return Mission.fail(r,"The passengers could not be located.") end
            Mission.track(r,ped)
            setElementData(ped,"mission:fireVictim",true,"broadcast","deny")
            r.actors[#r.actors+1]=ped
            if not warpPedIntoVehicle(ped,vehicle,seat) then return Mission.fail(r,"The passengers could not board.") end
            f.crew[#f.crew+1]=ped
        end
    end
    r.deadline=now+r.remaining+math.floor(distance*40)+(level<=5 and 10000 or level<=10 and 22500 or 25000)
    Mission.message(r,"Extinguish the burning ~b~vehicles~w~. Hold the vehicle fire control to use the water cannon.")
end

local function startAirWave(r,now)
    r.fires,r.water,r.returning,r.nextWave={},100,false,nil
    for i=firstSite[r.level],lastSite[r.level] do
        local p=FireCopterSites[i]
        if not fire(r,p[1],p[2],p[3],nil,"roof") then return Mission.fail(r,"The fire could not be located.") end
    end
    r.deadline=now+(r.level==1 and 300000 or 360000)
    Mission.hud(r,nil,nil,"Water",r.water)
    Mission.message(r,"Extinguish all ~y~fires~w~ in the allotted time. Hold vehicle fire to release water.")
end

local function groundResult(r,f,saved,now)
    discard(f.marker)
    f.done=true
    if saved then
        Mission.checkpointCue(r)
        r.deadline=r.deadline+(f.kind=="car" and 5000 or 10000)
        r.saved=r.saved+1
    else
        r.perfect=false
        r.deadline=r.deadline-15000
    end
    if f.kind=="occupant" and isElement(f.entity) then
        exports.npchlc_traffic:assignTrafficPedObjective(f.entity,"extinguish")
    end
    if f.kind=="car" and saved then
        for _,ped in ipairs(f.crew) do
            if isElement(ped) and not isPedDead(ped) then
                exports.npchlc_traffic:assignTrafficPedObjective(ped,"exitVehicle")
                local px,py,pz=getElementPosition(ped)
                local victim=fire(r,px,py,pz,ped,"occupant")
                if not victim then return Mission.fail(r,"The passengers could not be located.") end
                victim.exitBy=now+2400
            end
        end
    end
end

local function objectiveVisibility(r,visible)
    for _,p in ipairs(Mission.participants(r)) do
        for _,fire in ipairs(r.fires or {}) do
            if isElement(fire.marker) then exports.marker:setMarkerVisibleTo(fire.marker,p,visible) end
        end
        if isElement(r.padMarker) then exports.marker:setMarkerVisibleTo(r.padMarker,p,visible) end
    end
end

local function driver(r,now)
    local v=getPedOccupiedVehicle(r.player)
    if v and Mission.driverOf(v)==r.player and not isVehicleBlown(v) then
        if v==r.vehicle or (not r.air and Mission.model(v)==194 and Mission.switchVehicle(r,v)) then
            if r.returnBy then
                r.returnBy,r.returnSeconds=nil,nil
                Mission.clearReturnVehicle(r)
                objectiveVisibility(r,true)
                Mission.message(r,r.returning and "Get back to the ~y~fire station~w~." or "Extinguish the fires.")
            end
            return true
        end
    end
    if r.air and (not isElement(r.vehicle) or isVehicleBlown(r.vehicle)) then
        Mission.fail(r,"You can't put out fires with a destroyed helicopter!")
        return false
    end
    if not r.returnBy then
        r.returnBy=now+30000
        r.sprayUntil,r.refillUntil=nil,nil
        if r.air and r.spraying then
            r.spraying=false
            setElementData(r.bucket,"mission:bucketSpraying",false,"broadcast","deny")
        end
        objectiveVisibility(r,false)
    end
    local original=isElement(r.vehicle) and not isVehicleBlown(r.vehicle)
    if original then Mission.showReturnVehicle(r,r.vehicle) else Mission.clearReturnVehicle(r) end
    local seconds=math.ceil((math.min(r.returnBy,r.deadline or r.returnBy)-now)/1000)
    if seconds<=0 then
        Mission.fail(r,"You took too long to get back to your vehicle.")
    elseif seconds~=r.returnSeconds then
        local action=r.air and "return to the helicopter" or original and "return to the Fire Truck" or "find a Fire Truck"
        Mission.message(r,("You have %d second%s to %s."):format(seconds,seconds==1 and "" or "s",action))
        r.returnSeconds=seconds
    end
    return false
end

-- The owner samples the native turret. Validate hits against the stream trajectory in vehicle space.
local function cannonHit(r,px,py,pz,x,y,z)
    local dx,dy,dz=px-x,py-y,pz-z-1.8
    local forward=dx*r.aimX+dy*r.aimY
    if forward<0 or forward>32 then return false end
    local lateral=math.abs(dx*r.aimY-dy*r.aimX)
    local height=forward*r.slope-0.013*forward*forward
    return lateral<2.6 and math.abs(dz-height)<3.0
end

local function groundTick(r,now)
    if not driver(r,now) then return end
    if r.nextWave then
        if now>=r.nextWave then startGroundWave(r,now) end
        return
    end
    local x,y,z=getElementPosition(r.vehicle)
    local count=0
    for i=1,#r.fires do
        local f=r.fires[i]
        if not f.done then
            local e=f.entity
            if not isElement(e) or (f.kind=="car" and isVehicleBlown(e)) or (f.kind=="occupant" and isPedDead(e)) then
                groundResult(r,f,false,now)
            else
                local px,py,pz=getElementPosition(e)
                if f.kind=="occupant" and not f.burnBy and (not getPedOccupiedVehicle(e) or now>=f.exitBy) then
                    if getPedOccupiedVehicle(e) then removePedFromVehicle(e) end
                    if not exports.npchlc_traffic:assignTrafficPedObjective(e,"ignite") then
                        exports.npchlc_traffic:assignTrafficPedObjective(e,"flee",r.player)
                    end
                    f.burnBy=now+math.random(14000,22000)
                end
                if f.burnBy and now>=f.burnBy then
                    killPed(e)
                    groundResult(r,f,false,now)
                elseif isElementInWater(e) or (r.sprayUntil and now<r.sprayUntil and
                    (f.kind=="car" or f.burnBy) and cannonHit(r,px,py,pz,x,y,z)) then
                    groundResult(r,f,true,now)
                end
            end
        end
        if not Mission.active(r) then return end
    end
    for _,f in ipairs(r.fires) do if not f.done then count=count+1 end end
    if count>0 then return end
    local bonus=r.perfect and (r.level>10 and 20000 or r.level>5 and 10000 or r.level>1 and 5000 or 0) or 0
    r.remaining=math.max(0,r.deadline-now)+bonus
    r.deadline=nil
    setElementHealth(r.vehicle,math.min(1000,getElementHealth(r.vehicle)+150))
    for _,e in ipairs(r.actors) do discard(e) end
    Mission.finishLevel(r,20*r.saved)
    r.nextWave=now+5000
end

local function aboveWater(x,y,z)
    local water=exports.vcs:getVcsWaterQuadLevel(x,y)
    return water and z>water-2 and z<20
end

local function airTick(r,now)
    if not driver(r,now) then return end
    if r.nextWave then
        if now>=r.nextWave then startAirWave(r,now) end
        return
    end
    local x,y,z=getElementPosition(r.vehicle)
    if r.returning then
        if math.abs(x-pad[1])<10 and math.abs(y-pad[2])<10 and math.abs(z-pad[3])<2 then
            local reward=math.floor((r.deadline-now)/100)+10*r.water
            discard(r.padMarker)
            r.deadline=nil
            Mission.finishLevel(r,reward)
            if Mission.active(r) then r.nextWave=now+5000 end
        end
        return
    end
    if r.refillUntil and now<r.refillUntil and z<20 and r.water<100 and now>=(r.canRefill or 0) and aboveWater(x,y,z) then
        r.water=math.min(100,r.water+5)
        r.canRefill=now+1000
    end
    local spray=r.water>0 and r.sprayUntil and now<r.sprayUntil
    if spray then
        r.water=math.max(0,r.water-6) -- Six PS2 30 Hz frames per server tick.
        if r.water==0 then Mission.message(r,"Fly low over deep water to replenish your bucket.") end
    end
    if spray~=r.spraying then
        r.spraying=spray
        setElementData(r.bucket,"mission:bucketSpraying",spray==true,"broadcast","deny")
    end
    Mission.hud(r,nil,nil,"Water",r.water)
    local m=getElementMatrix(r.vehicle)
    if not m then return end
    local bx,by,bz=Mission.slingPosition(r,m)
    local left=0
    for _,f in ipairs(r.fires) do
        if not f.done then
            if math.abs(f.x-x)<2 and math.abs(f.y-y)<2 and math.abs(f.z-z)<4 then
                setElementHealth(r.vehicle,math.max(100,getElementHealth(r.vehicle)-5))
            end
            if spray and bx and math.abs(f.x-bx)<5 and math.abs(f.y-by)<5 and math.abs(f.z-bz)<10 then
                f.done=true
                discard(f.marker)
            else left=left+1 end
        end
    end
    if left==0 then
        r.returning=true
        setElementData(r.bucket,"mission:bucketSpraying",false,"broadcast","deny")
        r.padMarker=Mission.marker(r,pad[1],pad[2],pad[3]-1,"cylinder",10,pink,true)
        Mission.message(r,"All fires extinguished. Return to the ~y~fire station~w~ for appraisal.")
    end
end

addEvent("mission:fireRoadReady",true)
addEventHandler("mission:fireRoadReady",resourceRoot,function(token,car,surface)
    if not client or source~=resourceRoot or not isElement(car) or type(surface)~="number" then return end
    local r=Mission.forParticipant(client,token,"firefighter")
    if not r or not r.fires or getElementDimension(client)~=r.dimension or getElementInterior(client)~=r.interior then return end
    local px,py,pz=getElementPosition(client)
    for _,f in ipairs(r.fires) do
        if f.entity==car and f.kind=="car" and not f.done and not f.grounded and math.abs(surface-f.z)<=8
            and getDistanceBetweenPoints3D(px,py,pz,f.x,f.y,f.z)<=205 then
            f.grounded=true
            setElementPosition(car,f.x,f.y,surface+0.85)
            setElementVelocity(car,0,0,0)
            setElementSyncer(car,client,false)
            setElementFrozen(car,false)
            removeElementData(car,"mission:fireRoad")
            return
        end
    end
end,false)

addEvent("mission:fireControls",true)
addEventHandler("mission:fireControls",resourceRoot,function(token,id,pressed,ax,ay,slope,deep)
    if not client or source~=resourceRoot or (id~="firefighter" and id~="firecopter") then return end
    local r=Mission.forParticipant(client,token,id)
    if not r or not isElement(r.vehicle) or Mission.driverOf(r.vehicle)~=client then return end
    local now=getTickCount()
    if now<(r.nextInput or 0) then return end
    r.nextInput=now+90
    if type(ax)~="number" or type(ay)~="number" or type(slope)~="number" then return end
    local norm=ax*ax+ay*ay
    if not (norm>0.95 and norm<1.05 and slope>=-2 and slope<=2) then return end
    r.sprayUntil=pressed==true and now+400 or nil
    r.aimX,r.aimY,r.slope=ax,ay,slope
    r.refillUntil=deep==true and now+400 or nil
end,false)

local function stop(r)
    if isElement(r.bucket) then
        removeElementData(r.bucket,"mission:bucketSpraying")
        removeElementData(r.bucket,"mission:airRescueCable")
    end
    local provider=getResourceFromName("npchlc_traffic")
    if not provider or getResourceState(provider)~="running" then return end
    for _,f in ipairs(r.fires or {}) do
        if f.kind=="occupant" and not f.done and isElement(f.entity) and not isPedDead(f.entity) then
            exports.npchlc_traffic:assignTrafficPedObjective(f.entity,"extinguish")
        end
    end
end

Mission.register("firefighter",{models={194},title="Fire Fighter",tick=groundTick,stop=stop,
    start=function(r,now)
        r.remaining=r.level==1 and 30000 or r.level<8 and 180000 or 360000
        startGroundWave(r,now)
    end})
Mission.register("firecopter",{models={188},title="Fire Copter",tick=airTick,stop=stop,
    startLevel=function() return 1 end,
    canStart=function(player,vehicle)
        local x,y,z=getElementPosition(vehicle)
        return math.abs(x+783.38)<=8 and math.abs(y-923.28)<=8 and math.abs(z-10.09)<=8
    end,
    start=function(r,now)
        r.air=true
        local bucket=createObject(1271,getElementPosition(r.vehicle))
        if not bucket then return Mission.fail(r,"The helicopter bucket is unavailable.") end
        r.bucket=bucket
        putInWorld(r,bucket)
        setElementAlpha(bucket,0)
        setElementCollisionsEnabled(bucket,false)
        if not Mission.attachSling(r,bucket) then
            return Mission.fail(r,"The helicopter bucket is unavailable.")
        end
        setElementData(bucket,"mission:airRescueCable",7350,"broadcast","deny")
        startAirWave(r,now)
    end})
