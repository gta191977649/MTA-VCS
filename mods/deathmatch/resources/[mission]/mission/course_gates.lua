-- SCM location tests run every frame. Sweep consecutive server samples so a fast
-- aircraft or bike can pass a narrow gate between two mission ticks.
CourseGates = {}
function CourseGates.crossed(run, now, point, width, height, zOffset)
    local last = run.gateSample
    if not last or last.now ~= now or last.vehicle ~= run.vehicle then
        local x,y,z = getElementPosition(run.vehicle)
        local sample = {x=x,y=y,z=z,vehicle=run.vehicle,now=now}
        if last and last.vehicle==run.vehicle and now>=last.now and now-last.now<=400 then
            local dx,dy,dz = x-last.x,y-last.y,z-last.z
            if dx*dx+dy*dy+dz*dz <= 64*64 then
                sample.fromX,sample.fromY,sample.fromZ = last.x,last.y,last.z
            end
        end
        run.gateSample = sample
        last = sample
    end
    local gx,gy,gz = point[1],point[2],point[3]+(zOffset or 0)
    height = height or width
    if math.abs(last.x-gx)<=width and math.abs(last.y-gy)<=width and math.abs(last.z-gz)<=height then return true end
    if not last.fromX then return false end
    local enter,leave = 0,1
    local function slab(old,current,center,radius)
        local delta = current-old
        if delta==0 then return math.abs(old-center)<=radius end
        local a,b=(center-radius-old)/delta,(center+radius-old)/delta
        enter,leave=math.max(enter,math.min(a,b)),math.min(leave,math.max(a,b))
        return enter<=leave
    end
    return slab(last.fromX,last.x,gx,width) and slab(last.fromY,last.y,gy,width)
        and slab(last.fromZ,last.z,gz,height)
end
