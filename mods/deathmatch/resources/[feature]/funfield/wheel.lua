-- US PS2 00175620 / 001763E0. Angles grow in the original wheel direction.
Ferris = {x=342.189087,y=-243.189011,z=36.895248,radius=23,count=12,
    entrance={337.69,-243.22,12.06}, exit={336.3,-243.22,12.06},
    step=1/30, spacing=math.pi/6, tau=math.pi*2, grace=5000}
-- MAIN.SCM GLOBMON_633..803. These are attachment origins, not ground
-- coordinates: 00213FB8 applies them directly, without a +1 m adjustment.
Ferris.seats={{-0.3,-0.72,-2.1,0},{0.3,-0.72,-2.1,0},
    {-0.3,0.76,-2.1,180},{0.3,0.76,-2.1,180}}

function Ferris.new()
    return {angle=0,speed=0,phase="starting",swing=0,swingSpeed=0,time=0}
end

function Ferris.nextStop(s,index)
    local base = index and (math.pi-index*Ferris.spacing) or 0
    local period = index and Ferris.tau or Ferris.spacing
    return base + math.ceil((s.angle + 0.14-base)/period)*period
end

function Ferris.stop(s,target)
    if s.phase=="stopped" or s.phase=="stopping" then return false end
    s.target=target or Ferris.nextStop(s)
    s.phase="stopping"
    return true
end

function Ferris.advance(s,dt)
    local push=0
    if s.phase=="starting" then
        s.speed=math.min(0.05,s.speed+dt*0.01)
        push=0.001
        if s.speed==0.05 then s.phase="running" end
    elseif s.phase=="running" then s.speed=0.05
    elseif s.phase=="stopping" then
        local remaining=s.target-s.angle
        if remaining<0.1308997 then
            s.speed=math.min(s.speed,math.max(0,math.sin(remaining*7.639437)*0.05))
            push=0.001
        else s.speed=math.min(0.05,s.speed+dt*0.01) end
        if s.speed<=0.003 and remaining<0.1308997 or remaining<=s.speed*dt then
            s.angle,s.speed,s.phase=s.target,0,"stopped"
            s.stoppedAt=s.time
        end
    else s.speed=0 end
    s.angle=s.angle+s.speed*dt
    s.swingSpeed=(s.swingSpeed+push-s.swing*0.1)*0.95
    s.swing=s.swing+s.swingSpeed*dt*50
    if math.abs(s.swing)<1e-8 and math.abs(s.swingSpeed)<1e-8 then s.swing,s.swingSpeed=0,0 end
    s.time=s.time+dt*1000
end

function Ferris.position(s,index)
    local angle=s.angle+index*Ferris.spacing
    return Ferris.x,Ferris.y+math.sin(angle)*Ferris.radius,Ferris.z+math.cos(angle)*Ferris.radius
end

function Ferris.seatMatrix(s,index,seatIndex)
    local x,y,z=Ferris.position(s,index)
    local seat=Ferris.seats[seatIndex]
    local c,t=math.cos(s.swing),math.sin(s.swing)
    local direction=seat[4]==0 and 1 or -1
    return {{-direction,0,0,0},{0,-c*direction,t*direction,0},{0,t,c,0},
        {x-seat[1],y-c*seat[2]+t*seat[3],z+t*seat[2]+c*seat[3],1}}
end

function Ferris.rider(s,x,y,z)
    if math.abs(x-Ferris.x)>2.1 then return nil end
    for i=0,11 do
        local _,cy,cz=Ferris.position(s,i)
        -- Ped origins stand roughly 1.1 m below the hanging pivot.
        if math.abs(y-cy)<1.9 and z>cz-3.5 and z<cz+2 then return i end
    end
end

function Ferris.atEntrance(x,y,z)
    return ((math.abs(x-337.69)<1.1 and math.abs(z-12.06)<1.8)
        or (math.abs(x-339.17)<1.1 and math.abs(z-12.29)<1.8)) and math.abs(y+243.22)<1.1
end
