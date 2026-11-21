FerrisCinema={}
local active,blockedSeat,session,last,original,subject
local elapsed,shot,reason,fallback=0,0,"idle",false
local plan,nextPlan
local currentMotion,probeContext,cameraCars
local suspended=false
local arrivalAt
local greetingCycle=-1
local cameraHub,cameraCar,playerHead,viewFov,neighborTarget
local seatedFocus
local previousCar
local motionBlocked=false
function FerrisCinema.setPlayerFocus(x,y,z)
    local px,py,pz=getElementPosition(localPlayer)
    seatedFocus={x-px,y-py,z-pz}
end
local wheel={Ferris.x,Ferris.y,Ferris.z}
local function running(name)
    local r=getResourceFromName(name)
    return r and getResourceState(r)=="running"
end
local radioMode
local function radio(mode)
    if mode~=radioMode and running("radio") then
        exports.radio:setCinematicRadio(mode)
        radioMode=mode
    end
end
local function presentation(enabled)
    if running("frontend") then exports.frontend:setCinematicPresentation(enabled) end
end
local function distance(a,b)
    return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2+(a[3]-b[3])^2)
end
local function blend(a,b,t)
    return {a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t}
end
local function ownsCamera()
    if not last then return true end
    if getCameraTarget() then return false end
    local x,y,z,tx,ty,tz=getCameraMatrix()
    local a,b={tx-x,ty-y,tz-z},{last.target[1]-x,last.target[2]-y,last.target[3]-z}
    local al,bl=distance(a,{0,0,0}),distance(b,{0,0,0})
    if al<.001 or bl<.001 then return false end
    return distance({x,y,z},last.position)<.12 and (a[1]*b[1]+a[2]*b[2]+a[3]*b[3])/(al*bl)>.999
end
function FerrisCinema.stop(why,external)
    if not active then return end
    blockedSeat=session
    active=false reason=why or "released"
    presentation(false)
    radio("off")
    if original then
        toggleControl("change_camera",original.control)
        if not external and ownsCamera() then
            if isElement(original.target) then setCameraTarget(original.target)
            elseif original.target==localPlayer then setCameraTarget(localPlayer)
            else setCameraMatrix(unpack(original.matrix)) end
            setCameraFieldOfView("player",original.fov)
        end
    end
    last,original,subject,plan,nextPlan,suspended,previousCar=nil,nil,nil,nil,nil,false,nil
end
local function start(key)
    original={target=getCameraTarget(),matrix={getCameraMatrix()},fov=getCameraFieldOfView("player"),
        control=isControlEnabled("change_camera")}
    active,session,elapsed,shot,reason=true,key,0,0,"playing"
    plan,nextPlan,last,suspended,arrivalAt,greetingCycle=nil,nil,nil,false,nil,-1
    previousCar=nil
    toggleControl("change_camera",false)
    presentation(true)
end
local function meshHit(element,a,b)
    if probeContext and probeContext.motion and currentMotion then
        local forecast=probeContext.motion
        local function intoCurrent(p)
            local cx,cy,cz=getElementPosition(element)
            local nx,ny,nz=cx,cy,cz
            local angle
            if element==cameraHub then
                cx,cy,cz=wheel[1],wheel[2],wheel[3]
                nx,ny,nz=cx,cy,cz
                angle=forecast.angle-currentMotion.angle
            else
                local index
                for i,car in pairs(cameraCars or {}) do if car==element then index=i break end end
                if index==nil then return p end
                nx,ny,nz=Ferris.position(forecast,index)
                angle=forecast.swing-currentMotion.swing
            end
            local y,z=p[2]-ny,p[3]-nz
            return {cx+p[1]-nx,cy+y*math.cos(angle)-z*math.sin(angle),cz+z*math.cos(angle)+y*math.sin(angle)}
        end
        a,b=intoCurrent(a),intoCurrent(b)
    end
    return processLineAgainstMesh(element,a[1],a[2],a[3],b[1],b[2],b[3])
end
local function clearLine(a,b,ignored)
    local hit,_,_,_,element=processLineOfSight(a[1],a[2],a[3],b[1],b[2],b[3],true,true,false,true,true,false,false,false,cameraCar or ignored)
    if hit then
        local id=isElement(element) and getElementID(element) or ""
        local wheelObject=isElement(element) and (element==cameraHub or id:find("funfield:carriage:",1,true)==1)
        if not wheelObject or meshHit(element,a,b) then return false end
    end
    for _,element in ipairs({cameraHub or false,cameraCar or false,
        probeContext and cameraCars and cameraCars[probeContext.pedIndex] or false}) do
        if isElement(element) and meshHit(element,a,b) then return false end
    end
    return true
end
local function playerInFrame(p,target,focus)
    focus=focus or playerHead
    local dx,dy,dz=target[1]-p[1],target[2]-p[2],target[3]-p[3]
    local length=math.sqrt(dx*dx+dy*dy+dz*dz)
    dx,dy,dz=dx/length,dy/length,dz/length
    local horizontal=math.max(.001,math.sqrt(dx*dx+dy*dy))
    local rx,ry=-dy/horizontal,dx/horizontal
    local ux,uy,uz=-dz*ry,dz*rx,dx*ry-dy*rx
    local x,y,z=focus[1]-p[1],focus[2]-p[2],focus[3]-p[3]
    local forward=x*dx+y*dy+z*dz
    local width,height=guiGetScreenSize()
    local tangent=math.tan(math.rad(viewFov/2))
    return forward>.15 and math.abs(x*rx+y*ry)<forward*tangent*.8
        and math.abs(x*ux+y*uy+z*uz)<forward*tangent/math.max(2.2,width/height)*.8
end
local function validPosition(p,target,subjectType)
    if distance(p,wheel)>80 then return false end
    local radius=subjectType=="cabin" and .08 or .4
    for _,d in ipairs({{radius,0,0},{-radius,0,0},{0,radius,0},{0,-radius,0},{0,0,radius},{0,0,-radius}}) do
        if not clearLine(p,{p[1]+d[1],p[2]+d[2],p[3]+d[3]},localPlayer) then return false end
    end
    if subjectType=="player" then
        if not playerInFrame(p,target) or not playerInFrame(p,target,{playerHead[1],playerHead[2],playerHead[3]-.35})
            or not clearLine(p,playerHead,localPlayer) then return false end
        for _,offset in ipairs({{.12,0,0},{-.12,0,0},{0,.12,0},{0,-.12,0},{0,0,.15}}) do
            if not clearLine(p,{playerHead[1]+offset[1],playerHead[2]+offset[2],playerHead[3]+offset[3]},localPlayer) then return false end
        end
        return not neighborTarget or playerInFrame(p,target,neighborTarget) and clearLine(p,neighborTarget,localPlayer)
    end
    return true
end
local function choosePed(seat,records,context)
    local best,bestScore=nil,math.huge
    for _,r in ipairs(records or {}) do
        local apart=math.abs(r.index-seat.index)
        apart=math.min(apart,12-apart)
        if apart>0 and isElement(r.ped) and not isPedDead(r.ped) then
            local head={getPedBonePosition(r.ped,8)}
            context.ped=head
            local candidate=FerrisCinemaPath.evaluate(FerrisCinemaPath.timeFor("neighboring-riders"),context)
            local horizontal=math.max(1,math.sqrt((head[1]-context.aim[1])^2+(head[2]-context.aim[2])^2))
            local score=distance(context.aim,head)+math.abs(head[3]-context.aim[3])/horizontal*60
            if not clearLine(candidate.position,head,localPlayer) or not clearLine(candidate.position,playerHead,localPlayer) then score=score+1000 end
            if score<bestScore then best,bestScore=r.ped,score end
        end
    end
    return best
end
local function validatePath(frame,context,previous,includeNeighbor)
    local savedProbe,savedHead,savedFov,savedNeighbor=probeContext,playerHead,viewFov,neighborTarget
    probeContext=context
    playerHead={context.aim[1],context.aim[2],context.aim[3]+.06}
    viewFov=frame.fov
    local neighborEmphasis=frame.name=="neighboring-riders" and frame.progress>=.2 and frame.progress<=.7
        or frame.name=="greeting" and frame.greeting=="reply"
    neighborTarget=includeNeighbor and neighborEmphasis and context.ped or nil
    local valid=validPosition(frame.position,frame.target,frame.subject)
        and (frame.greeting~="player" or playerInFrame(frame.position,frame.target,
            {playerHead[1],playerHead[2],playerHead[3]+.95}))
        and (not previous or clearLine(previous.position,frame.position,localPlayer))
    local glow=valid and frame.glow and frame.progress>=.74 and playerInFrame(frame.position,frame.target,frame.glow)
        and clearLine(frame.position,frame.glow,localPlayer)
    probeContext,playerHead,viewFov,neighborTarget=savedProbe,savedHead,savedFov,savedNeighbor
    return valid,glow
end
local function setNeighborContext(context,ped,records)
    context.ped=nil context.pedIndex=nil context.pedElement=nil
    if isElement(ped) and not isPedDead(ped) then
        context.ped={getPedBonePosition(ped,8)}
        context.pedElement=ped
        for _,r in ipairs(records or {}) do if r.ped==ped then context.pedIndex=r.index break end end
    end
end
local function neighborCandidates(context,seat,records)
    local ranked={}
    for _,r in ipairs(records or {}) do
        if r.index~=seat.index and isElement(r.ped) and not isPedDead(r.ped) then
            local head={getPedBonePosition(r.ped,8)}
            local horizontal=math.max(1,math.sqrt((head[1]-context.aim[1])^2+(head[2]-context.aim[2])^2))
            ranked[#ranked+1]={ped=r.ped,score=distance(context.aim,head)+math.abs(head[3]-context.aim[3])/horizontal*60}
        end
    end
    table.sort(ranked,function(a,b) return a.score<b.score end)
    context.candidates={}
    for i=1,math.min(8,#ranked) do
        local candidate={}
        for k,value in pairs(context) do if k~="candidates" then candidate[k]=value end end
        setNeighborContext(candidate,ranked[i].ped,records)
        context.candidates[#context.candidates+1]=candidate
    end
    if #context.candidates==0 then context.candidates=nil end
end
local function beginPlan(start,duration,context,arrival,ped,lead)
    if not arrival and start==FerrisCinemaPath.timeFor("skyline-light") and running("skygfx") then
        local a={exports.skygfx:getVcsRenderedSun(lead or 0)}
        local b={exports.skygfx:getVcsRenderedSun((lead or 0)+duration)}
        if a[4] and b[4] and math.max(a[3],b[3])<=math.sin(math.rad(25)) then
            context.sunVariants={}
            for _,radius in ipairs({3,1.6,.85}) do
                for _,direction in ipairs({1,-1}) do
                    table.insert(context.sunVariants,{style="sun",startSun=a,endSun=b,radius=radius,direction=direction})
                end
            end
        end
    end
    local job=FerrisCinemaPlanner.begin(start,duration,context,arrival,validatePath)
    job.ped=ped
    job.name=arrival and "exit-platform" or FerrisCinemaPath.evaluate(start,context).name
    return job
end
function FerrisCinema.update(seat,car,exitReady,phase,delta,records,cars,hub,motion)
    local key=seat and tostring(seat.index)..":"..seat.seat
    if not key then
        FerrisCinema.stop("unseated")
        blockedSeat,session=nil,nil
        return
    end
    if not running("frontend") or not isElement(car) then FerrisCinema.stop("dependency") return end
    if active and session~=key then FerrisCinema.stop("seat changed") blockedSeat=nil end
    if not active then if blockedSeat==key then return end start(key) end
    if isMainMenuActive() or isPlayerMapVisible() or isConsoleActive() then radio("paused") return end
    if suspended then
        if getCameraTarget()~=localPlayer then return end
        suspended=false last=nil presentation(true) reason="playing"
    elseif not ownsCamera() then
        suspended=true radio("paused") presentation(false) reason="external camera"
        return
    end
    radio("playing")
    elapsed=elapsed+math.min(delta/1000,.1)
    local cx,cy,cz=getElementPosition(car)
    cameraHub,cameraCar,cameraCars,currentMotion=hub,car,cars,motion
    -- Attachment origin is above the seated pelvis. This aim stays stable even
    -- before GTA has processed the final custom skeleton for this frame.
    local px,py,pz=getElementPosition(localPlayer)
    local focus=seatedFocus or {0,0,.27}
    local hx,hy,hz=px+focus[1],py+focus[2],pz+focus[3]
    playerHead={hx,hy,hz}
    local context={wheel=wheel,car={cx,cy,cz},aim={hx,hy,hz-.06},side=seat.seat<=2 and 1 or -1,motion=motion,index=seat.index}
    local nextCar=cars and cars[(seat.index+1)%12]
    if isElement(nextCar) then
        local nx,ny,nz=getElementPosition(nextCar)
        context.neighbor={nx,ny,nz-1.3}
    end
    setNeighborContext(context,subject,records)
    local frame=FerrisCinemaPath.evaluate(elapsed,context)
    if exitReady and phase=="stopped" then
        arrivalAt=arrivalAt or elapsed
        local sinceArrival=(elapsed-arrivalAt)%24
        if sinceArrival<8 then frame=FerrisCinemaPath.arrival(sinceArrival,context) end
    else arrivalAt=nil end
    local cut=not last or frame.name~=last.name
    if cut then
        shot=frame.shot
        if nextPlan and nextPlan.name==frame.name then
            plan=nextPlan nextPlan=nil subject=plan.ped
        else
            nextPlan=nil
            if frame.name=="neighboring-riders" then subject=choosePed(seat,records,context)
            elseif frame.name~="greeting" then subject=nil end
            setNeighborContext(context,subject,records)
            if frame.name=="neighboring-riders" then neighborCandidates(context,seat,records) end
            local start=frame.name=="exit-platform" and 0 or FerrisCinemaPath.timeFor(frame.name)
            plan=beginPlan(start,frame.name=="exit-platform" and 8 or FerrisCinemaPath.durations[shot],context,frame.name=="exit-platform",subject)
        end
        while not plan.done do FerrisCinemaPlanner.resume(plan,128) end
        subject=plan.ped
        setNeighborContext(context,subject,records)
        if frame.name~="exit-platform" then frame=FerrisCinemaPath.evaluate(elapsed,context) end
    end
    local cycle=math.floor(elapsed/FerrisCinemaPath.length)
    if frame.name=="greeting" and greetingCycle~=cycle then
        greetingCycle=cycle
        triggerServerEvent("funfield:greeting",resourceRoot,isElement(subject) and subject or false)
    end
    -- Lock the certified full-shot path until the next editorial cut.
    -- No per-frame alternative search or angle replacement occurs here.
    frame=FerrisCinemaPath.planned(frame,context,plan.variant)
    fallback=plan.variant.style=="sheltered" or plan.variant.style=="two"
        or (plan.variant.angle or 0)~=0 or (plan.variant.rise or 0)~=0
    viewFov=frame.fov
    neighborTarget=nil
    -- Prepare the following shot before its cut, spreading mesh probes across
    -- frames. Forecasts include running, acceleration, braking and swing.
    if frame.shot>0 and not (exitReady and phase=="stopped") then
        local duration=FerrisCinemaPath.durations[frame.shot]
        local remaining=duration*(1-frame.progress)
        if remaining<=2 and not nextPlan then
            local index=frame.shot%#FerrisCinemaPath.names+1
            local name=FerrisCinemaPath.names[index]
            local ped=name=="greeting" and subject or nil
            if name=="neighboring-riders" then ped=choosePed(seat,records,context) end
            local forecast={}
            for k,value in pairs(context) do forecast[k]=value end
            setNeighborContext(forecast,ped,records)
            if name=="neighboring-riders" then neighborCandidates(forecast,seat,records) end
            forecast=FerrisCinemaPath.predict(forecast,remaining)
            nextPlan=beginPlan(FerrisCinemaPath.timeFor(name),FerrisCinemaPath.durations[index],forecast,false,ped,remaining)
        end
    end
    if nextPlan and not nextPlan.done then FerrisCinemaPlanner.resume(nextPlan,24) end
    -- Keep editorial cuts between shots. Within a shot, ease obstruction
    -- recovery instead of snapping the lens to a newly selected alternative.
    local dt=math.min(delta/1000,.1)
    local from=not cut and last or nil
    motionBlocked=false
    if from then
        local position={unpack(from.position)}
        -- Carry an established cabin-relative view with the cabin; the authored
        -- easing then changes its local composition without trailing the rider.
        if previousCar and from.name~="vice-point-reveal" and frame.name~="vice-point-reveal" then
            for i=1,3 do position[i]=position[i]+context.car[i]-previousCar[i] end
        end
        local alpha=1-math.exp(-dt*2.5)
        local function stepToward(to)
            local step=blend(position,to,alpha)
            local length=distance(position,step)
            if length>3.5*dt then step=blend(position,step,3.5*dt/length) end
            return step
        end
        local nextPosition=stepToward(frame.position)
        local function safeMove(to)
            return clearLine(position,to,localPlayer)
        end
        if not safeMove(nextPosition) then
            motionBlocked=true
            nextPosition=position
        end
        local function angles(p,target)
            local x,y,z=target[1]-p[1],target[2]-p[2],target[3]-p[3]
            return math.atan2(y,x),math.atan2(z,math.max(.001,math.sqrt(x*x+y*y)))
        end
        local yaw,pitch=angles(from.position,from.target)
        local wantedYaw,wantedPitch=angles(nextPosition,frame.target)
        local function turn(a,b,rate)
            local difference=math.atan2(math.sin(b-a),math.cos(b-a))
            local step=difference*(1-math.exp(-dt*3.5))
            local limit=math.rad(rate)*dt
            return a+math.max(-limit,math.min(limit,step))
        end
        yaw,pitch=turn(yaw,wantedYaw,42),turn(pitch,wantedPitch,28)
        frame.position=nextPosition
        frame.target={nextPosition[1]+math.cos(yaw)*math.cos(pitch)*10,
            nextPosition[2]+math.sin(yaw)*math.cos(pitch)*10,nextPosition[3]+math.sin(pitch)*10}
        local fovStep=(frame.fov-from.fov)*(1-math.exp(-dt*3.5))
        frame.fov=from.fov+math.max(-8*dt,math.min(8*dt,fovStep))
    end
    previousCar=context.car
    setCameraMatrix(frame.position[1],frame.position[2],frame.position[3],
        frame.target[1],frame.target[2],frame.target[3],0,frame.fov)
    last=frame
end
function FerrisCinema.state()
    return {active=active or false,shot=last and last.name or FerrisCinemaPath.names[shot],elapsed=elapsed,
        fov=last and last.fov or false,subject=last and last.subject or false,
        progress=last and last.progress or 0,motionBlocked=motionBlocked,
        fallback=fallback,alternate=plan and (plan.variant.angle or plan.variant.style) or false,
        planned=plan and plan.validated or false,emergency=plan and plan.variant.style=="sheltered" or false,reason=reason,suspended=suspended,neighbor=isElement(subject) and subject or false,
        greeting=last and last.greeting or false}
end
addEventHandler("onClientResourceStop",root,function(resource)
    local name=getResourceName(resource)
    if name=="radio" then radioMode=nil end
    if resource==getThisResource() or name=="frontend" or name=="vcs" then FerrisCinema.stop("resource stopped") end
end)
