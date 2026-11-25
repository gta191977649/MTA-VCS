"""Check range-LOD opacity composition using the production Lua 5.1 code."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
RESOURCE = ROOT / "mods/deathmatch/resources"


def check():
    lua = LuaRuntime()
    lua.execute("""
root = {}; localPlayer = {dimension=0}
cameraX, cameraY, hour = 0, 0, 12
timers, handlers = {}, {}
function getCameraMatrix() return cameraX, cameraY, 0 end
function getElementAlpha(e) return e.alpha end
function setElementAlpha(e, a) e.alpha = a return true end
function getElementType(e) return 'object' end
function getElementDimension(e) return e.dimension end
function setElementDimension(e, d) e.dimension = d end
function getElementCollisionsEnabled(e) return e.collisions end
function setElementCollisionsEnabled(e, c) e.collisions = c end
function getTime() return hour end
function isElement(e) return not e.destroyed end
function setTimer(fn) timers[#timers+1] = fn end
function addEventHandler(name, element, fn) handlers[name] = fn end
""")
    source = (RESOURCE / "[vcs]/eagleLoader/client/general_helper.lua").read_text()
    lua.execute(source.split("-- Object Flags", 1)[0])
    lua.execute("""
local e = {alpha=255, dimension=0, collisions=true}
registerRangeLOD(e, 100, -1, -1, 1, 1)
assert(e.alpha == 0, 'inside bounds must be hidden immediately')
local expected = {{101,0}, {106,63}, {111,127}, {116,191}, {121,255}}
for pass=1,2 do
    for i=1,#expected do
        local row=expected[pass==1 and i or #expected-i+1]
        cameraX=row[1]; handlers.onClientPreRender()
        assert(e.alpha==row[2], 'near fade must be continuous and reversible')
    end
end
cameraX=111; handlers.onClientPreRender()
setPlacementAlpha(e,128)
assert(e.alpha==64, 'placement opacity must compose immediately')
handlers.onClientPreRender()
assert(e.alpha==64, 'frame updates must not compound opacity')
registerRangeLOD(e,100,-1,-1,1,1)
assert(e.alpha==64, 're-registering bounds must preserve the original placement alpha')
setModelStreamTime(nil,'test',6,18)
hour=23; prepTime(e,'test')
handlers.onClientPreRender()
assert(e.alpha==0 and not e.collisions and e.dimension==65534,
    'timed visibility must override the range fade')
hour=12; timers[2]()
assert(e.alpha==64 and e.collisions and e.dimension==0,
    'timed visibility must restore the original placement opacity')
setPlacementAlpha(e,0); cameraX=200; handlers.onClientPreRender()
assert(e.alpha==0, 'range updates must preserve explicit invisibility')
setPlacementAlpha(e,255); handlers.onClientPreRender()
assert(e.alpha==255)
local long = {alpha=255, dimension=0, collisions=true}
cameraX=306; registerRangeLOD(long,300,-1,-1,1,1)
assert(long.alpha==127, 'long-range LODs must use the extended SA fade band')
local ordinary = {alpha=255}
setPlacementAlpha(ordinary,128)
assert(ordinary.alpha==128, 'ordinary entities must retain native opacity ownership')
e.destroyed=true; long.destroyed=true
handlers.onClientPreRender(); handlers.onClientPreRender()
""")
    for name in (
        "[vcs]/eagleLoader/client/general_helper.lua",
        "[graphic]/skygfx/pipeline/vcs.lua",
    ):
        lua.execute("assert(loadstring(...))", (RESOURCE / name).read_text())
    print("PASS: reversible range fades, placement/timed opacity, cleanup and Lua 5.1 syntax")


if __name__ == "__main__":
    check()
