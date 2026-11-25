-- DRIVERA, USA PS2 mission 18. All distances are in map units (metres).
DrivingRange = {entry={76.6337,592,13.75}, tee={73.92,590.4,13.53}}
local range=DrivingRange
local yaw=math.rad(20)
range.ball={range.tee[1]-math.sin(yaw),range.tee[2]+math.cos(yaw),13.53}
range.buoy={range.ball[1]-130*math.cos(yaw),range.ball[2]-130*math.sin(yaw),2}

function range.power(position)
    if position>=73 and position<=84 then return 100 end
    return position<73 and 17+position or 174-position
end

function range.angle(position)
    if position<17 then return 10*(17-position)/17 end
    if position>28 then return -10*(position-28)/72 end
    return 0
end

-- Integrate the two SCM timing ramps independently of the client's frame rate.
function range.meter(phase,ms,power)
    if phase=="aim" then return math.max(0,100-ms*0.15/125*power) end
    local ramp=math.min(1300,math.max(0,ms-250))
    return math.min(100,0.02*ms+0.00005*ramp*ramp+0.13*math.max(0,ms-1550))
end

-- Opcode 0224 (0030F930) converts SCM speeds to 50 Hz physics units.
-- A fixed step lets both observers replay the same shot without syncing an object.
function range.flight(power,angle)
    local speed=power-0.75*math.abs(angle)
    local bearing=math.rad(20+angle)
    local dx,dy=-math.cos(bearing),-math.sin(bearing)
    local x,y,z=unpack(range.ball)
    local horizontal,vertical=speed*0.02,speed*0.004
    local points={{x,y,z}}
    local buoy=false
    repeat
        horizontal=horizontal*0.99
        vertical=(vertical-0.008)*0.99
        x,y,z=x+dx*horizontal,y+dy*horizontal,z+vertical
        if not buoy and (x-range.buoy[1])^2+(y-range.buoy[2])^2<=1.5^2 and z<=8 then
            buoy=#points+1
            horizontal=-0.2*horizontal
        end
        points[#points+1]={x,y,z}
    until z<=6
    return points,math.sqrt((x-range.ball[1])^2+(y-range.ball[2])^2),buoy
end
