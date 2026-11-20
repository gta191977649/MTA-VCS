PedRoadInjury = {}

-- CBike::VehicleDamage, SLUS_215.90 00336934..00336B14 (ambient rider).
function PedRoadInjury.bikeScore(model, impulse, mass, matrix, x,y,z)
    if not matrix or not mass or mass<=0 then return 0 end
    local initial = impulse*800/mass
    if initial<=10 then return 0 end
    local function dot(axis)
        return x*axis[1]+y*axis[2]+z*axis[3]
    end
    local forward,right,up = math.abs(dot(matrix[2])),math.abs(dot(matrix[1])),dot(matrix[3])
    local frontWeight,upWeight = 0.6,0.05
    if forward>0.85 and z>=0.85 then frontWeight=frontWeight+7*z*z end
    if model==205 or model==231 or model==232 then
        frontWeight,upWeight=frontWeight*0.65,upWeight*0.75
    end
    return initial*(frontWeight*forward+0.45*right+upWeight*math.max(0,up)-1.5*math.min(0,up))
end

function PedRoadInjury.startBike(ped,walk,impact,launch,road,passenger)
    if walk.roadFall or isPedDead(ped) or isPedInVehicle(ped) then return end
    walk.roadFall = {attacker=impact.attacker,road=road,passenger=passenger,started=getTickCount()}
    walk.hitAt = nil
    if launch then
        -- Reason 0x2A jumps through 004C2A48 to 003F0EF8. Copy bike
        -- velocity, then apply the contact force to the 70-unit body.
        local kick = -0.6*impact.impulse/impact.mass
        setPedAnimation(ped,"PED","BIKE_fall_off",-1,false,false,false,true)
        setElementVelocity(ped,impact.vx+impact.nx*kick,impact.vy+impact.ny*kick,
            impact.vz+(8+7*math.random())/70)
        local hp = getElementHealth(ped)-impact.score*0.05
        if hp<=0 then killPed(ped,impact.attacker or nil,49) else setElementHealth(ped,hp) end
    end
end

function PedRoadInjury.update(ped,walk,now)
    local fall = walk.roadFall
    if isPedInVehicle(ped) then walk.roadFall=nil return end
    if not fall.landed then
        if (now-fall.started)%4294967296<(fall.downTime or 250) or not isPedOnGround(ped) then return end
        fall.landed=now
        setPedAnimation(ped,"PED","getup_front",900,false,false,false,false)
    elseif (now-fall.landed)%4294967296>=900 then
        walk.roadFall,walk.hitAt=nil,nil
        PedAI.afterRoadFall(ped,fall.attacker,fall.road)
        if fall.passenger and not PedAI.busy(ped) then
            walk.bikePassenger,walk.bikeReturnAt=fall.passenger,now
        end
    end
end

-- 001DA320, ordinary civilian hit by a land vehicle.
function PedRoadInjury.pedDamage(impulse,vertical)
    if impulse>12 then return 1000 end
    if impulse>6 or vertical < -0.8 and impulse>3 then return 30 end
    return 0
end

local function pedestrianVelocity(ped,car,damage,vx,vy,vz)
    local x,y,z=getElementPosition(ped)
    local m=getElementMatrix(car)
    if not m then return getElementVelocity(ped) end
    local dx,dy,dz=x-m[4][1],y-m[4][2],z-m[4][3]
    local speed=math.sqrt(vx*vx+vy*vy+vz*vz)
    local horizontal=math.sqrt(vx*vx+vy*vy)
    local distance=math.max(0.001,math.sqrt(dx*dx+dy*dy+dz*dz))
    if damage==30 then
        local shove=2*math.min(horizontal*10,1.5)*math.min(70/90,1)/70
        local scale=0.95/math.max(horizontal,0.001)
        return vx*0.75+shove*(vx*scale+0.05*dx/distance),
            vy*0.75+shove*(vy*scale+0.05*dy/distance),shove*0.05*dz/distance
    end
    local right,forward,up=m[1],m[2],m[3]
    local _,rear,_,width,front,top=exports.server_coldata:getModelBoundingBox(getElementModel(car))
    if not top or front<=rear or vx*forward[1]+vy*forward[2]+vz*forward[3]<0 then return getElementVelocity(ped) end
    local flank = math.abs(dx*right[1]+dy*right[2]+dz*right[3]) > width*0.99
    if flank then
        local along = dx*forward[1]+dy*forward[2]+dz*forward[3]
        if math.abs(along) < front*0.85 then return vx*0.9,vy*0.9,0 end
    else
        local roll=math.random(0,3)
        if (dx*up[1]+dy*up[2]+dz*up[3]<=0.1 or roll<2) and roll~=0 then return vx*0.9,vy*0.9,0 end
    end
    local pitch=forward[3]
    local extent=pitch < -0.2 and rear or pitch > 0.1 and front or 0
    local dzTop=m[4][3]+top*up[3]+extent*pitch-z
    local span=extent==0 and front or front-rear
    local lift=dzTop*speed/math.max(0.1,span)*(1.5+math.random(0,255)*0.002)
    local _,_,yaw=getElementRotation(ped)
    local sideways=math.abs(vx*math.cos(math.rad(yaw))+vy*math.sin(math.rad(yaw)))>horizontal*0.7071
    return vx*lift*0.2/speed,vy*lift*0.2/speed,math.min(0.1,lift*(sideways and 1.5 or 1)+vz*lift*0.2/speed)+0.2/90
end

function PedRoadInjury.strike(ped,walk,car,impulse,normalZ,vx,vy,vz)
    local now=getTickCount()
    if not vx then vx,vy,vz=TrafficRoad.contactVelocity(car,now) end
    local speed=math.sqrt(vx*vx+vy*vy+vz*vz)
    if speed<0.025 then return end
    -- Corroborate the remote impulse against the vehicle's synchronized
    -- motion and the original 70-unit body mass.
    local damage=PedRoadInjury.pedDamage(math.min(impulse,70*(speed+0.05)*1.5),normalZ)
    if damage==0 then return end
    local last=walk.carContact
    if last and last.car==car and (now-last.at)%4294967296<1000 and damage<=last.damage then return end
    local brain=PedAI.brain(ped)
    local health=getElementHealth(ped)
    local baseline=brain and brain.health and (now-brain.sampled)%4294967296<=250 and math.max(health,brain.health) or health
    walk.carContact={car=car,at=now,damage=damage}
    local driver=getVehicleOccupant(car,0)
    TrafficAmbient.suspend(ped)
    PedVehicleEvasion.cancel(ped)
    local tx,ty,tz=pedestrianVelocity(ped,car,damage,vx,vy,vz)
    if damage>=baseline then
        killPed(ped,driver or nil,damage==1000 and 50 or 49)
        setElementVelocity(ped,tx,ty,tz)
        return
    end
    setPedAnimation(ped,"PED","FALL_front",-1,false,false,false,true)
    setElementVelocity(ped,tx,ty,tz)
    walk.roadFall={attacker=driver,started=now,downTime=1000}
    -- Let native damage arrive first. Apply only the outstanding loss; never
    -- restore HP lost to another source in the intervening frame.
    local receipt=walk.carContact
    setTimer(function()
        if walk.carContact==receipt and isElement(ped) and not isPedDead(ped)
            and not PedAI.isScriptControlled(ped) then
            local remaining=baseline-damage
            if getElementHealth(ped)>remaining then setElementHealth(ped,remaining) end
        end
    end,120,1)
end
