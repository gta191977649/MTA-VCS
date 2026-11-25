"""Exercise the actual mission registry and golf turn handling with two Lua 5.1 players."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

MISSION = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission"
vm = LuaRuntime()
vm.execute("""
root,resourceRoot={},{}
a,b={name="A"},{name="B"}
players={a,b}
now=0
local handlers={}
function addEvent() end
function addCommandHandler() end
function addEventHandler(name,e,fn) handlers[name]=fn end
function fire(p,name,...) client,source=p,resourceRoot return handlers[name](...) end
function setTimer(fn) tick=fn end
function getTickCount() return now end
function isElement(p) return p==a or p==b end
function getElementType() return "player" end
function getPlayerName(p) return p.name end
function getElementsByType() return players end
function getElementInterior() return 0 end
function getElementDimension() return 0 end
function setElementPosition() end
function setElementRotation() end
function getElementPosition() return 76.6,592,13.75 end
function getDistanceBetweenPoints3D() return 0 end
function isPedDead() return false end
function isPedInVehicle() return false end
function getPedOccupiedVehicle() return false end
function isControlEnabled() return true end
function isElementFrozen(p) return p.frozen or false end
function setElementFrozen(p,b) p.frozen=b end
function outputDebugString(s) error(s) end
function givePlayerMoney(p,n) p.money=(p.money or 0)+n end
function triggerClientEvent(p,event,from,...)
    local args={...}
    if event=="mission:start" then p.token=args[2]
    elseif event=="mission:courseMenu" then p.menu=args[4]
    elseif event=="mission:golfTurn" then p.turn,p.actor,p.phase=args[2],args[3],"ready"
    elseif event=="mission:golfPhase" then p.phase=args[3]
    elseif event=="mission:hud" and args[4]=="Shot" then
        assert(args[4]=="Shot" and args[5]:match("^[1-5]/5$"))
        assert(args[10].label=="Score" and type(args[10].value)=="number")
    elseif event=="mission:end" then p.ended=true end
end
exports={npchlc_traffic={isTrafficPlayerInCustody=function() return false end}}
""")
for name in ("main.lua", "golf_data.lua", "golf.lua"):
    vm.execute((MISSION / name).read_text())
vm.execute("""
function Mission.profile(p) return {owner=p.name} end
function Mission.courseRecord(run,course) return run.player.record or {wins=0} end
function Mission.recordCourse() return true end
function Mission.finishCourse(run,course,metrics,cash,passed,msg)
    local p=run.player
    p.result,p.cash,p.passed,p.score=msg,cash,passed,metrics.score
    p.record={score=metrics.score,wins=(p.record and p.record.wins or 0)+(passed and 1 or 0)}
    Mission.endRun(p,msg,false,passed)
end
local function choose(p,i) fire(p,"mission:courseChoice",p.token,"golf",i,p.menu) end
local function enter(p) fire(p,"mission:golfEnter") end
local function press(p,phase,action)
    fire(p,"mission:golfInput",p.token,p.turn,phase,action or "strike")
end
local function step(ms) now=now+ms; tick() end
local function invite()
    enter(a);choose(a,2);enter(b)
end
local function shot(p)
    assert(p.actor==p and p.phase=="ready")
    press(p,"ready");assert(p.phase=="power")
    now=now+1240;press(p,"power");press(p,"power");assert(p.phase=="aim")
    now=now+1150;press(p,"aim");step(805);assert(p.phase=="flight")
    press(p,"flight",true);step(8000);assert(p.phase=="result")
    step(3501)
end
invite();choose(b,2);step(200)
assert(not Mission.isPlayerBusy(a) and not Mission.isPlayerBusy(b))
invite();choose(b,1)
assert(a.frozen and b.frozen and not Mission.startActivity(a,"golf"))
Mission.toggle(a);assert(Mission.isPlayerBusy(a))
press(b,"ready");assert(a.phase=="ready" and b.phase=="ready")
for i=1,5 do shot(a);shot(b) end
assert(a.passed and b.passed and a.score==b.score and a.result:find("Draw"))
assert(a.cash==1000 and b.cash==1000 and a.money==250 and b.money==250)
assert(not a.frozen and not b.frozen)
invite();choose(b,1);shot(a)
Mission.endRun(b,nil,true)
assert(not b.frozen and a.frozen and a.actor==a)
for i=2,5 do shot(a) end
assert(not a.passed and a.cash==0 and not a.frozen)
for _,score in ipairs({500,501}) do
    a.record=nil;enter(a);choose(a,1)
    local r=Mission.forParticipant(a,a.token,"golf")
    r.score,r.shots,r.match.phase,r.match.start=score,5,"result",now
    step(3501)
    assert(a.passed==(score==501))
end
""")
print("Golf passed: ten alternating shots, input ownership, duplicate input, decline, disconnect, cleanup, tie, records, and first-pass rewards.")
