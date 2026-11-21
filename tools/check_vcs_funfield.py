"""Motion regression and isolated real-client acceptance fixture for funfield."""
import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "mods/deathmatch/resources/[feature]/funfield"


def check_motion():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    for path in RESOURCE.glob("*.lua"):
        function, error = lua.eval("function(s) local f,e=loadstring(s); return f,e end")(path.read_text())
        assert function, (path, error)
    lua.execute((RESOURCE / "wheel.lua").read_text())
    lua.execute("""
        local s=Ferris.new()
        for n=1,150 do Ferris.advance(s,Ferris.step) end
        assert(math.abs(s.speed-0.05)<1e-9)
        assert(Ferris.stop(s))
        local target=s.target
        for n=1,2000 do
            local old=s.angle
            Ferris.advance(s,Ferris.step)
            assert(s.angle>=old and s.angle<=target+1e-9)
            if s.phase=='stopped' then break end
        end
        assert(s.phase=='stopped' and s.speed==0 and s.angle==target)
        assert(math.abs(s.angle/Ferris.spacing-math.floor(s.angle/Ferris.spacing+0.5))<1e-8)
        for index=0,11 do
            s.phase='running'; s.speed=.05
            assert(Ferris.stop(s,Ferris.nextStop(s,index)))
            for n=1,5000 do
                Ferris.advance(s,Ferris.step)
                if s.phase=='stopped' then break end
            end
            assert(s.phase=='stopped')
            local x,y,z=Ferris.position(s,index)
            assert(math.abs(y-Ferris.y)<1e-8 and math.abs(z-(Ferris.z-23))<1e-8)
            assert(Ferris.rider(s,x,y,z-2.15)==index)
            for seat=1,4 do
                local m=Ferris.seatMatrix(s,index,seat)
                assert(#m==4 and #m[1]==4 and #m[4]==4 and m[4][4]==1)
                local offset=Ferris.seats[seat]
                assert(math.abs(m[4][3]-(z+math.sin(s.swing)*offset[2]+math.cos(s.swing)*offset[3]))<1e-8)
                local dy=y-m[4][2]
                assert(m[2][2]*dy>0) -- both rows face into the aisle
            end
        end
        for _,fps in ipairs({20,30,60,144}) do
            local a,acc=Ferris.new(),0
            for frame=1,fps*120 do
                acc=acc+1/fps
                while acc+1e-10>=Ferris.step do
                    Ferris.advance(a,Ferris.step); acc=acc-Ferris.step
                end
            end
            assert(math.abs(a.angle-5.8758333333333)<0.002)
            assert(math.abs(a.swing)<0.001)
        end
        local long=Ferris.new()
        for n=1,54000 do Ferris.advance(long,Ferris.step) end
        assert(long.angle==long.angle and long.swing==0 and long.swingSpeed==0)
    """)
    meta=ET.parse(RESOURCE / "meta.xml")
    for element in meta.getroot():
        if element.tag in ("script", "file"):
            assert (RESOURCE / element.attrib["src"]).is_file()
    manifest=json.loads((RESOURCE / "assets/manifest.json").read_text())
    import hashlib
    for name, entry in manifest["assets"].items():
        assert hashlib.sha256((RESOURCE / "assets" / name).read_bytes()).hexdigest()==entry["sha256"]
    print("FUNFIELD_MOTION_PASS: 12 stop targets; 20/30/60/144 fps; 30-minute stability; Lua syntax; asset hashes")


def check_players():
    """Exercise server ownership and native-event boundaries with two players."""
    from lupa.lua51 import LuaRuntime
    lua=LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        root={}; resourceRoot={}; clock=1000; handlers={}; packets={}; players={}; timers={}
        exports={npchlc_traffic={getTrafficPopulationAt=function() return false end,
            acquireTrafficPedInArea=function() return false end}}
        function getTickCount() return clock end
        function getThisResource() return 'funfield' end
        function getResourceFromName(name) return name end
        function getResourceName(name) return name end
        function getResourceState() return 'running' end
        function isElement(p) return type(p)=='table' and not p.destroyed end
        function getElementType(p) return p.kind end
        function isPedDead(p) return p.health<=0 end
        function getElementHealth(p) return p.health end
        function getElementInterior(p) return p.interior or 0 end
        function getElementDimension(p) return p.dimension or 0 end
        function isPedInVehicle(p) return p.vehicle~=nil end
        function getElementPosition(p) return unpack(p.pos) end
        function setElementPosition(p,x,y,z) p.pos={x,y,z} end
        function setElementMatrix(p,m) assert(#m==4 and #m[4]==4); p.pos={unpack(m[4],1,3)} end
        function isElementFrozen(p) return p.frozen or false end
        function setElementFrozen(p,v) p.frozen=v end
        function getElementCollisionsEnabled(p) return p.collisions~=false end
        function setElementCollisionsEnabled(p,v) p.collisions=v end
        function setElementVelocity(p,...) p.velocity={...} end
        function setElementData(p,k,v) p[k]=v end
        function setPedRotation() end
        function getTime() return 12 end
        function addEvent() end
        function addEventHandler(name,element,fn)
            handlers[name]=handlers[name] or {}; table.insert(handlers[name],fn)
        end
        function setTimer(fn,delay) timers[delay]=fn end
        function getElementsByType(kind) return kind=='player' and players or {} end
        function triggerClientEvent(target,name,eventSource,...) packets[#packets+1]={target=target,name=name,args={...}} end
        function outputDebugString() end
        function cancelEvent() cancelled=true end
        function fire(name,player,origin,...)
            client=player; source=origin; cancelled=false
            for _,fn in ipairs(handlers[name] or {}) do fn(...) end
        end
        function tick() clock=clock+34; timers[33]() end
    ''')
    lua.execute((RESOURCE / "wheel.lua").read_text())
    lua.execute((RESOURCE / "server.lua").read_text())
    lua.execute(r'''
        local function makePlayer()
            local p={kind='player',health=100,pos={Ferris.x,Ferris.y,Ferris.z-23-2.15}}
            players[#players+1]=p
            fire('funfield:ready',p,resourceRoot)
            return p
        end
        local a,b=makePlayer(),makePlayer()
        fire('funfield:seat',a,resourceRoot,false)
        fire('funfield:seat',b,resourceRoot,false)
        local state=getFerrisWheelState()
        assert(#state.players==2)
        assert(state.players[1].seat~=state.players[2].seat)
        assert(not a.frozen and not b.frozen and not a.collisions and not b.collisions)
        fire('funfield:greeting',a,{},false)
        for _,r in ipairs(getFerrisWheelState().players) do assert(not r.greetingAt) end
        fire('funfield:greeting',a,resourceRoot,false)
        local greetingAt
        for _,r in ipairs(getFerrisWheelState().players) do
            if r.ped==a then greetingAt=r.greetingAt assert(r.greetingUntil-greetingAt==1200) end
        end
        assert(greetingAt)
        fire('funfield:greeting',a,resourceRoot,false)
        for _,r in ipairs(getFerrisWheelState().players) do if r.ped==a then assert(r.greetingAt==greetingAt) end end
        fire('onVehicleStartEnter',nil,{},a)
        assert(cancelled)
        local function acknowledgements()
            local n=0
            for _,p in ipairs(packets) do if p.target==a and p.name=='funfield:exitQueued' then n=n+1 end end
            return n
        end
        fire('funfield:exit',a,resourceRoot)
        fire('funfield:exit',a,resourceRoot)
        assert(acknowledgements()==1)
        fire('funfield:seat',a,resourceRoot,false)
        assert(not a.frozen and a.collisions and not a['funfield:seated'])
        assert(a.velocity and #a.velocity==3)
        local last=packets[#packets-1] -- stood notification precedes the broadcast snapshots
        local stood=false
        for _,packet in ipairs(packets) do
            if packet.target==a and packet.name=='funfield:stood' and packet.args[1]==nil then stood=true end
        end
        assert(stood and #getFerrisWheelState().players==1)
        a.pos={Ferris.x-8,Ferris.y,Ferris.z-23-4}
        tick()
        assert(getFerrisWheelState().phase~='stopping') -- abandoned stop is cancelled
        fire('onVehicleStartEnter',nil,{},a); assert(cancelled) -- F action window
        clock=clock+1000
        fire('onVehicleStartEnter',nil,{},a); assert(not cancelled)
        b.dimension=7
        local z=b.pos[3]
        tick()
        assert(#getFerrisWheelState().players==0 and not b.frozen and b.collisions and b.pos[3]==z)
        b.dimension=0; b.pos={Ferris.x,Ferris.y,Ferris.z-23-2.15}
        fire('funfield:seat',b,resourceRoot,false)
        assert(#getFerrisWheelState().players==1)
        fire('onPlayerWasted',nil,b)
        assert(#getFerrisWheelState().players==0 and not b.frozen and b.collisions)
        b.pos={Ferris.x,Ferris.y,Ferris.z-23-2.15}
        fire('funfield:seat',b,{},false) -- spoofed event source is ignored
        assert(#getFerrisWheelState().players==0)
        fire('funfield:seat',b,resourceRoot,false)
        fire('onPlayerSpawn',nil,b)
        assert(#getFerrisWheelState().players==0 and not b.frozen and b.collisions)
        b.pos={Ferris.x,Ferris.y,Ferris.z-23-2.15}
        fire('funfield:seat',b,resourceRoot,false)
        b.health=90
        tick()
        assert(#getFerrisWheelState().players==0 and b.collisions and not b.frozen)
    ''')
    print("FUNFIELD_PLAYERS_PASS: exclusive seats; F stand release; vehicle-entry cancellation; world/death/spawn cleanup")


SERVER = r'''
local testPlayer
local commandSequence
local function prepare(player)
    if getElementData(player,"funfield:seated") then
        setElementHealth(player,0)
        setTimer(prepare,200,1,player)
        return
    end
    spawnPlayer(player,337.69,-243.22,12.2,270,0,0,0)
    fadeCamera(player,true)
    setCameraTarget(player,player)
    setTime(12,0)
    setWeather(0)
    triggerClientEvent(player,"funfieldQA:begin",resourceRoot)
end
addEvent("funfieldQA:ready",true)
addEventHandler("funfieldQA:ready",resourceRoot,function()
    if not client then return end
    testPlayer=client
    outputDebugString("FUNFIELD_QA_CLIENT_READY "..getPlayerName(client))
    if getElementData(client,"funfield:seated") then
        triggerClientEvent(client,"funfieldQA:begin",resourceRoot,true)
    else prepare(client) end
end)
setTimer(function()
    if not fileExists("control.json") then return end
    local f=fileOpen("control.json",true)
    if not f then return end
    local c=fromJSON(fileRead(f,fileGetSize(f))) fileClose(f)
    if not c or c.sequence==commandSequence then return end
    commandSequence=c.sequence
    fileDelete("control.json")
    if c.action=="restartWheel" then restartResource(getResourceFromName("funfield"))
    elseif c.action=="restartProbe" then restartResource(getThisResource())
    elseif c.action=="run" and isElement(testPlayer) then prepare(testPlayer)
    elseif c.action=="cleanup" and isElement(testPlayer) then
        triggerClientEvent(testPlayer,"funfieldQA:control",resourceRoot,{stop=true,report="FINAL_CLEANUP"})
        setTimer(setCameraTarget,250,1,testPlayer,testPlayer)
    elseif c.action=="death" and isElement(testPlayer) then killPed(testPlayer)
    elseif c.action=="damage" and isElement(testPlayer) then setElementHealth(testPlayer,getElementHealth(testPlayer)-10)
    elseif c.action=="world" and isElement(testPlayer) then setElementDimension(testPlayer,7)
    elseif c.action=="vehicleCheck" and isElement(testPlayer) then
        local x,y,z=getElementPosition(testPlayer)
        local car=createVehicle(411,x+3,y,z)
        local allowed=triggerEvent("onVehicleStartEnter",car,testPlayer,0,false,0)
        outputDebugString("FUNFIELD_QA_SERVER_VEHICLE_GUARD "..toJSON({allowed=allowed,seated=getElementData(testPlayer,"funfield:seated")}))
        destroyElement(car)
    elseif c.action=="client" and isElement(testPlayer) then triggerClientEvent(testPlayer,"funfieldQA:control",resourceRoot,c) end
end,500,0)
addEvent("funfieldQA:sample",true)
addEventHandler("funfieldQA:sample",resourceRoot,function(value)
    if client==testPlayer then outputDebugString("FUNFIELD_QA "..toJSON(value,true)) end
end)
addEvent("funfieldQA:shot",true)
addEventHandler("funfieldQA:shot",resourceRoot,function(tag)
    if client==testPlayer and type(tag)=="string" and tag:match("^wheel%-%w[%w%-]*$") then
        takePlayerScreenShot(client,960,600,tag,90,1200000)
    end
end)
addEventHandler("onPlayerScreenShot",root,function(resource,status,data,timestamp,tag)
    if resource~=getThisResource() or source~=testPlayer or status~="ok" then
        outputDebugString("FUNFIELD_QA_SCREENSHOT_FAILURE "..tostring(status)) return
    end
    local file=fileCreate(tag..".jpg")
    if file then fileWrite(file,data) fileClose(file) outputDebugString("FUNFIELD_QA_SCREENSHOT "..tag) end
end)
'''

CLIENT = r'''
local phase="loading"
local started,phaseAt,boardStart
local samples=0
local baseline
local inspection
local function report(kind,extra)
    if getResourceState(getResourceFromName("funfield"))~="running" then return end
    local s=exports.funfield:getFerrisWheelState()
    if not s then return end
    local x,y,z=getElementPosition(localPlayer)
    local contact=getPedContactElement(localPlayer)
    triggerServerEvent("funfieldQA:sample",resourceRoot,{kind=kind,phase=phase,x=x,y=y,z=z,
        wheel=s.phase,angle=s.angle,riding=s.riding,contact=contact and getElementID(contact),
        fps=getFPSLimit(),extra=extra,npcs=s.npcCount,spectators=s.spectatorCount,seated=s.seated,
        frozen=isElementFrozen(localPlayer),collisions=getElementCollisionsEnabled(localPlayer),health=getElementHealth(localPlayer),
        dimension=getElementDimension(localPlayer),jumpEnabled=isControlEnabled("jump"),
        forwardEnabled=isControlEnabled("forwards"),exitQueued=s.exitQueued,
        lod=isElement(s.lod) and getElementID(s.lod) or false})
end
local function shot(tag)
    triggerServerEvent("funfieldQA:shot",resourceRoot,tag)
end
addEvent("funfieldQA:begin",true)
addEventHandler("funfieldQA:begin",resourceRoot,function(resume)
    phase=resume and "inspect" or "loading"
    started=getTickCount()
    phaseAt=started
    setCameraMatrix(326,-243.22,14,342,-243.22,12)
    setFPSLimit(60)
end)
addEvent("funfieldQA:control",true)
addEventHandler("funfieldQA:control",resourceRoot,function(c)
    if c.camera then setCameraMatrix(unpack(c.camera)) end
    if c.shot then shot(c.shot) end
    if c.actionKey then executeCommandHandler(c.actionKey) end
    if c.position then setElementPosition(localPlayer,unpack(c.position)) end
    if c.fps then setFPSLimit(c.fps) end
    if c.jump then setPedControlState(localPlayer,"jump",true) setTimer(setPedControlState,200,1,localPlayer,"jump",false) end
    if c.stop then phase="done" setPedControlState(localPlayer,"forwards",false) end
    if c.report then report(c.report) end
    if c.vehicleCheck then
        local x,y,z=getElementPosition(localPlayer)
        local car=createVehicle(411,x+3,y,z)
        local allowed=triggerEvent("onClientVehicleStartEnter",car,localPlayer,0,0)
        report("CLIENT_VEHICLE_GUARD",{allowed=allowed,seated=s and s.seated})
        destroyElement(car)
    end
    if c.edgeFall then
        inspection=nil
        phase="edgeFall" phaseAt=getTickCount()
        local x,y,z=getElementPosition(localPlayer)
        baseline=z
        setCameraMatrix(x+8,y,z+2,x-8,y,z)
        executeCommandHandler("exitferris")
        setTimer(executeCommandHandler,150,1,"sitferris")
        setTimer(setPedControlState,220,1,localPlayer,"jump",true)
        setTimer(setPedControlState,420,1,localPlayer,"jump",false)
        setTimer(setPedControlState,250,1,localPlayer,"forwards",true)
        setTimer(setPedControlState,1700,1,localPlayer,"forwards",false)
        report("JUMP_CASE_START")
    end
    if c.inspect then
        local s=exports.funfield:getFerrisWheelState()
        local selected
        for _,r in ipairs(c.subject=="player" and s.players or s.riders) do
            if (c.subject~="player" or r.ped==localPlayer) and (not c.row or (r.seat<=2 and 1 or 2)==c.row) then selected=r break end
        end
        if selected then
            inspection={record=selected,shotAt=getTickCount()+1500,ends=getTickCount()+2200,
                tag=c.inspect,view=c.view or "door"}
            phase="inspect"
            setPedControlState(localPlayer,"forwards",false)
        else report("INSPECTION_NO_SUBJECT",c.subject) end
    end
end)
addEventHandler("onClientPreRender",root,function()
    if not inspection or getTickCount()>inspection.ends then return end
    local r=inspection.record
    local s=exports.funfield:getFerrisWheelState()
    local car=s.carriages[r.index]
    if not isElement(car) or not isElement(r.ped) then return end
    local x,y,z=getElementPosition(car)
    local px,py,pz=getElementPosition(r.ped)
    local side=inspection.view=="front" and 3 or inspection.view=="rear" and -3 or -1.8
    setCameraMatrix(x-3.6,y+side,z-0.7,px,py,pz+0.35)
    if not inspection.shot and getTickCount()>=inspection.shotAt then
        inspection.shot=true shot(inspection.tag)
    end
end,true,"low")
addEventHandler("onClientPedsProcessed",root,function()
    if not inspection or inspection.measured or getTickCount()<inspection.shotAt then return end
    local r=inspection.record
    local s=exports.funfield:getFerrisWheelState()
    local car=s.carriages[r.index]
    if not isElement(car) or not isElement(r.ped) then return end
    local cm=getElementMatrix(car)
    local pm=getElementMatrix(r.ped)
    local sample={seat=r.seat,index=r.index,subject=r.ped==localPlayer and "player" or "npc",
        animation={getPedAnimation(r.ped)},position={getElementPosition(r.ped)},bones={},forward=pm[2]}
    for _,bone in ipairs({2,3,8,41,42,43,44,51,52,53,54}) do
        local bm=getElementBoneMatrix(r.ped,bone)
        if bm then
            local dx,dy,dz=bm[4][1]-cm[4][1],bm[4][2]-cm[4][2],bm[4][3]-cm[4][3]
            sample.bones[tostring(bone)]={dx*cm[1][1]+dy*cm[1][2]+dz*cm[1][3],
                dx*cm[2][1]+dy*cm[2][2]+dz*cm[2][3],dx*cm[3][1]+dy*cm[3][2]+dz*cm[3][3]}
        end
    end
    triggerServerEvent("funfieldQA:sample",resourceRoot,{kind="POSE",measurement=sample})
    inspection.measured=true
end,true,"low-100")
addEventHandler("onClientResourceStart",resourceRoot,function()
    setTimer(function() triggerServerEvent("funfieldQA:ready",resourceRoot) end,2500,1)
end)
setTimer(function()
    if not started then return end
    local resource=getResourceFromName("funfield")
    if not resource or getResourceState(resource)~="running" then return end
    local now=getTickCount()
    local s=exports.funfield:getFerrisWheelState()
    if not s then return end
    if phase~="done" and now-phaseAt>180000 then report("TIMEOUT") phase="done" setPedControlState(localPlayer,"forwards",false) end
    if phase=="loading" and s.ready then
        phase="waiting" phaseAt=now report("MAP_READY") shot("wheel-npc-overview-front")
    elseif phase=="waiting" and s.phase=="stopped" then
        phase="boarding" phaseAt=now
        local x,y,z=getElementPosition(localPlayer)
        setCameraMatrix(x-8,y,z+2,x+8,y,z)
        setPedRotation(localPlayer,270)
        setPedControlState(localPlayer,"forwards",true)
        report("WALK_BOARD_START")
    elseif phase=="boarding" then
        local x=getElementPosition(localPlayer)
        if x>341.9 or now-phaseAt>4500 then
            setPedControlState(localPlayer,"forwards",false)
            phase="sitting" phaseAt=now
            report("WALK_BOARD_END") shot("wheel-player-boarding-side")
            setTimer(executeCommandHandler,400,1,"sitferris")
        end
    elseif phase=="sitting" then
        if s.seated then
            phase="riding" phaseAt=now
            report("SIT_CONFIRMED") shot("wheel-player-seated-side")
        elseif now-phaseAt>3000 then report("SIT_FAILED") phase="done" end
    elseif phase=="riding" then
        if now-phaseAt>15000 then
            report("RIDE_60FPS_END") shot("wheel-player-riding-side")
            setFPSLimit(30)
            phase="riding30" phaseAt=now
        end
    elseif phase=="riding30" and now-phaseAt>15000 then
        report("RIDE_30FPS_END")
        setFPSLimit(144)
        phase="riding144" phaseAt=now
    elseif phase=="riding144" and now-phaseAt>15000 then
        report("RIDE_HIGHFPS_END")
        executeCommandHandler("exitferris")
        phase="exit" phaseAt=now report("EXIT_REQUESTED")
    elseif phase=="exit" and s.phase=="stopped" and s.exitReady then
        report("EXIT_STOP") shot("wheel-player-exit-platform")
        executeCommandHandler("sitferris")
        phase="standing" phaseAt=now
    elseif phase=="standing" and not s.seated then
        report("STAND_CONFIRMED")
        phase="leaving" phaseAt=now
        local x,y,z=getElementPosition(localPlayer)
        setCameraMatrix(x+8,y,z+2,x-8,y,z)
        setPedRotation(localPlayer,90)
        setPedControlState(localPlayer,"forwards",true)
    elseif phase=="leaving" and now-phaseAt>2500 then
        setPedControlState(localPlayer,"forwards",false)
        setCameraTarget(localPlayer)
        setFPSLimit(60)
        local x=getElementPosition(localPlayer)
        report(x<340 and not s.riding and "COMPLETE" or "EXIT_WALK_FAILED")
        shot("wheel-player-exited-front") phase="done"
    elseif phase=="edgeFall" then
        local x,y,z=getElementPosition(localPlayer)
        local vx,vy,vz=getElementVelocity(localPlayer)
        if z<baseline-2 and vz<-.02 and not s.seated and not s.riding then
            report("JUMP_FALL_CONFIRMED") shot("wheel-player-jump-falling-side")
            phase="edgeLanding" phaseAt=now
        elseif now-phaseAt>7000 then report("JUMP_CASE_FAILED") phase="done" end
    elseif phase=="edgeLanding" and now-phaseAt>6000 then
        report("JUMP_LANDED") shot("wheel-player-jump-landed-front")
        phase="done" setCameraTarget(localPlayer)
    end
    if phase~="done" then
        samples=samples+1
        if samples%5==0 then report("TRACE") end
        local x,y,z=getElementPosition(localPlayer)
        if phase=="riding" or phase=="riding30" or phase=="riding144" or phase=="exit" or phase=="edgeLanding" then
            setCameraMatrix(x-10,y-14,z+5,x,y,z)
        end
    end
end,200,0)
addEventHandler("onClientResourceStop",resourceRoot,function()
    setPedControlState(localPlayer,"forwards",false)
    setPedControlState(localPlayer,"jump",false)
    setCameraTarget(localPlayer)
    setFPSLimit(60)
end)
'''


def port(kind):
    with socket.socket(socket.AF_INET,kind) as sock:
        sock.bind(("127.0.0.1",0))
        return sock.getsockname()[1]


def stage_live():
    stage=Path(tempfile.mkdtemp(prefix="mta-vcs-funfield-"))
    dm=stage / "mods/deathmatch"
    resources=dm / "resources"
    resources.mkdir(parents=True)
    shutil.copy2(ROOT / "MTA Server64.exe",stage)
    shutil.copytree(ROOT / "x64",stage / "x64")
    for name in ("acl.xml","vehiclecolors.conf"):
        shutil.copy2(ROOT / "mods/deathmatch" / name,dm / name)
    inventory={p.parent.name:p.parent for p in (ROOT / "mods/deathmatch/resources").rglob("meta.xml")}
    selected=set()
    startup=[]
    def copy_resource(name):
        if name in selected: return
        selected.add(name)
        source=inventory[name]
        # Binary asset hardlinks are read-only inputs. All editable configs/scripts
        # and the server's writable databases remain independent copies.
        def copy_file(src,dst):
            if Path(src).suffix.lower() in (".img",".dff",".txd",".col",".png",".wav",".ogg",".ifp"):
                try: os.link(src,dst); return dst
                except OSError: pass
            return shutil.copy2(src,dst)
        shutil.copytree(source,resources / name,copy_function=copy_file,
                        ignore=shutil.ignore_patterns(".git","*.db","*.db-journal","__pycache__"))
        for include in ET.parse(source / "meta.xml").getroot().findall("include"):
            copy_resource(include.attrib["resource"])
        startup.append(name)
    for name in ("funfield","vcs_model","skygfx","water"):
        copy_resource(name)
    probe=resources / "funfield_qa"
    probe.mkdir()
    (probe / "meta.xml").write_text('<meta><include resource="funfield"/><script src="server.lua" type="server"/><script src="client.lua" type="client"/></meta>')
    (probe / "server.lua").write_text(SERVER)
    (probe / "client.lua").write_text(CLIENT)
    acl=ET.parse(dm / "acl.xml")
    group=ET.SubElement(acl.getroot(),"group",name="FerrisAcceptance")
    ET.SubElement(group,"object",name="resource.funfield_qa")
    ET.SubElement(group,"acl",name="FerrisAcceptance")
    rights=ET.SubElement(acl.getroot(),"acl",name="FerrisAcceptance")
    ET.SubElement(rights,"right",name="function.restartResource",access="true")
    acl.write(dm / "acl.xml",encoding="utf-8")
    config=ET.parse(ROOT / "mods/deathmatch/mtaserver.conf")
    root=config.getroot()
    for item in root.findall("resource"): root.remove(item)
    game_port=port(socket.SOCK_DGRAM)
    settings={"servername":"VCS Ferris Wheel isolated QA","serverip":"127.0.0.1", "serverport":game_port,
              "httpport":port(socket.SOCK_STREAM),"httpdownloadurl":"","ase":0,"maxplayers":8,
              "password":"","scriptdebugloglevel":3,"fpslimit":144}
    for key,value in settings.items():
        node=root.find(key)
        if node is None: node=ET.SubElement(root,key)
        node.text=str(value)
    for name in startup+["funfield_qa"]:
        ET.SubElement(root,"resource",src=name,startup="1",protected="0")
    config.write(dm / "mtaserver.conf",encoding="utf-8")
    result={"stage":str(stage),"port":game_port}
    (Path(tempfile.gettempdir()) / "funfield-qa-state.json").write_text(json.dumps(result))
    print(json.dumps(result))


if __name__=="__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage-live",action="store_true")
    args=parser.parse_args()
    check_motion()
    check_players()
    if args.stage_live: stage_live()
