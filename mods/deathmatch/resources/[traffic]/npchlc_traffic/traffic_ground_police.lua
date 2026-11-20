-- PS2 wanted rosters are per player. Entity ownership prevents two nearby
-- suspects from issuing different orders to the same officer or patrol.
TrafficGroundPolice = {}
local police = TrafficGroundPolice
local rosters, officerOwner, dutyOwner = {}, {}, {}
local zoneGuards, associatedDrivers = {}, {}
local viceIndex, viceAt = 0, getTickCount()
local function roster(player)
    local r = rosters[player]
    if not r then
        r = {officers={}, units={}, cops=0, cars=0}
        rosters[player] = r
    end
    return r
end

function police.response(player)
    local level = getPlayerWantedLevel(player)
    return level, TrafficWanted.getPoliceResponse(level, player)
end

-- GAME.DTZ root +0x78/+0x7c, loaded by 00332460. Of 631
-- attribute boxes only these two have bits 0x10 or 0x100 set.
function police.zoneFlags(x,y,z)
    if -101<x and x< -67 and 919<y and y<945 and 9<z and z<23 then return 0x110 end
    if -165<x and x< -111 and 44<y and y<92 and -1<z and z<17 then return 0x10 end
    return 0
end

function police.enabled(response)
    return response and not response.suppressGarage and not response.suppressPolice
end

-- US PS2 model's handling pointer (+0x38), followed by handling +0x54.
local handling={[191]=.725556612,[193]=.811112165,[204]=.931112051,[207]=.658889771,
    [218]=.510001183,[219]=.295557022,[234]=.711111903,[246]=.434444785,[261]=1.101111889}
local multipliers={[3]=1.10,[4]=1.20,[5]=1.25,[6]=1.30}
function police.cruiseSpeed(original,stars)
    if stars<=1 then return 25 end
    if stars==2 then return 34 end
    return math.floor((handling[original] or handling[207])*multipliers[stars]*60)
end

-- 0042B050 draws once on assignment. 00428C48 updates the cruise byte
-- of an active pursuit independently of the mission and its close/far state.
function police.updatePursuitLevel(patrol, original, stars)
    if patrol.level == stars then return end
    if original == 191 then
        if not patrol.mission or (stars == 1) ~= (patrol.level == 1) then
            patrol.mission = stars == 1 and 4 or 21
        end
    elseif not patrol.mission then
        local draw = math.random(0, 7)
        local block = stars == 1 and bitAnd(draw, 2) == 0
            or stars == 2 and draw < 3 or stars == 3 and draw < 2 or stars >= 4 and draw == 0
        patrol.mission = block and 4 or 2
    end
    patrol.level = stars
    patrol.speed = police.cruiseSpeed(original, stars)
end

function police.available(player, response)
    local r = rosters[player]
    return police.enabled(response) and (r and r.cars or 0) < response.pursuitVehicleLimit
        and (r and r.cops or 0) < response.pursuitPedLimit
end

function police.releaseOfficer(ped)
    local r = rosters[officerOwner[ped]]
    if r then r.officers[ped], r.cops = nil, r.cops - 1 end
    officerOwner[ped] = nil
end

function police.releaseVehicle(vehicle)
    local player = dutyOwner[vehicle]
    local r = rosters[player]
    if r then r.units[vehicle], r.cars = nil, r.cars - 1 end
    dutyOwner[vehicle] = nil
    if TrafficPolice and TrafficPolice.isBoatAssigned and TrafficPolice.isBoatAssigned(vehicle) then TrafficPolice.releaseBoat(vehicle) end
end

function police.enroll(ped, player)
    if officerOwner[ped] and officerOwner[ped] ~= player then return false end
    local level, response = police.response(player)
    if level == 0 or not police.enabled(response) then return false end
    local r = roster(player)
    if r.officers[ped] and r.cops <= response.pursuitPedLimit then return true end
    local x,y,z = getElementPosition(getPedOccupiedVehicle(player) or player)
    local distance = getDistanceBetweenPoints3D(x,y,z,getElementPosition(ped))
    if r.cops >= response.pursuitPedLimit then
        local far, worst = nil, math.max(10, distance)
        for other in pairs(r.officers) do
            if isElement(other) then
                local d = getDistanceBetweenPoints3D(x,y,z,getElementPosition(other))
                if d > worst then far,worst = other,d end
            end
        end
        if not far then
            if r.officers[ped] and distance > 10 then police.releaseOfficer(ped) end
            return r.officers[ped] == true
        end
        police.releaseOfficer(far)
    end
    if not r.officers[ped] then
        officerOwner[ped],r.officers[ped],r.cops = player,true,r.cops + 1
    end
    return true
end

function police.associateDriver(state, player)
    associatedDrivers[state.driver]={state=state,player=player}
end

function police.returnDriver(ped)
    local entry=associatedDrivers[ped]
    if not entry then return false end
    local car,player=entry.state.vehicle,entry.player
    if not isElement(car) or isVehicleBlown(car) or getElementInterior(car)~=getElementInterior(ped)
        or getElementDimension(car)~=getElementDimension(ped) then associatedDrivers[ped]=nil return false end
    if isElement(player) and getPlayerWantedLevel(player)>0 then return false end
    associatedDrivers[ped]=nil
    local driver=getVehicleOccupant(car,0)
    if isElement(driver) and getElementType(driver)=="player" then
        exports.wanted:raisePlayerWanted(driver,1,"policeVehicle")
        return false
    end
    return PedAI.returnServiceDriver(ped,entry.state)
end

function police.target(ped) return officerOwner[ped] end

function police.officerCount(player)
    local r = rosters[player]
    return r and r.cops or 0
end

function police.vehicleTarget(vehicle) return dutyOwner[vehicle] end

function police.assignVehicle(state, player)
    if dutyOwner[state.vehicle] then return dutyOwner[state.vehicle] == player end
    local level, response = police.response(player)
    if level == 0 or not police.available(player,response) then return false end
    local r = roster(player)
    r.units[state.vehicle],r.cars,dutyOwner[state.vehicle] = true,r.cars + 1,player
    state.policeTarget = player
    return true
end

local function loaded(model,ped)
    return TrafficModelBindings.get(model) and TrafficAmbient.getPedestrianModel(ped)
end

function police.chooseVehicle(player,level,response)
    if level < 2 or not police.available(player,response) or level == 2 and math.random(0,65535)%31 <= 15 then return end
    local original = 207
    if response.undercover and (getTickCount()-viceAt)%4294967296 > 120000 and loaded(204,117)
        and TrafficAmbient.getPedestrianModel(118) then
        original = 204
    elseif response.swat and loaded(234,9) then
        if math.random(3)==3 then original=234 end
    elseif response.fbi and loaded(193,10) then original=193
    elseif response.army and loaded(246,11) and TrafficModelBindings.get(218) then
        original=math.random(2)==1 and 218 or 246
    end
    return TrafficModelBindings.get(original),original,13
end

function police.viceModel()
    return viceIndex < 2 and 117 or 118
end

function police.commitVice()
    viceAt,viceIndex=getTickCount(),(viceIndex+1)%4
end

function police.passengers(original,level)
    if original==234 or original==193 then return 3 end
    if original==204 then return 1 end
    if level>1 and (original==207 or original==218 or original==246) then return 1 end
    return 0
end

local function clearPlayer(player)
    local r=rosters[player]
    if not r then return end
    for vehicle in pairs(r.units) do police.releaseVehicle(vehicle) end
    for ped in pairs(r.officers) do police.releaseOfficer(ped) end
    rosters[player]=nil
end

addEventHandler("onPlayerQuit",root,function() clearPlayer(source) end)
addEventHandler("onPlayerWasted",root,function() clearPlayer(source) end)
addEventHandler("onElementDestroy",root,function()
    if officerOwner[source] then police.releaseOfficer(source) end
    if dutyOwner[source] then police.releaseVehicle(source) end
end)
addEventHandler("onPedWasted",root,function() if officerOwner[source] then police.releaseOfficer(source) end end)

local hlc = exports.npc_hlc
local shapes = exports.server_coldata
local graph
local nodes, visits, barriers, guards, stingers = {}, {}, {}, {}, {}
local blockCars, strips, nextObserver = 0, 0, 0
local deployedStrips = {}
local stripKey = "npchlc_traffic:stinger"

function police.footCandidate(player)
    local _,response=police.response(player)
    if not police.enabled(response) then return false end
    if getPedOccupiedVehicle(player) then
        local draw = math.random(0,31)==0
        return draw,draw
    end
    local r=rosters[player]
    if not response or not (r and r.cars>=response.pursuitVehicleLimit or TrafficRoad.policePopulationFull(player)) then return false end
    local x,y,z=getElementPosition(player)
    local count=0
    for _,ped in ipairs(getElementsWithinRange(x,y,z,90,"ped",getElementInterior(player),getElementDimension(player)) or {}) do
        if TrafficActors.isPolicePed(ped) and not isPedDead(ped) then count=count+1 end
    end
    return count<response.pursuitPedLimit,false
end

function police.prepareStinger(ped,player,from,to,pathTarget)
    hlc:clearNPCTasks(ped)
    stingers[ped]={player=player,pathTarget=pathTarget or to,interior=getElementInterior(ped),dimension=getElementDimension(ped)}
end

local function removeStrip(ped)
    local s=stingers[ped]
    if s and s.start then
        strips=strips-1
        deployedStrips[ped]=nil
        if isElement(ped) then removeElementData(ped,stripKey) end
    end
    stingers[ped]=nil
end

-- 0039D9A8 reads the crossing vehicle's model-info float at +0x58.
-- All other eligible US PS2 models use 0.7, also the untagged MTA default.
local wheelScales = {
    [174]=.6,[176]=.66,[178]=.6,[179]=.6,[181]=1.4,[184]=.5,[186]=.8,
    [190]=.654,[191]=.654,[192]=.64,[194]=1,[199]=.64,[200]=.82,[202]=.464,
    [205]=.66,[208]=.3,[209]=.9,[212]=.67,[216]=1.1,[218]=1.2,[220]=1.2,
    [221]=1.2,[227]=.9,[228]=.75,[229]=.464,[230]=.76,[231]=.654,[232]=.654,
    [234]=.9,[235]=.9,[236]=.9,[237]=1,[238]=.76,[240]=.85,[241]=1.06,
    [243]=.84,[245]=.92,[246]=1.5,[251]=.5,[252]=.66,[253]=.66,[255]=.9,
    [259]=.9,[268]=1.1,[269]=1.085,[271]=.66,
}

local function touchesSlats(wheel,last,spacing,oldSpacing,radiusSq)
    for pair=1,6 do
        -- Subtract the moving slat center before sweeping the wheel. Each
        -- crossed pair shares a center throughout the opening animation.
        local x,y,z=last[1]-pair*oldSpacing,last[2],last[3]
        local dx,dy,dz=wheel[1]-pair*spacing-x,wheel[2]-y,wheel[3]-z
        local lengthSq=dx*dx+dy*dy+dz*dz
        if lengthSq>0 then
            local t=math.max(0,math.min(1,-(x*dx+y*dy+z*dz)/lengthSq))
            x,y,z=x+t*dx,y+t*dy,z+t*dz
        end
        if x*x+y*y+z*z<radiusSq then return true end
    end
    return false
end

-- The server receives discrete vehicle transforms. Sweep each estimated wheel
-- between successive observations so a fast axle cannot skip the strip.
local function puncture(s, now)
    local spacing=TrafficStinger.geometry((now-s.start)%4294967296)
    local mx,my=s.x+s.dx*3.5*spacing,s.y+s.dy*3.5*spacing
    local previous=s.contacts or {}
    local elapsed=s.checked and (now-s.checked)%4294967296 or 0
    s.contacts,s.checked={},now
    for _,car in ipairs(getElementsWithinRange(mx,my,s.z,18,"vehicle",s.interior,s.dimension) or {}) do
        local kind=getVehicleType(car)
        local twoWheels=kind=="Bike" or kind=="BMX"
        if kind=="Automobile" or twoWheels or kind=="Quad" or kind=="Monster Truck" then
            local matrix=getElementMatrix(car)
            local lx,ly,lz,hx,hy=shapes:getModelBoundingBox(getElementModel(car))
            if matrix and type(hy)=="number" then
                local old={getVehicleWheelStates(car)}
                local vx,vy,vz=getElementVelocity(car)
                local sample={speed=math.sqrt(vx*vx+vy*vy+vz*vz),spacing=spacing}
                local prior=elapsed<=250 and previous[car]
                if prior then
                    local px,py,pz=matrix[4][1]-prior.x,matrix[4][2]-prior.y,matrix[4][3]-prior.z
                    -- MTA velocity units are 50 world units/s. Discard teleports.
                    local travel=1.5+math.max(prior.speed,sample.speed)*elapsed*.05
                    if px*px+py*py+pz*pz>travel*travel then prior=nil end
                end
                sample.x,sample.y,sample.z=matrix[4][1],matrix[4][2],matrix[4][3]
                s.contacts[car]=sample
                local original=getElementData(car,"npchlc_traffic:originalModel",false)
                local radiusSq=((wheelScales[original] or .7)+.1)^2
                local changed=false
                for i=1,4 do
                    local side=twoWheels and 0 or (i<=2 and lx or hx)*.9
                    local axle=(i%2==1 and hy or ly)*.65
                    local x=matrix[4][1]+side*matrix[1][1]+axle*matrix[2][1]+lz*matrix[3][1]-s.x
                    local y=matrix[4][2]+side*matrix[1][2]+axle*matrix[2][2]+lz*matrix[3][2]-s.y
                    local z=matrix[4][3]+side*matrix[1][3]+axle*matrix[2][3]+lz*matrix[3][3]
                    local along=x*s.dx+y*s.dy
                    local across,height=x*s.dy-y*s.dx,z-s.z
                    local wheel={along,across,height}
                    sample[i]=wheel
                    if old[i]==0 and touchesSlats(wheel,prior and prior[i] or wheel,
                        spacing,prior and prior.spacing or spacing,radiusSq) then
                        old[i],changed=1,true
                    end
                end
                if changed then setVehicleWheelStates(car,unpack(old)) end
            end
        end
    end
end

-- 00268880 searches the cells intersecting a five-unit box. Within them it
-- ranks road nodes by |dx| + |dy| + 3|dz|, starting with a best score of 25.
local function stingerRoadPoint(x,y,z)
    if not graph or not graph.roadNodeCells then return end
    local best, score = nil, 25
    for cx=math.floor((x-5)/80+30),math.floor((x+5)/80+30) do
        local column=graph.roadNodeCells[cx]
        for cy=math.floor((y-5)/80+25),math.floor((y+5)/80+25) do
            for _,node in ipairs(column and column[cy] or {}) do
                local reach=math.abs(node.x-x)+math.abs(node.y-y)+3*math.abs(node.z-z)
                if reach<score and bitAnd(node.flags,0x140)==0 then best,score=node,reach end
            end
        end
    end
    if not best then return end
    -- 0026B200 offsets a divided road's node relative to its first link.
    if (best.width or 0)>0 and best.linkCount>0 then
        local neighbor=graph.nodes[graph.links[best.firstLink+1].to+1]
        local fx,fy=neighbor.x-best.x,neighbor.y-best.y
        local length=math.sqrt(fx*fx+fy*fy)
        if length>0 then
            local offset=(best.width+2.5)/length
            if fx<0 then offset=-offset end
            return best.x-fy*offset,best.y+fx*offset
        end
    end
    return best.x,best.y
end

local function publishStrip(ped,s,age)
    setElementData(ped,stripKey,{s.x,s.y,s.z,s.dx,s.dy,age},"broadcast","deny")
    s.published=age
end

local function deployStrip(ped,s,now)
    local car=getPedOccupiedVehicle(s.player)
    if not car or getVehicleType(car)~="Automobile" and getVehicleType(car)~="Bike" then removeStrip(ped) return false end
    local x,y,z=getElementPosition(ped)
    local cx,cy=getElementPosition(car)
    local vx,vy=getElementVelocity(car)
    local distance=getDistanceBetweenPoints2D(x,y,cx,cy)
    local speed=math.sqrt(vx*vx+vy*vy)
    if strips>=2 or speed==0 or distance==0 or distance>=30
        or ((x-cx)*vx+(y-cy)*vy)/(distance*speed)<=.8 then return true end
    -- 00327D98 faces across the pedestrian path toward the road node.
    -- The approaching vehicle qualifies the throw but does not pick its side.
    local roadX,roadY=stingerRoadPoint(x,y,z)
    if not roadX then return true end
    local fx,fy=s.pathTarget.x-x,s.pathTarget.y-y
    local length=math.sqrt(fx*fx+fy*fy)
    if length<=1 then return true end
    local dx,dy=-fy/length,fx/length
    local offset=(roadX-x)*dx+(roadY-y)*dy
    if offset==0 then return true end
    if offset<0 then dx,dy=-dx,-dy end
    s.start,s.x,s.y,s.z,s.dx,s.dy=now,x,y,z-.85,dx,dy
    strips=strips+1
    deployedStrips[ped]=s
    hlc:clearNPCTasks(ped)
    setPedRotation(ped,-math.deg(math.atan2(dx,dy)))
    publishStrip(ped,s,0)
    return true
end

local function advanceStrip(ped,s,now)
    local age=(now-s.start)%4294967296
    if age>390 and (not s.visible or s.published<2500 and (age>=2500 or age-s.published>=250)) then
        publishStrip(ped,s,math.min(age,2500))
        s.visible=true
    end
    if s.visible and (not s.checked or (now-s.checked)%4294967296>=100) then
        puncture(s,now)
    end
    return age<=2500
end

function police.updateSpecial(ped,now)
    local zonePlayer=zoneGuards[ped] or officerOwner[ped]
    if zonePlayer and isElement(zonePlayer) and getElementDimension(zonePlayer)==getElementDimension(ped)
        and getElementInterior(zonePlayer)==getElementInterior(ped) and getPlayerWantedLevel(zonePlayer)>0
        and police.zoneFlags(getElementPosition(zonePlayer))~=0 then
        local _,response=police.response(zonePlayer)
        if police.enabled(response) then
            if not zoneGuards[ped] then
                police.releaseOfficer(ped)
                PedServices.interrupt(ped)
                hlc:clearNPCTasks(ped)
                zoneGuards[ped]=zonePlayer
            end
            return true
        end
    end
    zoneGuards[ped]=nil
    local guard=guards[ped]
    if guard then
        local player,car=guard.player,guard.car
        local _,response
        if isElement(player) then _,response=police.response(player) end
        if police.enabled(response) and isElement(car) and getPlayerWantedLevel(player)>0
            and getElementDimension(player)==getElementDimension(ped) and getElementInterior(player)==getElementInterior(ped) then
            local x,y,z=getElementPosition(ped)
            local tx,ty,tz=getElementPosition(player)
            local targetCar=getPedOccupiedVehicle(player)
            local cx,cy=getElementPosition(car)
            local d=(x-tx)^2+(y-ty)^2
            local vx,vy=getElementVelocity(targetCar or player)
            local leave=d>2500 and vx*(tx-x)+vy*(ty-y)>0
                or d<=2500 and (tx-cx)*guard.sideX+(ty-cy)*guard.sideY<0
                or d<25 and (not targetCar or vx*vx+vy*vy<.000025)
            if not leave then
                local target=targetCar or player
                if d<PedAIRules.attackRange(getPedWeapon(ped))^2 then
                    if guard.target~=target then
                        hlc:setNPCTask(ped,{"shootElement",target})
                        guard.target=target
                    end
                elseif guard.target then
                    hlc:clearNPCTasks(ped)
                    guard.target=nil
                end
                return true
            end
        end
        guards[ped]=nil
        hlc:clearNPCTasks(ped)
    end
    local s=stingers[ped]
    if not s then return false end
    if not isElement(s.player) or getPlayerWantedLevel(s.player)==0
        or getElementDimension(ped)~=s.dimension or getElementDimension(s.player)~=s.dimension
        or getElementInterior(ped)~=s.interior or getElementInterior(s.player)~=s.interior
        or isPedInVehicle(ped) or isPedDead(ped) then removeStrip(ped) return false end
    if not s.start then
        local _,response=police.response(s.player)
        if not police.enabled(response) then removeStrip(ped) return false end
        return deployStrip(ped,s,now)
    end
    return advanceStrip(ped,s,now)
end

local function removeBarrier(car)
    local b=barriers[car]
    if not b then return end
    barriers[car],blockCars=nil,blockCars-1
    if isElement(car) then
        if TrafficVisibility.hasPlayerOccupant(car) then TrafficRoad.retainPlayerVehicle(car)
        else destroyElement(car) end
    end
end

local function spawnGuard(b,car,sign)
    local model=PedServices.policeCrewModel(b.original) or 8
    if not TrafficAmbient.getPedestrianModel(model) then model=8 end
    local skin=TrafficAmbient.getPedestrianModel(model)
    if not skin then return end
    local matrix=getElementMatrix(car)
    if not matrix then return end
    local cx,cy,cz=getElementPosition(car)
    local x=cx+b.sideX*1.7+matrix[2][1]*sign*1.4
    local y=cy+b.sideY*1.7+matrix[2][2]*sign*1.4
    local ped=createPed(skin,x,y,cz+.3)
    if not ped then return end
    setElementDimension(ped,b.dimension)
    TrafficModelBindings.tag(ped,model)
    if not hlc:enableHLCForNPC(ped,"walk") or not TrafficAmbient.adoptDriver(ped,nil,nil,model) then destroyElement(ped) return end
    PedAI.attach(ped,model)
    setTrafficPolicePed(ped,true)
    if model==8 then setPedWeaponSlot(ped,2) end
    guards[ped]={player=b.player,car=car,sideX=b.sideX,sideY=b.sideY}
end

local placements={}
local function cancelPlacement(plan)
    if plan then
        TrafficWorld.cancelRoad(plan.player,plan,"roadblock")
        placements[plan.player]=nil
    end
end

-- 001345A0 computes the parked origin clearance from wheel dummy, radius
-- and suspension. These are the four US PS2 roadblock vehicles.
local rideHeight={[207]=.757143,[234]=1.03,[193]=.8675,[218]=1.436667}

local function barrierGroundReady(player,plan,result)
    if placements[player]~=plan then return end
    plan.ground=result and result.probes or {}
end

local function layBarrier(player,node,response)
    if placements[player] or blockCars>=18 then return end
    local first,second=graph.links[node.firstLink+1],graph.links[node.firstLink+2]
    if not first or not second then return end
    local a,b=graph.nodes[first.to+1],graph.nodes[second.to+1]
    local fx,fy=b.x-a.x,b.y-a.y
    local length=math.sqrt(fx*fx+fy*fy)
    if length<1 then return end
    fx,fy=fx/length,fy/length
    local dx,dy=-fy,fx
    local original=response.army and 218 or response.fbi and 193 or response.swat and 234 or 207
    if not TrafficModelBindings.get(original) then original=207 end
    local model=TrafficModelBindings.get(original)
    if not model then return end
    local lx,ly,lz,hx,hy,hz=shapes:getModelBoundingBox(model)
    if type(hz)~="number" then return end
    local radius=math.sqrt((hx-lx)^2+(hy-ly)^2+(hz-lz)^2)*.5
    local width=math.max(first.leftLanes+first.rightLanes,second.leftLanes+second.rightLanes)*5+5
    local count=math.min(6,math.floor(width/(radius*1.5+.25)))
    local dimension=getElementDimension(player)
    local px,py=getElementPosition(player)
    local side=(px-node.x)*fx+(py-node.y)*fy>0 and 1 or -1
    local median=node.width or node.rawWidth/16
    local sections=median>0 and 2 or 1
    local slots,points={},{}
    local heading=-math.deg(math.atan2(dx,dy))
    for section=1,sections do
        local start=sections==1 and -width/2 or section==1 and -median-width or median
        for i=1,count do
            local offset=start+width*(i-.5)/count
            local x,y=node.x+dx*offset,node.y+dy*offset
            local yaw=heading+math.random(-13,13)
            local angle=math.rad(yaw)
            local vx,vy=-math.sin(angle),math.cos(angle)
            slots[#slots+1]={x=x,y=y,yaw=yaw}
            -- 00151A88 samples the front and rear collision-box extents.
            points[#points+1]={x=x+vx*hy,y=y+vy*hy,z=node.z}
            points[#points+1]={x=x+vx*ly,y=y+vy*ly,z=node.z}
        end
    end
    if #slots==0 then return end
    local now=getTickCount()
    local plan={slots=slots,points=points,index=1,model=model,original=original,player=player,dimension=dimension,
        x=node.x,y=node.y,rear=ly,span=hy-ly,height=math.max(-lz,rideHeight[original]),radius=math.max(2,radius),
        started=now,requested=now,
        sideX=fx*side,sideY=fy*side}
    placements[player]=plan
    TrafficWorld.probeRoad(player,plan,barrierGroundReady,"roadblock")
end

local function placeCars(plan,now,budget)
    local player=plan.player
    if not isElement(player) or isPedDead(player) or getPlayerWantedLevel(player)<3
        or getElementDimension(player)~=plan.dimension or getElementInterior(player)~=0
        or blockCars>=18 or (now-plan.started)%4294967296>=8000 then cancelPlacement(plan) return budget end
    local px,py=getElementPosition(player)
    if (px-plan.x)^2+(py-plan.y)^2>170^2 then cancelPlacement(plan) return budget end
    if not plan.ground then
        -- The map may still be streaming when the player crosses the 160-unit boundary.
        if (now-plan.requested)%4294967296>=1000 then
            plan.requested=now
            TrafficWorld.probeRoad(player,plan,barrierGroundReady,"roadblock")
        end
        return budget
    end
    -- A wide divided road can request twelve cars. Spread its native creates
    -- and sync traffic over the existing 50 ms scheduler visits.
    while budget>0 and plan.index<=#plan.slots and blockCars<18 do
        local i=plan.index
        local slot=plan.slots[i]
        plan.index=plan.index+1
        local front,rear=plan.ground[2*i-1],plan.ground[2*i]
        if not slot.done and front and rear then
            budget=budget-1
            slot.done=true
            local grade=(front.groundZ-rear.groundZ)/plan.span
            local pitch=math.atan(grade)
            local up=math.cos(pitch)
            local z=rear.groundZ-plan.rear*grade+plan.height/up
            local occupied=getElementsWithinRange(slot.x,slot.y,z,plan.radius,"vehicle",0,plan.dimension)
            local car=up>.94 and occupied and #occupied==0 and
                createVehicle(plan.model,slot.x,slot.y,z,math.deg(pitch),0,slot.yaw)
            if car then
                setElementDimension(car,plan.dimension)
                TrafficModelBindings.tag(car,plan.original)
                setVehicleEngineState(car,false)
                barriers[car]={player=player,dimension=plan.dimension,original=plan.original,sideX=plan.sideX,sideY=plan.sideY}
                blockCars=blockCars+1
            end
        end
    end
    if plan.index>#plan.slots then
        for _,slot in ipairs(plan.slots) do
            if not slot.done then
                plan.index,plan.ground=1,nil
                return budget
            end
        end
        cancelPlacement(plan)
    end
    return budget
end

local lastSweep
function police.step(players,now)
    if not graph then return end
    -- Deployed strips continue checking contacts while their officer runs
    -- another task. The two-strip budget bounds this work for all players.
    for ped,s in pairs(deployedStrips) do
        if not isElement(ped) or not isElement(s.player) or getPlayerWantedLevel(s.player)==0
            or getElementDimension(ped)~=s.dimension or getElementDimension(s.player)~=s.dimension
            or getElementInterior(ped)~=s.interior or getElementInterior(s.player)~=s.interior then
            removeStrip(ped)
        else advanceStrip(ped,s,now) end
    end
    local budget=2
    for _,plan in pairs(placements) do budget=placeCars(plan,now,budget) end
    if blockCars>0 and (not lastSweep or (now-lastSweep)%4294967296>=250) then
        lastSweep=now
        for car,b in pairs(barriers) do
            local player=b.player
            if not isElement(player) or not isElement(car) or getElementDimension(player)~=b.dimension or getElementInterior(player)~=0
                or getPlayerWantedLevel(player)==0 or isPedDead(player) then removeBarrier(car)
            else
                local x,y,z=getElementPosition(car)
                local px,py,pz=getElementPosition(player)
                local horizontal=(x-px)^2+(y-py)^2
                if horizontal+(z-pz)^2>170^2 then removeBarrier(car)
                elseif not b.deployed and horizontal<51^2 then
                    b.deployed=true
                    spawnGuard(b,car,-1)
                    spawnGuard(b,car,1)
                    break
                end
            end
        end
    end
    if #players==0 or #nodes==0 then return end
    nextObserver=nextObserver%#players+1
    local player=players[nextObserver]
    if getPlayerWantedLevel(player)<3 or getElementInterior(player)~=0 or isPedDead(player) then visits[player]=nil return end
    local dim=getElementDimension(player)
    local v=visits[player]
    if not v or v.dimension~=dim then v={index=1,inside={},dimension=dim}; visits[player]=v end
    local x,y=getElementPosition(player)
    for _=1,math.ceil(#nodes/16) do
        local i=v.index
        local node=nodes[i]
        local previous=v.inside[i]
        local inside=(x-node.x)^2+(y-node.y)^2<25600
        v.inside[i],v.index=inside,i%#nodes+1
        if previous==false and inside and getPedOccupiedVehicle(player) then
            local _,response=police.response(player)
            if police.enabled(response) and bitAnd(math.random(0,32767),100)<response.roadblockThreshold then
                layBarrier(player,node,response)
                break
            end
        end
    end
end

function police.start(loadedGraph)
    if loadedGraph.edition~="SLUS-21590 USA v1.00" then return end
    graph=loadedGraph
    for _,node in ipairs(graph.nodes) do
        if node.kind=="vehicle" and bitAnd(node.flags,0x8f)==0x82 then
            nodes[#nodes+1]=node
            if #nodes==300 then break end
        end
    end
end

function police.stop()
    for _,plan in pairs(placements) do cancelPlacement(plan) end
    for car in pairs(barriers) do removeBarrier(car) end
    for ped in pairs(stingers) do removeStrip(ped) end
    for player in pairs(rosters) do clearPlayer(player) end
    graph,nodes,visits,guards,zoneGuards,associatedDrivers=nil,{},{},{},{},{}
end

local function clearInterest(player)
    clearPlayer(player)
    visits[player]=nil
    cancelPlacement(placements[player])
    for car,b in pairs(barriers) do if b.player==player then removeBarrier(car) end end
    for ped,s in pairs(stingers) do if s.player==player then removeStrip(ped) end end
    for ped,target in pairs(zoneGuards) do if target==player then zoneGuards[ped]=nil end end
end
addEventHandler("onPlayerQuit",root,function() clearInterest(source) end)
addEventHandler("onPlayerWanted",root,function(_,level) if level==0 then clearInterest(source) end end)
addEventHandler("onPlayerPoliceResponseChange",root,function()
    -- Go directly to the authority on this event. Same-priority cache
    -- invalidation handlers are not ordered across MTA scripts.
    local response=exports.wanted:getPlayerPoliceResponse(source)
    if not police.enabled(response) then clearInterest(source) end
end)
addEventHandler("onElementDimensionChange",root,function() if visits[source] or rosters[source] then clearInterest(source) end end)
addEventHandler("onElementInteriorChange",root,function() if visits[source] or rosters[source] then clearInterest(source) end end)
addEventHandler("onElementDestroy",root,function()
    guards[source],zoneGuards[source],associatedDrivers[source]=nil,nil,nil
    if stingers[source] then removeStrip(source) end
    if barriers[source] then barriers[source],blockCars=nil,blockCars-1 end
end)
addEventHandler("onPedWasted",root,function()
    guards[source],zoneGuards[source],associatedDrivers[source]=nil,nil,nil
    if stingers[source] then removeStrip(source) end
end)
