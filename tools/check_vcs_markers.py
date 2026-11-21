"""Run the marker resource on an isolated loopback server and real MTA client.

The generated test resource and server configuration stay in the temporary stage.
Screenshots are original JPEG bytes received through onPlayerScreenShot. Review
them visually after the run; the pass sentinel covers API assertions, not fidelity.
"""

import argparse
import json
import os
from pathlib import Path
import shutil
import socket
import subprocess
import tempfile
import time
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/deathmatch"
CLIENT_LOG = Path(r"D:/Game/MTA San Andreas 1.7/MTA/logs/clientscript.log")
EVIDENCE = ROOT / "docs/qa/vcs-markers"

SERVER = r'''
local player, received, pending, markers = nil, {}, {}, {}
local function fail(message) outputServerLog("MARKER_QA_FAIL " .. tostring(message)) end
local function shot(tag)
    pending[tag] = true
    if not takePlayerScreenShot(player, 960, 600, tag, 90, 1200000) then fail("screenshot request " .. tag) end
end
addEventHandler("onPlayerScreenShot", root, function(resource, status, pixels, timestamp, tag)
    if resource ~= getThisResource() or source ~= player or not pending[tag] then return end
    pending[tag] = nil
    if status ~= "ok" then fail("screenshot " .. tag .. " status=" .. tostring(status)); return end
    local file = fileCreate(tag .. ".jpg")
    if not file then fail("screenshot file " .. tag); return end
    fileWrite(file, pixels)
    fileClose(file)
    received[tag] = true
    outputServerLog("MARKER_QA_SCREENSHOT " .. tag)
end)
addEvent("markerQA:ready", true)
addEventHandler("markerQA:ready", resourceRoot, function()
    if not client or player then return end
    player = client
    outputServerLog("MARKER_QA_CLIENT_READY " .. getPlayerName(player))
    spawnPlayer(player, 1480, -2420, 14.5)
    setElementFrozen(player, true)
    setElementAlpha(player, 0)
    setTime(12, 0)
    setWeather(0)
    local types = {"checkpoint", "ring", "cylinder", "arrow", "corona", "arrow2", "pointer", "cylinder2"}
    assert(#exports.marker:getMarkerTypes() == #types, "complete marker type catalog")
    for _, nativeType in ipairs({1,2,3,6,7,8}) do
        local marker = exports.marker:createMarker(1480, -2400, 16, nativeType, 3)
        assert(isElement(marker), "numeric marker type " .. nativeType)
        destroyElement(marker)
    end
    for index, kind in ipairs(types) do
        local x = 1470 + ((index - 1) % 6) * 6
        local y = -2400 + math.floor((index - 1) / 6) * 9
        local z = kind == "cylinder" and 13.6 or 16
        markers[index] = exports.marker:createMarker(x, y, z, kind, 3, 237, 130, 180, 200)
        if not isElement(markers[index]) then fail("server create " .. kind); return end
        outputServerLog("MARKER_QA_CREATED " .. kind .. " actual=" .. tostring(exports.marker:getMarkerType(markers[index])) .. " visible=" .. tostring(exports.marker:isMarkerVisibleTo(markers[index], player)))
        assert(not exports.marker:isMarkerBlipVisible(markers[index]), "default minimap visibility")
        assert(not exports.marker:getMarkerBlip(markers[index]), "default no minimap element")
        assert(exports.marker:isMarkerVisibleTo(markers[index], player), "default marker visibility")
        setElementID(markers[index], "marker-qa-" .. kind)
    end
    triggerClientEvent(player, "markerQA:scene", resourceRoot, markers)
    setTimer(function() shot("run1-all-types-front-phase1") end, 2800, 1)
    setTimer(function() shot("run1-all-types-front-phase2") end, 5000, 1)
    setTimer(function()
        setMarkerSize(markers[4], 4)
        assert(exports.marker:setMarkerColor(markers[4], 0, 255, 255, 180), "export color mutation")
        setElementPosition(markers[4], 1488, -2400, 18)
        setElementDimension(markers[5], 23)
        setElementInterior(markers[6], 5)
        assert(exports.marker:isMarkerVisibleTo(markers[7], player), "visibility before hide")
        assert(exports.marker:setMarkerVisibleTo(markers[7], player, false), "visibility mutation")
        assert(not exports.marker:isMarkerVisibleTo(markers[7], player), "visibility after hide")
        assert(exports.marker:setMarkerBlipVisible(markers[4], true), "minimap opt-in")
        local blip = exports.marker:getMarkerBlip(markers[4])
        assert(isElement(blip) and getElementAttachedTo(blip) == markers[4], "minimap attachment")
        triggerClientEvent(player, "markerQA:mutated", resourceRoot, markers)
    end, 6000, 1)
    setTimer(function() shot("run1-mutated-blip-on-side") end, 8500, 1)
    setTimer(function()
        local blip = exports.marker:getMarkerBlip(markers[4])
        assert(exports.marker:setMarkerBlipVisible(markers[4], false), "minimap opt-out")
        assert(not isElement(blip) and not exports.marker:getMarkerBlip(markers[4]), "minimap cleanup")
        setElementPosition(player, 1482, -2400, 14.5)
    end, 9000, 1)
    setTimer(function()
        for _, marker in ipairs(markers) do if isElement(marker) then destroyElement(marker) end end
        triggerClientEvent(player, "markerQA:destroyed", resourceRoot)
    end, 10000, 1)
    setTimer(function()
        if not received["run1-all-types-front-phase1"] or not received["run1-all-types-front-phase2"] or not received["run1-mutated-blip-on-side"] then
            fail("missing screenshot evidence"); return
        end
        setElementAlpha(player, 255)
        setElementFrozen(player, false)
        triggerClientEvent(player, "markerQA:finish", resourceRoot)
        outputServerLog("MARKER_QA_SERVER_COMPLETE")
    end, 12000, 1)
end)
addEvent("markerQA:result", true)
addEventHandler("markerQA:result", resourceRoot, function(result)
    if client ~= player then return end
    outputServerLog("MARKER_QA_CLIENT_RESULT " .. tostring(result))
end)
'''

CLIENT = r'''
local scene, initialCamera, initialTarget, collision, sample = nil, nil, nil, false, nil
local function report(message) triggerServerEvent("markerQA:result", resourceRoot, message) end
addEventHandler("onClientResourceStart", resourceRoot, function()
    initialCamera = {getCameraMatrix()}
    initialTarget = getCameraTarget()
    triggerServerEvent("markerQA:ready", resourceRoot)
end)
addEvent("markerQA:scene", true)
addEventHandler("markerQA:scene", resourceRoot, function(markers)
    scene = markers
    fadeCamera(true)
    setCameraMatrix(1484, -2430, 33, 1484, -2396, 16, 0, 65)
    addEventHandler("onClientMarkerHit", markers[3], function(hit, sameDimension)
        if hit == localPlayer and sameDimension then collision = true end
    end)
    setTimer(function()
        for index, marker in ipairs(scene) do assert(isElement(marker), "server marker synchronization " .. index) end
        local styleSnapshot = {}
        for index, marker in ipairs(scene) do styleSnapshot[index] = exports.marker:getMarkerType(marker) end
        report("all-styles " .. toJSON(styleSnapshot))
        report("style-snapshot " .. tostring(exports.marker:getMarkerType(scene[4])) .. " render=" .. toJSON(exports.frontend:getWorldMarkerState(scene[4])))
        assert(exports.marker:getMarkerType(scene[4]) == "arrow", "style synchronization")
        for _, marker in ipairs(scene) do
            assert(not exports.marker:isMarkerBlipVisible(marker) and not exports.marker:getMarkerBlip(marker), "client default no blip")
            local state = exports.frontend:getWorldMarkerState(marker)
            assert(state and state.visible, "marker render submission")
        end
        sample = exports.frontend:getWorldMarkerState(scene[4])
        local marker = exports.marker:createMarker(1490, -2405, 16, "arrow", 2, 255, 255, 0, 200)
        assert(isElement(marker), "client marker creation")
        assert(exports.marker:setMarkerBlipVisible(marker, true), "local minimap opt-in")
        local blip = exports.marker:getMarkerBlip(marker)
        assert(isElement(blip) and getElementAttachedTo(blip) == marker, "local minimap attachment")
        assert(exports.marker:setMarkerBlipVisible(marker, false), "local minimap opt-out")
        assert(not isElement(blip), "local minimap cleanup")
        destroyElement(marker)
        assert(not isElement(marker), "client marker destruction")
        report("initial-and-client-lifecycle-pass")
    end, 1500, 1)
    setTimer(function()
        local current = exports.frontend:getWorldMarkerState(scene[4])
        assert(current and current.visible and sample, "animation samples")
        assert(current.elapsed > sample.elapsed and current.angle ~= sample.angle and current.phase ~= sample.phase, "animation advances")
        report("animation-samples " .. toJSON({before=sample, after=current}, true))
    end, 2200, 1)
end)
addEvent("markerQA:mutated", true)
addEventHandler("markerQA:mutated", resourceRoot, function(markers)
    setCameraMatrix(1510, -2420, 30, 1484, -2396, 16, 0, 65)
    setTimer(function()
        local x, y, z = getElementPosition(markers[4])
        assert(x == 1488 and y == -2400 and z == 18, "position synchronization")
        assert(getMarkerSize(markers[4]) == 4, "size synchronization")
        assert(getElementDimension(markers[5]) == 23, "dimension synchronization")
        assert(getElementInterior(markers[6]) == 5, "interior synchronization")
        local r, g, b, a = exports.marker:getMarkerColor(markers[4])
        assert(r == 0 and g == 255 and b == 255 and a == 180, "color synchronization")
        assert(exports.marker:isMarkerBlipVisible(markers[4]) and isElement(exports.marker:getMarkerBlip(markers[4])), "minimap synchronization")
        for _, index in ipairs({5,6}) do
            local state = exports.frontend:getWorldMarkerState(markers[index])
            assert(state and not state.visible, "dimension/interior rendering filter")
        end
        local hidden = exports.frontend:getWorldMarkerState(markers[7])
        assert(not hidden or not hidden.visible, "per-player rendering visibility")
        report("mutation-pass")
    end, 750, 1)
end)
addEvent("markerQA:destroyed", true)
addEventHandler("markerQA:destroyed", resourceRoot, function()
    setTimer(function()
        for _, marker in ipairs(scene) do assert(not isElement(marker), "server destruction synchronization") end
        assert(collision, "native marker collision event")
        report("destruction-pass")
    end, 500, 1)
end)
addEvent("markerQA:finish", true)
addEventHandler("markerQA:finish", resourceRoot, function()
    for _, control in ipairs({"accelerate", "brake_reverse", "vehicle_left", "vehicle_right", "forwards", "backwards"}) do
        setPedControlState(localPlayer, control, false)
    end
    if isElement(initialTarget) then setCameraTarget(initialTarget)
    elseif initialCamera then setCameraMatrix(unpack(initialCamera))
    else setCameraTarget(localPlayer) end
    report("finish-pass")
end)
'''


def port(kind):
    with socket.socket(type=kind) as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


def prepare(stage):
    stage.mkdir(parents=True, exist_ok=False)
    mod = stage / "mods/deathmatch"
    resources = mod / "resources"
    resources.mkdir(parents=True)
    shutil.copy2(ROOT / "MTA Server64.exe", stage)
    shutil.copytree(ROOT / "x64", stage / "x64")
    for name in ("acl.xml", "vehiclecolors.conf"):
        shutil.copy2(MOD / name, mod)
    catalog = {path.parent.name: path.parent for path in (MOD / "resources").rglob("meta.xml")}
    copied = set()

    def copy_resource(name):
        if name in copied:
            return
        copied.add(name)
        source = catalog[name]
        shutil.copytree(source, resources / name)
        for include in ET.parse(source / "meta.xml").getroot().findall("include"):
            copy_resource(include.attrib["resource"])

    copy_resource("marker")
    probe = resources / "marker_qa"
    probe.mkdir()
    (probe / "meta.xml").write_text('<meta><include resource="marker"/><script src="server.lua" type="server"/><script src="client.lua" type="client" cache="false"/></meta>')
    (probe / "server.lua").write_text(SERVER)
    (probe / "client.lua").write_text(CLIENT)
    config = ET.parse(MOD / "mtaserver.conf")
    root = config.getroot()
    for child in root.findall("resource"):
        root.remove(child)
    game_port, http_port = port(socket.SOCK_DGRAM), port(socket.SOCK_STREAM)
    settings = {"servername": "VCS marker isolated acceptance", "serverip": "127.0.0.1", "serverport": game_port,
                "httpport": http_port, "ase": 0, "httpdownloadurl": "", "scriptdebugloglevel": 3}
    for key, value in settings.items():
        node = root.find(key)
        if node is None:
            node = ET.SubElement(root, key)
        node.text = str(value)
    ET.SubElement(root, "resource", src="marker_qa", startup="1", protected="0")
    config.write(mod / "mtaserver.conf", encoding="utf-8")
    (stage / "qa.json").write_text(json.dumps({"stage": str(stage), "gamePort": game_port, "httpPort": http_port}, indent=2))
    print(f"Prepared {stage}; game port {game_port}; resources {sorted(copied)}", flush=True)


def powershell(command):
    return subprocess.check_output(["powershell", "-NoProfile", "-Command", command], text=True).strip()


def run(stage, output, timeout):
    metadata = json.loads((stage / "qa.json").read_text())
    executable = stage / "MTA Server64.exe"
    server_log = stage / "mods/deathmatch/logs/server.log"
    server_offset = server_log.stat().st_size if server_log.exists() else 0
    escaped = str(stage).replace("'", "''")
    pid = int(powershell(f"(Start-Process -FilePath '{escaped}\\MTA Server64.exe' -WorkingDirectory '{escaped}' -WindowStyle Hidden -PassThru).Id"))
    metadata["serverPid"] = pid
    (stage / "qa.json").write_text(json.dumps(metadata, indent=2))
    client_offset = CLIENT_LOG.stat().st_size if CLIENT_LOG.exists() else 0
    started, connected, passed = time.monotonic(), False, False

    def save_evidence():
        output.mkdir(parents=True, exist_ok=True)
        if server_log.exists():
            with server_log.open("rb") as stream:
                stream.seek(server_offset if server_log.stat().st_size >= server_offset else 0)
                (output / "server.log").write_bytes(stream.read())
        for image in (stage / "mods/deathmatch/resources/marker_qa").glob("run*.jpg"):
            shutil.copy2(image, output / image.name)
        if CLIENT_LOG.exists():
            with CLIENT_LOG.open("rb") as stream:
                stream.seek(client_offset if CLIENT_LOG.stat().st_size >= client_offset else 0)
                (output / "clientscript.log").write_bytes(stream.read())
        shutil.copy2(stage / "qa.json", output / "run.json")

    try:
        while time.monotonic() - started < timeout:
            if server_log.exists():
                with server_log.open("rb") as stream:
                    stream.seek(server_offset if server_log.stat().st_size >= server_offset else 0)
                    log = stream.read().decode(errors="replace")
            else:
                log = ""
            if not connected and "Server started and is ready to accept connections!" in log:
                os.startfile(f"mtasa://127.0.0.1:{metadata['gamePort']}")
                connected = True
                print(f"Opened real client connection to {metadata['gamePort']}", flush=True)
            if "MARKER_QA_FAIL" in log or "ERROR:" in log:
                raise RuntimeError(log[-5000:])
            required = ("JOIN:", "MARKER_QA_CLIENT_READY", "MARKER_QA_SERVER_COMPLETE", "initial-and-client-lifecycle-pass",
                        "mutation-pass", "destruction-pass", "finish-pass")
            if all(token in log for token in required):
                passed = True
                break
            time.sleep(0.3)
        if not passed:
            raise RuntimeError(f"Client acceptance timed out; stage retained at {stage}\n{log[-4500:]}")
        print(f"MARKER_QA_PASS; original screenshots and logs: {output}", flush=True)
    finally:
        save_evidence()
        # Both PID and executable identity must match this run before stopping it.
        actual = powershell(f"(Get-CimInstance Win32_Process -Filter 'ProcessId={pid}').ExecutablePath")
        if actual and Path(actual).resolve() == executable.resolve():
            powershell(f"Stop-Process -Id {pid}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path)
    parser.add_argument("--prepare-only", action="store_true")
    parser.add_argument("--run-existing", action="store_true")
    parser.add_argument("--output", type=Path, default=EVIDENCE)
    parser.add_argument("--timeout", type=int, default=180)
    args = parser.parse_args()
    stage = args.stage or Path(tempfile.gettempdir()) / ("mta-vcs-markers-" + str(time.time_ns()))
    if not args.run_existing:
        prepare(stage)
    else:
        # Refresh every copied production resource from the current workspace.
        catalog = {path.parent.name: path.parent for path in (MOD / "resources").rglob("meta.xml")}
        copied = set()

        def refresh_resource(name):
            if name in copied:
                return
            copied.add(name)
            source = catalog[name]
            shutil.copytree(source, stage / "mods/deathmatch/resources" / name, dirs_exist_ok=True)
            for include in ET.parse(source / "meta.xml").getroot().findall("include"):
                refresh_resource(include.attrib["resource"])

        refresh_resource("marker")
        probe = stage / "mods/deathmatch/resources/marker_qa"
        (probe / "server.lua").write_text(SERVER)
        (probe / "client.lua").write_text(CLIENT)
    if not args.prepare_only:
        run(stage, args.output, args.timeout)


if __name__ == "__main__":
    main()
