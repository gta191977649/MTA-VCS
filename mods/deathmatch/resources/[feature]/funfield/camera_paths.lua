-- World-space editorial paths. Seconds, metres and degrees; no frame dependence.
FerrisCinemaPath={durations={7,9,8,8,8,8,7,8,8,9},names={
    "seated-introduction","vice-point-reveal","city-lookout","neighboring-riders","greeting",
    "skyline-light","height","waterfront","wheel-scale","quiet-farewell"},length=80}
local function add(a,x,y,z) return {a[1]+x,a[2]+y,a[3]+z} end
local function mix(a,b,t) return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t} end
local function ease(t) return t*t*(3-2*t) end
local function lerp(a,b,t) return a+(b-a)*t end
local function orbit(aim,radius,angle,rise,side)
    angle=math.rad(angle)
    return add(aim,math.cos(angle)*radius,math.sin(angle)*radius*side,rise)
end
-- Compose subjects by their viewing directions rather than their world distance.
-- A distant skyline must not pull the nearby player outside the letterbox.
local function compose(p,head,other,weight)
    local a,b={},{}
    local al,bl=0,0
    for i=1,3 do a[i]=head[i]-p[i] b[i]=other[i]-p[i] al=al+a[i]^2 bl=bl+b[i]^2 end
    al,bl=math.max(.001,math.sqrt(al)),math.max(.001,math.sqrt(bl))
    return {p[1]+((1-weight)*a[1]/al+weight*b[1]/bl)*10,
        p[2]+((1-weight)*a[2]/al+weight*b[2]/bl)*10,
        p[3]+((1-weight)*a[3]/al+weight*b[3]/bl)*10}
end
function FerrisCinemaPath.timeFor(name)
    local start=0
    for i,n in ipairs(FerrisCinemaPath.names) do
        if n==name then return start end
        start=start+FerrisCinemaPath.durations[i]
    end
end
function FerrisCinemaPath.evaluate(seconds,c)
    local t=seconds%FerrisCinemaPath.length
    local shot=1
    while t>=FerrisCinemaPath.durations[shot] do t=t-FerrisCinemaPath.durations[shot] shot=shot+1 end
    local progress=t/FerrisCinemaPath.durations[shot]
    local u,v=ease(progress),ease(math.min(1,progress*1.15))
    local w,car,aim,side=c.wheel,c.car,c.aim,c.side
    local openSide=aim[1]>=car[1] and 1 or -1
    local position,target,f0,f1,greeting,other,weight
    target=add(aim,0,0,lerp(-.09,.03,v))
    if shot==1 then
        position=mix({car[1]+.65,car[2]-side*.6,aim[3]+.05},{car[1]+.25,car[2]-side*.45,aim[3]+.3},u)
        target=add(aim,0,0,lerp(-.2,-.12,v))
        f0,f1=64,56
    elseif shot==2 then
        position=mix(add(w,-70,-27,3),add(w,-63,-36,8),u)
        target=mix(add(w,0,3,0),add(w,0,-3,-2),v)
        f0,f1=74,68
    elseif shot==3 then
        position={car[1]+openSide*lerp(3.8,4.8,u),car[2]+side*lerp(-.3,.2,u),aim[3]+lerp(.45,.05,u)}
        other,weight=add(car,-openSide*70,-65,-2),lerp(.14,.2,v)
        f0,f1=62,54
    elseif shot==4 then
        other=c.ped or c.neighbor or add(car,0,12,-1.4)
        local dx,dy=other[1]-aim[1],other[2]-aim[2]
        local length=math.max(.01,math.sqrt(dx*dx+dy*dy))
        dx,dy=dx/length,dy/length
        local back,offset=lerp(3.7,3.2,u),lerp(2.1,1.45,u)
        position=add(aim,-dx*back-dy*offset,-dy*back+dx*offset,lerp(.05,.55,u))
        target=add(aim,0,0,-.18)
        weight=.45
        f0,f1=66,58
    elseif shot==5 then
        position=orbit(aim,lerp(4.1,3.7,u),lerp(188,170,u),lerp(.2,-.15,u),side)
        greeting=t<1 and "anticipation" or t<2.3 and "player" or t<4.3 and "reply" or "settling"
        if c.ped then
            other=c.ped
            local dx,dy=other[1]-aim[1],other[2]-aim[2]
            local length=math.max(.01,math.sqrt(dx*dx+dy*dy)); dx,dy=dx/length,dy/length
            local back,offset=lerp(5.5,4.8,u),lerp(-2.3,-3.2,u)
            position=add(aim,-dx*back-dy*offset,-dy*back+dx*offset,lerp(.2,-.15,u))
            target=add(aim,0,0,-.15)
            weight=lerp(.15,.4,ease(math.max(0,math.min(1,(t-2)/2.3))))
        end
        f0,f1=60,54
    elseif shot==6 then
        position={car[1]+openSide*lerp(4.1,4.8,u),car[2]+side*lerp(.25,-.3,u),aim[3]+lerp(-.05,.65,u)}
        other=add(car,-openSide*120,70,3)
        weight=.18
        f0,f1=58,64
    elseif shot==7 then
        position={car[1]+openSide*lerp(5.2,5.8,u),car[2]+side*lerp(-.35,.25,u),aim[3]+lerp(1.3,.65,u)}
        target=add(aim,0,0,lerp(-.35,-.1,v))
        f0,f1=60,70
    elseif shot==8 then
        position={car[1]+openSide*lerp(4.8,4.3,u),car[2]+side*lerp(.5,-.3,u),aim[3]+lerp(.35,.05,u)}
        other,weight=add(car,-openSide*50,90,-8),.12
        f0,f1=56,50
    elseif shot==9 then
        position={car[1]+openSide*lerp(5,4.5,u),car[2]+side*lerp(.25,-.2,u),aim[3]+lerp(-.25,.15,u)}
        target=add(aim,0,0,lerp(.18,.02,v))
        f0,f1=68,60
    else
        position={car[1]+openSide*lerp(2.4,5.5,u),car[2]+side*lerp(-.2,.3,u),aim[3]+lerp(.05,.65,u)}
        target=add(aim,0,0,lerp(-.02,-.25,v))
        f0,f1=52,62
    end
    if other then target=compose(position,target,other,weight) end
    return {position=position,target=target,fov=lerp(f0,f1,u),shot=shot,
        name=FerrisCinemaPath.names[shot],progress=progress,greeting=greeting,
        subject=shot==2 and "wheel" or "player"}
end
-- Theme-preserving alternate: rotate the whole composition about the player.
-- Retain the authored FOV, progression and relative subject placement.
function FerrisCinemaPath.alternate(frame,c,angle,rise)
    local a=math.rad(angle)
    local function rotate(p)
        local x,y=p[1]-c.aim[1],p[2]-c.aim[2]
        return {c.aim[1]+x*math.cos(a)-y*math.sin(a),c.aim[2]+x*math.sin(a)+y*math.cos(a),p[3]+rise}
    end
    local result={}
    for k,value in pairs(frame) do result[k]=value end
    result.position=rotate(frame.position)
    result.target=rotate(frame.target)
    return result
end
function FerrisCinemaPath.arrival(seconds,c)
    local progress=math.min(1,seconds/8)
    local u=ease(progress)
    local position=mix(add(c.car,-8,-c.side*4,-.1),add(c.car,-6.5,-c.side*2.5,.6),u)
    local platform={Ferris.exit[1],Ferris.exit[2],Ferris.exit[3]+.5}
    return {position=position,target=compose(position,c.aim,platform,lerp(.2,.32,u)),fov=52-6*u,
        shot=0,name="exit-platform",subject="player",progress=progress}
end

-- Forecast using the same fixed-step simulation as the production wheel.
function FerrisCinemaPath.predict(c,seconds)
    local result={}
    for k,value in pairs(c) do result[k]=value end
    if not c.motion then return result end
    local state={}
    for k,value in pairs(c.motion) do state[k]=value end
    local remaining=seconds
    while remaining>0 do
        local step=math.min(Ferris.step,remaining)
        Ferris.advance(state,step)
        remaining=remaining-step
    end
    result.motion=state
    if c.candidates then
        result.candidates={}
        for i,candidate in ipairs(c.candidates) do result.candidates[i]=FerrisCinemaPath.predict(candidate,seconds) end
    end
    local function carry(point,index)
        local x,y,z=Ferris.position(c.motion,index)
        local nx,ny,nz=Ferris.position(state,index)
        local delta=state.swing-c.motion.swing
        local dy,dz=point[2]-y,point[3]-z
        return {point[1]+nx-x,ny+dy*math.cos(delta)+dz*math.sin(delta),nz+dz*math.cos(delta)-dy*math.sin(delta)}
    end
    result.car={Ferris.position(state,c.index)}
    result.aim=carry(c.aim,c.index)
    if c.ped and c.pedIndex then result.ped=carry(c.ped,c.pedIndex) end
    if c.neighbor then result.neighbor=carry(c.neighbor,(c.index+1)%12) end
    return result
end
function FerrisCinemaPath.planned(frame,c,variant)
    if variant.style=="sun" then
        local u=ease(frame.progress)
        local a,b=variant.startSun,variant.endSun
        local sun=mix(a,b,frame.progress)
        local azimuth=math.atan2(sun[2],sun[1])+variant.direction*math.rad(lerp(6,24,u))
        local radius=variant.radius
        local p=add(c.aim,-radius*math.cos(azimuth),-radius*math.sin(azimuth),
            -radius*lerp(sun[3]*.65,sun[3]+.04,u))
        local glow=add(p,sun[1]*150,sun[2]*150,sun[3]*150)
        frame.position=p
        frame.target=compose(p,add(c.aim,0,0,-.12),glow,lerp(.24,.48,u))
        frame.glow=glow
        return frame
    end
    if variant.style=="two" and c.ped then
        local a,b=c.aim,c.ped
        local span=math.sqrt((a[2]-b[2])^2+(a[3]-b[3])^2)
        local u=ease(frame.progress)
        local radius=math.max(10,span*1.8)+variant.radius
        local direction=variant.direction
        local p={lerp(a[1],b[1],.5)+direction*radius,
            lerp(a[2],b[2],lerp(.35,.5,u)),math.max(a[3],b[3])+lerp(.8,.15,u)}
        local result={}
        for k,value in pairs(frame) do result[k]=value end
        result.position=p
        result.target=compose(p,add(a,0,0,-.1),b,frame.name=="greeting" and lerp(.3,.48,u) or .48)
        return result
    elseif variant.style=="portrait" then
        local result={}
        for k,value in pairs(frame) do result[k]=value end
        local u=ease(frame.progress)
        result.position={c.car[1]-lerp(3.8,3.4,u),c.car[2]+c.side*lerp(-.2,.15,u),c.aim[3]+lerp(.15,-.1,u)}
        result.target=add(c.aim,0,0,lerp(-.15,-.05,u))
        return FerrisCinemaPath.alternate(result,c,variant.angle,0)
    elseif variant.style=="sheltered" then
        -- Distinct, bounded interior paths for geometry that rules out an
        -- exterior composition. They are chosen once, before the shot begins.
        local u=ease(frame.progress)
        local patterns={{.65,.25,.6,.45,.05,.3},{.4,-.4,.55,.45,.15,.35},
            {-.6,-.25,.45,.6,.3,.05},{-.65,-.45,.5,.2,.2,.05},
            {-.55,-.15,.55,.45,.05,.2},{.55,-.35,.6,.5,.05,.3},
            {-.5,-.15,.45,.6,.65,.35},{-.65,-.25,.45,.55,.2,.05},
            {.6,.25,.5,.6,-.05,.2},{.2,-.55,.4,.6,.05,.35}}
        local p=patterns[math.max(1,frame.shot)]
        local result={}
        for k,value in pairs(frame) do result[k]=value end
        result.position={c.car[1]+lerp(p[1],p[2],u)*variant.direction,
            c.car[2]-c.side*lerp(p[3],p[4],u),c.aim[3]+lerp(p[5],p[6],u)}
        result.target=add(c.aim,frame.shot==4 and variant.direction*.3 or 0,0,lerp(-.18,-.1,u))
        if frame.name=="greeting" then
            result.position={c.car[1]-.7*variant.direction,c.car[2]-c.side*lerp(1,.9,u),c.aim[3]+lerp(.2,.35,u)}
            result.target=add(c.aim,0,0,.36)
            result.fov=lerp(100,90,u)
        end
        result.subject="player"
        return result
    end
    return FerrisCinemaPath.alternate(frame,c,variant.angle,variant.rise)
end
