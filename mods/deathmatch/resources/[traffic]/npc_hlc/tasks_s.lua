performTask = {}

function performTask.walkToPos(npc, task, elapsed)
    stepNPCToPoint(npc, task[2], task[3], task[4], elapsed)
end

performTask.walkTrafficToPoint = performTask.walkToPos

function performTask.walkTrafficCrossing(npc, task, elapsed)
    local pace = getNPCTrafficCrossingPace(npc, task)
    if pace ~= "wait" then stepNPCToPoint(npc, task[2], task[3], task[4], elapsed, nil, pace) end
end

function performTask.driveToPos(npc, task, elapsed)
    stepNPCToPoint(getPedOccupiedVehicle(npc), task[2], task[3], task[4], elapsed, getNPCDriveSpeed(npc))
end

-- A syncer can receive the car before it receives the map collision. Restore
-- a car that fell through the world to the current lane, preserving its order.
function restoreFallenRaceVehicle(state,car,task)
    if not car then return false end
    local x,y,z=getElementPosition(car)
    if z>=0 then
        if task[1]=="driveRaceToPoint" and isVehicleOnGround(car) then
            state.groundedRaceTask=task
            state.groundedRaceX,state.groundedRaceY,state.groundedRaceZ=x,y,z
        end
        return false
    end
    if isVehicleBlown(car) or isElementInWater(car) then return false end
    local rx,ry,rz
    if task.race then
        local anchor,link=task[4],task[5][1]
        local dx,dy=link[3]-anchor[1],link[4]-anchor[2]
        local squared=dx*dx+dy*dy
        local t=squared>0 and math.max(0,math.min(1,((x-anchor[1])*dx+(y-anchor[2])*dy)/squared)) or 0
        rx,ry,rz=anchor[1]+t*dx,anchor[2]+t*dy,anchor[3]+t*(link[5]-anchor[3])
    else
        if state.groundedRaceTask==task then
            rx,ry,rz=state.groundedRaceX,state.groundedRaceY,state.groundedRaceZ
        else
            rx,ry,rz=x,y,task[4]
        end
    end
    if z>=rz-10 then return false end
    local _,_,heading=getElementRotation(car)
    local body,pitch,roll=getVcsRoadVehiclePose(car,rx,ry,rz+0.65,heading)
    setElementPosition(car,rx,ry,body or rz+1.0,false)
    setElementRotation(car,pitch or 0,roll or 0,heading)
    setElementVelocity(car,0,0,0)
    setElementAngularVelocity(car,0,0,0)
    triggerEvent("npc_hlc:onRaceVehicleReposition",car)
    return true
end

-- MTA releases the vehicle syncer outside streaming range. Continue the same
-- coordinate order on the current road segment or direct approach until a
-- client acquires it again. The control scheduler bounds each step to 250 ms.
local function raceTurnFactor(angle)
    -- VCS 00438060 reduces cruise as the error grows from 0.4 to 1.2 radians.
    return 1-0.6*math.max(0,math.min(1,(math.abs(angle)-0.4)/0.8))
end

-- The server has no tyre simulation. Start braking when the remaining
-- distance and the fallback's 8 m/sÂ² braking can no longer fit the turn.
-- Eight metres is the acceptance distance at a passed lane waypoint.
local function fallbackBendSpeed(speed,distance,ax,ay,bx,by,cornering)
    local turn=math.abs(math.atan2(ax*by-ay*bx,ax*bx+ay*by))
    if turn<=0.4 then return speed end
    local radius=math.max(2,8/math.tan(turn*0.5))
    return math.min(speed,math.sqrt(cornering*radius+2*8*math.max(0,distance-4)))
end

local function fallbackCruise(task,x,y,cruise,cornering)
    local speed=cruise*(50/60)
    if task[1]=="driveRaceToPoint" then
        if task[5] and (task[5]~=task[2] or task[6]~=task[3]) then
            local dx,dy=task[2]-x,task[3]-y
            local distance=math.sqrt(dx*dx+dy*dy)
            local ox,oy=task[5]-task[2],task[6]-task[3]
            speed=getNPCRaceApproachSpeed(cruise,distance,math.atan2(dy,dx),math.atan2(oy,ox),task[7])*(50/60)
            speed=fallbackBendSpeed(speed,distance,dx,dy,ox,oy,cornering)
        end
    else
        local link=task[5][1]
        local distance=math.sqrt((link[3]-x)^2+(link[4]-y)^2)
        speed=getNPCRaceWindowSpeed(task,1,distance,cruise)*(50/60)
        for i=2,#task[5] do
            if distance>4+speed*speed/(2*8) then break end
            local after=task[5][i]
            speed=fallbackBendSpeed(speed,distance,link[6],link[7],after[6],after[7],cornering)
            distance=distance+math.sqrt((after[3]-link[3])^2+(after[4]-link[4])^2)
            link=after
        end
    end
    return speed
end

local function stepRaceVehicle(npc,task,x,y,z,elapsed)
    local car=getPedOccupiedVehicle(npc)
    if elapsed<=0 or not car or isElementFrozen(car) or isVehicleBlown(car) then return end
    local frame=getElementMatrix(car)
    if not frame then return end
    local cx,cy,cz=unpack(frame[4])
    local dx,dy=x-cx,y-cy
    local distance=math.sqrt(dx*dx+dy*dy)
    if distance<0.01 then return end
    local vx,vy=getElementVelocity(car)
    local speed=math.sqrt(vx*vx+vy*vy)*50
    local cruise=getNPCDriveSpeed(npc)*50*(50/60)
    local dt=elapsed/1000
    local kind=getVehicleType(car)
    local lateralAcceleration=kind=="Quad" and 8 or kind=="Bike" and 11 or 13
    local requested=fallbackCruise(task,cx,cy,getNPCDriveSpeed(npc)*50,lateralAcceleration)
    local height=kind=="Bike" and 0.55 or 0.8
    local tx,ty,tz,passLimit=getRaceFallbackTarget(car,cx,cy,cz,x,y,z+height,speed,requested,task[1]=="driveTrafficPhysics" and task)
    if passLimit then requested=math.min(requested,passLimit) end
    local target=math.atan2(ty-cy,tx-cx)
    local heading=math.atan2(frame[2][2],frame[2][1])
    local error=math.atan2(math.sin(target-heading),math.cos(target-heading))
    requested=math.min(requested,cruise*raceTurnFactor(error))
    -- At short range the circle needed to reach a point limits entry speed.
    -- A car facing away must first slow sufficiently to turn within the leg.
    -- The unsynced approximation follows the measured cornering rate of
    -- each chassis. Small heading corrections on a straight do not require
    -- a fresh braking maneuver at every intermediate graph waypoint.
    if math.abs(error)>0.4 then
        local radius=distance/(2*math.max(0.1,math.sin(math.min(math.pi/2,math.abs(error)))))
        requested=math.min(requested,math.sqrt(lateralAcceleration*radius))
    end
    speed=math.max(speed-8*dt,math.min(requested,speed+6*dt))
    local avoiding=math.abs(dx*(ty-cy)-dy*(tx-cx))>0.01*distance
    if avoiding then lateralAcceleration=math.max(12,lateralAcceleration) end
    local turn=dt*math.min(1.8,lateralAcceleration/math.max(speed,3))
    heading=heading+math.max(-turn,math.min(turn,error))
    local travel=math.min(speed*dt,distance)
    local dz=(tz-cz)/math.max(1,math.sqrt((tx-cx)^2+(ty-cy)^2))*travel
    local nx,ny=cx+travel*math.cos(heading),cy+travel*math.sin(heading)
    local yaw=math.deg(heading)-90
    local body,pitch,roll=getVcsRoadVehiclePose(car,nx,ny,cz,yaw)
    if not body then
        local floor=getVcsGroundHeight(nx,ny,cz-height)
        if floor then body=floor+height end
    end
    if body then dz=body-cz end
    -- A discontinuity can be a curb, rooftop or a different bridge deck.
    -- Follow a normal grade in one step, but bound any correction in either direction.
    local climb=travel*0.65+2*dt
    dz=math.max(-climb,math.min(climb,dz))
    stepNPCToPoint(car,nx,ny,cz+dz,elapsed,math.sqrt(travel^2+dz^2)/(dt*50))
    local ax,ay,az=getElementPosition(car)
    if pitch and (ax~=cx or ay~=cy) then setElementRotation(car,pitch,roll,yaw) end
    setElementVelocity(car,(ax-cx)/(dt*50),(ay-cy)/(dt*50),(az-cz)/(dt*50))
end

function performTask.driveRaceToPoint(npc,task,elapsed)
    stepRaceVehicle(npc,task,task[2],task[3],task[4],elapsed)
end

function performTask.driveTrafficPhysics(npc,task,elapsed)
    if task.race then
        local point=task[5][1]
        stepRaceVehicle(npc,task,point[3],point[4],point[5],elapsed)
    end
end

function performTask.walkAlongLine(npc, task, elapsed)
    stepNPCAlongLine(npc, task, elapsed)
end

function performTask.driveAlongLine(npc, task, elapsed)
    stepNPCAlongLine(getPedOccupiedVehicle(npc), task, elapsed, getNPCDriveSpeed(npc))
end

function performTask.walkAroundBend(npc, task, elapsed)
    stepNPCAroundBend(npc, task, elapsed)
end

function performTask.driveAroundBend(npc, task, elapsed)
    stepNPCAroundBend(getPedOccupiedVehicle(npc), task, elapsed, getNPCDriveSpeed(npc))
end

function performTask.walkFollowElement() end
function performTask.walkFormation(npc,task,elapsed)
    local x,y,z,fx,fy = getNPCFormationSlot(task)
    if not x then return end
    local px,py = getElementPosition(npc)
    if (px-x)^2+(py-y)^2 > task[3]^2 then
        stepNPCToPoint(npc,x,y,z,elapsed)
    elseif task[4]>0 and task[5]==0 then
        local heading = math.deg(math.atan2(-fx,fy))
        local _,_,current = getElementRotation(npc)
        if math.abs((heading-current+180)%360-180)>0.5 then setPedRotation(npc,heading) end
    end
end
function performTask.shootPoint() end
function performTask.shootElement() end
function performTask.killPed() end
function performTask.attackOccupiedVehicle() end
function performTask.approachDriverDoor() end
-- These tasks act on the native vehicle through its syncer.
function performTask.stopVehicle() end
function performTask.driveAtPed() end
function performTask.drivePoliceBlock() end
function performTask.waitForGreenLight() end
