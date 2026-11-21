-- VCS mission 19. The player keeps the same cab unless replacing a damaged one.
local restrictedStops = {
    [6]=true, [8]=true, [9]=true, [10]=true, [11]=true, [12]=true, [13]=true,
    [14]=true, [17]=true, [18]=true, [26]=true, [27]=true, [29]=true,
    [30]=true, [31]=true, [32]=true, [33]=true, [34]=true,
}
local tailJobs = {}

local function distance(element, point)
    local x, y = getElementPosition(element)
    return getDistanceBetweenPoints2D(x, y, point[1], point[2])
end

local function clearElement(t, key)
    if isElement(t[key]) then destroyElement(t[key]) end
    t[key] = nil
end

local function focus(r, element, red)
    local t = r.taxi
    clearElement(t, "focus")
    local blip = createBlipAttachedTo(element, 0, 2, red and 255 or 0, red and 40 or 0,
        red and 40 or 255, 255, 0, 65535, r.player)
    if blip then
        setElementDimension(blip, getElementDimension(element))
        setElementInterior(blip, getElementInterior(element))
        Mission.track(r, blip)
        t.focus = blip
    end
end

local function setStop(r, stop, message)
    local t = r.taxi
    clearElement(t, "goal")
    local p = stop.curb
    t.goal = Mission.marker(r, p[1], p[2], p[3], "cylinder", 5, {235,210,65,135}, true)
    t.stop = stop
    Mission.message(r, message .. stop.name .. ".")
end

local function restoreView(r)
    local t=r.taxi
    if t.cutscene and isElement(r.player) then
        local x,y,z=getCameraMatrix(r.player)
        local position=t.first.camera
        if not getCameraTarget(r.player) and x and math.abs(x-position[1])<0.1
            and math.abs(y-position[2])<0.1 and math.abs(z-position[3])<0.1 then
            if isElement(t.cameraTarget) then setCameraTarget(r.player,t.cameraTarget)
            elseif t.cameraMatrix and t.cameraMatrix[1] then setCameraMatrix(r.player,unpack(t.cameraMatrix))
            else setCameraTarget(r.player,r.player) end
        end
        for control,enabled in pairs(r.taxi.cutscene) do toggleControl(r.player,control,enabled) end
    end
    t.cutscene,t.cameraMatrix,t.cameraTarget=nil,nil,nil
end

local function releaseTail(r)
    local t = r.taxi
    if t.driver then
        if not r.silent then Mission.notify(r,"mission:tailTarget",false,false,r.token) end
        tailJobs[t.driver] = nil
        if isElement(t.car) then setVehicleLocked(t.car, t.wasLocked) Mission.releaseVehicle(r,t.car) end
        if isElement(t.driver) then Mission.release(r, t.driver) end
    end
    t.driver, t.car, t.routeResult, t.alertSince = nil, nil, nil, nil
end

local function releaseFare(r)
    local t = r.taxi
    if isElement(t.ped) then
        if getPedOccupiedVehicle(t.ped) == r.vehicle then removePedFromVehicle(t.ped) end
        if t.armed then
            takeWeapon(t.ped,22)
            if t.armed.weapon>0 then giveWeapon(t.ped,t.armed.weapon,t.armed.ammo,false) end
            setPedWeaponSlot(t.ped,t.armed.slot)
        end
        setPedAnimation(t.ped)
        Mission.release(r, t.ped)
    end
    t.previous, t.ped, t.armed, t.boardSeat = t.ped, nil, nil, nil
    restoreView(r)
    releaseTail(r)
    clearElement(t, "focus")
    clearElement(t, "goal")
    t.tip, t.savedTime, t.pausedTime, t.tooClose, t.collision = nil, nil, nil, nil, nil
end

local function dispatch(r, now)
    releaseFare(r)
    r.taxi.phase, r.taxi.nextSearch = "search", now
    setVehicleTaxiLightOn(r.vehicle, true)
end

local function showHud(r)
    local t = r.taxi
    Mission.hud(r, "Fares", t.fares, t.tip and "Tip" or nil, t.tip and math.floor(t.tip))
end

local function search(r, now)
    local t = r.taxi
    if now < t.nextSearch then return end
    t.nextSearch = now + 750
    local x, y, z = getElementPosition(r.vehicle)
    local ped = exports.npchlc_traffic:acquireTrafficPedInArea(x-50,y-50,x+50,y+50,z,
        getElementInterior(r.vehicle),getElementDimension(r.vehicle),true,false,false,t.previous)
    if not isElement(ped) then
        if not t.noFares then Mission.message(r, "There aren't any fares around here. Look elsewhere.") end
        t.noFares = true
        return
    end
    if distance(ped, {x,y}) <= 15 then
        exports.npchlc_traffic:releaseTrafficPed(ped)
        t.previous = ped
        return
    end
    Mission.lease(r, ped)
    t.ped, t.phase, t.noFares = ped, "pickup", nil
    setPedAnimation(ped,"PED","IDLE_taxi", -1, true, false, false, false)
    focus(r, ped)
    Mission.message(r, "Stop near the highlighted pedestrian to pick up a fare.")
end

local function board(r, radius)
    local t = r.taxi
    local actualSeat=getPedOccupiedVehicleSeat(t.ped)
    if type(actualSeat)=="number" and actualSeat>0 and getPedOccupiedVehicle(t.ped)==r.vehicle then
        if exports.npchlc_traffic:isMissionPedSeated(t.ped,r.vehicle,actualSeat) then
            t.boardSeat=actualSeat
            return true
        end
        -- The native enter task can choose another passenger door. Preserve
        -- its reservation until onVehicleEnter confirms the actual seat.
        return
    end
    if t.boardSeat then
        local occupant=getVehicleOccupant(r.vehicle,t.boardSeat)
        if occupant==t.ped then return end
        if occupant then t.boardSeat=nil end
    end
    local x,y,z = getElementPosition(t.ped)
    local vx,vy,vz = getElementVelocity(r.vehicle)
    if distance(r.vehicle,{x,y}) > radius or math.abs(select(3,getElementPosition(r.vehicle))-z)>10
        or vx*vx+vy*vy+vz*vz > 0.0016 then return end
    if t.boardSeat then
        if t.nextBoard and getTickCount()<t.nextBoard then return end
        t.nextBoard=getTickCount()+2000
        if exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"enterVehicle",r.vehicle,t.boardSeat) then return end
        t.boardSeat=nil
    end
    for seat=1,getVehicleMaxPassengers(r.vehicle) do
        if not getVehicleOccupant(r.vehicle,seat) then
            setPedAnimation(t.ped)
            if exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"enterVehicle",r.vehicle,seat) then
                t.boardSeat=seat
            end
            return
        end
    end
end

local function pickStops(r)
    local t = r.taxi
    local candidates = {}
    for id,stop in ipairs(TaxiDestinations) do
        if id ~= t.lastStop and distance(r.vehicle,stop.curb) >= 100 then
            candidates[#candidates+1] = id
        end
    end
    local first = candidates[math.random(#candidates)]
    local second = math.random(#TaxiDestinations - 1)
    if second >= first then second=second+1 end
    t.lastStop, t.first, t.second = first, TaxiDestinations[first], TaxiDestinations[second]
end

local function takeTail(r)
    local t = r.taxi
    local x,y,z = getElementPosition(r.vehicle)
    local cars = getElementsWithinRange(x,y,z,99,"vehicle",getElementInterior(r.vehicle),getElementDimension(r.vehicle))
    for i=#cars,2,-1 do
        local j=math.random(i)
        cars[i],cars[j]=cars[j],cars[i]
    end
    for _,car in ipairs(cars) do
        local driver=getVehicleOccupant(car,0)
        local cx,cy=getElementPosition(car)
        if isElement(driver) and getElementType(driver)=="ped" and car~=r.vehicle
            and Mission.vehicleAvailable(r,car) and getVehicleType(car)=="Automobile" and distance(car,{x,y})>=20
            and math.abs(cx-x)<=70 and math.abs(cy-y)<=70 and exports.npchlc_traffic:acquireMissionTrafficDriver(driver) then
            Mission.lease(r,driver)
            local p=t.first.tail
            if exports.npchlc_traffic:driveMissionTrafficTo(driver,p[1],p[2],p[3],23) then
                t.driver,t.car,t.wasLocked=driver,car,isVehicleLocked(car)
                setVehicleLocked(car,true)
                tailJobs[driver]=r
                Mission.claimVehicle(r,car)
                t.tailNumber=(t.tailNumber or 0)+1
                Mission.notify(r,"mission:tailTarget",car,t.tailNumber,r.token)
                focus(r,car,true)
                return true
            end
            Mission.release(r,driver)
        end
    end
end

local function beginFare(r, now)
    local t = r.taxi
    setVehicleTaxiLightOn(r.vehicle, false)
    clearElement(t,"focus")
    pickStops(r)
    local maxRoll=restrictedStops[t.lastStop] and 5 or 9
    local roll=t.fares==0 and math.random(2,5) or math.random(0,maxRoll)
    if roll<2 and not takeTail(r) then roll=math.random(2,maxRoll) end
    t.kind=roll<2 and "tail" or roll<6 and "single" or roll<8 and "robbery" or "shopping"
    t.leg=1
    t.firstDistance=distance(r.vehicle,t.kind=="tail" and t.first.tail or t.first.curb)
    t.secondDistance=0
    if t.kind=="shopping" or t.kind=="robbery" then
        t.secondDistance=getDistanceBetweenPoints2D(t.first.curb[1],t.first.curb[2],t.second.curb[1],t.second.curb[2])
    end
    t.tip, t.savedTip, t.tipTick, t.damageMark=100,0,now,getElementHealth(r.vehicle)-50
    local remaining=r.deadline and math.max(0,r.deadline-now) or 0
    if t.kind=="tail" then
        t.phase,t.savedTime,r.deadline="tail",remaining,nil
        Mission.message(r,"Follow that vehicle.")
    else
        local factor=remaining>120000 and 0.5 or remaining>90000 and 0.75 or 1
        local allowance=math.floor((t.firstDistance+t.secondDistance)*factor)*70
        if allowance>240000 then allowance=210000 end
        r.deadline=now+remaining+allowance+(t.fares==0 and 20000 or 0)
        t.phase="drive"
        setStop(r,t.first,"Destination: ")
    end
    showHud(r)
end

local function decayTip(r,now)
    local t = r.taxi
    local budget=0.9*math.max(1,t.leg==1 and t.firstDistance or t.secondDistance)
    local elapsed=now-t.tipTick
    t.tipTick=now
    if not t.tip then return end
    if getElementHealth(r.vehicle)<t.damageMark then
        t.damageMark=getElementHealth(r.vehicle)-50
        t.tip=t.tip-20
    end
    -- MAIN runs each frame on the 30 Hz PS2 build.
    local rate=0.4
    if t.kind=="tail" then rate=t.tooClose and 2 or 0 end
    t.tip=t.tip-(elapsed*0.03)*rate*100/budget
    if t.tip<1 then t.tip=nil end
end

local function leave(r,phase,now)
    local t=r.taxi
    t.phase,t.boardSeat,t.exitRetry=phase,nil,now+1500
    exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"exitVehicle")
    clearElement(t,"goal")
end

local function pay(r,now)
    local t=r.taxi
    t.fares=t.fares+1
    local fare=math.max(5,math.floor((t.firstDistance+t.secondDistance)/30))
    if t.tip then
        local bonus=t.leg==2 and (t.secondDistance*0.9*t.tip/100+t.savedTip)/(t.firstDistance*0.9)
            or t.tip/100
        fare=math.floor(fare*(1.25+3*bonus))
        if t.kind=="robbery" then fare=fare+50 end
    end
    local streak=t.fares%5==0 and 125*(t.fares/5) or 0
    Mission.message(r,(t.tip and "Speed bonus: $" or "Fare complete: $")..fare
        ..(streak>0 and (" + "..t.fares.." in a row bonus, $"..streak) or ""))
    Mission.taxiFare(r,fare+streak)
    if t.kind=="robbery" then exports.npchlc_traffic:setPlayerWanted(r.player,0,"Taxi fare delivered") end
    if t.savedTime then r.deadline=now+t.savedTime end
    if r.deadline and r.deadline-now<30000 then r.deadline=r.deadline+10000 end
    dispatch(r,now)
    t.nextSearch=now+4000
    showHud(r)
end

local function tailLost(r,now,spotted)
    local t=r.taxi
    Mission.message(r,spotted and "The target spotted you. Let the fare out of the cab."
        or "The target got away. Let the fare out of the cab.")
    r.deadline=now+(t.savedTime or 0)
    releaseTail(r)
    clearElement(t,"focus")
    leave(r,"lostFare",now)
end

local function follow(r,now)
    local t=r.taxi
    if not isElement(t.car) or isVehicleBlown(t.car) or not isElement(t.driver)
        or getVehicleOccupant(t.car,0)~=t.driver or t.routeResult==false then
        t.savedTime=t.savedTime+10000
        return tailLost(r,now,false)
    end
    local range=distance(r.vehicle,{getElementPosition(t.car)})
    t.tooClose=range<25
    if t.collision then t.collision=nil return tailLost(r,now,true) end
    if t.tooClose or range>85 then
        if not t.alertSince then
            t.alertSince=now
            Mission.message(r,t.tooClose and "You are too close to the target. Pull back."
                or "You are too far from the target. Hurry up.")
        end
        if now-t.alertSince>=8000 then return tailLost(r,now,t.tooClose) end
    else
        t.alertSince=nil
    end
    if t.routeResult or distance(t.car,t.first.tail)<5 then
        releaseTail(r)
        clearElement(t,"focus")
        t.phase,t.tooClose="drive",false
        setStop(r,t.first,"Destination: ")
    end
end

addEventHandler("npchlc_traffic:onNPCTrafficRouteDone",root,function(completed)
    local r=tailJobs[source]
    if r then r.taxi.routeResult=completed end
end)

addEvent("mission:tailCollision",true)
addEventHandler("mission:tailCollision",resourceRoot,function(car,token,number)
    if not isElement(car) or getElementType(car)~="vehicle" then return end
    local driver=getVehicleOccupant(car,0)
    local r=driver and tailJobs[driver]
    if r and Mission.forParticipant(client,token,"taxi")==r and number==r.taxi.tailNumber
        and r.taxi.car==car and r.taxi.phase=="tail" and isElement(r.vehicle)
        and Mission.driverOf(r.vehicle)==client and getElementDimension(car)==r.dimension
        and getElementInterior(car)==r.interior and distance(r.vehicle,{getElementPosition(car)})<18 then
        r.taxi.collision=true
    end
end,false)

local function stopover(r,now)
    local t=r.taxi
    t.savedTip=t.tip or 0
    t.pausedTime=math.max(0,r.deadline-now)
    r.deadline=nil
    local camera,curb=t.first.camera,t.first.curb
    t.cameraTarget=getCameraTarget(r.player)
    if not t.cameraTarget then t.cameraMatrix={getCameraMatrix(r.player)} end
    setCameraMatrix(r.player,camera[1],camera[2],camera[3],curb[1],curb[2],curb[3])
    t.cutscene={}
    for _,control in ipairs({"accelerate","brake_reverse","vehicle_left","vehicle_right","enter_exit","vehicle_fire","vehicle_secondary_fire"}) do
        t.cutscene[control]=isControlEnabled(r.player,control)
        toggleControl(r.player,control,false)
    end
    leave(r,"shopExit",now)
    Mission.message(r,t.kind=="robbery" and "Wait while the fare takes care of business." or "Wait while the fare shops.")
end

local function handleStop(r,now)
    local t=r.taxi
    if t.phase=="shopExit" or t.phase=="dropoff" or t.phase=="lostFare" then
        if getPedOccupiedVehicle(t.ped)==r.vehicle then
            if now>=t.exitRetry then
                exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"exitVehicle")
                t.exitRetry=now+1500
            end
        elseif t.phase=="dropoff" then
            pay(r,now)
        elseif t.phase=="lostFare" then
            dispatch(r,now)
        else
            local p=t.first.entrance
            exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"walk",p[1],p[2],p[3],"run")
            t.phase,t.readyAt="shopping",now+2000
        end
    elseif t.phase=="shopping" and now>=t.readyAt then
        local p=t.first.entrance
        exports.npchlc_traffic:assignTrafficPedObjective(t.ped,"clear")
        setElementPosition(t.ped,p[1],p[2],p[3])
        local px,py=getElementPosition(r.vehicle)
        setPedRotation(t.ped,math.deg(math.atan2(p[1]-px,py-p[2])))
        if t.kind=="robbery" then
            t.armed={weapon=getPedWeapon(t.ped,2) or 0,ammo=getPedTotalAmmo(t.ped,2) or 0,slot=getPedWeaponSlot(t.ped)}
            giveWeapon(t.ped,22,5,true)
        end
        t.phase,t.readyAt="shopReturn",now+500
    elseif t.phase=="shopReturn" and now>=t.readyAt then
        restoreView(r)
        t.phase="reboard"
    elseif t.phase=="reboard" and board(r,23) then
        restoreView(r)
        if t.kind=="robbery" then
            exports.npchlc_traffic:setPlayerWanted(r.player,math.min(6,(exports.npchlc_traffic:getPlayerWanted(r.player) or 0)+2),"Taxi getaway")
        end
        t.phase,t.leg,t.tip,t.tipTick="drive",2,100,now
        r.deadline=now+t.pausedTime
        t.pausedTime=nil
        setStop(r,t.second,t.kind=="robbery" and "Your fare is wanted by the cops. Get them to " or "Now take the fare to ")
    end
end

local function tick(r,now)
    local t=r.taxi
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return Mission.fail(r,"Your taxi has been destroyed.") end
    if isElementInWater(r.vehicle) then return Mission.fail(r,"You sunk the car.") end
    if t.phase~="repair" and getElementHealth(r.vehicle)<=500 then
        if t.savedTime then r.deadline=now+t.savedTime end
        if t.pausedTime then r.deadline=now+t.pausedTime end
        releaseFare(r)
        t.phase="repair"
        setVehicleTaxiLightOn(r.vehicle,false)
        Mission.message(r,"Your car is trashed, get it repaired.")
    end
    local vehicle=getPedOccupiedVehicle(r.player)
    if t.phase=="repair" and vehicle and Mission.driverOf(vehicle)==r.player then
        local model=Mission.model(vehicle)
        if (model==183 or model==226) and vehicle~=r.vehicle then
            local previous=r.vehicle
            if Mission.switchVehicle(r,vehicle) then
                setVehicleTaxiLightOn(previous,t.originalLight)
                t.originalLight=isVehicleTaxiLightOn(vehicle)
            end
        end
    end
    if vehicle~=r.vehicle or Mission.driverOf(r.vehicle)~=r.player then
        if not t.returnBy then
            t.returnBy=math.min(r.deadline or now+45000,now+45000)
            focus(r,r.vehicle)
        end
        local seconds=math.ceil((t.returnBy-now)/1000)
        if seconds<=0 then return Mission.fail(r,"You failed to return to your vehicle.") end
        if seconds~=t.lastSeconds then
            Mission.message(r,"You have "..seconds.." second"..(seconds==1 and "" or "s").." to return to your vehicle.")
            t.lastSeconds=seconds
        end
        return
    elseif t.returnBy then
        t.returnBy,t.lastSeconds=nil,nil
        clearElement(t,"focus")
        if t.phase=="pickup" and isElement(t.ped) then focus(r,t.ped) end
        if t.phase=="tail" and isElement(t.car) then focus(r,t.car,true) end
    end
    if t.phase=="repair" then
        if getElementHealth(r.vehicle)>500 then dispatch(r,now) end
    elseif t.phase=="search" then
        search(r,now)
    elseif not isElement(t.ped) or isPedDead(t.ped) then
        if t.phase=="pickup" then dispatch(r,now) else Mission.fail(r,"Your fare is dead.") end
    elseif t.phase=="pickup" then
        if distance(r.vehicle,{getElementPosition(t.ped)})>70 then dispatch(r,now)
        elseif board(r,10) then beginFare(r,now) end
    elseif t.phase=="drive" then
        decayTip(r,now)
        if distance(r.vehicle,t.stop.curb)<=5 then
            if t.leg==1 and t.secondDistance>0 then stopover(r,now)
            else leave(r,"dropoff",now) end
        end
    elseif t.phase=="tail" then
        decayTip(r,now)
        follow(r,now)
    else
        handleStop(r,now)
    end
    showHud(r)
end

Mission.register("taxi",{
    title="Taxi Driver", models={226,183},
    start=function(r)
        r.taxi={fares=0,originalLight=isVehicleTaxiLightOn(r.vehicle)}
        dispatch(r,getTickCount())
        showHud(r)
    end,
    toggle=function(r,now)
        if r.taxi.cancelBy and now<=r.taxi.cancelBy then return Mission.fail(r,"Taxi mission cancelled.") end
        r.taxi.cancelBy=now+2500
        Mission.message(r,"Use the sub-mission control again to cancel the mission.")
    end,
    tick=tick,
    stop=function(r)
        if not r.taxi then return end
        releaseFare(r)
        if isElement(r.vehicle) then setVehicleTaxiLightOn(r.vehicle,r.taxi.originalLight) end
    end,
})
