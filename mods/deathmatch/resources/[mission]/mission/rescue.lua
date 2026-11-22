local blue = {0, 0, 255, 225}
local airSkins = {19, 16, 58, 56, 37, 38}
local hospitalPink = {237, 130, 180, 135}
local sling = {{0,1.2,180},{0,-1.2,0},{1.2,0,90},{-1.2,0,270}}

local function discard(element)
    if isElement(element) then destroyElement(element) end
end

local function nearest(points, x, y)
    local best, distance
    for i, point in ipairs(points) do
        local d = getDistanceBetweenPoints2D(x, y, point[1], point[2])
        if not distance or d < distance then best, distance = i, d end
    end
    return best, distance
end

local function inside(x,y,box)
    return x > box[1] and x < box[2] and y > box[3] and y < box[4]
end

local function separated(patients, x, y, radius)
    for _, patient in ipairs(patients) do
        if math.abs(patient.x-x)<radius and math.abs(patient.y-y)<radius then return false end
    end
    return true
end

local function groundSite(r, x, y)
    local h, district = r.hospital, RescueData.districts[r.hospitalIndex]
    for attempt=1,200 do
        local range = (r.level+3)*100 + math.floor(attempt/6)*10
        local left, right = math.max(district[1],h[1]-range), math.min(district[2],h[1]+range)
        local bottom, top = math.max(district[3],h[2]-range), math.min(district[4],h[2]+range)
        local node = exports.npchlc_traffic:findTrafficPedestrianAnchor(left+math.random()*(right-left),
            bottom+math.random()*(top-bottom), h[3])
        if node then
            local px,py,pz = exports.npchlc_traffic:getTrafficNodePosition(node)
            if px and pz>=6 and inside(px,py,district) and getDistanceBetweenPoints2D(px,py,x,y)>=100
                and separated(r.patients,px,py,20) then
                local distance = getDistanceBetweenPoints2D(px,py,h[1],h[2])
                local allowed = distance>=200 and distance<=range
                for _, box in ipairs(RescueData.excluded) do
                    if inside(px,py,box) then allowed=false break end
                end
                if allowed then
                    if Mission.claimSite(r,"patient/"..node) then return px,py,pz+1,distance end
                    r.busySite=true
                end
            end
        end
    end
end

local function airSite(r,x,y)
    local candidates = {}
    for i,point in ipairs(RescueData.sites) do
        local recent = false
        for _,index in ipairs(r.recentSites) do
            if index==i then recent=true break end
        end
        if not recent and getDistanceBetweenPoints2D(x,y,point[1],point[2])>=100
            and separated(r.patients,point[1],point[2],50) then
            if Mission.siteAvailable(r,"airrescue/"..i) then candidates[#candidates+1]=i else r.busySite=true end
        end
    end
    if #candidates == 0 then return end
    local index = candidates[math.random(#candidates)]
    Mission.claimSite(r,"airrescue/"..index)
    local p = RescueData.sites[index]
    table.insert(r.recentSites,index)
    if #r.recentSites>5 then table.remove(r.recentSites,1) end
    local _,distance = nearest(RescueData.helipads,p[1],p[2])
    return p[1],p[2],p[3],(distance+getDistanceBetweenPoints2D(x,y,p[1],p[2]))/2,index
end

local function markPatient(r, patient)
    if isElement(patient.marker) then return end
    local x,y,z = getElementPosition(patient.ped)
    patient.marker = Mission.marker(r,x,y,z+1.4,"arrow",0.8,blue,true)
    if isElement(patient.marker) then attachElements(patient.marker,patient.ped,0,0,1.4) end
end

local function objective(r)
    local left, aboard = r.count-r.saved-r.aboard, r.aboard
    if aboard==0 then
        Mission.message(r,left==1 and "Pick up the ~b~patient." or "Pick up the ~b~patients.")
    elseif left==0 or aboard==(r.air and 4 or 3) then
        local subject = aboard==1 and "this patient" or "these patients"
        Mission.message(r,"Take "..subject.." to the "..(r.air and "nearest " or "").."~y~hospital.")
    else
        Mission.message(r,"Pick up "..(left==1 and "the last" or "another").." ~b~patient~w~, or take your patients to the ~y~hospital.")
    end
end

local function updateHospital(r,x,y)
    if r.air then
        local index = nearest(RescueData.helipads,x,y)
        if r.hospitalIndex~=index then
            discard(r.dropMarker)
            r.hospitalIndex, r.hospital = index, RescueData.helipads[index]
        end
    end
    if r.aboard==0 or r.returnBy then
        discard(r.dropMarker)
    elseif not isElement(r.dropMarker) then
        local h = r.hospital
        r.dropMarker = Mission.marker(r,h[1],h[2],h[3]-0.8,"cylinder",r.air and 5 or 6,hospitalPink,true)
    end
end

local function addPatient(r,px,py,pz,site)
    local skin = airSkins[math.random(#airSkins)]
    if not r.air then
        local population = exports.npchlc_traffic:getTrafficPopulationAt(px,py,pz,getTime(),math.random(0,15))
        if population and population.originalModelId then skin=population.originalModelId end
    end
    local ped = exports.npchlc_traffic:createTrafficScriptPed(skin,px,py,pz,getElementInterior(r.player),getElementDimension(r.player))
    if not isElement(ped) then return false end
    Mission.track(r,ped)
    setElementData(ped,"mission:rescuePatient",r.player,"broadcast","deny")
    setElementRotation(ped,0,0,math.random(0,359))
    setElementHealth(ped,r.air and 200 or 500)
    local patient = {ped=ped,state="waiting",x=px,y=py}
    table.insert(r.patients,patient)
    if r.air then
        setElementFrozen(ped,true)
        local swimmer=site==26 or site==55 or site==58 or site==60
        Mission.servicePose(ped,swimmer and "oj_swim_wave" or "oj_heli_wave")
    end
    markPatient(r,patient)
    return true
end

local function startWave(r)
    Mission.releaseSites(r)
    local x,y = getElementPosition(r.player)
    r.count = r.air and math.min(math.ceil(r.level/2),4) or math.min(r.level,15)
    r.saved, r.aboard, r.patients, r.returnBy = 0,0,{},nil
    local sum = 0
    local previousSites={unpack(r.recentSites)}
    r.busySite=nil
    local choose = r.air and airSite or groundSite
    for _=1,r.count do
        local px,py,pz,distance,site = choose(r,x,y)
        if not px and r.busySite then
            for _,p in ipairs(r.patients) do discard(p.marker) discard(p.ped) end
            Mission.releaseSites(r)
            r.patients,r.recentSites,r.nextWave={},previousSites,getTickCount()+2000
            if not r.waitingForDispatch then Mission.message(r,"Waiting for the next available rescue call.") end
            r.waitingForDispatch=true
            return
        end
        if not px or not addPatient(r,px,py,pz,site) then
            Mission.fail(r,"The radio is out of range. Get closer to a hospital.")
            return
        end
        sum = sum+math.floor(distance*100)
    end
    r.waitingForDispatch=nil
    local time = math.floor((sum+math.floor(sum/r.count/2)*(r.count+1))/r.count)
    r.bonus = math.floor(time/2)
    if not r.air then time=time+math.floor(getDistanceBetweenPoints2D(x,y,r.hospital[1],r.hospital[2])*50) end
    r.deadline = getTickCount()+time
    Mission.hud(r,nil,nil)
    objective(r)
end

local function begin(r,air)
    r.air, r.recentSites, r.discharged = air,{},{}
    r.crimeMultiplier=exports.wanted:getPlayerCrimeMultiplier(r.player)
    exports.wanted:setPlayerCrimeMultiplier(r.player,0.5)
    local x,y,z = getElementPosition(r.player)
    if air then
        r.wantedCap=exports.wanted:getPlayerWantedCap(r.player)
        exports.wanted:setPlayerWantedCap(r.player,0)
        local hook = createObject(1271,x,y,z)
        if not hook then return Mission.fail(r,"The rescue winch is unavailable.") end
        r.hook = hook
        Mission.track(r,hook)
        setElementInterior(hook,getElementInterior(r.player))
        setElementDimension(hook,getElementDimension(r.player))
        setElementCollisionsEnabled(hook,false)
        setElementAlpha(hook,0)
        if not Mission.attachSling(r,hook) then
            return Mission.fail(r,"The rescue winch is unavailable.")
        end
        setElementData(hook,"mission:airRescueCable",true,"broadcast","deny")
    else
        r.hospitalIndex = nearest(RescueData.hospitals,x,y)
        r.hospital = RescueData.hospitals[r.hospitalIndex]
        r.sirenHintAt=getTickCount()+6000
    end
    startWave(r)
end

local function repair(car,amount)
    setElementHealth(car,math.min(1000,getElementHealth(car)+amount))
end

local function boarded(r,p)
    p.state = "aboard"
    r.aboard = r.aboard+1
    discard(p.marker)
    r.deadline = r.deadline+r.bonus
    objective(r)
    Mission.notify(r,"mission:help",r.token,"Pick up bonus. +"..math.floor(r.bonus/1000).." seconds",3500)
end

local function freeSeat(r)
    for seat=1,math.min(3,getVehicleMaxPassengers(r.vehicle) or 0) do
        local reserved = false
        for _,p in ipairs(r.patients) do
            if p.state=="boarding" and p.seat==seat then reserved=true break end
        end
        if not reserved and not getVehicleOccupant(r.vehicle,seat) then return seat end
    end
end

local function discharge(r,p,now)
    p.state="saved"
    r.aboard, r.saved = r.aboard-1,r.saved+1
    local h = r.hospital
    exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"walk",h[4],h[5],h[6],"walk")
    r.discharged[p.ped]=now+10000
    if r.saved%3==0 then
        r.deadline=r.deadline+r.bonus
        Mission.notify(r,"mission:help",r.token,"Drop off bonus. +"..math.floor(r.bonus/1000).." seconds",3500)
    end
    if r.saved<r.count then objective(r) end
end

local function groundPatient(r,p,now,x,y,z,speed)
    local px,py,pz = getElementPosition(p.ped)
    local d = getDistanceBetweenPoints2D(x,y,px,py)
    if (p.state=="waiting" or p.state=="boarding") and exports.npchlc_traffic:isMissionPedSeated(p.ped,r.vehicle) then
        p.seat=getPedOccupiedVehicleSeat(p.ped)
        exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"waitInCar",0)
        boarded(r,p)
    elseif p.state=="waiting" and d<10 and math.abs(z-pz)<5 and speed<5 then
        local seat=freeSeat(r)
        if seat and exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"enterVehicle",r.vehicle,seat) then
            p.state,p.seat,p.retryAt="boarding",seat,now+2000
        end
    elseif p.state=="boarding" then
        if d>20 or speed>10 then
            exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"clear")
            p.state,p.seat="waiting",nil
        elseif getPedOccupiedVehicle(p.ped)==r.vehicle then
            -- MTA reports the reserved seat while the native door task is still running.
            return
        elseif getVehicleOccupant(r.vehicle,p.seat) then
            exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"clear")
            p.state,p.seat="waiting",nil
        elseif now>=p.retryAt then
            p.retryAt=now+2000
            if not exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"enterVehicle",r.vehicle,p.seat) then
                exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"clear")
                p.state,p.seat="waiting",nil
            end
        end
    elseif p.state=="aboard" then
        local h = r.hospital
        local occupied=getPedOccupiedVehicle(p.ped)
        local stoppedAtHospital=speed<1 and getDistanceBetweenPoints2D(x,y,h[1],h[2])<6 and math.abs(z-h[3])<2
        if occupied~=r.vehicle then
            if not occupied and stoppedAtHospital and getDistanceBetweenPoints2D(px,py,h[1],h[2])<=9 and math.abs(pz-h[3])<=3 then
                discharge(r,p,now)
            elseif p.missingSince and now-p.missingSince>=1500 then
                r.aboard=r.aboard-1
                p.state,p.missingSince="waiting",nil
                markPatient(r,p)
                objective(r)
            else p.missingSince=p.missingSince or now end
        else
            p.missingSince=nil
            if stoppedAtHospital then
                r.unloadAt=r.unloadAt or now
                if now-r.unloadAt>=(p.seat-1)*500 and exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"exitVehicle") then p.state="leaving" end
            end
        end
    elseif p.state=="leaving" and not getPedOccupiedVehicle(p.ped) then
        discharge(r,p,now)
    end
end

local function airPatient(r,p,now,speed,m)
    if p.state=="waiting" then
        local hx,hy,hz=Mission.slingPosition(r,m)
        local px,py,pz=getElementPosition(p.ped)
        if not hx or speed>=5 or math.abs(hx-px)>2.5 or math.abs(hy-py)>2.5 or math.abs(hz-pz)>3 then return end
        local used={}
        for _,patient in ipairs(r.patients) do if patient.slot then used[patient.slot]=true end end
        for slot,offset in ipairs(sling) do
            if not used[slot] then
                setElementFrozen(p.ped,false)
                setElementCollisionsEnabled(p.ped,false)
                if not attachElements(p.ped,r.hook,offset[1],offset[2],-1.4,0,0,offset[3]) then
                    setElementCollisionsEnabled(p.ped,true)
                    setElementFrozen(p.ped,true)
                    return
                end
                p.slot=slot
                Mission.servicePose(p.ped,"oj_rescue_ped")
                repair(r.vehicle,75)
                boarded(r,p)
                return
            end
        end
    elseif p.state=="aboard" then
        local h,offset=r.hospital,sling[p.slot]
        local px,py,pz=Mission.slingPosition(r,m,offset[1],offset[2],-1.4)
        if px and speed<6 and math.abs(px-h[1])<3 and math.abs(py-h[2])<3 and math.abs(pz-h[3])<6 then
            p.slot=nil
            detachElements(p.ped)
            Mission.servicePose(p.ped,nil)
            setElementPosition(p.ped,px,py,h[3])
            setElementCollisionsEnabled(p.ped,true)
            discharge(r,p,now)
        end
    end
end

local function handleVehicle(r,now)
    local car = getPedOccupiedVehicle(r.player)
    if car and Mission.driverOf(car)==r.player and
        (car==r.vehicle or r.allowReplacement and Mission.model(car)==227 and Mission.switchVehicle(r,car)) then
        if r.returnBy then
            r.vehicle,r.returnBy,r.allowReplacement,r.returnSecond=car,nil,nil,nil
            discard(r.vehicleMarker)
            for _,p in ipairs(r.patients) do if p.state=="waiting" then markPatient(r,p) end end
            objective(r)
        end
        return true
    end
    if not r.returnBy then
        r.unloadTick,r.unloadAt=nil,nil
        r.allowReplacement = not r.air and r.aboard==0
        for _,p in ipairs(r.patients) do
            if p.state=="boarding" then
                r.allowReplacement=false
                exports.npchlc_traffic:assignTrafficPedObjective(p.ped,"clear")
                p.state,p.seat="waiting",nil
            end
            discard(p.marker)
        end
        r.returnBy=math.min(now+(r.air and 45000 or 30000),r.deadline-1)
        discard(r.dropMarker)
        if not r.allowReplacement and isElement(r.vehicle) then
            local x,y,z=getElementPosition(r.vehicle)
            r.vehicleMarker=Mission.marker(r,x,y,z+2,"arrow",1,blue,true)
            if isElement(r.vehicleMarker) then attachElements(r.vehicleMarker,r.vehicle,0,0,2) end
        end
    end
    local seconds=math.ceil((r.returnBy-now)/1000)
    local name = r.air and "the helicopter" or (r.allowReplacement and "an ambulance" or "the ambulance")
    if seconds<=0 then Mission.fail(r,"You didn't return to "..name.." in time.")
    elseif not r.allowReplacement and (not isElement(r.vehicle) or isVehicleBlown(r.vehicle)) then
        Mission.fail(r,r.air and "The helicopter has been destroyed." or "The ambulance has been destroyed.")
    elseif seconds~=r.returnSecond then
        r.returnSecond=seconds
        Mission.message(r,"You have "..seconds.." second"..(seconds==1 and "" or "s").." to return to "..name..".")
    end
    return false
end

local function tick(r,now)
    for ped,when in pairs(r.discharged) do
        if now>=when then discard(ped) r.discharged[ped]=nil end
    end
    if r.nextWave then
        if now>=r.nextWave then r.nextWave=nil startWave(r) end
        return
    end
    for _,p in ipairs(r.patients) do
        if p.state~="saved" and (not isElement(p.ped) or isPedDead(p.ped)) then
            return Mission.fail(r,"One of your patients has died.")
        end
    end
    if not handleVehicle(r,now) then return end
    if r.sirenHintAt and now>=r.sirenHintAt and not r.pickupHint then
        r.sirenHintAt=nil
        Mission.notify(r,"mission:help",r.token,"Tap the horn to toggle your ambulance's siren.",5000)
    end
    local x,y,z=getElementPosition(r.vehicle)
    local vx,vy,vz=getElementVelocity(r.vehicle)
    local speed=50*math.sqrt(vx*vx+vy*vy+vz*vz)
    updateHospital(r,x,y)
    local m=r.air and getElementMatrix(r.vehicle)
    if not r.air then
        local h=r.hospital
        if r.aboard>0 and getDistanceBetweenPoints2D(x,y,h[1],h[2])<6 and math.abs(z-h[3])<2 and speed<1 then
            if r.unloadTick then r.deadline=r.deadline+now-r.unloadTick end
            r.unloadTick=now
        else
            r.unloadAt,r.unloadTick=nil,nil
        end
    end
    for _,p in ipairs(r.patients) do
        if not r.pickupHint and p.state=="waiting" and getDistanceBetweenPoints2D(x,y,p.x,p.y)<30 then
            r.pickupHint=true
            Mission.notify(r,"mission:help",r.token,r.air and "Fly close to a patient to pick them up with the winch."
                or "Stop near a patient to pick them up.",5000)
        end
        if p.state~="saved" then
            if r.air then
                if m then airPatient(r,p,now,speed,m) end
            else groundPatient(r,p,now,x,y,z,speed) end
        end
    end
    updateHospital(r,x,y)
    if r.saved==r.count then
        repair(r.vehicle,r.air and 250 or 200)
        r.deadline,r.unloadAt,r.unloadTick=nil,nil,nil
        Mission.finishLevel(r,r.level*100*(r.air and r.count or 1))
        r.nextWave=now+5000
    end
end

local function stop(r)
    local wanted=getResourceFromName("wanted")
    if not isElement(r.player) or not wanted or getResourceState(wanted)~="running" then return end
    if r.air and r.wantedCap and exports.wanted:getPlayerWantedCap(r.player)==0 then
        exports.wanted:setPlayerWantedCap(r.player,r.wantedCap)
    end
    if r.crimeMultiplier and exports.wanted:getPlayerCrimeMultiplier(r.player)==0.5 then
        exports.wanted:setPlayerCrimeMultiplier(r.player,r.crimeMultiplier)
    end
end

local timeout="Your lack of urgency was fatal to the patient."
Mission.register("paramedic",{models={227},title="Paramedic",timeout=timeout,start=function(r) begin(r,false) end,tick=tick,stop=stop})
Mission.register("airrescue",{models={189},title="Air Rescue",timeout=timeout,start=function(r) begin(r,true) end,tick=tick,stop=stop})
