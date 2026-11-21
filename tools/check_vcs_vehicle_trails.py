"""Check VCS lamp streak behavior; optionally run isolated real-client acceptance."""

import argparse
import json
import os
import re
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
SKY = ROOT / "mods/deathmatch/resources/[graphic]/skygfx"
EVIDENCE = ROOT / "docs/qa/vcs-vehicle-trails"
CLIENT_LOG = Path("D:/Game/MTA San Andreas 1.7/MTA/logs/clientscript.log")


def check_logic():
    from lupa.lua51 import LuaRuntime
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute(r'''
        root, resourceRoot, localPlayer = {}, {}, {}
        SKYGFX = {vehicleLightTrails=true}
        car={kind="vehicle",model=400,lights=true,dimension=0,interior=0,alpha=255,lightStates={},x=0}
        cars={car}; tick=0; screenW=960; screenH=600; cameraY=10; occluded=false; blend="blend"; draws={}; events={}
        function isElement(e) return e and not e.destroyed end
        function getElementType(e) return e.kind end
        function isElementStreamedIn(e) return not e.out end
        function getElementsByType() return cars end
        function getElementModel(e) return e.model end
        function getVehicleDummyPosition(e, name) return 1, name=="light_front_main" and 2 or -2, 1 end
        function getVehicleHandling() return {modelFlags=0} end
        function bitAnd() return 0 end
        function getElementDimension(e) return e.dimension or 0 end
        function getElementInterior(e) return e.interior or 0 end
        function getElementAlpha(e) return e.alpha end
        function getCameraInterior() return 0 end
        function getElementMatrix(e) return {{1,0,0},{0,1,0},{0,0,1},{e.x,0,0}} end
        function getCameraMatrix() return 0,cameraY,3, 0,0,1, 0,70 end
        function guiGetScreenSize() return screenW,screenH end
        function getTickCount() return tick end
        function isMainMenuActive() return false end
        function areVehicleLightsOn(e) return e.lights end
        function getElementVelocity() return 0,speed or 0,0 end
        function getVehicleController() return driver end
        function getPedControlState() return brake end
        function getVehicleCurrentGear() return gear or 1 end
        function getVehicleLightState(e,i) return e.lightStates[i] or 0 end
        function getScreenFromWorldPosition(x,y,z) return 400+x*10,300+z end
        function isLineOfSightClear() return not occluded end
        function tocolor(r,g,b,a) return {r,g,b,a} end
        function dxGetBlendMode() return blend end
        function dxSetBlendMode(b) blend=b end
        function dxCreateShader() if failShader then return false end return {kind="shader"} end
        function outputDebugString() end
        function destroyElement(e) e.destroyed=true end
        function dxDrawMaterialPrimitive(kind,material,post,...)
            assert(kind=="linelist" and not post and blend=="add")
            assert(isElement(material) and material.kind=="shader")
            draws[#draws+1]={...}; return true
        end
        function addEventHandler(name,root,fn) events[name]=fn end
        function removeEventHandler(name) events[name]=nil end
        function frame() tick=tick+33; car.x=car.x+0.05; draws={}; VCSVehicleTrails.render(); assert(blend=="blend") end
    ''')
    for path in (SKY / "pipeline/vcsVehicleTrails.lua", SKY / "pipeline/vcs.lua", SKY / "config.lua"):
        lua.eval("function(s) assert(loadstring(s)) end")(path.read_text(encoding="utf-8"))
    lua.execute((SKY / "pipeline/vcsVehicleTrails.lua").read_text())
    lua.execute(r'''
        VCSVehicleTrails.start()
        frame(); assert(VCSVehicleTrails.getStats().segments==0)
        frame(); assert(VCSVehicleTrails.getStats().segments==2, "draw after two samples, not six")
        for i=1,5 do frame() end
        assert(VCSVehicleTrails.getStats().segments==10, "two headlights, five segments each")
        local first,last=draws[1][1][3],draws[1][10][3]
        assert(first[4]==255 and last[4]==255 and first[1]>last[1], "fade RGB, not alpha")
        assert(first[1]==math.floor(math.floor(210*(.3+5/math.sqrt(109)))*128/256), "warm directional headlight")
        car.lightStates[0]=1
        for i=1,6 do frame() end
        assert(VCSVehicleTrails.getStats().segments==5, "front-left damage leaves front-right alive")
        occluded=true
        for i=1,6 do frame() end
        assert(VCSVehicleTrails.getStats().segments==0, "occluded history expires")
        occluded=false; frame(); assert(VCSVehicleTrails.getStats().segments==0, "no bridge across gap")
        frame(); assert(VCSVehicleTrails.getStats().segments==1)
        car.x=car.x+6; frame(); assert(VCSVehicleTrails.getStats().samples==0, "50-pixel jump rejection")
        frame(); assert(VCSVehicleTrails.getStats().segments<5)
        car.lights=false
        for i=1,6 do frame() end
        assert(VCSVehicleTrails.getStats().segments==0, "lights off expires history")
        car.lights=true; car.lightStates={}; cameraY=-10
        for i=1,7 do frame() end
        assert(VCSVehicleTrails.getStats().segments==10, "rear lamps")
        assert(draws[1][1][3][1]>0 and draws[1][1][3][2]==0, "red rear lamps")
        local tail=draws[1][1][3][1]
        driver={}; brake=true
        for i=1,6 do frame() end
        assert(draws[1][1][3][1]>tail, "braking brightens rear lamps")
        gear=0; speed=-0.1
        for i=1,6 do frame() end
        assert(draws[1][1][3][1]==draws[1][1][3][2], "reverse uses gray")
        car.lights=false
        for i=1,6 do frame() end
        assert(draws[1][1][3][1]==60 and draws[1][1][3][2]==60, "daytime reverse base RGB 120")
        car.lights=true; driver=nil; brake=false; gear=1; speed=0
        screenW=1280; frame(); assert(VCSVehicleTrails.getStats().segments==0, "resolution reset")
        frame(); assert(VCSVehicleTrails.getStats().segments==2)
        car.dimension=17; frame(); assert(VCSVehicleTrails.getStats().segments==0, "no history in another dimension")
        car.dimension=0; frame(); assert(VCSVehicleTrails.getStats().segments==0)
        frame(); assert(VCSVehicleTrails.getStats().segments==2)
        car.alpha=0; frame(); assert(VCSVehicleTrails.getStats().segments==0, "hidden vehicle has no stale trail")
        car.alpha=255; frame(); assert(VCSVehicleTrails.getStats().segments==0)
        SKYGFX.vehicleLightTrails=false; frame(); assert(VCSVehicleTrails.getStats().segments==0)
        SKYGFX.vehicleLightTrails=true; frame(); assert(VCSVehicleTrails.getStats().segments==0)
        source=car; events.onClientElementStreamOut(); frame(); assert(VCSVehicleTrails.getStats().lamps==0)
        events.onClientElementStreamIn(); frame(); assert(VCSVehicleTrails.getStats().lamps==4)
        source=car; events.onClientElementModelChange(); frame(); assert(VCSVehicleTrails.getStats().segments==0)
        VCSVehicleTrails.stop(); assert(not VCSVehicleTrails.getStats().active and next(events)==nil)
        VCSVehicleTrails.start(); frame(); assert(VCSVehicleTrails.getStats().segments==0)
        VCSVehicleTrails.stop()
        failShader=true; VCSVehicleTrails.start()
        assert(not VCSVehicleTrails.getStats().active and next(events)==nil, "failed material does not install handlers")
        assert(VCSVehicleTrails.getStats().failures==1)
    ''')
    meta = ET.parse(SKY / "meta.xml").getroot()
    scripts = [node.attrib["src"] for node in meta.findall("script")]
    assert scripts.index("pipeline/vcsVehicle.lua") < scripts.index("pipeline/vcsVehicleTrails.lua") < scripts.index("pipeline/vcs.lua")
    print("TRAIL_LOGIC_PASS: syntax, fade, damage, gaps, jump, light state, resets, lifecycle, blend", flush=True)


SERVER = r'''
local player, car
local pending, received = {}, {}
local function log(message) outputServerLog("TRAIL_QA "..message) end
addEvent("trailQA:ready",true)
addEventHandler("trailQA:ready",resourceRoot,function()
    if not client or player then return end
    player=client
    log("CLIENT_READY")
    spawnPlayer(player, -843.125, -565.625, 14)
    setTime(23,0); setMinuteDuration(600000); setWeather(0)
    -- A controlled player car; ambient NPCs remain production-owned.
    car=createVehicle(420,-843.125,-565.625,14,0,0,8)
    setElementData(car,"vcs_vehicle:originalModel",226)
    setElementFrozen(car,true)
    setVehicleOverrideLights(car,2)
    warpPedIntoVehicle(player,car)
    triggerClientEvent(player,"trailQA:scene",resourceRoot,car)
end)
addEvent("trailQA:sample",true)
addEventHandler("trailQA:sample",resourceRoot,function(message)
    if client==player then log(message) end
end)
addEvent("trailQA:shot",true)
addEventHandler("trailQA:shot",resourceRoot,function(tag)
    if client~=player or type(tag)~="string" or not tag:match("^run%d[%w%-]+$") then return end
    pending[tag]=true
    if not takePlayerScreenShot(player,960,600,tag,90,1200000) then log("FAIL screenshot request "..tag) end
end)
addEventHandler("onPlayerScreenShot",root,function(resource,status,pixels,stamp,tag)
    if resource~=getThisResource() or source~=player or not pending[tag] then return end
    pending[tag]=nil
    if status~="ok" then log("FAIL screenshot "..tag.." "..tostring(status)); return end
    local file=fileCreate(tag..".jpg")
    if not file then log("FAIL screenshot file"); return end
    fileWrite(file,pixels); fileClose(file); received[tag]=true
    log("SCREENSHOT "..tag)
end)
addEvent("trailQA:state",true)
addEventHandler("trailQA:state",resourceRoot,function(action,ground)
    if client~=player then return end
    if action=="reset" then
        setElementPosition(car,-843.125,-565.625,(tonumber(ground) or 9)+1)
        setElementRotation(car,0,0,8)
        setElementVelocity(car,0,0,0)
        setElementAngularVelocity(car,0,0,0)
        setElementFrozen(car,false)
    elseif action=="npc" then
        removePedFromVehicle(player)
        setElementFrozen(player,true); setElementAlpha(player,0)
        setElementPosition(player,-843.125,-565.625,12)
        setElementDimension(car,999)
    elseif action=="damage" then setVehicleLightState(car,0,1)
    elseif action=="repair" then setVehicleLightState(car,0,0)
    elseif action=="off" then setVehicleOverrideLights(car,1)
    elseif action=="on" then setVehicleOverrideLights(car,2)
    elseif action=="model" then
        setElementData(car,"vcs_vehicle:originalModel",207)
        setElementModel(car,596)
    elseif action=="finish" then
        setTimer(function()
            local count=0; for _ in pairs(received) do count=count+1 end
            setElementFrozen(player,false); setElementAlpha(player,255)
            if count<6 or next(pending) then log("FAIL missing screenshots") else log("COMPLETE") end
        end,3000,1)
    end
end)
addEvent("trailQA:npc",true)
addEventHandler("trailQA:npc",resourceRoot,function(vehicle)
    if client~=player or not isElement(vehicle) then return end
    local driver=getVehicleOccupant(vehicle,0)
    log("NPC_SERVER "..toJSON({originalModel=getElementData(vehicle,"npchlc_traffic:originalModel"),
        model=getElementModel(vehicle),driver=isElement(driver) and getElementType(driver),
        assignment=isElement(driver) and exports.npc_hlc:getNPCDebugAssignment(driver)},true))
end)
'''

CLIENT = r'''
local car, started, phase, phaseAt, camera, previousTarget, previousFPS
local total, maximum, sampleFrames, failed = 0,0,0,false
local captured, ground, switching = false, 9, false
local npc, npcFrames, npcSegments = nil,0,0
local cases={"front-full","rear-full","front-reduced","front-off","damaged","lights-off","disabled","reenabled","model","npc"}
local function report(message) triggerServerEvent("trailQA:sample",resourceRoot,message) end
local function state(action) triggerServerEvent("trailQA:state",resourceRoot,action,ground) end
local function shot(tag) triggerServerEvent("trailQA:shot",resourceRoot,tag) end
local function release()
    for _,control in ipairs({"accelerate","brake_reverse","vehicle_left","vehicle_right"}) do setPedControlState(localPlayer,control,false) end
end
local function begin(index)
    phase=index; phaseAt=getTickCount(); total,maximum,sampleFrames=0,0,0; captured=false; switching=false
    local name=cases[index]
    if not name then
        release(); exports.skygfx:trailQASetEnabled(true); exports.skygfx:setVcsPostProcessing("full")
        setFPSLimit(previousFPS)
        if isElement(previousTarget) then setCameraTarget(previousTarget) else setCameraMatrix(unpack(camera)) end
        state("finish"); started=false; report("FINISH"); return
    end
    release()
    if name~="npc" then state("reset") else state("npc") end
    exports.skygfx:setVcsPostProcessing(name=="front-reduced" and "reduced" or name=="front-off" and "off" or "full")
    exports.skygfx:trailQASetEnabled(name~="disabled")
    if name=="damaged" then state("damage") elseif name=="lights-off" then state("off")
    else state("repair"); state("on") end
    if name=="model" then state("model") end
    if name~="npc" then setPedControlState(localPlayer,"accelerate",true) end
    report("BEGIN "..name)
end
addEventHandler("onClientResourceStart",resourceRoot,function()
    camera={getCameraMatrix()}; previousTarget=getCameraTarget(); previousFPS=getFPSLimit()
    triggerServerEvent("trailQA:ready",resourceRoot)
end)
addEvent("trailQA:scene",true)
addEventHandler("trailQA:scene",resourceRoot,function(vehicle)
    car=vehicle; fadeCamera(true); setFPSLimit(30)
    setTimer(function()
        ground=getGroundPosition(-843.125,-565.625,100)
        report("GROUND "..tostring(ground))
        started=true; begin(1)
    end,15000,1)
end)
addEventHandler("onClientPreRender",root,function()
    if not started or not isElement(car) then return end
    local name=cases[phase]
    local target=car
    if name=="npc" then
        if not isElement(npc) then
            for _,vehicle in ipairs(getElementsByType("vehicle",root,true)) do
                local driver=getVehicleController(vehicle)
                if vehicle~=car and isElement(driver) and getElementType(driver)=="ped"
                        and getElementDimension(vehicle)==0 and getElementInterior(vehicle)==0 then
                    npc=vehicle; triggerServerEvent("trailQA:npc",resourceRoot,vehicle); break
                end
            end
        end
        if isElement(npc) then target=npc end
    end
    local m=getElementMatrix(target)
    if not m then return end
    local rear=name=="rear-full" or name=="npc"
    local elapsed=(getTickCount()-phaseAt)/1000
    -- Orbit slowly to expose the screen-space trail even when following a car.
    local side=math.sin(elapsed*1.4)*2
    local lookOffset=math.sin(elapsed*4)*1.5
    local distance=rear and -12 or 12
    local x,y,z=m[4][1],m[4][2],m[4][3]
    setCameraMatrix(x+m[2][1]*distance+m[1][1]*side,y+m[2][2]*distance+m[1][2]*side,z+2.5,
        x+m[1][1]*lookOffset,y+m[1][2]*lookOffset,z+.5,0,65)
end,false,"high")
addEventHandler("onClientHUDRender",root,function()
    if not started then return end
    local elapsed=getTickCount()-phaseAt
    local s=exports.skygfx:getVcsGraphicsStats().vehicleTrails
    if elapsed>1000 then
        total=total+s.segments; maximum=math.max(maximum,s.segments); sampleFrames=sampleFrames+1
        if s.failures>0 then failed=true end
    end
    local name=cases[phase]
    if name=="npc" and isElement(npc) then
        npcFrames=npcFrames+1; npcSegments=npcSegments+s.segments
    end
    if not captured and elapsed>2500 and (s.segments>0 or name=="lights-off" or name=="disabled") then
        captured=true
        shot("run4-"..(name=="npc" and "npc" or "player").."-"..name.."-orbit")
    end
    if not switching and (elapsed>5000 and name~="npc" or elapsed>25000 and name=="npc") then
        switching=true
        local expected=name~="lights-off" and name~="disabled"
        -- Other production vehicles may contribute; controlled checks are in logic tests.
        if expected and maximum==0 and name~="npc" then failed=true end
        report("RESULT "..name.." "..toJSON({frames=sampleFrames,total=total,maximum=maximum,stats=s,
            model=getElementModel(car),driver=getVehicleController(car)==localPlayer,npc=isElement(npc),
            npcFrames=npcFrames,npcSegments=npcSegments,failed=failed},true))
        if name=="npc" then
            report(isElement(npc) and "NPC_OBSERVED" or "NPC_UNVERIFIED")
            report(failed and "FAIL assertions" or "ASSERTIONS_PASS")
        end
        setTimer(function() begin(phase+1) end,500,1)
    end
end,false,"low-10")
addEventHandler("onClientResourceStop",resourceRoot,release)
'''


def port(kind):
    with socket.socket(type=kind) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def prepare(stage):
    resources = stage / "mods/deathmatch/resources"
    resources.mkdir(parents=True)
    dm = resources.parent
    shutil.copy2(ROOT / "MTA Server64.exe", stage)
    shutil.copytree(ROOT / "x64", stage / "x64")
    for name in ("acl.xml", "vehiclecolors.conf"):
        shutil.copy2(ROOT / "mods/deathmatch" / name, dm / name)
    catalog = {p.parent.name: p.parent for p in (ROOT / "mods/deathmatch/resources").rglob("meta.xml")}
    copied, startup = set(), []

    def copy_resource(name):
        if name in copied:
            return
        copied.add(name)
        source = catalog[name]
        shutil.copytree(source, resources / name, ignore=shutil.ignore_patterns(".git", "*.db", "*.db-journal", "__pycache__"))
        for include in ET.parse(source / "meta.xml").getroot().findall("include"):
            copy_resource(include.attrib["resource"])
        startup.append(name)

    for name in ("dgs", "skygfx", "vcs", "vcs_model", "water", "npchlc_traffic"):
        copy_resource(name)
    probe = resources / "trail_qa"
    probe.mkdir()
    (probe / "meta.xml").write_text('<meta><script src="server.lua" type="server"/><script src="client.lua" type="client" cache="false"/></meta>')
    (probe / "server.lua").write_text(SERVER)
    (probe / "client.lua").write_text(CLIENT)
    # The toggle is installed only in the isolated copy, never production.
    (resources / "skygfx/trail_qa.lua").write_text('function trailQASetEnabled(value) SKYGFX.vehicleLightTrails=value return true end')
    meta = ET.parse(resources / "skygfx/meta.xml")
    ET.SubElement(meta.getroot(), "script", src="trail_qa.lua", type="client")
    ET.SubElement(meta.getroot(), "export", function="trailQASetEnabled", type="client")
    meta.write(resources / "skygfx/meta.xml", encoding="utf-8")
    config = ET.parse(ROOT / "mods/deathmatch/mtaserver.conf")
    root = config.getroot()
    for node in root.findall("resource"):
        root.remove(node)
    game_port = port(socket.SOCK_DGRAM)
    settings = {"servername": "VCS lamp trails isolated acceptance", "serverip": "127.0.0.1", "serverport": game_port,
                "httpport": port(socket.SOCK_STREAM), "ase": 0, "httpdownloadurl": "", "password": "", "scriptdebugloglevel": 3, "fpslimit": 60}
    for key, value in settings.items():
        node = root.find(key)
        if node is None:
            node = ET.SubElement(root, key)
        node.text = str(value)
    for name in startup+["trail_qa"]:
        ET.SubElement(root, "resource", src=name, startup="1", protected="0")
    config.write(dm / "mtaserver.conf", encoding="utf-8")
    (stage / "qa.json").write_text(json.dumps({"stage": str(stage), "gamePort": game_port}))
    print(f"Prepared {stage}; game port {game_port}", flush=True)


def run(stage, output, timeout):
    metadata = json.loads((stage / "qa.json").read_text())
    executable = stage / "MTA Server64.exe"
    server_log = stage / "mods/deathmatch/logs/server.log"
    server_offset = server_log.stat().st_size if server_log.exists() else 0
    client_offset = CLIENT_LOG.stat().st_size if CLIENT_LOG.exists() else 0
    process = subprocess.Popen([str(executable)], cwd=stage, stdin=subprocess.PIPE,
                               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, creationflags=subprocess.CREATE_NO_WINDOW)
    metadata["serverPid"] = process.pid
    started, connected = time.monotonic(), False
    try:
        while time.monotonic()-started < timeout:
            log = ""
            if server_log.exists():
                with server_log.open("rb") as stream:
                    stream.seek(server_offset if server_log.stat().st_size >= server_offset else 0)
                    log = stream.read().decode(errors="replace")
            if not connected and "Server started and is ready to accept connections!" in log:
                os.startfile(f"mtasa://127.0.0.1:{metadata['gamePort']}")
                connected = True
                print("Opened real MTA client", flush=True)
            if "TRAIL_QA FAIL" in log:
                raise RuntimeError(log[-8000:])
            if "TRAIL_QA COMPLETE" in log and "TRAIL_QA FINISH" in log and "TRAIL_QA ASSERTIONS_PASS" in log:
                print("TRAIL_LIVE_PASS", flush=True)
                return
            if process.poll() is not None:
                raise RuntimeError("QA server stopped: "+log[-4000:])
            time.sleep(.5)
        raise RuntimeError("QA timed out: "+log[-6000:])
    finally:
        output.mkdir(parents=True, exist_ok=True)
        (output / "server.log").write_text(log, encoding="utf-8")
        for tag in re.findall(r"TRAIL_QA SCREENSHOT ([\w-]+)", log):
            image = stage / "mods/deathmatch/resources/trail_qa" / (tag+".jpg")
            if image.exists():
                shutil.copy2(image, output / image.name)
        if CLIENT_LOG.exists():
            with CLIENT_LOG.open("rb") as stream:
                stream.seek(client_offset if CLIENT_LOG.stat().st_size >= client_offset else 0)
                (output / "clientscript.log").write_bytes(stream.read())
        (output / "run.json").write_text(json.dumps(metadata, indent=2))
        actual = subprocess.check_output(["powershell", "-NoProfile", "-Command",
            f"(Get-CimInstance Win32_Process -Filter 'ProcessId={process.pid}').ExecutablePath"], text=True).strip()
        if actual and Path(actual).resolve() == executable.resolve() and process.poll() is None:
            process.terminate()
            process.wait(timeout=15)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--run-existing", action="store_true")
    parser.add_argument("--output", type=Path, default=EVIDENCE)
    parser.add_argument("--timeout", type=int, default=240)
    args = parser.parse_args()
    check_logic()
    if args.live:
        stage = args.stage or Path(tempfile.gettempdir()) / ("mta-vcs-trails-"+str(time.time_ns()))
        if not args.run_existing:
            prepare(stage)
        else:
            # Refresh editable production inputs before every verification run.
            resources = stage / "mods/deathmatch/resources"
            shutil.copytree(SKY, resources / "skygfx", dirs_exist_ok=True)
            meta = ET.parse(resources / "skygfx/meta.xml")
            ET.SubElement(meta.getroot(), "script", src="trail_qa.lua", type="client")
            ET.SubElement(meta.getroot(), "export", function="trailQASetEnabled", type="client")
            meta.write(resources / "skygfx/meta.xml", encoding="utf-8")
            (resources / "trail_qa/server.lua").write_text(SERVER)
            (resources / "trail_qa/client.lua").write_text(CLIENT)
        run(stage, args.output, args.timeout)
