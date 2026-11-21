"""Ferris cinematic path/ownership regression and isolated real-client fixture."""
import argparse
from pathlib import Path
import check_vcs_funfield as base
from lupa.lua51 import LuaRuntime


def check_camera():
    forecast=LuaRuntime(unpack_returned_tuples=True)
    forecast.execute((base.RESOURCE/'wheel.lua').read_text())
    forecast.execute((base.RESOURCE/'camera_paths.lua').read_text())
    forecast.execute('''
        for _,phase in ipairs({"starting","running","stopping","stopped"}) do
            local state=Ferris.new(); state.angle=1; state.speed=.035; state.phase=phase
            if phase=="stopping" then state.target=1.2 end
            local c={motion=state,index=3,car={Ferris.position(state,3)},side=1}
            c.aim={c.car[1]+.3,c.car[2]+.72,c.car[3]-2}
            for _,seconds in ipairs({0,.5,2,8,11}) do
                local result=FerrisCinemaPath.predict(c,seconds)
                local expected={}; for k,v in pairs(state) do expected[k]=v end
                local remaining=seconds
                while remaining>0 do local dt=math.min(Ferris.step,remaining); Ferris.advance(expected,dt); remaining=remaining-dt end
                local x,y,z=Ferris.position(expected,3)
                assert(math.abs(result.car[1]-x)<1e-8 and math.abs(result.car[2]-y)<1e-8 and math.abs(result.car[3]-z)<1e-8)
                assert(result.motion.phase==expected.phase and state.angle==1)
                local before=(c.aim[2]-c.car[2])^2+(c.aim[3]-c.car[3])^2
                local after=(result.aim[2]-result.car[2])^2+(result.aim[3]-result.car[3])^2
                assert(math.abs(before-after)<1e-8)
            end
        end
    ''')
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute((base.RESOURCE/'camera_paths.lua').read_text())
    lua.execute('''
        local c={wheel={342,-243,37},car={342,-243,14},aim={342,-243,12},side=1}
        for _,fps in ipairs({20,30,60,144}) do
            for _,side in ipairs({-1,1}) do
                c.side=side
                for frame=0,160*fps do
                    c.car[2]=-243+23*math.sin(frame/fps*.05)
                    c.car[3]=37+23*math.cos(frame/fps*.05)
                    c.aim={c.car[1]+.3,c.car[2]+side*.72,c.car[3]-1.83}
                    local p=FerrisCinemaPath.evaluate(frame/fps,c)
                    assert(p.shot>=1 and p.shot<=10 and p.fov>=40 and p.fov<=74)
                    local d=0
                    for i=1,3 do
                        assert(p.position[i]==p.position[i] and p.target[i]==p.target[i])
                        d=d+(p.position[i]-c.wheel[i])^2
                    end
                    assert(d<80^2)
                end
            end
        end
        assert(FerrisCinemaPath.evaluate(80,c).shot==1)
        local function angles(p)
            local x,y,z=p.target[1]-p.position[1],p.target[2]-p.position[2],p.target[3]-p.position[3]
            return math.atan2(y,x),math.atan2(z,math.sqrt(x*x+y*y))
        end
        for _,side in ipairs({-1,1}) do
            c.side=side; c.car={342,-243,37}; c.aim={342.3,-243+side*.72,35.17}
            for _,ped in ipairs({false,{342,-231,36}}) do
                c.ped=ped or nil
                for i,name in ipairs(FerrisCinemaPath.names) do
                    local t=FerrisCinemaPath.timeFor(name)
                    local a=FerrisCinemaPath.evaluate(t+.1,c)
                    local b=FerrisCinemaPath.evaluate(t+FerrisCinemaPath.durations[i]-.1,c)
                    local ay,ap=angles(a); local by,bp=angles(b)
                    assert(math.abs(a.fov-b.fov)>3,name.." FOV")
                    assert(math.abs(math.atan2(math.sin(by-ay),math.cos(by-ay)))>math.rad(2),name.." yaw")
                    assert(math.abs(bp-ap)>math.rad(1),name.." pitch")
                    assert(a.subject==(i==2 and "wheel" or "player"))
                    -- A frozen cabin isolates authored movement from wheel motion.
                    for sample=0,20 do
                        local f=FerrisCinemaPath.evaluate(t+FerrisCinemaPath.durations[i]*sample/21,c)
                        if i~=2 then
                            local x,y,z=f.target[1]-f.position[1],f.target[2]-f.position[2],f.target[3]-f.position[3]
                            local l=math.sqrt(x*x+y*y+z*z); x,y,z=x/l,y/l,z/l
                            local h=math.sqrt(x*x+y*y); local rx,ry=-y/h,x/h
                            for _,aspect in ipairs({4/3,16/9,21/9}) do
                                for _,height in ipairs({0,-.35}) do
                                    local hx,hy,hz=c.aim[1]-f.position[1],c.aim[2]-f.position[2],c.aim[3]+height-f.position[3]
                                    local forward=hx*x+hy*y+hz*z
                                    local tan=math.tan(math.rad(f.fov/2))
                                    assert(forward>.15,name.." behind camera")
                                    assert(math.abs(hx*rx+hy*ry)<forward*tan*.8,name.." horizontal framing")
                                    assert(math.abs(-hx*z*ry+hy*z*rx+hz*h)<forward*tan/math.max(2.2,aspect)*.8,name.." letterbox framing")
                                end
                            end
                        end
                    end
                end
            end
        end
        for _,side in ipairs({-1,1}) do
            for _,seatX in ipairs({-.3,.3}) do
                c.side=side; c.aim={342+seatX,-243+side*.72,35.17}; c.ped=nil
                for _,direction in ipairs({-1,1}) do
                    for _,seconds in ipairs({33.05,33.65,34.25}) do
                        local f=FerrisCinemaPath.planned(FerrisCinemaPath.evaluate(seconds,c),c,{style="sheltered",direction=direction})
                        local x,y,z=f.target[1]-f.position[1],f.target[2]-f.position[2],f.target[3]-f.position[3]
                        local l=math.sqrt(x*x+y*y+z*z); x,y,z=x/l,y/l,z/l
                        local h=math.sqrt(x*x+y*y); local rx,ry=-y/h,x/h
                        for _,height in ipairs({-.29,1.01}) do
                            local hx,hy,hz=c.aim[1]-f.position[1],c.aim[2]-f.position[2],c.aim[3]+height-f.position[3]
                            local forward=hx*x+hy*y+hz*z
                            assert(math.abs(-hx*z*ry+hy*z*rx+hz*h)<forward*math.tan(math.rad(f.fov/2))/(21/9)*.8,"sheltered gesture crop")
                        end
                    end
                end
            end
        end
        Ferris={exit={336,-243,12}}
        local a,b=FerrisCinemaPath.arrival(0,c),FerrisCinemaPath.arrival(7.9,c)
        local ay,ap=angles(a); local by,bp=angles(b)
        assert(a.shot==0 and a.name=="exit-platform" and a.fov~=b.fov)
        assert(math.abs(by-ay)>.01 and math.abs(bp-ap)>.01)

    ''')
    # Resource-scoped UI claims must survive an overlapping owner's release.
    lua.execute('''
        tick=0; handlers={}; root={}; resourceRoot={}; chat=true
        function getTickCount() return tick end
        function addEventHandler(name,element,fn) handlers[#handlers+1]={name,element,fn} end
        function guiGetScreenSize() return 1920,1080 end
        function isChatVisible() return chat end
        function showChat(value) chat=value end
        function isPlayerHudComponentVisible() return true end
        function setPlayerHudComponentVisible(_,value) radar=value end
        function getResourceName(r) return r end
        Hud={owner=function() return owner end,baseUiVisible=function() return true end}
    ''')
    lua.execute((base.ROOT/'mods/deathmatch/resources/[hud]/frontend/cinematic_c.lua').read_text())
    lua.execute('''
        owner='wheel'; assert(setCinematicPresentation(true)); tick=400
        assert(getCinematicPresentation().active and not chat)
        assert(math.abs(getCinematicPresentation().inset-(1080-1920/2.2)/2)<.001)
        owner='cutscene'; setCinematicPresentation(true)
        owner='wheel'; setCinematicPresentation(false)
        assert(getCinematicPresentation().active and not chat)
        for _,h in ipairs(handlers) do if h[1]=='onClientResourceStop' and h[2]==root then h[3]('cutscene') end end
        assert(not getCinematicPresentation().active and chat)
        assert(not setCinematicPresentation('bad'))
    ''')
    lua.execute('''
        Ferris={x=342,y=-243,z=37,exit={336.3,-243.22,12.06}}; localPlayer={}; car={}; root={}; resourceRoot={}
        cam={330,-243,15,342,-243,12,0,70}; camTarget=localPlayer
        controls=true; menu=false; tick=0; presentation=false
        function getResourceFromName(n) return n end
        function getResourceState(r) return 'running' end
        function getThisResource() return 'funfield' end
        function getCameraTarget() return camTarget end
        function getCameraMatrix() return unpack(cam) end
        function setCameraMatrix(...) cam={...}; camTarget=false end
        function setCameraTarget(p) camTarget=p end
        function getCameraFieldOfView() return 70 end
        function setCameraFieldOfView(_,v) restoredFov=v end
        function isControlEnabled() return controls end
        function toggleControl(_,v) controls=v end
        function isElement(e) return type(e)=='table' end
        function getElementPosition(e) if e==car then return 342,-243,25 end return 342,-243,22.9 end
        function processLineOfSight() return false end
        function processLineAgainstMesh() return false end
        function getPedBonePosition() return 342,-243,23.5 end
        function isMainMenuActive() return menu end
        function isPlayerMapVisible() return false end
        function isConsoleActive() return false end
        function getElementsByType() return {} end
        waves=0
        function triggerServerEvent(name) assert(name=='funfield:greeting'); waves=waves+1 end
        exports={frontend={setCinematicPresentation=function(_,v) presentation=v end},
            radio={setCinematicRadio=function() end}, skygfx={getVcsRenderedSun=function() return 0,1,1,true end}}
    ''')
    lua.execute((base.RESOURCE/'camera_plan.lua').read_text())
    lua.execute('''
        local context={wheel={342,-243,37},car={342,-243,37},aim={342.3,-242.28,35.17},side=1}
        local inspectedEnd=false
        local job=FerrisCinemaPlanner.begin(16,8,context,false,function(frame,c,previous)
            if frame.progress>.5 then inspectedEnd=true end
            return frame.progress<.5 or frame.position[1]>340.5
        end)
        while not job.done do FerrisCinemaPlanner.resume(job,8) end
        assert(inspectedEnd and job.variant and job.validated)
        context.ped={342,-230,36}
        context.candidates={}
        for _,name in ipairs({"blocked","clear"}) do
            local candidate={}; for k,v in pairs(context) do if k~="candidates" then candidate[k]=v end end
            candidate.pedElement=name; context.candidates[#context.candidates+1]=candidate
        end
        job=FerrisCinemaPlanner.begin(24,8,context,false,function(frame,c) return c.pedElement=="clear" end)
        while not job.done do FerrisCinemaPlanner.resume(job,8) end
        assert(job.validated and job.ped=="clear","neighbor must have a clear whole-shot path")
    ''')
    lua.execute((base.RESOURCE/'camera.lua').read_text())
    lua.execute('''
        local seat={index=6,seat=1}
        for i=1,10 do tick=tick+16 FerrisCinema.update(seat,car,false,'running',16) end
        assert(FerrisCinema.state().active and presentation and not controls)
        local before=FerrisCinema.state().elapsed
        menu=true; FerrisCinema.update(seat,car,false,'running',1000); menu=false
        assert(FerrisCinema.state().elapsed==before)
        FerrisCinema.stop('jump')
        assert(not FerrisCinema.state().active and not presentation and controls and camTarget==localPlayer and restoredFov==70)
        FerrisCinema.update(seat,car,false,'running',16)
        assert(not FerrisCinema.state().active) -- stale seat packet cannot reacquire
        FerrisCinema.update(nil,nil,false,'running',16)
        FerrisCinema.update(seat,car,false,'running',16)
        FerrisCinema.update(seat,car,true,'stopped',16)
        assert(FerrisCinema.state().active and presentation and not camTarget)
        assert(FerrisCinema.state().shot=='exit-platform')
        FerrisCinema.update(seat,car,false,'running',16)
        assert(FerrisCinema.state().active) -- loops at the platform while seated
        FerrisCinema.update(nil,nil,false,'running',16)
        FerrisCinema.update(seat,car,false,'running',16)
        setCameraMatrix(100,200,300,0,0,0,0,60)
        FerrisCinema.update(seat,car,false,'running',16)
        assert(FerrisCinema.state().active and FerrisCinema.state().suspended and cam[1]==100 and not presentation)
        setCameraTarget(localPlayer)
        FerrisCinema.update(seat,car,false,'running',16)
        assert(FerrisCinema.state().active and not FerrisCinema.state().suspended and presentation)
        FerrisCinema.update(nil,nil,false,'running',16)
        local previous,previousName,previousVariant
        local function viewAngles(m)
            local x,y,z=m[4]-m[1],m[5]-m[2],m[6]-m[3]
            return math.atan2(y,x),math.atan2(z,math.sqrt(x*x+y*y))
        end
        for i=1,60*161 do
            tick=tick+1000/60; FerrisCinema.update(seat,car,false,'running',1000/60)
            local name=FerrisCinema.state().shot
            if previous and previousName==name then
                local ay,ap=viewAngles(previous); local by,bp=viewAngles(cam)
                assert(FerrisCinema.state().alternate==previousVariant,"path changed inside shot")
                assert(math.abs(math.atan2(math.sin(by-ay),math.cos(by-ay)))<=math.rad(42)/60+.00001,"yaw snap")
                assert(math.abs(bp-ap)<=math.rad(28)/60+.00001,"pitch snap")
                assert(math.abs(cam[8]-previous[8])<=8/60+.00001,"FOV snap")
                local d=0; for axis=1,3 do d=d+(cam[axis]-previous[axis])^2 end
                assert(math.sqrt(d)<=3.5/60+.00001,"position snap")
            end
            previous,previousName,previousVariant=cam,name,FerrisCinema.state().alternate
        end
        assert(FerrisCinema.state().active and waves==2)
        for _,fps in ipairs({20,30,60,144}) do
            previous,previousName=cam,FerrisCinema.state().shot
            for i=1,fps*4 do
                function processLineOfSight() return i<fps*2 end
                tick=tick+1000/fps; FerrisCinema.update(seat,car,false,'running',1000/fps)
                local state=FerrisCinema.state()
                if i==fps then assert(state.motionBlocked) end
                if previousName==state.shot then
                    local ay,ap=viewAngles(previous); local by,bp=viewAngles(cam)
                    assert(math.abs(math.atan2(math.sin(by-ay),math.cos(by-ay)))<=math.rad(42)/fps+.00001,"obstruction yaw snap")
                    assert(math.abs(bp-ap)<=math.rad(28)/fps+.00001,"obstruction pitch snap")
                    assert(math.abs(cam[8]-previous[8])<=8/fps+.00001,"obstruction FOV snap")
                    local d=0; for axis=1,3 do d=d+(cam[axis]-previous[axis])^2 end
                    assert(math.sqrt(d)<=3.5/fps+.00001,"obstruction lens snap")
                end
                previous,previousName=cam,state.shot
            end
        end
        FerrisCinema.stop('stand')
        assert(not presentation and controls and camTarget==localPlayer)
    ''')
    source=(base.RESOURCE/'client.lua').read_text()
    assert 'bindKey("space"' not in source and 'addCommandHandler("jumpferris"' not in source
    print('FUNFIELD_CAMERA_PASS: two loops at 20/30/60/144 fps; both rows/all heights; ten distinct shots; authored FOV/yaw/pitch; letterbox framing; bounded paths; full-shot collision planning; locked paths; obstruction rate limits; UI ownership; menu pause; F handoff; platform loop; external camera suspension; no jump binding')


CLIENT=r'''
local phase="loading"
local phaseAt=0
local started=false
local lastShot,lastCycle
local run="day"
local finish=false
local lastSitAttempt=0
local faceUntil
local measuredFPS=0
local previousCamera
local motion={samples=0,pathChanges=0,maxYaw=0,maxPitch=0,maxFov=0,maxLens=0}
local function measure(delta)
    local resource=getResourceFromName("funfield")
    if not resource or getResourceState(resource)~="running" then previousCamera=nil return end
    local s=exports.funfield:getFerrisWheelState()
    if not s.cinematic.active or s.cinematic.suspended or getCameraTarget() then previousCamera=nil return end
    local m={getCameraMatrix()}
    local key=math.floor(s.cinematic.elapsed/80)..":"..s.cinematic.shot
    local car=s.carriages[s.riding]
    local anchor=isElement(car) and {getElementPosition(car)} or {0,0,0}
    local x,y,z=m[4]-m[1],m[5]-m[2],m[6]-m[3]
    local yaw,pitch=math.atan2(y,x),math.atan2(z,math.sqrt(x*x+y*y))
    local old=previousCamera
    local age=old and old.key==key and old.age+delta or 0
    -- MTA applies the FOV component of an intentional cut one render later.
    -- Exclude the first 100 ms after that cut from within-shot rate metrics.
    if old and old.key==key and old.age>100 and age>100 then
        local dt=delta/1000
        motion.samples=motion.samples+1
        if old.variant~=s.cinematic.alternate then motion.pathChanges=motion.pathChanges+1 end
        motion.maxYaw=math.max(motion.maxYaw,math.deg(math.abs(math.atan2(math.sin(yaw-old.yaw),math.cos(yaw-old.yaw))))/dt)
        motion.maxPitch=math.max(motion.maxPitch,math.deg(math.abs(pitch-old.pitch))/dt)
        local rate=math.abs(m[8]-old.matrix[8])/dt
        if rate>motion.maxFov then
            motion.fovPeak={before=old.matrix[8],after=m[8],expectedBefore=old.fov,expectedAfter=s.cinematic.fov,
                age=age,delta=delta,key=key,beforeTime=old.elapsed,afterTime=s.cinematic.elapsed}
        end
        motion.maxFov=math.max(motion.maxFov,rate)
        local length=0
        for i=1,3 do
            local d=m[i]-old.matrix[i]
            if s.cinematic.shot~="vice-point-reveal" then d=d-(anchor[i]-old.anchor[i]) end
            length=length+d*d
        end
        motion.maxLens=math.max(motion.maxLens,math.sqrt(length)/dt)
    end
    previousCamera={key=key,age=age,fov=s.cinematic.fov,elapsed=s.cinematic.elapsed,variant=s.cinematic.alternate,yaw=yaw,pitch=pitch,matrix=m,anchor=anchor}
end
addEventHandler("onClientPreRender",root,function(delta)
    measuredFPS=measuredFPS*.9+1000/math.max(1,delta)*.1
    measure(delta)
    if phase=="boarding" then
        local x=getElementPosition(localPlayer)
        if x>341.75 then
            setPedControlState(localPlayer,"forwards",false)
            setCameraTarget(localPlayer)
            phase="sitting" phaseAt=getTickCount()
            lastSitAttempt=phaseAt+400
            setTimer(executeCommandHandler,400,1,"sitferris")
        end
    end
    if not faceUntil or getTickCount()>faceUntil then return end
    local x,y,z=getPedBonePosition(localPlayer,8)
    local s=exports.funfield:getFerrisWheelState()
    local side=s.seated and s.seated<=2 and 1 or -1
    setCameraMatrix(x+1.4,y-side*.5,z+.05,x,y,z-.04,0,35)
end,true,"low-100")
local function report(kind)
    local resource=getResourceFromName("funfield")
    if not resource or getResourceState(resource)~="running" then return end
    local s=exports.funfield:getFerrisWheelState()
    local neighbor=s.cinematic.neighbor
    s.cinematic.neighbor=isElement(neighbor) and {model=getElementModel(neighbor),seat=getElementData(neighbor,"funfield:rider")} or false
    local pose={}
    for name,bone in pairs({head=5,jaw=8,pelvis=1,rightHand=24,leftHand=34}) do
        local m=getElementBoneMatrix(localPlayer,bone)
        pose[name]=m and m[4][3] or false
    end
    local x,y,z=getElementPosition(localPlayer)
    local frontend=getResourceFromName("frontend")
    triggerServerEvent("funfieldQA:sample",resourceRoot,{kind=kind,phase=phase,
        seated=s.seated,riding=s.riding,wheel=s.phase,exitReady=s.exitReady,exitQueued=s.exitQueued,
        camera=s.cinematic,matrix={getCameraMatrix()},motion=motion,pose=pose,
        rain=getRainLevel(),vcsWeather=exports.skygfx:getVcsWeather(),presentation=frontend and getResourceState(frontend)=="running" and exports.frontend:getCinematicPresentation() or false,
        cameraTarget=getCameraTarget()==localPlayer,changeCamera=isControlEnabled("change_camera"),
        forward=isControlEnabled("forwards"),collisions=getElementCollisionsEnabled(localPlayer),
        menu=isMainMenuActive(),console=isConsoleActive(),chat=isChatBoxInputActive(),ground=isPedOnGround(localPlayer),
        contact=isElement(getPedContactElement(localPlayer)) and getElementID(getPedContactElement(localPlayer)) or false,
        x=x,y=y,z=z,fps=getFPSLimit(),measuredFPS=measuredFPS,run=run})
end
local function shot(tag) triggerServerEvent("funfieldQA:shot",resourceRoot,tag) end
addEvent("funfieldQA:begin",true)
addEventHandler("funfieldQA:begin",resourceRoot,function(resume)
    phase=resume and "cinema" or "loading" phaseAt=getTickCount() started=true
    lastShot,lastCycle=nil,nil
    setCameraTarget(localPlayer) setFPSLimit(60)
end)
addEvent("funfieldQA:control",true)
addEventHandler("funfieldQA:control",resourceRoot,function(c)
    if c.stop then phase="done" setPedControlState(localPlayer,"forwards",false) end
    if c.finish~=nil then finish=c.finish end
    if c.actionKey then executeCommandHandler(c.actionKey) end
    if c.fps then setFPSLimit(c.fps) end
    if c.vcsWeather then exports.skygfx:setVcsWeather(c.vcsWeather) end
    if c.camera then setCameraMatrix(unpack(c.camera)) end
    if c.follow then setCameraTarget(localPlayer) end
    if c.position then setElementPosition(localPlayer,unpack(c.position)) end
    if c.run then run=c.run end
    if c.shot then shot(c.shot) end
    if c.report then report(c.report) end
    if c.diagnose then
        local s=exports.funfield:getFerrisWheelState()
        local car=s.carriages[s.riding]
        local p=getElementBoneMatrix(localPlayer,5)[4]
        local npc=s.cinematic.neighbor
        if not isElement(npc) then for _,r in ipairs(s.riders) do if r.index~=s.riding then npc=r.ped break end end end
        if isElement(car) and isElement(npc) then
            local context={wheel={342.189087,-243.189011,36.895248},car={getElementPosition(car)},
                aim={p[1],p[2],p[3]+.09},ped={getPedBonePosition(npc,8)},side=s.seated<=2 and 1 or -1}
            local f=FerrisCinemaPath.evaluate(FerrisCinemaPath.timeFor("neighboring-riders"),context)
            local head={p[1],p[2],p[3]+.15}
            local function mesh(element,to)
                return processLineAgainstMesh(element,f.position[1],f.position[2],f.position[3],to[1],to[2],to[3])
            end
            triggerServerEvent("funfieldQA:sample",resourceRoot,{kind="NEIGHBOR_DIAGNOSTIC",frame=f,head=head,
                npc=context.ped,car=context.car,carHead=mesh(car,head),hubHead=mesh(s.hub,head),
                carNPC=mesh(car,context.ped),hubNPC=mesh(s.hub,context.ped)})
        end
    end
    if c.face then
        faceUntil=getTickCount()+2000
        setTimer(function() shot("wheel-cinema-cj-mouth-close") end,700,1)
    end
    if c.walk then
        setPedRotation(localPlayer,c.walk)
        setPedControlState(localPlayer,"forwards",true)
        setTimer(setPedControlState,c.duration or 2000,1,localPlayer,"forwards",false)
    end
end)
addEventHandler("onClientResourceStart",resourceRoot,function()
    setTimer(function() triggerServerEvent("funfieldQA:ready",resourceRoot) end,2500,1)
end)
setTimer(function()
    if not started then return end
    local r=getResourceFromName("funfield")
    if not r or getResourceState(r)~="running" then return end
    local s=exports.funfield:getFerrisWheelState()
    local now=getTickCount()
    if phase=="loading" and s.ready then phase="waiting" phaseAt=now report("MAP_READY")
    elseif phase=="waiting" and s.phase=="stopped" then
        phase="boarding" phaseAt=now
        -- Fix the direction of native forward input while walking onto the deck.
        setCameraMatrix(330,-243.22,14,350,-243.22,12)
        setPedRotation(localPlayer,270) setPedControlState(localPlayer,"forwards",true)
        report("BOARD_START")
    elseif phase=="boarding" then
        local x=getElementPosition(localPlayer)
        if x>341.9 or now-phaseAt>4500 then
            setPedControlState(localPlayer,"forwards",false)
            setCameraTarget(localPlayer)
            phase="sitting" phaseAt=now
            setTimer(executeCommandHandler,400,1,"sitferris")
        end
    elseif phase=="sitting" then
        if s.seated then phase="cinema" phaseAt=now report("SIT_CONFIRMED")
        elseif not getElementData(localPlayer,"funfield:seated") and now-lastSitAttempt>500 and now-phaseAt<3000 then
            lastSitAttempt=now executeCommandHandler("sitferris") report("SIT_RETRY")
        elseif now-phaseAt>3500 then phase="done" report("SIT_FAILED") end
    elseif phase=="cinema" then
        if s.cinematic.active then
            local cycle=math.floor(s.cinematic.elapsed/80)
            if s.cinematic.shot~=lastShot or cycle~=lastCycle then
                lastShot,lastCycle=s.cinematic.shot,cycle
                local tag="wheel-cinema-"..run.."-"..cycle.."-"..lastShot
                local duration=8
                for i,name in ipairs(FerrisCinemaPath.names) do
                    if name==lastShot then duration=FerrisCinemaPath.durations[i] end
                end
                local expectedShot,expectedCycle=lastShot,cycle
                local offset=s.cinematic.progress*duration*1000
                local function capture(suffix,kind)
                    local current=exports.funfield:getFerrisWheelState().cinematic
                    if current.shot~=expectedShot or math.floor(current.elapsed/80)~=expectedCycle then
                        report("CAPTURE_SKIPPED") return
                    end
                    shot(tag..suffix) report(kind)
                end
                for _,sample in ipairs({{300,"start"},{duration*500,"middle"},{duration*1000-400,"end"}}) do
                    local suffix=sample[2]
                    if sample[1]>offset then
                        setTimer(function() capture("-"..suffix,"SHOT_"..suffix) end,sample[1]-offset,1)
                    end
                end
                if lastShot=="greeting" then
                    if offset<1650 then setTimer(function() capture("-player","GREETING_PLAYER") end,1650-offset,1) end
                    if offset<2950 then setTimer(function() capture("-reply","GREETING_REPLY") end,2950-offset,1) end
                end
            end
        elseif s.seated then report("CAMERA_INACTIVE") end
        if finish and s.cinematic.elapsed>=162 then
            executeCommandHandler("exitferris") phase="exit" phaseAt=now report("EXIT_REQUESTED")
        end
    elseif phase=="exit" and s.exitReady and s.phase=="stopped" then
        phase="arrival" phaseAt=now report("EXIT_ARRIVED")
        setTimer(function() shot("wheel-cinema-exit-arrival") report("ARRIVAL_SHOT") end,2500,1)
        setTimer(function() shot("wheel-cinema-exit-still-seated") report("ARRIVAL_LOOP") end,9500,1)
    elseif phase=="arrival" and now-phaseAt>12000 then
        executeCommandHandler("sitferris") phase="standing" phaseAt=now
    elseif phase=="standing" and not s.seated then
        report("STAND_CONFIRMED") phase="leaving" phaseAt=now
        local x,y,z=getElementPosition(localPlayer)
        setCameraMatrix(x+8,y,z+2,x-8,y,z)
        setPedRotation(localPlayer,90) setPedControlState(localPlayer,"forwards",true)
    elseif phase=="leaving" and now-phaseAt>2500 then
        setPedControlState(localPlayer,"forwards",false) setCameraTarget(localPlayer)
        phase="done" report("COMPLETE") shot("wheel-cinema-exited-platform")
    end
    if phase~="done" and now-phaseAt>240000 then phase="done" report("TIMEOUT") end
end,200,0)
setTimer(function() if started then report("TRACE") end end,2000,0)
addEventHandler("onClientResourceStop",resourceRoot,function()
    setPedControlState(localPlayer,"forwards",false)
    setPedControlState(localPlayer,"jump",false)
    setCameraTarget(localPlayer) setFPSLimit(60)
end)
'''


def stage_live():
    base.CLIENT=(base.RESOURCE/'camera_paths.lua').read_text()+"\n"+CLIENT
    base.SERVER=base.SERVER.replace('elseif c.action=="death"', '''elseif c.action=="environment" then
        setTime(c.hour or 12,c.minute or 0) setWeather(c.weather or 0)
    elseif c.action=="reloadProduction" then
        restartResource(getResourceFromName("frontend"))
        setTimer(function() restartResource(getResourceFromName("funfield")) end,500,1)
        setTimer(function() if isElement(testPlayer) then prepare(testPlayer) end end,1500,1)
    elseif c.action=="death"''')
    lua=LuaRuntime()
    lua.execute("assert(loadstring(...))",base.CLIENT)
    lua.execute("assert(loadstring(...))",base.SERVER)
    base.stage_live()


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--stage-live',action='store_true')
    args=parser.parse_args()
    base.check_motion()
    base.check_players()
    check_camera()
    if args.stage_live: stage_live()
