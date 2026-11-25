-- Run from the repository root with Lua 5.1. The real MTA acceptance run exercises rendering.
local path = "mods/deathmatch/resources/[feature]/car_crusher/"
local now, events, cars, payments, snapshots, completions = 1000, {}, {}, {}, {}, {}
local registered, update, hook
root, resourceRoot = {}, {}
local function entity(kind,x,y,z)
    return {kind=kind,position={x,y,z},rotation={0,0,0},collision=true,
        frozen=false,locked=false,occupants={},health=1000}
end
function addEvent() end
function addEventHandler(name,element,handler)
    events[name] = handler
end
local function emit(name,element,...)
    local prev=source
    source=element
    events[name](...)
    source=prev
end
function triggerEvent(name,element,player,amount)
    assert(name=="onCarCrusherCrushed" and isElement(element))
    assert(not completions[element],"duplicate completion")
    completions[element]={player,amount}
end
function triggerClientEvent(player,name,_,revision,stamp,crane,lid)
    if name=="car_crusher:motion" then snapshots[player]={revision,stamp,crane,lid} end
end
function isElement(e) return type(e)=="table" and e.kind and not e.dead end
function getElementType(e) return e.kind end
function getElementData(e,key) return e[key] end
function setElementData(e,key,value) e[key]=value end
function removeElementData(e,key) e[key]=nil end
function getElementDimension() return 0 end
function getElementInterior() return 0 end
function getElementPosition(e) return unpack(e.position) end
function setElementPosition(e,x,y,z) e.position={x,y,z} end
function getElementRotation(e) return unpack(e.rotation) end
function setElementRotation(e,x,y,z) e.rotation={x,y,z} end
function setElementFrozen(e,b) e.frozen=b end
function isElementFrozen(e) return e.frozen end
function setElementCollisionsEnabled(e,b) e.collision=b end
function getElementCollisionsEnabled(e) return e.collision end
function setVehicleLocked(e,b) e.locked=b end
function isVehicleLocked(e) return e.locked end
function setElementAlpha() end
function setElementID(e) hook=e end
function getVehicleOccupants(e) return e.occupants end
function getPedOccupiedVehicle(player) return player.car end
function getVehicleType() return "Automobile" end
function isVehicleBlown(e) return e.health==0 end
function getElementHealth(e) return e.health end
function getElementVelocity() return 0,0,0 end
function setElementVelocity() end
function getElementModel() return 410 end
function getVehicleHandling() return {monetary=9000} end
function getElementAttachedTo(e) return e.parent end
function attachElements(e,parent) e.parent=parent return true end
function detachElements(e) e.parent=nil end
function destroyElement(e) e.dead=true;emit("onElementDestroy",e) end
function createObject(_,x,y,z) return entity("object",x,y,z) end
function createColCuboid() return {} end
function createPickup() return {} end
function getElementsWithinColShape() return cars end
function getDistanceBetweenPoints2D(x,y,a,b) return ((x-a)^2+(y-b)^2)^0.5 end
function getDistanceBetweenPoints3D(x,y,z,a,b,c) return ((x-a)^2+(y-b)^2+(z-c)^2)^0.5 end
function setTimer(fn) update=fn end
function getTickCount() return now end
function givePlayerMoney(p,cash) payments[p]=(payments[p] or 0)+cash end
function cancelEvent() registered=true end
local hints={}
exports={server_coldata={getModelBoundingBox=function() return -1,-2,-.5,1,2,1 end},
    frontend={showTextBox=function(_,p) hints[p]=(hints[p] or 0)+1 end}}
dofile(path.."layout.lua")
dofile(path.."motion.lua")
dofile(path.."server.lua")
emit("onResourceStart",resourceRoot)

local function advance(ms)
    for _=1,math.ceil(ms/120) do now=now+120;update() end
end
local function untilState(check)
    for _=1,1600 do if check() then return end;advance(120) end
    error("cycle timed out")
end
local function connect(player)
    client=player
    emit("car_crusher:requestMotion",resourceRoot,now-60)
    client=nil
    assert(snapshots[player])
end
local function deliver(player,x)
    local car=entity("vehicle",Crusher.pickupMin[1]+x,Crusher.pickupMin[2]+6,Crusher.pickupMin[3]+0.6)
    cars[#cars+1]=car
    emit("onVehicleExit",car,player,0)
    return car
end

local a,b=entity("player",0,0,0),entity("player",0,0,0)
connect(a)
local first,second=deliver(a,2),deliver(b,6)
untilState(function() return first.parent==hook end)
advance(1200)
connect(b)
local u,v=snapshots[a],snapshots[b]
assert(u[1]==v[1] and v[2]>u[2],"late observer restarted the phase")
local function renderAt(motion,start,finish,step)
    for t=start,finish,step do cranePose(motion,t) end
    return {cranePose(motion,finish)}
end
local early=renderAt(u[3],u[2],now+200,1000/30)
local late=renderAt(v[3],v[2],now+200,1000/144)
for i=1,#early do assert(math.abs(early[i]-late[i])<1e-8) end
emit("onVehicleStartEnter",first,b,0)
assert(registered and not second.parent)
untilState(function() return first.dead end)
assert(payments[a]==43 and not payments[b])
untilState(function() return second.dead end)
assert(payments[a]==43 and payments[b]==43 and completions[first][1]==a and completions[second][1]==b)
local third=deliver(a,3)
untilState(function() return third.parent==hook end)
emit("onPlayerQuit",a)
advance(65000)
assert(not third.dead and not third.parent and not third.locked and not third.frozen and third.collision)
assert(payments[a]==43)
local wreck=deliver(b,4)
wreck.health=0
advance(40000)
assert(not completions[wreck])
local fourth=deliver(b,5)
setCrusherMissionVehicle(b,fourth)
b.car=fourth
b.position=Crusher.missionHelp
advance(240)
setCrusherMissionVehicle(b,third)
b.car=third
advance(240)
assert(hints[b]==1)
untilState(function() return fourth.parent==hook end)
emit("onResourceStop",resourceRoot)
assert(not fourth.parent and not fourth.locked and not fourth.frozen and fourth.collision)
dofile(path.."server.lua")
emit("onResourceStart",resourceRoot)
advance(65000)
assert(not fourth.dead and not fourth.parent and payments[b]==43)
print("PASS: competing drivers, late observer at 144/30 fps, single payouts, entry guard, quit, wreck, restart, shared mission help")
