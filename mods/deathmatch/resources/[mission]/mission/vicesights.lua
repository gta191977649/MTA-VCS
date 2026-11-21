local home = {-1236.1198,-924.8318,14.8681}
local start = {-1236.3562,-901.2057,13.9299}
local ranges = {{1,3,240},{4,6,240},{7,10,300},{11,14,300},{15,18,300}}
local pink = {237,130,180,210}

local function inside(element,point,xr,yr,zr)
    local x,y,z = getElementPosition(element)
    return math.abs(x-point[1])<=xr and math.abs(y-point[2])<=yr and math.abs(z-point[3])<=zr
end

local function speed(heli)
    local x,y,z = getElementVelocity(heli)
    local forward=getElementMatrix(heli)[2]
    local metres=math.sqrt(x*x+y*y+z*z)*50
    -- GET_CAR_SPEED, SLUS 003D3538, negates speed when travelling backwards.
    return x*forward[1]+y*forward[2]+z*forward[3]<0 and -metres or metres
end

local function beginTour(r,now)
    local t = r.tour
    local limits = ranges[r.level]
    t.sights,t.remaining,t.fun,t.sample,t.viewing = {},limits[2]-limits[1]+1,100,now,nil
    r.deadline = now+limits[3]*1000
    for i=limits[1],limits[2] do
        local p=ViceSightsData[i]
        local marker=Mission.marker(r,p[1],p[2],p[3],"ring",5,pink,true)
        if not marker then return Mission.fail(r,"The tour sights are unavailable.") end
        if p[4]~=-1000 then exports.marker:setMarkerTarget(marker,p[4],p[5],p[6]) end
        t.sights[i]=marker
    end
    Mission.hud(r,nil,nil,"Fun",t.fun)
    Mission.message(r,"Fly through each of the sight markers in the allotted time.")
end

local function startTour(r,now)
    local t={passengers={},damageMark=1000}
    r.tour=t
    local x,y,z=getElementPosition(r.vehicle)
    for _,model in ipairs({58,16}) do
        local seat
        for i=1,getVehicleMaxPassengers(r.vehicle) do
            if not getVehicleOccupant(r.vehicle,i) then seat=i break end
        end
        if not seat then return Mission.fail(r,"The tourists need two empty seats.") end
        local ped=exports.npchlc_traffic:createTrafficScriptPed(model,x,y,z,r.interior,r.dimension)
        if not ped then return Mission.fail(r,"The tourists could not board.") end
        Mission.track(r,ped)
        setElementData(ped,"mission:tourOwner",r.player,"broadcast","deny")
        if not warpPedIntoVehicle(ped,r.vehicle,seat) then return Mission.fail(r,"The tourists could not board.") end
        t.passengers[#t.passengers+1]=ped
    end
    beginTour(r,now)
end

local function updateFun(r,now,velocity)
    local t=r.tour
    while t.damageMark>0 and getElementHealth(r.vehicle)<t.damageMark do
        if t.fun>20 then t.fun=t.fun-10 end
        t.damageMark=t.damageMark-100
    end
    if now-t.sample>=2500 then
        t.sample=now
        local _,_,z=getElementPosition(r.vehicle)
        local ground=t.ground and now-t.ground.at<3500 and t.ground.z or 6
        local height=z-ground
        if velocity<10 then t.fun=t.fun-4 end
        if velocity>9 and velocity<20 then t.fun=t.fun-1 end
        if velocity>19 and velocity<25 then t.fun=t.fun+1 end
        if velocity>25 then t.fun=t.fun+2 end
        if height<20 then t.fun=t.fun+2 end
        if height>19 and height<30 then t.fun=t.fun+1 end
        if height>35 then t.fun=t.fun-2 end
    end
    t.fun=math.min(100,math.max(0,t.fun))
    if t.fun<40 and not t.warned then
        t.warned=true
        Mission.message(r,"Your fun level is low. Fly low and fast.")
    elseif t.fun>50 then t.warned=false end
    Mission.hud(r,nil,nil,"Fun",t.fun)
    if t.fun==0 then Mission.fail(r,"Bored tourists won't recommend this tour!") return false end
    return true
end

local function sightBlips(t,visible)
    for _,marker in pairs(t.sights) do exports.marker:setMarkerBlipVisible(marker,visible) end
    if t.base then exports.marker:setMarkerBlipVisible(t.base,visible) end
end

local function tick(r,now)
    local t=r.tour
    if not isElement(r.vehicle) or isVehicleBlown(r.vehicle) then return Mission.fail(r,"You can't tour with a destroyed helicopter!") end
    for _,ped in ipairs(t.passengers) do
        if not isElement(ped) or isPedDead(ped) or getPedOccupiedVehicle(ped)~=r.vehicle then
            return Mission.fail(r,"You lost a passenger!")
        end
    end
    if Mission.driverOf(r.vehicle)~=r.player then
        if not t.returnAt then
            t.returnAt=now+30000
            sightBlips(t,false)
            Mission.showReturnVehicle(r,r.vehicle)
            Mission.message(r,"Get back to your helicopter within 30 seconds!")
        end
        if now>=t.returnAt then Mission.fail(r,"You took too long to get back to your helicopter!") end
        if t.viewing then Mission.notify(r,"mission:tourPhotos",r.token,false) end
        t.viewing=nil
        return
    end
    if t.returnAt then
        Mission.clearReturnVehicle(r)
        sightBlips(t,true)
        t.returnAt=nil
    end
    local velocity=speed(r.vehicle)
    if not updateFun(r,now,velocity) then return end
    if t.base then
        if inside(r.vehicle,home,10,10,2) then
            destroyElement(t.base)
            t.base=nil
            local bonus=math.floor((r.deadline-now)/100)+10*t.fun
            if Mission.finishLevel(r,bonus) then beginTour(r,now) end
        end
        return
    end
    if t.viewing then
        if now-t.viewStart>1800 and velocity>10 then
            t.viewing=nil
            Mission.notify(r,"mission:tourPhotos",r.token,false)
            return Mission.message(r,"Unsteady! You need to try this sight again.")
        end
        if now-t.viewStart>=4000 then
            destroyElement(t.sights[t.viewing])
            t.sights[t.viewing],t.viewing=nil,nil
            t.remaining=t.remaining-1
            t.fun=math.min(100,t.fun+20)
            if t.remaining==0 then
                t.base=Mission.marker(r,home[1],home[2],home[3],"cylinder",6,pink,true)
                if not t.base then return Mission.fail(r,"The landing pad is unavailable.") end
                Mission.message(r,"All sights viewed. Return to base to collect your payment.")
            else Mission.message(r,"Sight viewed! Fly to another sight marker now.") end
        end
        return
    end
    for i in pairs(t.sights) do
        if inside(r.vehicle,ViceSightsData[i],7.5,7.5,7.5) then
            if velocity<=10 then
                t.viewing,t.viewStart=i,now
                Mission.notify(r,"mission:tourPhotos",r.token,r.vehicle)
                Mission.message(r,"Hold your helicopter steady for a few seconds!")
            elseif t.slowHint~=i then
                t.slowHint=i
                Mission.message(r,"Fly slower when nearing a sight to begin viewing!")
            end
            return
        end
    end
    t.slowHint=nil
end

addEvent("mission:tourGround",true)
addEventHandler("mission:tourGround",resourceRoot,function(token,heli,z)
    local r=client and Mission.forParticipant(client,token,"vicesights")
    if source~=resourceRoot or not r or client~=r.player or heli~=r.vehicle or not isElement(heli)
        or Mission.driverOf(heli)~=client or type(z)~="number" or z~=z then return end
    local now=getTickCount()
    local t=r.tour
    local _,_,alt=getElementPosition(heli)
    if t and (not t.ground or now-t.ground.at>=750) and z>=-20 and z<=alt+1 then
        t.ground={z=z,at=now}
    end
end,false)

Mission.register("vicesights",{title="Vice Sights",models={213},canStart=function(player,vehicle)
    return inside(vehicle,start,8,8,8)
end,startLevel=function() return 1 end,start=startTour,tick=tick,timeout="You've taken too long! Tour over!"})
