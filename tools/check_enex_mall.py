"""Exercise both directions of the PS2 mall portals under the shipped MTA ACL."""
import socket
import subprocess
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from shutil import copy2, copytree
from tempfile import TemporaryDirectory

ROOT = Path(__file__).resolve().parents[1]
MOD = ROOT / "mods/deathmatch"
MAPS = MOD / "resources/[vcs]"


def check(stage):
    mod = stage / "mods/deathmatch"
    resources = mod / "resources"
    for name in ("enex", "vcs"):
        (resources / name).mkdir(parents=True)
    copy2(ROOT / "MTA Server64.exe", stage)
    copytree(ROOT / "x64", stage / "x64")
    for name in ("acl.xml", "vehiclecolors.conf"):
        copy2(MOD / name, mod)
    catalog = MAPS / "vcs/portals.xml"
    server_catalog = MAPS / "enex/passage_routes.xml"
    assert catalog.read_bytes() == server_catalog.read_bytes(), (
        "Update enex/passage_routes.xml from vcs/portals.xml after changing the portal catalog"
    )
    for resource in ("enex", "vcs"):
        meta = ET.Element("meta")
        for node in ET.parse(MAPS / resource / "meta.xml").getroot():
            # Keep vcs at its old, client-only manifest while exercising the new enex.
            if resource == "vcs" and node.get("src") != "portals.xml":
                continue
            if node.get("type") == "server" or node.get("src") in {"portals.xml", server_catalog.name}:
                meta.append(node)
                if node.get("src"):
                    copy2(MAPS / resource / node.get("src"), resources / resource)
        ET.ElementTree(meta).write(resources / resource / "meta.xml")
    # Exercise the production handlers using a native ped as the sender.
    # Replace only the client transport and capture the registered callbacks.
    server = resources / "enex/server.lua"
    prefix = """
local handlers,ready,client={},nil,nil
local register=addEventHandler
local function addEventHandler(name,element,fn,...)
    handlers[name]=fn
    return register(name,element,fn,...)
end
local function triggerClientEvent(player,event,root,serial)
    assert(player==client and event=="enex:passageReady")
    ready=serial
end
"""
    probe = """
register("onResourceStart",resourceRoot,function()
    client=createPed(0,0,0,10)
    handlers["enex:requestPassage"]("MALL4",true,99)
    assert(not ready)
"""
    count = 0
    for pair in ET.parse(catalog).getroot():
        route = pair.get("id")
        if not route.startswith("MALL"):
            continue
        a, b = (node.attrib for node in pair)
        for entering, door, dest in (("true", a, b), ("false", b, a)):
            count += 1
            probe += f"""
    setElementInterior(client,{door['interior']})
    setElementDimension(client,{door['dimension']})
    setElementPosition(client,{door['x']},{door['y']},{door['z']})
    ready=nil
    handlers["enex:requestPassage"]("{route}",{entering},{count})
    assert(ready=={count},"{route} authorization")
    handlers["enex:landed"]({count},{dest['spawnX']},{dest['spawnY']},{dest['floorZ']}+0.85)
    assert(getElementDimension(client)=={dest['dimension']} and getElementInterior(client)=={dest['interior']},"{route} landing")
"""
    assert count >= 8
    marker = f"ENEX_MALL_PASS directions={count}"
    server.write_text(prefix + server.read_text() + probe + f'    outputServerLog("{marker}")\nend)\n')
    config = ET.parse(MOD / "mtaserver.conf")
    root = config.getroot()
    for node in root.findall("resource"):
        root.remove(node)
    for name, kind in (("serverport", socket.SOCK_DGRAM), ("httpport", socket.SOCK_STREAM)):
        with socket.socket(type=kind) as sock:
            sock.bind(("127.0.0.1", 0))
            root.find(name).text = str(sock.getsockname()[1])
    for name, value in (("serverip", "127.0.0.1"), ("ase", "0"), ("httpdownloadurl", ""), ("scriptdebugloglevel", "3")):
        root.find(name).text = value
    for name in ("vcs", "enex"):
        ET.SubElement(root, "resource", src=name, startup="1")
    config.write(mod / "mtaserver.conf")
    with subprocess.Popen([str(stage / "MTA Server64.exe")], cwd=stage, creationflags=subprocess.CREATE_NO_WINDOW,
                          stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL) as server_proc:
        try:
            for _ in range(100):
                log = "\n".join(p.read_text(errors="replace") for p in (mod / "logs").glob("*.log"))
                if marker in log:
                    print(marker)
                    return
                if "ERROR: enex" in log or server_proc.poll() is not None:
                    break
                time.sleep(0.15)
            raise RuntimeError(log[-5000:])
        finally:
            if server_proc.poll() is None:
                server_proc.terminate()


if __name__ == "__main__":
    with TemporaryDirectory(prefix="mta-vcs-enex-") as directory:
        check(Path(directory))
