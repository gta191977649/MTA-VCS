"""Exercise migrated production marker creation on a real isolated MTA client.

Load the unmodified entrance client and concert server scripts with their real
portal catalog. Temporary manifests isolate marker initialization from map
streaming, concert playback, and teleportation. Present representative production
markers in the existing SA-airport marker acceptance scene.
"""
from pathlib import Path
import shutil
import tempfile
import time
import xml.etree.ElementTree as ET

import check_vcs_markers as qa


SERVER = r'''
addEventHandler("onResourceStart", resourceRoot, function()
    local concert = getResourceFromName("phill_concert")
    local markers = getElementsByType("marker", getResourceRootElement(concert))
    assert(#markers == 1, "production concert marker count")
    local marker = markers[1]
    assert(exports.marker:getMarkerType(marker) == "cylinder", "concert VCS type")
    local x,y,z = getElementPosition(marker)
    assert(math.abs(x+1056.27)<.01 and math.abs(y-1330.77)<.01 and math.abs(z-11.58)<.01, "concert coordinates preserved")
    local r,g,b,a = exports.marker:getMarkerColor(marker)
    assert(r==245 and g==88 and b==145 and a==150, "concert color preserved")
    assert(not exports.marker:getMarkerBlip(marker), "concert default no blip")
    setElementPosition(marker,1494,-2390,13.6)
    outputServerLog("MARKER_CONSUMERS_SERVER_PASS")
end)
'''

CLIENT = r'''
addEventHandler("onClientResourceStart", resourceRoot, function()
    setTimer(function()
        local enex = getResourceFromName("enex")
        local markers = getElementsByType("marker", getResourceRootElement(enex))
        assert(#markers>10, "production portal markers loaded")
        for _,marker in ipairs(markers) do
            assert(exports.marker:getMarkerType(marker)=="arrow", "portal VCS type")
            local r,g,b,a=exports.marker:getMarkerColor(marker)
            assert(r==0 and g==255 and b==255 and a==125, "portal color preserved")
            assert(not exports.marker:getMarkerBlip(marker), "portal default no blip")
        end
        local marker=markers[1]
        setElementInterior(marker,0)
        setElementDimension(marker,0)
        setElementPosition(marker,1500,-2390,16)
        setTimer(function()
            local state=exports.frontend:getWorldMarkerState(marker)
            assert(state and state.visible, "migrated portal rendering")
            local concert=getResourceFromName("phill_concert")
            local list=getElementsByType("marker",getResourceRootElement(concert))
            assert(#list==1, "migrated concert synchronization")
            local concertState=exports.frontend:getWorldMarkerState(list[1])
            assert(concertState and concertState.visible, "migrated concert rendering")
            triggerServerEvent("markerQA:result",resourceRoot,"migrated-consumers-pass portals="..#markers)
        end,300,1)
    end,1800,1)
end)
'''


def main():
    stage = Path(tempfile.gettempdir()) / ("mta-vcs-marker-consumers-" + str(time.time_ns()))
    qa.prepare(stage)
    resources = stage / "mods/deathmatch/resources"
    for name, source, side in (
        ("enex", qa.MOD / "resources/[vcs]/enex/ps2_portals.lua", "client"),
        ("phill_concert", qa.MOD / "resources/[feature]/phill_concert/server.lua", "server"),
    ):
        destination = resources / name
        destination.mkdir()
        shutil.copy2(source, destination / source.name)
        (destination / "meta.xml").write_text(
            f'<meta><include resource="marker"/><script src="{source.name}" type="{side}" cache="false"/></meta>'
        )
    catalog = resources / "vcs"
    catalog.mkdir()
    shutil.copy2(qa.MOD / "resources/[vcs]/vcs/portals.xml", catalog / "portals.xml")
    (catalog / "meta.xml").write_text('<meta><file src="portals.xml"/></meta>')
    probe = resources / "marker_qa"
    meta = ET.parse(probe / "meta.xml")
    for name in ("vcs", "enex", "phill_concert"):
        ET.SubElement(meta.getroot(), "include", resource=name)
    for name, side, code in (("consumers_server.lua", "server", SERVER), ("consumers_client.lua", "client", CLIENT)):
        (probe / name).write_text(code)
        ET.SubElement(meta.getroot(), "script", src=name, type=side, cache="false")
    meta.write(probe / "meta.xml", encoding="utf-8")
    output = qa.ROOT / "docs/qa/vcs-marker-consumers"
    qa.run(stage, output, 180)
    server = (output / "server.log").read_text(errors="replace")
    client = (output / "clientscript.log").read_text(errors="replace")
    assert "MARKER_CONSUMERS_SERVER_PASS" in server
    assert "migrated-consumers-pass" in server
    assert "ERROR:" not in client and "WARNING:" not in client, client
    print("MIGRATED_CONSUMERS_PASS", flush=True)


if __name__ == "__main__":
    main()
