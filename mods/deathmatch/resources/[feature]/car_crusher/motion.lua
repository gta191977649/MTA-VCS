-- Native rates are per 20 ms GTA time step; the network timeline uses milliseconds.
local pivot = Crusher.parts.doc_crane_cab
local function coordinates(x, y, z, yaw)
    return {angle=math.atan2(y-pivot[2],x-pivot[1]), radius=getDistanceBetweenPoints2D(x,y,pivot[1],pivot[2]),
        height=z, yaw=yaw}
end

local function travel(from, to, speed, elapsed)
    return from + math.max(-speed*elapsed, math.min(to-from, speed*elapsed))
end

function craneMovement(x,y,z,heading, tx,ty,tz, align,speed,now)
    local a = coordinates(x,y,z,heading)
    local b = coordinates(tx,ty,tz,heading)
    b.angle = a.angle + (b.angle-a.angle+math.pi)%(2*math.pi)-math.pi
    if align then b.yaw = a.yaw + (90+Crusher.rotation-a.yaw+90)%180-90 end
    local angular, radial, vertical, turn = 0.004/20*speed, 0.1/20*speed, 0.06/20*speed, math.deg(0.0035)/20
    local duration = math.ceil(math.max(math.abs(b.angle-a.angle)/angular, math.abs(b.radius-a.radius)/radial,
        math.abs(b.height-a.height)/vertical, math.abs(b.yaw-a.yaw)/turn))
    return {from=a,to=b,speed=speed,start=now,duration=duration}
end

function cranePose(motion, now)
    local t = math.max(0,math.min(now-motion.start,motion.duration))
    local a,b,s = motion.from,motion.to,motion.speed
    local angle = travel(a.angle,b.angle,0.004/20*s,t)
    local radius = travel(a.radius,b.radius,0.1/20*s,t)
    local z = travel(a.height,b.height,0.06/20*s,t)
    local yaw = travel(a.yaw,b.yaw,math.deg(0.0035)/20,t)
    return pivot[1]+math.cos(angle)*radius,pivot[2]+math.sin(angle)*radius,z,yaw,math.deg(angle)
end

function crusherLidPose(motion,now)
    local t = math.max(0,math.min(now-motion.start,motion.duration))
    local fraction = motion.duration > 0 and t/motion.duration or 1
    local dx,dy = 0,0
    if motion.shake and t < motion.duration then
        dx,dy = 0.022*math.sin(t*0.081),0.022*math.sin(t*0.103)
    end
    return motion.from+(motion.to-motion.from)*fraction,dx,dy
end
