"""PS2 roster, dispatch, barrier entry and spike-strip boundaries in Lua 5.1."""
from pathlib import Path

from lupa.lua51 import LuaRuntime


def check_police_renderer(resources):
    vm = LuaRuntime()
    vm.execute("""
        root, events, assets = {}, {}, {}
        SKYGFX = {sunGlare=true}
        function addEvent() end
        function addEventHandler(name,_,fn) events[name]=fn end
        function removeEventHandler(name) events[name]=nil end
        function getElementsByType() return cars end
        function getElementModel(e) return e.id end
        function isElement(e) return type(e)=="table" and not e.dead end
        function getElementType() return "vehicle" end
        function isElementStreamedIn() return true end
        function getElementData(e) return e.provider end
        function getResourceFromName(name) return name end
        function getResourceName(r) return r end
        function getResourceState(r) return assets[r] and "running" or "stopped" end
        function call(r,method,id)
            assert(method=="getVcsVehicleRenderMaterials")
            return assets[r][id] or false
        end
        function dxCreateShader(_, macros) return {macros=macros} end
        function dxCreateScreenSource() return {} end
        function dxCreateRenderTarget() return {} end
        function dxCreateTexture() return {} end
        function dxSetShaderValue(s,k,v) s[k]=v;return true end
        function destroyElement(e) assert(not e.dead);e.dead=true end
        function isWorldSpecialPropertyEnabled() return true end
        function setWorldSpecialPropertyEnabled() end
        function getVehicleSirensOn(v) return v.siren==true end
        function outputDebugString(message) error(message) end
        function engineApplyShaderToWorldTexture(shader,name,v)
            assert(not v.bound[name] and not shader.dead)
            v.bound[name]=shader
            return true
        end
        function engineRemoveShaderFromWorldTexture(shader,name,v)
            assert(v.bound[name]==shader)
            v.bound[name]=nil
        end
        local material={vcsglass_66b6c24c=true,vcsenv_20_body=true,
            vcssiren_left=true,vcssiren_right=true}
        assets.vcs_model={[596]=material}
        assets.npchlc_traffic={[598]={vcsglass_66b6c24c=true,vcsenv_05_body=true}}
        cars={{id=596,bound={}},{id=596,bound={}},{id=598,bound={},provider="npchlc_traffic"},
            {id=400,bound={}}}
    """)
    vm.execute((resources / "[graphic]/skygfx/pipeline/vcsVehicle.lua").read_text(encoding="utf-8"))
    vm.execute("""
        VCSVehicle.start()
        local a,b,fallback,native=unpack(cars)
        -- Model a streamed C++ element whose only strong Lua reference is
        -- the renderer. Collecting wrappers must never erase its shaders.
        local weak=setmetatable({}, {__mode="v"})
        source={id=596,bound={}}
        weak[1]=source
        events.onClientElementStreamIn()
        source=nil
        collectgarbage("collect")
        assert(weak[1] and weak[1].bound.vcsglass_66b6c24c)
        source=weak[1]; events.onClientElementStreamOut(); source=nil
        collectgarbage("collect")
        assert(not weak[1])
        assert(a.bound.vcsglass_66b6c24c.macros.VCS_GLASS and a.bound.vcsenv_20_body)
        assert(fallback.bound.vcsenv_05_body and not next(native.bound))
        a.siren=true; VCSVehicle.prepare()
        assert(a.bound.vcssiren_left.LensPhase==0 and a.bound.vcssiren_right.LensPhase==0.5)
        assert(not b.bound.vcssiren_left)
        b.siren=true; a.siren=false; VCSVehicle.prepare()
        assert(not a.bound.vcssiren_left and b.bound.vcssiren_right)
        source=b; events.onClientElementStreamOut(); assert(not next(b.bound))
        events.onClientElementStreamIn(); assert(b.bound.vcssiren_right)
        assets.npchlc_traffic=nil; events.onClientResourceStop("npchlc_traffic")
        assert(not next(fallback.bound) and a.bound.vcsglass_66b6c24c)
        assets.vcs_model[598]={vcsglass_17171798=true}
        source=fallback; events["npc_hlc:onVehicleGroundGeometry"]()
        assert(fallback.bound.vcsglass_17171798)
        a.id=400; source=a; events.onClientElementModelChange()
        assert(not next(a.bound))
        VCSVehicle.stop()
        assert(not next(b.bound) and not next(fallback.bound))
    """)


def main():
    resources = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources"
    vehicle_resource = resources / "[model]/vcs_vehicle"
    controls = LuaRuntime()
    controls.execute("""
        root,localPlayer,car,callbacks,now={},{},{base=598,original=193},{},0
        function addEventHandler(event,_,handler) callbacks[event]=handler end
        function isElement(e) return type(e)=="table" end
        function getElementType(e) return e==car and "vehicle" end
        function getElementData(e,key) return key=="vcs_vehicle:originalModel" and e.original end
        function getElementModel(e) return e.base end
        function getPedOccupiedVehicle() return car end
        function getVehicleOccupant() return driver end
        function isControlEnabled() return true end
        function isMTAWindowActive() return false end
        function isCursorShowing() return false end
        function getBoundKeys() return {capslock=true} end
        function getVehicleSirensOn() return on end
        function getTickCount() return now end
        function setTimer(fn) timer=fn end
        function triggerServerEvent(_,_,desired) writes=writes+1;on=desired end
        driver,on,writes=localPlayer,false,0
    """)
    for script in ("vehicle.lua", "police_siren_c.lua"):
        controls.execute((vehicle_resource / "controllers" / script).read_text())
    controls.execute("""
        local key=callbacks.onClientKey
        local function tap(native)
            key("capslock",true)
            if native then on=not on end
            now=now+15
            key("capslock",false)
            if timer then timer();timer=nil end
        end
        key("h",true);key("h",false);assert(not timer)
        tap(false);assert(on and writes==1)
        tap(true);assert(not on and writes==1)
        driver={};tap(false);assert(not on and writes==1)
        driver=localPlayer;car.base=411;tap(false);assert(not on and writes==1)
    """)
    check_police_renderer(resources)
    vm = LuaRuntime()
    vm.execute("""
        root,now,events,world = {},0,{},{}
        function addEvent() end
        exports={npc_hlc={clearNPCTasks=function() end},server_coldata={
            getModelBoundingBox=function() return -1,-2,-.5,1,2,1 end}}
        function addEventHandler(name,_,fn)
            events[name]=events[name] or {}
            table.insert(events[name],fn)
        end
        function getTickCount() return now end
        function isElement(e) return type(e)=="table" and not e.dead end
        function getPlayerWantedLevel(p) return p.stars end
        function getPedOccupiedVehicle(p) return p.car end
        function getElementPosition(e) return e.x or 0,e.y or 0,e.z or 0 end
        function getElementVelocity(e) return e.vx or 0,e.vy or 0,0 end
        function getElementInterior(e) return e.interior or 0 end
        function getElementDimension(e) return e.dimension or 0 end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function getDistanceBetweenPoints2D(x,y,a,b) return math.sqrt((x-a)^2+(y-b)^2) end
        function isPedDead() return false end
        function isPedInVehicle(e) return e.car~=nil end
        function getVehicleType() return "Automobile" end
        function setPedRotation() end
        function setPedAnimation() end
        function bitAnd(a,b)
            local n=0
            for i=0,15 do if math.floor(a/2^i)%2==1 and math.floor(b/2^i)%2==1 then n=n+2^i end end
            return n
        end
        function setElementData(e,k,v) e[k]=v end
        function getElementData(e,k) return e[k] end
        function removeElementData(e,k) e[k]=nil end
        function getElementsWithinRange() return {} end
        function createVehicle(model,x,y,z,pitch,roll,yaw)
            local e={x=x,y=y,z=z,pitch=pitch,yaw=yaw}; table.insert(world,e); return e
        end
        function destroyElement(e) e.dead=true end
        function setElementDimension() end
        function setVehicleEngineState() end
        TrafficAmbient={getPedestrianModel=function(id) return id end}
        TrafficVisibility={hasPlayerOccupant=function() return false end}
        TrafficModelBindings={get=function(id) return id end,tag=function(e,id) e.model=id end}
    """)
    vm.execute((resources / "[module]/wanted/rules.lua").read_text(encoding="utf-8"))
    vm.execute("TrafficWanted={getPoliceResponse=WantedRules.getPoliceResponse}")
    vm.execute((resources / "[traffic]/npchlc_traffic/traffic_stinger.lua").read_text(encoding="utf-8"))
    vm.execute((resources / "[traffic]/npchlc_traffic/traffic_ground_police.lua").read_text(encoding="utf-8"))
    vm.execute("""
        local random = math.random
        for level = 1, 6 do
            local blocks = 0
            for roll = 0, 7 do
                math.random = function(lo, hi) assert(lo == 0 and hi == 7); return roll end
                local patrol = {}
                TrafficGroundPolice.updatePursuitLevel(patrol, 207, level)
                if patrol.mission == 4 then blocks = blocks + 1 else assert(patrol.mission == 2) end
                if level == 1 then assert((patrol.mission == 4) == (bitAnd(roll, 2) == 0)) end
                math.random = function() error("active pursuit rerolled") end
                patrol.mission = patrol.mission + 1
                local closeMission = patrol.mission
                local path = {}
                patrol.order, patrol.path, patrol.seed = closeMission, path, 3
                TrafficGroundPolice.updatePursuitLevel(patrol, 207, level % 6 + 1)
                assert(patrol.mission == closeMission and patrol.order == closeMission)
                assert(patrol.seed == 3 and patrol.path == path)
                assert(patrol.speed == TrafficGroundPolice.cruiseSpeed(207, level % 6 + 1))
            end
            assert(blocks == ({4,3,2,1,1,1})[level])
        end
        local bike = {}
        TrafficGroundPolice.updatePursuitLevel(bike, 191, 1); assert(bike.mission == 4)
        TrafficGroundPolice.updatePursuitLevel(bike, 191, 2); assert(bike.mission == 21)
        TrafficGroundPolice.updatePursuitLevel(bike, 191, 6); assert(bike.mission == 21)
        TrafficGroundPolice.updatePursuitLevel(bike, 191, 1); assert(bike.mission == 4)
        math.random = random
    """)
    ram = LuaRuntime()
    ram.execute("function addEvent() end")
    ram.execute((resources / "[traffic]/npc_hlc/tasks_c.lua").read_text(encoding="utf-8"))
    ram.execute("""
        local patrol, driver, car, cop = {}, {}, {}, {}
        local now, steer, pedal, brake, aimX = 0
        local function matrix(x)
            return {{1,0,0},{0,1,0},{0,0,1},{x,0,0}}
        end
        patrol.frame, car.frame = matrix(-1.8), matrix(0)
        function getPedOccupiedVehicle(who) return who == cop and patrol or car end
        function getElementMatrix(e) return e.frame end
        function getElementPosition(e) return unpack(e.frame[4]) end
        function getElementType(e) return "vehicle" end
        function getElementBoundingBox(e) return -1,-2,-1,1,2,1 end
        function getElementVelocity(e) return 0,e.speed or 0,0 end
        function getVehicleHandling(e) return {steeringLock=30} end
        function getElementData(e) return 207 end
        function getNPCDriveSpeed(npc) return 0.5 end
        function getNPCPoliceAvoidance(vehicle, exempt) assert(exempt == car);return 0 end
        function getTickCount() return now end
        function recordNPCDebugTarget(_,x) aimX = x end
        function recordNPCDebugDriving() end
        function setNPCVehicleInputs(_,s,p,b) steer,pedal,brake = s,p,b end
        function setPedControlState(_,name,b) assert(name == "handbrake"); brake = b end
        for _, seed in ipairs({1,3}) do
            local direction = seed == 1 and 1 or -1
            patrol.frame[4][1], patrol.speed, now = -direction * 1.8, 0, 0
            local task, progress = {"driveAtPed",driver,seed}, {}
            performTask.driveAtPed(cop,task,16,progress)
            assert(progress.ramTurnAt == 0 and math.abs(aimX + direction*1.8) < 0.001)
            patrol.frame[4][2] = -20
            for _, t in ipairs({16,250,251}) do
                now=t; performTask.driveAtPed(cop,task,16,progress)
                assert(steer == direction and pedal == 1 and not brake)
            end
            assert(not progress.ramTurnAt)
            now=267; performTask.driveAtPed(cop,task,16,progress)
            assert(math.abs(steer) < 0.001)
            patrol.frame[4][2] = 0
        end
        -- Horizontal headings align but opposing slopes put the 3D dot below 0.5.
        car.frame[2],patrol.frame[2] = {0,0.7,0.714},{0,0.7,-0.714}
        patrol.speed = 0.4
        local progress = {}
        performTask.driveAtPed(cop,{"driveAtPed",driver,1},16,progress)
        assert(not progress.ramTurnAt and aimX > 90 and brake)
        assert(math.abs(steer - 0.5/math.rad(30)) < 0.001 and pedal == -0.5)
        local aimY
        function recordNPCDebugTarget(_, _, y) aimY=y end
        function getNPCPoliceAvoidance(vehicle,exempt) assert(not exempt);return 0.25 end
        car.speed=0.3
        performTask.drivePoliceBlock(cop,{"drivePoliceBlock",driver},16,{})
        assert(math.abs(aimY-7.8)<0.001)
    """)
    vm.execute("""
        local g=TrafficGroundPolice
        assert(g.zoneFlags(-80,930,10)==0x110 and g.zoneFlags(-140,60,4)==0x10)
        assert(g.zoneFlags(-101,930,10)==0 and g.zoneFlags(-140,60,17)==0)
        assert(not g.available({}, {suppressPolice=true,pursuitPedLimit=8,pursuitVehicleLimit=4}))
        assert(not g.available({}, {suppressGarage=true,pursuitPedLimit=8,pursuitVehicleLimit=4}))
        local a,b={stars=1},{stars=6}
        local near,far,third={x=3},{x=25},{x=18}
        assert(g.enroll(near,a) and g.enroll(far,a) and g.enroll(third,a))
        assert(g.target(near)==a and g.target(third)==a and not g.target(far))
        assert(not g.enroll({x=19},a) and not g.enroll(near,b))
        assert(g.assignVehicle({vehicle={}},b))
        local state={vehicle={}}
        assert(not g.assignVehicle(state,a))
        g.releaseOfficer(near)
        assert(g.assignVehicle(state,a) and not g.assignVehicle(state,b))
        g.releaseVehicle(state.vehicle)
        assert(g.assignVehicle(state,b))
        for level=1,6 do
            assert(g.cruiseSpeed(193,level)==({25,34,53,58,60,63})[level])
            local p={stars=level}
            local _,response=g.response(p)
            local draws={}
            for i=1,800 do
                local _,id=g.chooseVehicle(p,level,response)
                draws[id or 0]=true
            end
            if level==1 then assert(draws[0] and not draws[207])
            elseif level==2 then assert(draws[0] and draws[207])
            elseif level==3 then assert(draws[207] and not draws[0])
            elseif level==4 then assert(draws[234] and draws[207])
            elseif level==5 then assert(draws[193])
            else assert(draws[218] and draws[246]) end
        end
        now=120001
        local _,response=g.response(b)
        assert(select(2,g.chooseVehicle(b,6,response))==204 and g.viceModel()==117)
        g.commitVice()
        assert(select(2,g.chooseVehicle(b,6,response))~=204)
        assert(g.passengers(193,5)==3 and g.passengers(234,4)==3 and g.passengers(207,1)==0)
        local first={kind="vehicle",flags=130,firstLink=0,width=0,x=0,y=0,z=0}
        local graph={edition="SLUS-21590 USA v1.00",nodes={first,{x=-5,y=0,flags=0},{x=5,y=0,flags=0}},
          roadNodeCells={[30]={[25]={{kind="vehicle",x=3,y=0,z=1,flags=0,width=0}}}},
          links={{to=1,leftLanes=1,rightLanes=2},{to=2,leftLanes=1,rightLanes=2}}}
        g.start(graph)
        math.random=function(lo) return lo end
        local player={stars=4,car={},x=100}
        local batch, reply, attempts
        attempts=0
        TrafficWorld={probeRoad=function(owner,plan,fn,slot)
            assert(owner==player and slot=="roadblock")
            batch,reply=plan,fn
            attempts=attempts+1
            return true
        end,cancelRoad=function() end}
        g.step({player},now)
        assert(#world==0)
        player.x=180
        g.step({player},now)
        player.x=155
        g.step({player},now)
        assert(#world==0)
        g.step({player},now)
        assert(#world==0 and batch) -- No vehicle before the client's collision probe.
        local probes={}
        for i,p in ipairs(batch.points) do
            probes[i]={groundZ=2+p.y*.15}
        end
        local delayedRear=probes[6]
        probes[6]=nil -- The third slot has no rear support yet.
        for i=7,#batch.points,2 do probes[i]={groundZ=probes[i+1].groundZ+4} end
        reply(player,batch,{probes=probes})
        g.step({player},now)
        assert(#world==2 and world[1].model==234)
        for _,car in ipairs(world) do
            local road=2+car.y*.15
            assert(car.z>road+.99 and car.z<road+1.3 and car.pitch>7 and car.pitch<9)
        end
        g.step({player},now)
        local n=#world
        assert(n==2)
        g.step({player},now)
        assert(#world==n)
        now=now+1001
        g.step({player},now)
        assert(attempts==2 and #world==2)
        probes[6]=delayedRear
        reply(player,batch,{probes=probes})
        g.step({player},now)
        assert(#world==3,"retry must fill the missing slot once and skip steep surfaces")
        local createdGuards = 0
        PedServices={policeCrewModel=function() return 9 end}
        PedAI={attach=function() end}
        TrafficAmbient.adoptDriver=function() return true end
        exports.npc_hlc.enableHLCForNPC=function() return true end
        function setTrafficPolicePed() end
        function createPed() createdGuards=createdGuards+1; return {} end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
        player.x,player.y,player.z=world[1].x+50,world[1].y,world[1].z+40
        now=now+300
        g.step({player},now)
        assert(createdGuards==2)
        player.stars=0
        now=now+300
        g.step({player},now)
        assert(world[1].dead)
        source=b
        for _,fn in ipairs(events.onPlayerWanted) do fn(6,0) end
        assert(not g.vehicleTarget(state.vehicle))
        player.stars=3
        player.car={x=2,y=-20,vy=.1}
        local ped={x=0,y=0,z=1}
        g.prepareStinger(ped,player,{x=0,y=0},{x=0,y=5})
        player.stars=1
        player.car.vy=0
        assert(g.updateSpecial(ped,now-3000) and not ped["npchlc_traffic:stinger"])
        player.car.vy=-.1
        assert(g.updateSpecial(ped,now-2000) and not ped["npchlc_traffic:stinger"])
        player.car.vy=.1
        player.car.y=-31
        assert(g.updateSpecial(ped,now-1000) and not ped["npchlc_traffic:stinger"])
        player.car.x,player.car.y=12,-16
        assert(g.updateSpecial(ped,now-500) and not ped["npchlc_traffic:stinger"])
        player.car.x,player.car.y=2,-20
        assert(g.updateSpecial(ped,now))
        assert(g.updateSpecial(ped,now+390) and ped["npchlc_traffic:stinger"][6]==0)
        local crossing={wheels={0,2,0,0}}
        local writes=0
        function getElementsWithinRange(_,_,_,_,kind,interior,dimension)
            assert(kind=="vehicle" and interior==0 and dimension==0)
            return {crossing}
        end
        function getElementModel() return 596 end
        function getVehicleWheelStates(car) return unpack(car.wheels) end
        function setVehicleWheelStates(car,...) car.wheels={...}; writes=writes+1 end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{-.6,-1.3,.65}} end
        assert(g.updateSpecial(ped,now+391) and ped["npchlc_traffic:stinger"])
        assert(table.concat(crossing.wheels,",")=="0,2,1,0" and writes==1)
        crossing={wheels={0,2,0,0}}
        local position={-.6,-2.8,.65}
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},position} end
        function getElementVelocity(e) return 0,e==crossing and 1 or 0,0 end
        g.updateSpecial(ped,now+550)
        position[2]=.3
        g.updateSpecial(ped,now+650)
        assert(table.concat(crossing.wheels,",")=="0,2,1,0","fast front axle missed strip")
        local function pass(x,height,delay,speed)
            crossing={wheels={0,0,0,0}}
            function getElementVelocity() return 0,speed,0 end
            position={x,-4,height}
            g.updateSpecial(ped,now+800)
            position[2]=4
            g.updateSpecial(ped,now+800+delay)
            now=now+800+delay
            return table.concat(crossing.wheels,",")
        end
        assert(pass(13,.65,100,2)=="0,0,0,0","miss beside end of strip")
        assert(pass(2,4,100,2)=="0,0,0,0","elevated wheels")
        assert(pass(2,.65,100,0)=="0,0,0,0","discontinuous transform")
        assert(pass(2,.65,400,2)=="0,0,0,0","stale transform")
        assert(pass(2,.65,100,2)=="1,1,1,1","both axles crossed")
        local postCrossingWrites=writes
        assert(not g.updateSpecial(ped,now+2501))
        assert(writes==postCrossingWrites)
        player.interior=1
        assert(not g.updateSpecial(ped,now+2502) and not ped["npchlc_traffic:stinger"])
        now=now+3000
        player.interior=0
        g.prepareStinger(ped,player,{x=0,y=0},{x=0,y=5})
        crossing={wheels={0,0,0,0}}
        position={6,-1.3,.65}
        assert(g.updateSpecial(ped,now))
        assert(g.updateSpecial(ped,now+391))
        assert(table.concat(crossing.wheels,",")=="0,0,0,0","wheel ahead of opening strip")
        assert(not g.updateSpecial(ped,now+2501))
        assert(table.concat(crossing.wheels,",")=="1,0,1,0","extended slats reached front wheels")
        g.stop()
    """)
    vm.execute((resources / "[traffic]/npchlc_traffic/ped_models/models.lua").read_text(encoding="utf-8"))
    vm.execute((resources / "[traffic]/npchlc_traffic/traffic_model_bindings.lua").read_text(encoding="utf-8"))
    vm.globals().handlingData = (resources / "[model]/vcs_vehicle/data/handling.dat").read_text(encoding="ascii")
    vm.execute((resources / "[model]/vcs_vehicle/data/paint.lua").read_text(encoding="utf-8"))
    vm.execute((resources / "[model]/vcs_vehicle/vehicle_s.lua").read_text(encoding="utf-8"))
    vm.execute("""
        function getResourceFromName() return false end
        function getThisResource() return {} end
        function getResourceName() return "npchlc_traffic" end
        function getElementType(e) return e.kind end
        function getElementData(e,k) return e[k] end
        local reads,writes=0,0
        function fileOpen(path,readonly) assert(path=="data/handling.dat" and readonly);return {} end
        function fileGetSize() return #handlingData end
        function fileRead(_,size) assert(size==#handlingData);reads=reads+1;return handlingData end
        function fileClose() end
        exports.vcs_vehicle={getVcsHandlingData=getVcsHandlingData,
            bindVcsVehiclePaint=function(_,car,id)
                assert(car["npchlc_traffic:originalModel"]==id)
                car.painted=true
            end,
            configureVcsDashboardBeacon=function(_,e,id) return configureVcsDashboardBeacon(e,id) end}
        function getVehicleHandling(e) return e end
        function setVehicleHandling(e,key,value) e[key]=value;writes=writes+1;return true end
        function addVehicleSirens(e,count,kind,allSides,los,random,silent)
            assert(count==1 and kind==2 and not silent);e.beacon=true;return true
        end
        function setVehicleSirens(e,index,x,y,z) assert(e.beacon and index==1 and z<.3);return true end
        TrafficModelBindings.load({edition="SLUS-21590 USA v1.00"})
        for original,base in pairs({[9]=285,[10]=286,[11]=287,[117]=126,[118]=127,[119]=284}) do
            assert(TrafficModelBindings.getPedestrian(original)==base)
        end
        assert(TrafficGroundPolice.passengers(218,6)==1)
        local expected={
            [191]={800,190,40,"rwd"},[193]={1800.7,200,25,"rwd"},[204]={1400,200,33,"rwd"},
            [207]={1750,160,24,"rwd"},[218]={10500,180,20,"awd"},[219]={2200,190,1.7,"rwd"},
            [234]={2600,155,24,"awd"},[246]={25000,80,40,"awd"}}
        for original,base in pairs({[191]=523,[193]=598,[204]=597,[207]=596,[218]=433,[219]=430,[234]=427,[246]=432,[261]=497}) do
            assert(TrafficModelBindings.get(original)==base)
            local car={kind="vehicle"}
            TrafficModelBindings.tag(car,original)
            assert(car.painted)
            local row=expected[original]
            if row then
                assert(car.mass==row[1] and car.maxVelocity==row[2] and car.engineAcceleration==row[3]*.4 and car.driveType==row[4])
                assert(car.centerOfMass and car.steeringLock)
                assert((car.suspensionForceLevel~=nil)==(original~=219 and original~=191))
            else assert(not car.mass) end
            assert(not car.modelFlags and not car.handlingFlags and not car.animGroup)
            local previous=writes
            TrafficModelBindings.tag(car,original)
            assert(writes==previous and reads==1)
            if original==193 or original==204 then
                assert(car.beacon and car["npchlc_traffic:modelProvider"]=="npchlc_traffic")
            end
        end
        local ordinary={kind="vehicle"}
        TrafficModelBindings.tag(ordinary,171)
        assert(not ordinary.mass)
        assert(getVcsHandlingData()==handlingData and reads==1)
    """)
    vm.execute("""
        sourceResource={}
        PedAI={brain=function(p) return p.brain end}
        function getElementModel(e) return e.model end
        function getElementData(e,k) return e[k] end
        function isVehicleBlown() return false end
        function isPedInVehicle(e) return e.seated end
        function getElementType(e) return e.kind end
        function getElementRotation() return 0,0,60 end
        function setElementRotation(e,_,_,heading) e.heading=heading end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        function getElementAttachedTo(e) return e.truck end
        function attachElements(e,t,x,y,z,_,_,facing)
            if e.fail then return false end
            e.truck,e.x,e.y,e.z,e.heading=t,x,y,z,facing
            return true
        end
        function detachElements(e,t) assert(e.truck==t); e.truck=nil end
    """)
    vm.execute((resources/"[traffic]/npchlc_traffic/mission_barracks_s.lua").read_text())
    vm.execute("""
        local t={kind="vehicle",model=433}
        local a,b,c={kind="ped",x=20,y=3,z=1},{kind="ped"},{kind="ped",fail=true}
        assert(not mountPhilBarracksRiders(t,a,a,c))
        assert(not mountPhilBarracksRiders(t,a,b,c))
        assert(not a.truck and not b.truck and a.x==20 and a.heading==60)
        c.fail=false
        assert(mountPhilBarracksRiders(t,a,b,c) and mountPhilBarracksRiders(t,a,b,c))
        assert(a.x==.75 and b.x==-.75 and c.y==-4 and c.heading==180)
        local owner=sourceResource; sourceResource={}
        assert(not unmountPhilBarracksRiders(t))
        sourceResource=owner
        assert(unmountPhilBarracksRiders(t) and not a.truck and not c.truck)
        c.brain={scriptOwner={}}
        assert(not mountPhilBarracksRiders(t,a,b,c) and not a.truck)
    """)
    vm.execute((resources/"[traffic]/npchlc_traffic/ped_services.lua").read_text())
    vm.execute("""
        local arrive=events["npc_hlc:onDriverDoorArrival"][1]
        local name,workers=debug.getupvalue(arrive,1)
        assert(name=="workers")
        local car,suspect={},{}
        source={x=-10,y=0,z=0}
        now=10000
        local w={target=suspect,door=car,follow=true,doorAssigned=now,doorOrder=2}
        workers[source]=w
        local eligible,locked=true,false
        TrafficGroundPolice.target=function() return suspect end
        TrafficWanted.officerCanPursue=function() return eligible end
        TrafficWanted.driverArrestCar=function() return not locked and car end
        TrafficWanted.driverDoorApproach=function() return -1.55,.4 end
        function getElementMatrix() return {{1,0,0},{0,1,0},{0,0,1},{0,0,0}} end
        arrive(car,2); assert(source.x==-10) -- impossible travel time
        now=now+2500
        arrive(car,1); arrive({},2); assert(source.x==-10)
        locked=true; arrive(car,2); locked=false
        eligible=false; arrive(car,2); eligible=true
        assert(source.x==-10)
        source.x=-35; arrive(car,2); assert(source.x==-35)
        source.x,source.z=-10,4; arrive(car,2); assert(source.x==-10)
        source.z=0; arrive(car,2); assert(source.x==-1.55 and source.y==.4 and not w.doorOrder)
        source.x=-12; arrive(car,2); assert(source.x==-12)
    """)
    print("Verified six dispatch tiers, roadblocks, stingers, driver-door synchronization and mission Barracks attachments")


if __name__ == "__main__":
    main()
