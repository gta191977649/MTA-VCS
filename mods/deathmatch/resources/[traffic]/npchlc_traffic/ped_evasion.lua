PedEvasion = {key = "npchlc_traffic:vehicleEvasion"}
function PedEvasion.activityBlocks(ped)
    local motion=getElementData(ped,"npchlc_traffic:activityMotion",false)
    return motion and not (type(motion)=="table" and motion[6]=="PED")
end
function PedEvasion.clip(name)
    return VCS_TRAFFIC_EVADE_CLIPS[name]
end

-- Forward speeds are native movement units per 20 ms tick. 0x004342D8
-- compares the gap from the front bumper with v*50 before choosing a move.
function PedEvasion.threat(car, x, y, z, pvx, pvy)
    local dx, dy = x - car.x, y - car.y
    if math.abs(dx) >= 11 or math.abs(dy) >= 11 or math.abs(z-car.z) >= 4 then return end
    local front = dx*car.fx + dy*car.fy
    local side = dx*car.fy - dy*car.fx
    local gap = front - car.front
    local speed = car.vx*car.fx + car.vy*car.fy
    if speed <= 0 or gap <= 0 or gap >= speed*200 or math.abs(side) > car.width+0.5 then return end
    local closing = speed - pvx*car.fx - pvy*car.fy
    if closing <= 0.05 then return end
    local t = gap/(closing*50)
    if t > 4 then return end
    -- Extrapolate measured yaw and sideways drift so a turning/skidding
    -- automobile that will miss the pedestrian doesn't interrupt their walk.
    local yaw = car.yawRate*t
    local arcSide, advance = 0, speed*50*t
    if math.abs(car.yawRate) > 0.01 then
        arcSide = speed*50*(math.cos(yaw)-1)/car.yawRate
        advance = speed*50*math.sin(yaw)/car.yawRate
    end
    local drift = car.vx*car.fy - car.vy*car.fx
    local predictedSide = side + ((pvx*car.fy-pvy*car.fx)-drift)*50*t - arcSide
    local predictedFront = front + (pvx*car.fx+pvy*car.fy)*50*t - advance
    local lateral = predictedSide*math.cos(yaw) + predictedFront*math.sin(yaw)
    local vehicleZ = car.z + car.vz*50*t
    if math.abs(lateral) > car.width+0.5 or z < vehicleZ+car.bottom-0.2 or z-0.65 > vehicleZ+car.top+0.2 then return end
    if gap >= speed*50 then return "approach", lateral, t end
    if speed <= 0.1 or t > 1 then return end
    local surface = math.abs(side)
    local step = speed > 0.3 and surface > car.width+0.1 or speed <= 0.3 and surface > car.width-0.5
    return step and "ev_step" or "ev_dive", lateral, t
end

function PedEvasion.duration(kind)
    local clips = VCS_TRAFFIC_EVADE_CLIPS
    return PedEvasion.clip(kind).duration + (kind == "ev_dive" and clips.getup_front.duration or 0)
end

function PedEvasion.pose(kind, ms)
    if kind == "ev_dive" then
        local recovery = ms - PedEvasion.clip(kind).duration
        if recovery >= 0 then return "getup_front", recovery end
    end
    return kind, ms
end
