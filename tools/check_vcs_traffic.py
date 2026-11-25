"""Regression checks for the VCS graph, fixed-wing math and NPCHLC ownership."""

import argparse
import json
import math
from pathlib import Path
from shutil import copy2, copytree
import socket
import struct
from statistics import quantiles
import subprocess
from tempfile import TemporaryDirectory
from time import perf_counter, sleep
import xml.etree.ElementTree as ET
import zlib

from lupa.lua51 import LuaRuntime

from import_vcs_traffic import ROAD_MAP, assemble, encode_json
from vehicle_impact_import import export as export_collision_handling, export_decisions, export_service_sound
from ped_services_check import main as check_ped_services
from vcs_model_assets import chunks, vehicle_material_textures
from vcs_police_materials import POLICE_MODELS, atomic_geometry
from vcs_road_collision import ground_height, lane_centres, road_surfaces
from vcs_vehicle_ground import contact_geometry, read_archive, wheel_radius
from vcs_jetski_rider import bake as bake_jetski_rider
from vcs_jetski_engine import extract as extract_jetski_engine

ROOT = Path(__file__).resolve().parents[1]
TRAFFIC = ROOT / "mods/deathmatch/resources/[traffic]"
HLC = TRAFFIC / "npc_hlc"
RUNTIME = TRAFFIC / "npchlc_traffic"
VCS_VEHICLE = TRAFFIC.parent / "[model]" / "vcs_vehicle"

SERVER_MOCK = """
root, resourceRoot = {}, {}
events, timers, packets, completed = {}, {}, {}, {}
now = 10000

function addEvent() end
function addCommandHandler() end
function addEventHandler(name, element, callback)
    events[name] = events[name] or {}
    table.insert(events[name], callback)
end
function deliver(name, element, ...)
    local previous = source
    source = element
    for _, callback in ipairs(events[name] or {}) do callback(...) end
    source = previous
end
function setTimer(callback, interval) timers[interval] = callback end
function isTimer() return false end
function getTickCount() return now end
function getGameSpeed() return 1 end
function getTrafficLightState() return 2 end
function getResourceFromName() return false end
function getServerConfigSetting(name)
    if name == "unoccupied_vehicle_syncer_distance" then return "160" end
    return false
end
function get() end
function isElement(e) return type(e) == "table" and e.kind and not e.destroyed end
function getElementType(e) return e.kind end
function getElementModel(e) return e.model end
function getElementHealth(e) return e.health end
function setElementHealth(e,value) e.health=value end
function setPedStat(e,id,value) e[id]=value return true end
function getVehicleType(e) return e.vehicleType or "Automobile" end
function setVehicleColor(e,...) e.colors={...}; return true end
function isPedDead(e) return e.health == 0 end
function getPedOccupiedVehicle(e) return e.vehicle end
function isPedInVehicle(e) return e.vehicle ~= nil end
function getVehicleOccupant(e) return e.driver end
function getVehicleOccupants(e) return {[0]=e.driver, [1]=e.passenger} end
function getElementSyncer(e) return e.syncer end
function setElementSyncer(e, owner) e.syncer = owner return true end
function getElementDimension(e) return e.dimension or 0 end
function getElementInterior(e) return e.interior or 0 end
function getElementPosition(e) return e.x, e.y, e.z end
function getElementMatrix(e)
    local fx, fy = e.fx or 0, e.fy or 1
    return {{fy,-fx,0}, {fx,fy,0}, {0,0,1}, {e.x,e.y,e.z}}
end
function getVehicleSirensOn(e) return e.siren == true end
function getElementVelocity(e) return e.vx or 0, e.vy or 0, e.vz or 0 end
function getElementsWithinRange() return {} end
function setElementPosition(e, x, y, z) e.x, e.y, e.z = x, y, z end
function setElementRotation() end
function setPedRotation() end
function getDistanceBetweenPoints2D(x, y, u, v) return math.sqrt((x-u)^2+(y-v)^2) end
function getDistanceBetweenPoints3D(x, y, z, u, v, w)
    return math.sqrt((x-u)^2+(y-v)^2+(z-w)^2)
end
function setElementData(e, key, value) e[key] = value end
function getElementData(e, key) return e[key] or false end
function removeElementData(e, key) e[key] = nil end
function addElementDataSubscriber() end
function removeElementDataSubscriber() end
function triggerClientEvent(player, name, eventSource, ...)
    table.insert(packets, {owner=player, name=name, {...}})
end
function triggerEvent(name, npc, task)
    if name == "npc_hlc:onNPCTaskDone" then table.insert(completed, {npc, task}) end
    deliver(name, npc, task)
end
function element(kind, x)
    return {kind=kind, x=x or 0, y=0, z=0, health=100}
end
function tick()
    now = now + 50
    timers[50]()
end
"""

OWNERSHIP = """
local a, b = element("player"), element("player")
local npc, vehicle = element("ped"), element("vehicle")
npc.vehicle, vehicle.driver, vehicle.syncer = vehicle, npc, a
assert(enableHLCForNPC(npc))
assert(not addNPCTask(npc, false))
assert(not addNPCTask(npc, {"walkAlongLine", 0, 0, 0, 0, 0, 4, 1, 1}))
assert(addNPCTask(npc, {"driveToPos", "10", 0, 0, 0.5}))
assert(addNPCTask(npc, {"driveToPos", 20, 0, 0, 0.5}))
assert(#packets == 1 and packets[1].owner == a and packets[1][1][3][2] == 10)
tick()
assert(#completed == 0 and vehicle.x == 0)

vehicle.syncer = b
deliver("onElementStartSync", vehicle, b)
assert(#packets == 3 and packets[2].owner == a and packets[2][1][3] == false)
assert(packets[3].owner == b and packets[3][1][3][2] == 10)
assert(packets[3][1][2] > packets[1][1][2])
vehicle.x = 10
tick()
assert(#completed == 1 and completed[1][2][2] == 10)
assert(packets[4].owner == b and packets[4][1][3][2] == 20)

vehicle.driver, npc.vehicle = b, nil
deliver("onPedVehicleExit", npc, vehicle, 0)
assert(packets[#packets][1][3] == false)
tick()
assert(#completed == 1 and vehicle.x == 10)
assert(disableHLCForNPC(npc))

assert(enableHLCForNPC(npc, "walk"))
assert(setNPCTask(npc, {"walkToPos", 0.1, 0, 0, 0.01}))
tick()
tick()
tick()
tick()
assert(#completed == 2 and math.abs(npc.x - 0.1) < 0.001)
tick()
assert(#completed == 2)

addEventHandler("npc_hlc:onNPCTaskDone", npc, function()
    if source~=npc then return end
    assert(setNPCTask(npc, {"walkToPos", 12, 0, 0, 0.01}))
end)
assert(setNPCTask(npc, {"walkToPos", 0.1, 0, 0, 0.01}))
tick()
assert(all_npcs[npc].tasks[1][2] == 12 and #completed == 3)
deliver("onElementDestroy", npc)
assert(not all_npcs[npc])

local officer=element("ped")
officer.syncer=a
b.vehicle=vehicle
assert(enableHLCForNPC(officer,"run"))
assert(setNPCTask(officer,{"approachDriverDoor",b,-1.55,.4,27}))
local arrivals=0
addEventHandler("npc_hlc:onDriverDoorArrival",root,function(car)
    assert(source==officer and car==vehicle)
    arrivals=arrivals+1
end)
client=b
deliver("npc_hlc:driverDoorArrival",officer,vehicle,27)
client=a
deliver("npc_hlc:driverDoorArrival",officer,vehicle,26)
deliver("npc_hlc:driverDoorArrival",officer,element("vehicle"),27)
assert(arrivals==0)
deliver("npc_hlc:driverDoorArrival",officer,vehicle,27)
assert(arrivals==1)
clearNPCTasks(officer)
deliver("npc_hlc:driverDoorArrival",officer,vehicle,27)
assert(arrivals==1)
local walker=element("ped")
walker.syncer=a
assert(enableHLCForNPC(walker))
assert(setNPCTask(walker,{"walkTrafficToPoint",3,0,0,.35}))
assert(addNPCTask(walker,{"walkTrafficToPoint",6,0,0,.35}))
local revision=all_npcs[walker].revision
deliver("npc_hlc:walkArrival",walker,revision)
assert(getNPCTaskCount(walker)==2) -- owner too far from the waypoint
walker.x=2.55
client=b
deliver("npc_hlc:walkArrival",walker,revision)
client=a
deliver("npc_hlc:walkArrival",walker,revision-1)
assert(getNPCTaskCount(walker)==2)
deliver("npc_hlc:walkArrival",walker,revision)
assert(getNPCTaskCount(walker)==1)
deliver("npc_hlc:walkArrival",walker,revision)
assert(getNPCTaskCount(walker)==1)
disableHLCForNPC(walker)
client=nil
"""

CLIENT_OWNERSHIP = """
function isLineOfSightClear() return true end
local npc = element("ped")
localPlayer = element("player")
local other = element("player")
setElementData(npc, "npc_hlc", true)
setElementData(npc, "npc_hlc:profile", {"walk", 1, 1})
local issued, released, stopped = 0, 0, 0
local stream = true
function isElementStreamedIn() return stream end
function isElementSyncer(actor) return actor.syncer == localPlayer end
function getElementsByType() return {npc} end
function makeNPCWalkToPos() issued = issued + 1 end
function releaseNPCActions() released = released + 1 end
function stopAllNPCActions() stopped = stopped + 1 end
function triggerServerEvent(name, eventSource, changes)
    if name=="npc_hlc:walkArrival" then assert(eventSource==npc and type(changes)=="number");return end
    assert(name == "npc_hlc:watchProfiles" and eventSource == resourceRoot and changes[1][1] == npc)
end
deliver("onClientResourceStart", resourceRoot)
timers[150]()

npc.syncer = other
local move = {"walkToPos", 10, 0, 0, 0.1}
deliver("npc_hlc:control", resourceRoot, npc, 1, move, npc)
deliver("onClientPreRender", root)
assert(issued == 0)

npc.syncer = localPlayer
deliver("onClientPreRender", root)
assert(issued == 1)

deliver("npc_hlc:control", resourceRoot, npc, 2, false, false)
deliver("npc_hlc:control", resourceRoot, npc, 1, move, npc)
deliver("onClientPreRender", root)
assert(issued == 1 and released == 1)

deliver("npc_hlc:control", resourceRoot, npc, 3, move, npc)
deliver("onClientPreRender", root)
assert(issued == 2)
stream = false
deliver("onClientElementStreamOut", npc)
deliver("onClientPreRender", root)
assert(issued == 2 and released == 2)

local vehicle = element("vehicle")
vehicle.syncer, vehicle.driver, npc.vehicle = localPlayer, npc, vehicle
local trafficDrive = {"driveTrafficToPoint", 10, 0, 0, 0.1}
function makeNPCDriveToPos(_, _, _, _, traffic) assert(traffic) issued = issued + 1 end
stream = true
deliver("npc_hlc:control", resourceRoot, npc, 4, trafficDrive, vehicle)
assert(not getNPCDebugExecution(npc,4))
deliver("onClientPreRender", root)
assert(issued == 3)
assert(getNPCDebugExecution(npc,4)[9]==false)
vehicle.x, vehicle.z = 10, 4
deliver("onClientPreRender", root)
assert(issued == 3 and released == 3 and stopped == 0)
assert(getNPCDebugExecution(npc,4)[9]==true)

npc.vehicle = nil
npc.x, npc.z = 0, 0
local first = {"walkTrafficToPoint", 2, 0, 0, 0.25}
local nextWalk = {"walkTrafficToPoint", 4, 0, 0, 0.25}
local targets = {}
function makeNPCWalkToPos(_, x) targets[#targets + 1] = x end
deliver("npc_hlc:control", resourceRoot, npc, 5, first, npc, nextWalk)
assert(not getNPCDebugExecution(npc,4))
deliver("onClientPreRender", root)
npc.x = 2
deliver("onClientPreRender", root)
npc.x = 3
deliver("onClientPreRender", root)
deliver("npc_hlc:control", resourceRoot, npc, 6, nextWalk, npc)
deliver("onClientPreRender", root)
assert(table.concat(targets, ",") == "2,4,4,4" and released == 3 and stopped == 0)
assert(getNPCDebugExecution(npc,6)[1]=="walkTrafficToPoint")
function isPedOnGround() return true end
deliver("onClientPedDamage", npc, localPlayer, 0, 3, 5)
deliver("onClientPreRender", root)
assert(#targets==5 and targets[5]==4)
table.remove(targets)
deliver("onClientPedDamage", npc, false, 49, 3, 5)
deliver("onClientPreRender", root)
assert(#targets == 4 and released == 4)
now = now + 350
deliver("onClientPreRender", root)
assert(#targets == 5)
local facing, motion = "npchlc_traffic:socialFacing", "npchlc_traffic:activityMotion"
setElementData(npc, motion, {"idle_chat",false,10,1000,10,"PED"})
deliver("onClientElementDataChange", npc, motion)
assert(released == 5)
setElementData(npc, facing, other)
deliver("onClientElementDataChange", npc, facing)
deliver("npc_hlc:control", resourceRoot, npc, 7, nextWalk, npc)
removeElementData(npc, motion)
deliver("onClientElementDataChange", npc, motion)
deliver("onClientPreRender", root)
assert(#targets == 5)
removeElementData(npc, facing)
deliver("onClientElementDataChange", npc, facing)
deliver("onClientPreRender", root)
assert(#targets == 6)

local oldWalk=walkNPCTrafficFormation
local waypoints={}
function walkNPCTrafficFormation(_,x,y,state)
    assert(type(state)=="table" and state.bumper)
    waypoints[#waypoints+1]={x,y}
end
function getElementBoundingBox() return -1,-2,-.5,1,2,1 end
function getVehicleComponentPosition() return -1,0,0 end
function stopNPCWeaponActions() end
vehicle.x,vehicle.y,vehicle.z=0,0,0
vehicle.driver,other.vehicle=other,vehicle
npc.x,npc.y,npc.z=2,1,0
deliver("npc_hlc:control",resourceRoot,npc,8,{"approachDriverDoor",other},npc)
deliver("onClientPreRender",root)
assert(waypoints[1][2]>2 and waypoints[1][1]>=1)
npc.y=3
deliver("onClientPreRender",root)
assert(waypoints[2][1]<-1)
local rotation
local stopped
local previousRotation=setPedRotation
function setPedRotation(_,angle) rotation=angle end
function stopNPCWalkingActions() stopped=true end
deliver("npc_hlc:control",resourceRoot,npc,9,{"approachDriverDoor",other,-1.6,.4},npc)
npc.x,npc.y=-1.6,.4
deliver("onClientPreRender",root)
assert(stopped and rotation and math.abs(rotation+math.deg(math.atan2(1.6,-.4)))<.01)
local reports=0
local previousReport=triggerServerEvent
function triggerServerEvent(name,ped,car,order)
    assert(name=="npc_hlc:driverDoorArrival" and ped==npc and car==vehicle and order==14)
    reports=reports+1
end
deliver("npc_hlc:control",resourceRoot,npc,10,{"approachDriverDoor",other,-1.6,.4,14},npc)
deliver("onClientPreRender",root)
assert(reports==0)
for _=1,6 do now=now+1500; deliver("onClientPreRender",root) end
assert(reports==4)
triggerServerEvent=previousReport
setPedRotation=previousRotation
deliver("npc_hlc:control",resourceRoot,npc,11,false,false)
walkNPCTrafficFormation=oldWalk
-- A fleeing owner that reaches a node before the next server assignment
-- keeps moving in its escape direction while the arrival is acknowledged.
npc.x,npc.y=0,0
local flight={"walkTrafficToPoint",2,0,0,.25,flee=true}
deliver("npc_hlc:control",resourceRoot,npc,12,flight,npc)
deliver("onClientPreRender",root)
local continued=false
function steerNPCFlight(ped,walk,dx,dy)
    assert(ped==npc and dx>0 and dy==0)
    continued=true
    walk.action="Flee away from threat"
end
npc.x=2
deliver("onClientPreRender",root)
assert(continued and not getNPCDebugExecution(npc,12)[9])

"""

LOAD = """
local players = {}
benchActors = {}
for i = 1, 100 do
    players[i] = element("player", i * 4)
    for j = 1, 6 do
        local npc = element("ped", i * 4)
        if j <= 4 then npc.syncer = players[i] end
        assert(enableHLCForNPC(npc, "walk"))
        assert(addNPCTask(npc, {"walkToPos", 3000, 500, 0, 0.5}))
        benchActors[#benchActors + 1] = npc
    end
end

function benchStep()
    tick()
    if now % 1000 == 0 then
        local index = now / 1000 % #benchActors + 1
        local npc = benchActors[index]
        npc.syncer = players[1]
        deliver("onElementStartSync", npc, players[1])
    end
end
"""

NATIVE_MEDIC_PROBE = """
function verifyNativeMedicHandoff()
    local graph=PedAI.graph
    local mx,my,mz=379.938,1246.2159,-200.016
    local profile=TrafficPopulation.sample(graph.population,mx,my,mz,12,0)
    assert(profile.pedestrianGroupId==33)
    local eligible=0
    for _,node in ipairs(graph.nodes) do
        if node.kind=="pedestrian" and node.scene=="underground" then
            for i=1,node.linkCount do
                local edge=graph.links[node.firstLink+i]
                local target=graph.nodes[edge.to+1]
                local x,y,z=TrafficAmbient.samplePedestrianEdge(node,target,edge,mx,my,60,0,128,mz)
                if x and math.abs(z-mz)<=3 then
                    local distance=getDistanceBetweenPoints2D(x,y,mx,my)
                    if distance>35 and distance<60 then eligible=eligible+1 end
                end
            end
        end
    end
    assert(eligible>0,"MALL1 has no same-floor spawn candidates")
    local dim=728
    local car=assert(createVehicle(416,18,0,3))
    local medic=assert(createPed(274,0.55,0,3))
    local casualty=assert(createPed(23,0,0,3))
    for _,e in ipairs({car,medic,casualty}) do setElementDimension(e,dim) end
    for ped,id in pairs({[medic]=12,[casualty]=23}) do
        assert(exports.npc_hlc:enableHLCForNPC(ped,"walk"))
        TrafficModelBindings.tag(ped,id)
        assert(TrafficAmbient.adoptDriver(ped,nil,nil,id))
        PedAI.attach(ped,id)
    end
    -- Real native ped/vehicle and death notification; the server is one sync behind.
    local strikingCar=assert(createVehicle(411,0,-10,3))
    setElementDimension(strikingCar,dim)
    assert(setElementVelocity(strikingCar,0,.8,0))
    local vx,vy,vz=TrafficRoad.pedContactMotion(strikingCar,getTickCount(),0,0,3)
    assert(vy and vy>.79 and not TrafficRoad.pedContactMotion(strikingCar,getTickCount(),20,0,3))
    PedRoadInjury.strike(casualty,{},strikingCar,50,0,vx,vy,vz)
    assert(isPedDead(casualty) and not PedServices.keepCasualty(casualty))
    destroyElement(strikingCar)
    local road={driver=medic,vehicle=car,dimension=dim,originalVehicle=227}
    -- A dispatched crew already owns the parked ambulance when it starts CPR.
    PedServices.linkCrew(road,{crew=medic})
    local now=getTickCount()
    assert(PedServices.update(medic,12,now) and PedServices.keepCasualty(casualty))
    for i=1,8 do PedServices.update(medic,12,now+100*i) end
    assert(not isElement(casualty))
    local revived
    for _,ped in ipairs(getElementsByType("ped",resourceRoot)) do
        if ped~=medic and getElementDimension(ped)==dim then revived=ped end
    end
    assert(revived and getElementHealth(revived)>0)
    assert(PedAI.brain(medic).event.kind=="returnCar")
    assert(PedAI.update(medic,PedAI.graph))
    assert(exports.npc_hlc:getNPCDebugAssignment(medic)=="walkFollowElement")
    for _,e in ipairs({medic,revived,car}) do destroyElement(e) end

    local ordinary=assert(createPed(23,0,0,3))
    setElementDimension(ordinary,dim)
    TrafficModelBindings.tag(ordinary,23)
    assert(exports.npc_hlc:enableHLCForNPC(ordinary,"walk"))
    assert(TrafficAmbient.adoptDriver(ordinary,nil,nil,23))
    PedAI.attach(ordinary,23)
    assert(killPed(ordinary) and not PedServices.keepCasualty(ordinary))
    local wreck=assert(createVehicle(411,50,10,3))
    setElementDimension(wreck,dim)
    TrafficRoad.retainPlayerVehicle(wreck)
    assert(blowVehicle(wreck,false))
    return ordinary,wreck
end
"""

NATIVE_PROBE = """
local traffic, hlc
local controller = exports.vcs_vehicle
local standalone = {}
local function startPopulation()
    local vehicles = getResourceFromName("vcs_vehicle")
    assert(getResourceState(vehicles)=="running")
    for _,name in ipairs({"server_coldata","npc_hlc","vcs_model","npchlc_traffic"}) do
        local resource = assert(getResourceFromName(name))
        assert(getResourceState(resource)~="running", "vehicle resource started "..name)
    end
    for i,pair in ipairs({{473,233,"CJetSki"},{484,248,"CBoat"},{577,280,"CPlane"}}) do
        local vehicle = assert(createVehicle(pair[1],700+i*10,700,6))
        assert(controller:bindVcsVehicle(vehicle,pair[2]))
        assert(getElementData(vehicle,"vcs_vehicle:originalModel")==pair[2])
        assert(controller:getVcsVehicleClass(vehicle)==pair[3])
        standalone[i]={vehicle=vehicle,id=pair[2],class=pair[3]}
    end
    local handling=getVehicleHandling(standalone[1].vehicle)
    assert(math.abs(handling.mass-978.94458)<0.01 and handling.steeringLock==40)
    assert(standalone[1].class~=standalone[2].class and standalone[2].class~=standalone[3].class)
    local sedan=assert(createVehicle(411,700,690,10))
    assert(not controller:bindVcsVehicle(sedan,233) and not getElementData(sedan,"vcs_vehicle:originalModel"))
    destroyElement(sedan)
    assert(restartResource(vehicles))
    setTimer(function()
        for _,row in ipairs(standalone) do
            assert(isElement(row.vehicle) and controller:getVcsVehicleClass(row.vehicle)==row.class)
        end
        for _,name in ipairs({"server_coldata","npc_hlc","vcs_model","npchlc_traffic"}) do
            assert(startResource(getResourceFromName(name)), "could not start "..name)
        end
    end,400,1)
end
local function flightSlots()
    local slots = {}
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        local slot = getElementData(vehicle, "npchlc_traffic:flightSlot", false)
        if slot ~= false then
            assert(slot == 0 or slot == 1 or slot == 2)
            assert(not slots[slot] and isElementFrozen(vehicle))
            assert(getElementModel(vehicle) == 577 and getVehicleType(vehicle) == "Plane")
            assert(getElementData(vehicle, "npchlc_traffic:originalModel") == 280)
            assert(getElementData(vehicle, "npchlc_traffic:modelProvider") == "vcs_model")
            local matrix = getElementMatrix(vehicle)
            assert(matrix and matrix[4][3] > 0)
            slots[slot] = vehicle
        end
    end
    return slots
end
local loadTimer
setTimer(startPopulation, 50, 1)
loadTimer = setTimer(function()
    if getResourceState(getResourceFromName("npchlc_traffic"))~="running" then return end
    traffic, hlc = exports.npchlc_traffic, exports.npc_hlc
    local status, counts, failure = traffic:getTrafficStatus()
    if status == "loading" or status == "stopped" then return end
    killTimer(loadTimer)
    assert(status == "ready", tostring(failure))
    for i,row in ipairs(standalone) do
        local vehicle=assert(controller:createVcsVehicle(row.id,730+i*15,760,10))
        assert(getElementData(vehicle,"vcs_vehicle:originalModel")==row.id)
        assert(controller:getVcsVehicleClass(vehicle)==row.class)
        assert(getElementModel(vehicle)==getElementModel(row.vehicle))
        destroyElement(vehicle)
    end
    assert(counts.peds == 5308 and counts.cars == 2701 and counts.boats == 378 and counts.links == 17652)
    assert(traffic:getTrafficRoadStatus().range == 160, "configured traffic sync range was not applied")
    local corpse,wreck=traffic:verifyNativeMedicHandoff()
    assert(isElement(corpse) and isElement(wreck))
    local faded={}
    addEventHandler("onElementDataChange",root,function(key)
        if (source==corpse or source==wreck) and key=="npchlc_traffic:retiring" and getElementData(source,key) then
            faded[source]=true
        end
    end)
    local corpseFaded,wreckFaded=false,false
    addEventHandler("onElementDestroy",root,function()
        if source==corpse then corpseFaded=faded[source] end
        if source==wreck then wreckFaded=faded[source] end
    end)
    assert(traffic:sampleTrafficFlight("fake-plane", 0, 2))
    assert(traffic:getTrafficDynamicRoute("police-helicopter").spawnAttemptMs == 15000)
    -- No explicit binding before this assertion: exercise the production model provider.
    local slots = flightSlots()
    assert(slots[0] and slots[1] and slots[2], "AIRTRAIN slots missing after ordinary startup")
    assert(traffic:setTrafficPlanesMoving(false))
    local paused = traffic:getTrafficAircraftStatus()
    assert(paused.state=="paused" and paused.active==3)
    assert(traffic:setTrafficPlanesMoving(true))
    assert(traffic:getTrafficAircraftStatus().state=="running" and flightSlots()[1]==slots[1])
    for original, hull in pairs({[215]=452,[233]=473,[248]=484,[249]=484,[257]=446,[264]=446}) do
        local model = exports.vcs_model:getTrafficModelBase(original, "vehicle")
        assert(model==hull and getVehicleType(model)=="Boat")
    end
    local recovered = false
    local provider = getResourceFromName("vcs_model")
    assert(stopResource(provider))
    setTimer(function()
        assert(startResource(provider))
        local recoveryTimer
        recoveryTimer = setTimer(function()
            local rebound = flightSlots()
            if not (rebound[0] and rebound[1] and rebound[2]) then return end
            killTimer(recoveryTimer)
            assert(not traffic:bindTrafficFixedWingModel(411))
            assert(traffic:bindTrafficFixedWingModel(577))
            local same = flightSlots()
            for slot, vehicle in pairs(rebound) do assert(same[slot] == vehicle) end
            assert(traffic:bindTrafficFixedWingModel(false))
            for _, vehicle in pairs(rebound) do assert(not isElement(vehicle)) end
            recovered = true
        end, 100, 0)
    end, 200, 1)

    -- Exercise public mission exports across resources on native MTA elements.
    local missionPed = assert(traffic:createTrafficScriptPed(23,10,10,3,0,37))
    assert(getElementDimension(missionPed)==37 and traffic:acquireTrafficPed(missionPed))
    assert(traffic:assignTrafficPedObjective(missionPed,"walk",12,10,3,"walk"))
    assert(traffic:assignTrafficPedObjective(missionPed,"clear"))
    assert(traffic:assignTrafficPedObjective(missionPed,"ignite") and isElementOnFire(missionPed))
    assert(not traffic:assignTrafficPedObjective(missionPed,"walk",20,10,3,"run"))
    assert(traffic:releaseTrafficPed(missionPed) and not isElementOnFire(missionPed))
    assert(not traffic:releaseTrafficPed(missionPed) and getElementHealth(missionPed)==100)
    destroyElement(missionPed)

    local pedestrian = assert(createPed(7, 0, 0, 3))
    local driver = assert(createPed(7, 0, 8, 3))
    local vehicle = assert(createVehicle(411, 0, 8, 3))
    assert(warpPedIntoVehicle(driver, vehicle, 0))
    local completions = 0
    addEventHandler("npc_hlc:onNPCTaskDone", root, function()
        if source == pedestrian or source == driver then
            completions = completions + 1
            destroyElement(source)
        end
    end)
    assert(hlc:enableHLCForNPC(pedestrian, "walk"))
    assert(hlc:enableHLCForNPC(driver))
    assert(hlc:addNPCTask(pedestrian, {"walkToPos", 0.6, 0, 3, 0.03}))
    assert(hlc:addNPCTask(driver, {"driveToPos", 4, 8, 3, 0.03}))
    setTimer(function()
        assert(isElement(corpse) and isElement(wreck))
        assert(completions == 2, "server fallback did not complete both tasks")
        local actors = {}
        for i = 1, 600 do
            local x, y = 50 + i % 30 * 5, 100 + math.floor(i / 30) * 5
            local ped = assert(createPed(7, x, y, 3))
            actors[i] = ped
            assert(hlc:enableHLCForNPC(ped, "walk"))
            assert(hlc:addNPCTask(ped, {"walkToPos", x + 700, y, 3, 0.1}))
        end
        setTimer(function()
            assert(recovered, "AIRTRAIN failed to recover after model provider restart")
            assert(corpseFaded and wreckFaded and not isElement(corpse) and not isElement(wreck))
            local stats = hlc:getNPCSchedulerStats()
            local moved = getElementPosition(actors[600])
            assert(moved > 50 and stats.activeTasks == 600 and stats.samples >= 100)
            assert(stats.p95Ms <= 3 and stats.p99Ms <= 8,
                ("scheduler p95=%d ms, p99=%d ms, exhausted=%d"):format(
                    stats.p95Ms, stats.p99Ms, stats.budgetExhaustions))
            local summary = ("TRAFFIC_NATIVE_PASS tasks=%d samples=%d p95=%dms p99=%dms exhausted=%d")
                :format(stats.activeTasks, stats.samples, stats.p95Ms, stats.p99Ms, stats.budgetExhaustions)
            -- Restart the production traffic graph while its model provider is offline.
            -- This reproduces the opposite startup order in the same isolated server.
            assert(stopResource(provider))
            local population = getResourceFromName("npchlc_traffic")
            assert(restartResource(population))
            setTimer(function()
                local lateTimer, started
                lateTimer = setTimer(function()
                    if getResourceState(population) ~= "running" or traffic:getTrafficStatus() ~= "ready" then return end
                    if not started then
                        started = assert(startResource(provider))
                        return
                    end
                    local late = flightSlots()
                    if not (late[0] and late[1] and late[2]) then return end
                    killTimer(lateTimer)
                    outputServerLog(summary)
                end, 100, 0)
            end, 250, 1)
        end, 6000, 1)
    end, 1800, 1)
end, 100, 0)
"""


def load(lua, folder, files):
    for filename in files:
        path = folder / filename
        lua.execute(path.read_text(encoding="utf-8"), name=str(path))


def make_server():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, VCS_VEHICLE, ["controllers/vehicle.lua", "controllers/boat.lua"])
    lua.execute('exports={vcs_vehicle={steerBoatTraffic=function(_,...) return steerBoatTraffic(...) end}}')
    load(lua, HLC, [
        "npc_functions_s.lua", "npc_functions.lua", "npc_hlc_s.lua", "control_npc_s.lua",
        "valid_tasks_s.lua", "tasks_s.lua", "task_progress.lua", "traffic_rail.lua", "traffic_physics.lua",
        "actions_s.lua", "math.lua", "const.lua",
    ])
    lua.execute('deliver("onResourceStart", resourceRoot)')
    return lua


def percentile(samples, rank):
    return quantiles(samples, n=100, method="inclusive")[rank - 1]


def check_hlc():
    lua = make_server()
    lua.execute(OWNERSHIP)
    lua = make_server()
    lua.execute("""
    local owner, ped = element("player"), element("ped")
    ped.syncer = owner
    assert(enableHLCForNPC(ped, "walk"))
    assert(addNPCTask(ped, {"walkTrafficToPoint", 2, 0, 0, 0.25}))
    assert(addNPCTask(ped, {"walkTrafficToPoint", 4, 0, 0, 0.25}))
    local packet = packets[#packets]
    assert(packet.owner == owner and packet[1][3][2] == 2 and packet[1][5][2] == 4)
    ped.x = 2
    tick()
    assert(packets[#packets][1][3][2] == 4)
    assert(clearNPCTasks(ped))
    for _=1,4 do assert(addNPCTask(ped, {"walkToPos", 2, 0, 0, 0.25})) end
    assert(addNPCTask(ped, {"walkToPos", 7, 0, 0, 0.25}))
    tick()
    assert(getNPCTaskCount(ped)==1 and packets[#packets][1][3][2]==7)
    """)
    lua.execute("""
    local vehicle = element("vehicle")
    local rail = {"driveTrafficRail", -12,0,0, 0,0,0, 12,0,0, 24,0,0, 10,0,0.6}
    local x, y, z = sampleNPCTrafficRail(rail, 0.5)
    assert(x == 6 and y == 0 and z == 0)
    function getElementRotation() return 0, 0, 0 end
    function getElementAngularVelocity() return 0.01, 0.02, 0 end
    function setElementAngularVelocity(_, wx, wy) assert(wx == 0.01 and wy == 0.02) end
    function setElementVelocity(v, vx, vy, vz) v.vx, v.vy, v.vz = vx, vy, vz end
    function setElementPosition() error("cruise must use native motion") end
    local function drive(v, path, elapsed)
        advanceNPCTrafficRail(v, path, elapsed)
        v.x, v.y = v.x + v.vx * elapsed / 20, v.y + v.vy * elapsed / 20
    end
    vehicle.vz = -0.17
    for _ = 1, 12 do drive(vehicle, rail, 100) end
    assert(vehicle.vz == -0.17)
    assert(isNPCTaskComplete(nil, vehicle, rail))
    do
        local hull = element("vehicle"); hull.vehicleType="Boat"
        hull.fx, hull.fy, hull.vz = 1,0,-0.13
        local turn = {"driveTrafficRail",-20,0,0, 0,0,0, 20,0,0, 20,20,0, 10,0,0,
            0,20,40,0}
        local originalAngular = setElementAngularVelocity
        local getRotation, setRotation = getElementRotation, setElementRotation
        hull.heading = 270
        function getElementRotation() return 4,-3,hull.heading end
        function setElementRotation(_,pitch,roll,heading)
            assert(pitch == 4 and roll == -3)
            hull.heading = heading % 360
        end
        function setElementAngularVelocity() error("traffic boat wrote angular velocity") end
        for _=1,180 do
            advanceNPCTrafficRail(hull,turn,20,nil,true)
            assert(hull.vz==-0.13)
            hull.x, hull.y = hull.x + hull.vx, hull.y + hull.vy
        end
        assert(math.abs(hull.x-20)<2 and hull.y>10 and hull.vy>math.abs(hull.vx), "boat missed waterway turn")
        assert(math.min(hull.heading,360-hull.heading)<45, "bow failed to follow waterway turn")
        getElementRotation, setElementRotation = getRotation, setRotation
        setElementAngularVelocity = originalAngular
    end

    local window = {"driveTrafficRail", -12,0,0, 0,0,0, 12,0,0, 24,0,0, 10,0,0.6,
        0,36,0,0, 0,48,0,0}
    local blocked = element("vehicle")
    for frame = 1, 150 do advanceNPCTrafficRail(blocked, window, 20) end
    assert(blocked.x == 0 and not hasCompletedNPCTrafficRail(blocked, window, true))
    local refreshed = {"driveTrafficRail", 0,0,0, 12,0,0, 24,0,0, 36,0,0, 10,0,0.6,
        0,48,0,0, 0,60,0,0}
    assert(#normalizeNPCTask(window) == #window)
    local owner, observer = element("vehicle"), element("vehicle")
    for frame = 1, 145 do
        local previous = owner.x
        -- Simulate the new window arriving 500 ms after the first boundary.
        local task = frame <= 85 and window or refreshed
        drive(owner, task, 20)
        assert(math.abs(owner.x - previous - 0.2) < 0.025)
        if frame == 59 or frame == 65 then
            observer.x = owner.x
            assert(isNPCTaskComplete(nil, observer, window, true) == (frame == 65))
        end
    end
    assert(owner.x > 28.9 and owner.x < 29.1)

    local previous = owner.x
    advanceNPCTrafficRail(owner, refreshed, 20)
    assert(owner.x == previous)
    drive(owner, refreshed, 20)
    assert(math.abs(owner.x - previous - 0.2) < 0.025)

    local approaching = element("vehicle")
    window[17] = 1
    for _ = 1, 200 do drive(approaching, window, 20) end
    assert(approaching.x >= 16 and approaching.x < 24)
    local redPosition = approaching.x
    function getTrafficLightState() return 0 end
    for _ = 1, 60 do drive(approaching, window, 20) end
    assert(approaching.x > redPosition)

    local speedWindow = {"driveTrafficRail", -10,0,0, 0,0,0, 10,0,0, 20,0,0, 10,0,0.6,
        0,30,0,0, 0,100,0,0, 0,1,2}
    assert(#normalizeNPCTask(speedWindow) == 27)
    speedWindow[26] = 4
    assert(not normalizeNPCTask(speedWindow))
    speedWindow[26] = 1
    local moving = element("vehicle")
    for _ = 1, 50 do drive(moving, speedWindow, 20) end
    assert(math.abs(moving.x - 10) < 0.001)
    for _ = 1, 20 do drive(moving, speedWindow, 20) end
    assert(moving.x > 14 and moving.x < 15)
    assert(getNPCTrafficDriveMultiplier(moving, 2, 2000) == 2)
    assert(getNPCTrafficDriveMultiplier(moving, 1, 1000) == 1.5)
    assert(getNPCTrafficDriveMultiplier(moving, 3, 1000) == 1)
    local physical = {"driveTrafficToPoint", 0,10,0, 3, 2, 0,1, 15,10,0, 0, 1,0}
    assert(#normalizeNPCTask(physical) == 14)
    moving.x, moving.y = 9, 10
    assert(isNPCTaskComplete(nil, moving, physical, true))
    moving.x, moving.y = 0, 0
    assert(not isNPCTaskComplete(nil, moving, physical, true))
    local route = {"driveTrafficPhysics", 1, 11, {0,0,0},
        {{0,0,0,10,0,0,1,0,1}, {1,0,15,10,0,1,0,2,0}}}
    assert(normalizeNPCTask(route))
    for style=0,6 do
        route[6],speedWindow.style=style,style
        assert(normalizeNPCTask(route)[6]==style)
        local rail=assert(normalizeNPCTask(speedWindow))
        assert(rail.style==style and #rail==27 and rail[27]==2)
        function getTrafficLightState() return 2 end
        local stops=style~=2 and style~=3 and style~=4
        assert(isNPCTrafficSignalClosed(1,style)==stops)
        rail[15]=1
        assert(isNPCTrafficRailWaitingForSignal(rail,8,0,0,1,0)==stops)
    end
    for _,invalid in ipairs({-1,7,2.5,"2",false}) do
        route[6],speedWindow.style=invalid,invalid
        assert(not normalizeNPCTask(route) and not normalizeNPCTask(speedWindow))
    end
    route[6],speedWindow.style=nil,nil
    route[5][1][7] = 2
    assert(not normalizeNPCTask(route))
    route[5][1][7] = 1
    moving.x, moving.y = 0, 7
    function getTrafficLightState() return 2 end
    assert(not isNPCTaskComplete(nil, moving, route, true))
    -- A siren can leave the driver parallel to the road beyond the normal
    -- lane tolerance. Keep its stop line when evaluating the watchdog.
    moving.x, moving.y = 3.4,5.28
    local shortcut, displacedAtRed = getNPCTrafficPhysicsRejoin(route, moving)
    assert(not shortcut and not displacedAtRed, "pulling aside at red authorized a new route")
    moving.x, moving.y = 0,7
    function getTrafficLightState() return 0 end
    moving.vx = 0.2
    assert(not isNPCTaskComplete(nil, moving, route, true))
    moving.vx = 0
    moving.fx, moving.fy = 0, -1
    assert(not isNPCTaskComplete(nil, moving, route, true))
    moving.fx, moving.fy = 0, 1
    assert(isNPCTaskComplete(nil, moving, route, true))
    moving.vy = -0.008
    assert(not isNPCTaskComplete(nil, moving, route, true))
    moving.vy = 0
    assert(not isNPCTaskComplete(nil, moving, route, false))
    assert(canNPCTrafficPhysicsAvoid(route, 1, 0, 0, 0, 0.25, 0.97, 4, 1))
    assert(not canNPCTrafficPhysicsAvoid(route, 1, 1.4, 0, 0, 0.25, 0.97, 4, 1))
    moving.x, moving.y, moving.fx, moving.fy = 15, 10, 1, 0
    assert(getNPCTrafficPhysicsRejoin(route, moving) == 2)
    moving.y = 14
    local rejoin, displaced = getNPCTrafficPhysicsRejoin(route, moving)
    assert(not rejoin and displaced)
    moving.vx = 0.12
    rejoin, displaced = getNPCTrafficPhysicsRejoin(route, moving)
    assert(not rejoin and not displaced)
    local railDriver, unsynced = element("ped"), element("vehicle")
    railDriver.vehicle, unsynced.driver = unsynced, railDriver
    assert(enableHLCForNPC(railDriver))
    assert(setNPCTask(railDriver, rail))
    for _ = 1, 8 do tick() end
    assert(unsynced.x == 0 and unsynced.y == 0)
    """)
    print("NPCHLC queue, numeric arguments, fallback, owner handoff, vehicle takeover, event ordering and cleanup passed")

    client = LuaRuntime()
    client.execute(SERVER_MOCK)
    load(client, HLC, [
        "npc_functions.lua", "npc_hlc_c.lua", "control_npc_c.lua", "tasks_c.lua", "task_progress.lua", "math.lua",
        "traffic_rail.lua", "traffic_rail_c.lua", "traffic_physics.lua", "traffic_physics_c.lua",
        "traffic_pedestrian_vehicles_c.lua", "traffic_pedestrians_c.lua",
    ])
    client.execute(CLIENT_OWNERSHIP)
    load(client, HLC, ["actions_c.lua"])
    client.execute("""
    local npc, vehicle = element("ped"), element("vehicle")
    npc["npc_hlc"], npc["npc_hlc:profile"] = true, {"walk", 1, 0.22}
    vehicle.syncer, vehicle.driver, npc.vehicle = localPlayer, npc, vehicle
    function getElementBoundingBox() return -1,-2,-0.6,1,2,0.8 end
    function processLineOfSight() return false end
    local inputs = {}
    function setPedCameraRotation() end
    local opposite = {vehicle_left="vehicle_right", vehicle_right="vehicle_left",
        steer_forward="steer_back", steer_back="steer_forward", accelerate="brake_reverse", brake_reverse="accelerate"}
    function setPedAnalogControlState(_, name, value)
        assert(value == 0 or (inputs[opposite[name]] or 0) == 0, name)
        inputs[name] = value
    end
    function setPedControlState(_, name, value) inputs[name] = value end
    setNPCVehicleInputs(npc, -0.8, 0.75, false, -0.25)
    assert(inputs.vehicle_left == 0.8 and inputs.steer_forward == 0.25 and inputs.accelerate == 0.75)
    setNPCVehicleInputs(npc, 0.4, -0.5, false, 0.6)
    assert(inputs.vehicle_right == 0.4 and inputs.steer_back == 0.6 and inputs.brake_reverse == 0.5)
    setNPCVehicleInputs(npc, 0, 0, false)
    vehicle.y = 9
    local turn = {"driveTrafficToPoint", 0,10,0, 3, 1, 0,1, 15,10,0, 0, 1,0}
    deliver("npc_hlc:control", resourceRoot, npc, 7, turn, vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_right > 0 and inputs.vehicle_left == 0 and inputs.accelerate > 0)
    local left = {"driveTrafficToPoint", -15,10,0, 3, 2, -1,0}
    deliver("npc_hlc:control", resourceRoot, npc, 8, left, vehicle)
    assert(inputs.vehicle_right > 0)
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_left > 0 and inputs.vehicle_right == 0)

    function isElementFrozen(car) return car.frozen == true end
    function getVehicleHandling() return {steeringLock=35} end
    local window = {"driveTrafficPhysics", 1, 11, {0,0,0},
        {{0,0,0,10,0,0,1,0,0}, {1,0,15,10,0,1,0,2,0}, {2,0,15,25,0,0,1,0,0}}}
    vehicle.x, vehicle.y = 0, 7
    deliver("npc_hlc:control", resourceRoot, npc, 9, window, vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_right > 0 and inputs.accelerate > 0)
    vehicle.x, vehicle.y, vehicle.fx, vehicle.fy = 12, 10, 1, 0
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_left > 0 and inputs.vehicle_right == 0)
    vehicle.syncer = element("player")
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_left == 0 and inputs.accelerate == 0 and not inputs.handbrake)
    vehicle.syncer = localPlayer
    -- The incoming tangent reaches the far curb, but this green-light
    -- route turns right. A barrier across the exit lane must still win.
    local oldCast,oldDebug = processLineOfSight,recordNPCDebugDriving
    local decision,exitBarrier
    function recordNPCDebugDriving(reason) decision=reason end
    function processLineOfSight(x,y,z,ex,ey)
        if y<12 and ey>=12 then
            return true,x+(ex-x)*(12-y)/(ey-y),12,z
        end
        if exitBarrier and x<3 and ex>=3 then
            return true,3,y+(ey-y)*(3-x)/(ex-x),z
        end
        return false
    end
    vehicle.x,vehicle.y,vehicle.fx,vehicle.fy,vehicle.vx,vehicle.vy=0,0,0,1,0,0.18
    for i=1,2 do
        exitBarrier=i==2
        resetNPCTrafficPhysicsSensor(vehicle)
        beginNPCTrafficPhysicsFrame()
        performTask.driveTrafficPhysics(npc,window,16,{})
        assert((decision=="obstacle")==exitBarrier,decision)
    end
    processLineOfSight,recordNPCDebugDriving=oldCast,oldDebug
    -- Style 2 close ram may make contact with its own target, but a
    -- different car on the same line must steer the officer around it.
    local targetCar=element("vehicle")
    targetCar.x,targetCar.y,targetCar.fx,targetCar.fy=0,10,0,1
    function getElementsWithinRange() return {vehicle,targetCar} end
    beginNPCTrafficPhysicsFrame()
    assert(getNPCPoliceAvoidance(vehicle,targetCar,0,20,{})==0)
    assert(getNPCPoliceAvoidance(vehicle,nil,0,20,{})~=0)
    function getElementsWithinRange() return {} end
    function processLineOfSight(x,y,z,ex,ey)
        if math.abs(ex-x)<0.5 then return true,x,y+3,z end
        return false
    end
    assert(getNPCPoliceAvoidance(vehicle,targetCar,0,20,{})~=0)
    processLineOfSight=oldCast
    -- A police Electra approaching a right angle must brake before it
    -- crosses the far curb. The same clear turn still admits a cruising car.
    vehicle.x,vehicle.y,vehicle.vx,vehicle.vy=0,3,0,0.16
    window[3],window[6]=25,2
    vehicle["npchlc_traffic:originalModel"]=191
    for _,siren in ipairs({false,true}) do
        vehicle.siren=siren
        resetNPCTrafficPhysicsSensor(vehicle)
        beginNPCTrafficPhysicsFrame()
        performTask.driveTrafficPhysics(npc,window,16,{})
        assert((inputs.brake_reverse>0)==siren,"tight pursuit corner must brake with the original handling")
    end
    window[3],window[6],vehicle.siren=11,nil,false
    -- At pursuit speed two collinear waypoints can fit in the braking
    -- distance for a later right turn. Test the turn beyond the current link.
    vehicle.y,vehicle.vy,vehicle.siren=0,0.40,true
    local previewBend={"driveTrafficPhysics",1,43,{0,-10,0},{
        {10,0,0,12,0,0,1,0,0},{11,0,0,24,0,0,1,0,0},{12,0,32,24,0,1,0,0,0}},2}
    resetNPCTrafficPhysicsSensor(vehicle);beginNPCTrafficPhysicsFrame()
    performTask.driveTrafficPhysics(npc,previewBend,16,{})
    assert(inputs.brake_reverse>0,"brake for the second link's bend")
    vehicle.siren=false
    resetNPCTrafficPhysicsSensor(vehicle)
    vehicle.vy=0
    vehicle.x, vehicle.y, vehicle.fx, vehicle.fy = 0, 7, 0, 1
    window[5][1][9] = 1
    deliver("npc_hlc:control", resourceRoot, npc, 10, window, vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.accelerate == 0 and inputs.handbrake)
    function getTrafficLightState() return 0 end
    deliver("onClientPreRender", root, 16)
    assert(inputs.vehicle_right > 0 and inputs.accelerate > 0 and not inputs.handbrake)

    vehicle.vx, vehicle.vy = 0.2, 0.08
    deliver("onClientVehicleCollision", vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.accelerate == 0 and inputs.brake_reverse == 1)
    assert(inputs.vehicle_left == 0 and inputs.vehicle_right == 0)

    local straight = {"driveTrafficPhysics", 3, 11, {0,0,0}, {{0,0,0,40,0,0,1,0,1}}}
    vehicle.x, vehicle.y, vehicle.vx, vehicle.vy = 0, 20, 0, 0.3
    function getTrafficLightState() return 2 end
    deliver("npc_hlc:control", resourceRoot, npc, 11, straight, vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.accelerate == 0 and inputs.brake_reverse > 0.8)

    function getTrafficLightState() return 0 end
    vehicle.y, vehicle.vy = 10, 0.1
    local casts = 0
    function processLineOfSight(x, y, z, _, _, _, _, _, _, _, _, _, _, _, ignored)
        assert(ignored == vehicle)
        casts = casts + 1
        if x > 0.5 then return true, x, y + 1, z end
        return false
    end
    deliver("onClientVehicleCollision", vehicle)
    deliver("onClientPreRender", root, 16)
    assert(casts == 3 and inputs.accelerate == 0 and inputs.brake_reverse == 1)
    deliver("onClientPreRender", root, 16)
    assert(casts == 3)
    function processLineOfSight() return false end
    local crossing = element("vehicle", -6)
    crossing.y, crossing.vx, crossing.fx, crossing.fy = 18, 0.12, 1, 0
    function getElementsWithinRange() return {vehicle, crossing} end
    deliver("onClientVehicleCollision", vehicle)
    deliver("onClientPreRender", root, 16)
    assert(inputs.accelerate == 0 and inputs.brake_reverse > 0)

    function getElementsWithinRange() return {} end
    local function render(ms)
        now = now + ms
        deliver("onClientPreRender", root, ms)
    end
    local frontBlocked, rightClear, rearBlocker, lead = true, false, nil, nil
    function getElementsWithinRange()
        return lead and {vehicle, lead} or {vehicle}
    end
    function processLineOfSight(x, y, z, ex, ey, _, _, cars)
        if ey < y and rearBlocker and (rearBlocker.kind ~= "vehicle" or cars) then
            return true, x, y - 0.5, z, rearBlocker
        end
        if ey > y and frontBlocked and (not lead or cars) and (not rightClear or ex - x <= 0.2) then
            return true, x, y + 0.2, z, lead
        end
        return false
    end
    vehicle.vy = 0
    rightClear = true
    render(100)
    assert(inputs.vehicle_right > 0 and inputs.accelerate > 0 and not inputs.handbrake)
    rightClear = false
    render(100)
    assert(inputs.accelerate == 0 and inputs.handbrake)
    render(999)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    render(1)
    assert(inputs.accelerate == 0 and inputs.brake_reverse > 0 and not inputs.handbrake)
    render(699)
    assert(inputs.brake_reverse > 0 and not inputs.handbrake)
    render(1)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    frontBlocked = false
    render(16)
    assert(inputs.accelerate > 0 and inputs.accelerate < 0.7 and not inputs.handbrake)

    frontBlocked = true
    render(100)
    render(1000)
    assert(inputs.brake_reverse > 0 and not inputs.handbrake)
    rearBlocker = element("ped")
    vehicle.vy = -0.014
    render(16)
    assert(inputs.accelerate == 0 and inputs.brake_reverse == 0 and inputs.handbrake)
    rearBlocker, vehicle.vy = element("vehicle"), 0
    render(100)
    render(1000)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)

    rearBlocker, lead = nil, element("vehicle")
    lead.x, lead.y = vehicle.x, vehicle.y + 5
    render(100)
    render(1000)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    lead.vy = 0.08
    render(100)
    assert(inputs.accelerate > 0 and not inputs.handbrake)
    do
        local nearby = getElementsWithinRange
        local function drive()
            beginNPCTrafficPhysicsFrame()
            resetNPCTrafficPhysicsSensor(vehicle)
            performTask.driveTrafficPhysics(npc,straight,16,{})
        end
        lead.y, lead.vy, lead.fy = vehicle.y+5.5, 0, -1
        straight[6] = 2
        drive()
        assert(inputs.accelerate==0 and inputs.handbrake, "opposing car before arbitration")
        setElementData(vehicle,"npchlc_traffic:headOnBlocker",lead)
        drive()
        assert(inputs.accelerate>0 and inputs.vehicle_left+inputs.vehicle_right>0, "winner failed to steer")
        local third = element("vehicle",vehicle.x)
        third.y = vehicle.y+4
        function getElementsWithinRange() return {vehicle,lead,third} end
        drive()
        assert(inputs.accelerate==0 and inputs.handbrake, "winner entered a third vehicle")
        getElementsWithinRange = nearby
        local previousY = vehicle.y
        vehicle.y, lead.y = 34,39.5
        function getTrafficLightState() return 2 end
        drive()
        assert(inputs.accelerate>0 and not inputs.handbrake, "avoid-cars winner still obeyed the signal")
        straight[6] = 5
        drive()
        assert(inputs.accelerate==0 and inputs.handbrake, "light-obeying winner ran a red light")
        function getTrafficLightState() return 0 end
        vehicle.y = previousY
        setElementData(vehicle,"npchlc_traffic:headOnBlocker",false)
        straight[6] = nil
        lead.y, lead.x = vehicle.y+5.5, vehicle.x+3.25
        drive()
        assert(inputs.accelerate>0 and not inputs.handbrake, "adjacent opposing lane blocked physics")
    end
    lead, vehicle.y = nil, 32
    function getTrafficLightState() return 2 end
    render(100)
    render(1000)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    function getTrafficLightState() return 0 end
    render(100)
    render(1000)
    assert(inputs.brake_reverse > 0)
    vehicle.syncer = element("player")
    render(16)
    assert(inputs.brake_reverse == 0 and inputs.accelerate == 0 and not inputs.handbrake)
    vehicle.syncer = localPlayer
    render(16)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)

    -- PS2 random-created cruise waits thirty seconds; other seeds keep waiting.
    setElementData(vehicle, "npchlc_traffic:stuckReverse", 0)
    render(31000)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    setElementData(vehicle, "npchlc_traffic:stuckReverse", 400)
    render(20)
    render(29999)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    render(1)
    assert(inputs.brake_reverse > 0 and not inputs.handbrake)
    render(399)
    assert(inputs.brake_reverse > 0 and not inputs.handbrake)
    render(1)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)

    local long = {"driveTrafficPhysics", 4, 12, {0,0,0}, {{3,0,0,1000,0,0,1,0,1}}}
    frontBlocked, vehicle.y, vehicle.vy = false, 0, 0.2
    render(2050)
    deliver("npc_hlc:control", resourceRoot, npc, 12, long, vehicle)
    local speed = 10
    for _ = 1, 500 do
        render(20)
        speed = math.max(0, speed + 0.02 * (6 * inputs.accelerate - 0.12 * speed - 5 * inputs.brake_reverse))
        vehicle.vy, vehicle.y = speed / 50, vehicle.y + speed * 0.02
    end
    assert(math.abs(speed - long[3]) < 0.35 and inputs.accelerate > 0.1)
    vehicle.y = 993
    function getTrafficLightState() return 2 end
    render(16)
    assert(inputs.accelerate == 0 and inputs.brake_reverse == 1)
    local target = element("player", 10)
    target.y, vehicle.vy = vehicle.y+15, 0
    deliver("npc_hlc:control", resourceRoot, npc, 13, {"driveAtPed", target}, vehicle)
    render(16)
    assert(inputs.vehicle_right > 0 and inputs.accelerate > 0)
    vehicle.vy = 0.2
    deliver("npc_hlc:control", resourceRoot, npc, 14, {"stopVehicle"}, vehicle)
    render(16)
    assert(inputs.brake_reverse == 1 and inputs.accelerate == 0)

    local function shortWindow(first)
        local segments={}
        for seq=first,first+7 do
            segments[#segments+1]={seq,0,0,seq*4,0,0,1,0,0}
        end
        return assert(normalizeNPCTrafficPhysics({"driveTrafficPhysics",first,20,{0,(first-1)*4,0},segments}))
    end
    local hinted,hints
    addEventHandler("npc_hlc:onRouteLow",root,function(first,last)
        if first==1 then hinted,hints=now,hints+1 end
    end)
    for i,lag in ipairs({50,150,300}) do
        vehicle.x,vehicle.y,vehicle.vx,vehicle.vy=0,0,0,0.3
        hinted,hints=nil,0
        local revision=20+i*2
        local firstWindow=shortWindow(1)
        deliver("npc_hlc:control",resourceRoot,npc,revision,firstWindow,vehicle)
        local renewed=false
        for frame=1,122 do
            vehicle.y=vehicle.y+0.24
            render(16)
            assert(inputs.accelerate>0 and inputs.brake_reverse==0 and not inputs.handbrake,table.concat({i,frame,vehicle.y,hints,inputs.accelerate,inputs.brake_reverse},','))
            if hinted and not renewed and now-hinted>=lag then
                local index=getNPCTrafficWindowProgress(firstWindow,vehicle)
                deliver("npc_hlc:control",resourceRoot,npc,revision+1,shortWindow(index),vehicle)
                renewed=true
            end
        end
        assert(renewed and hints==1)
    end
    -- Exhaust the frame budget immediately before this car's turn.
    local blockers={}
    local sensorTask=shortWindow(1)
    local function saturate()
        beginNPCTrafficPhysicsFrame()
        for i=1,12 do
            local car=element("vehicle")
            car.vy=0.3
            blockers[i],npc.vehicle=car,car
            performTask.driveTrafficPhysics(npc,sensorTask,16,{})
        end
        npc.vehicle=vehicle
    end
    vehicle.y=0
    now=now+250
    beginNPCTrafficPhysicsFrame()
    performTask.driveTrafficPhysics(npc,sensorTask,16,{})
    now=now+90
    saturate()
    performTask.driveTrafficPhysics(npc,sensorTask,16,{})
    assert(inputs.accelerate>0 and inputs.brake_reverse==0)
    now=now+90
    frontBlocked,rightClear=true,false
    saturate()
    performTask.driveTrafficPhysics(npc,sensorTask,16,{})
    assert(inputs.brake_reverse>0 and inputs.accelerate==0)
    """)
    client.execute("""
    local vehicle = element("vehicle")
    local water = 6
    function getElementModel() return 445 end
    function getVehicleType() return "Bike" end
    function getElementDistanceFromCentreOfMassToBaseOfModel() return 0.7 end
    function getVehicleComponents() return {wheel_lf_dummy=false, wheel_lb_dummy=false} end
    function getVehicleModelWheelSize() return {front_axle=0.8, rear_axle=0.8} end
    function getVehicleComponentPosition(_, name) return 0, name == "wheel_lf_dummy" and 1.5 or -1.5, -0.2 end
    function getVehicleWheelScale() return 1 end
    function processLineOfSight(x, y) return true, x, y, 10 + x * 0.1 end
    function getWaterLevel() return water end
    local z, pitch = groundNPCTrafficRail(vehicle, 0, 0, 10.6, 1, 0, 0.6)
    local clearance = 0.6 * math.sqrt(1.01)
    assert(math.abs(z - 10 - clearance) < 0.0001 and math.abs(pitch - math.deg(math.atan(0.1))) < 0.0001)
    z = groundNPCTrafficRail(vehicle, 0.5, 0, 10.65, 1, 0, 0.6)
    assert(math.abs(z - 10.05 - clearance) < 0.0001)
    water = 12
    assert(groundNPCTrafficRail(vehicle, 1, 0, 10.7, 1, 0, 0.6) == false)

    local modelResource = {}
    local assetsReady = false
    local metadata = {{2.144, -0.62, 0.35}, {-2.162, -0.62, 0.36}}
    function getResourceFromName() return modelResource end
    function getResourceState() return "running" end
    setElementData(vehicle, "npchlc_traffic:modelProvider", "custom_models")
    function getResourceExportedFunctions() return {"getTrafficVehicleGroundGeometry"} end
    function call(resource, name)
        assert(resource == modelResource and name == "getTrafficVehicleGroundGeometry")
        return assetsReady and metadata
    end
    local ready = false
    function getVehicleType() return "Automobile" end
    function getVehicleHandling() return {suspensionUpperLimit=0.30, suspensionLowerLimit=-0.15, suspensionForceLevel=2} end
    function getVehicleComponentPosition(_, name)
        if not ready then return false end
        if name == "wheel_lf_dummy" then return 0, 2.144, -0.71 end
        return 0, -2.162, -0.69
    end
    function getVehicleComponentScale(_, name) return 1, 1, name == "wheel_lf_dummy" and 1.2 or 1.1 end
    local probes = {}
    function processLineOfSight(x, y) probes[#probes + 1] = x return true, x, y, 10 end
    water = 6
    resetNPCTrafficRailGround(vehicle)
    assert(math.abs(groundNPCTrafficRail(vehicle, 0, 10, 10.6, 1, 0, 0.6) - 10.6) < 0.0001)
    local before = #probes
    assetsReady = true
    deliver("npc_hlc:onVehicleGroundGeometry", vehicle)
    z, pitch = groundNPCTrafficRail(vehicle, 0, 10, 10.6, 1, 0, 0.6)
    local fallbackPitch = math.rad(pitch)
    assert(math.abs(z + 2.144 * math.sin(fallbackPitch) - 0.71375 * math.cos(fallbackPitch) - 0.35 - 10) < 0.0001)
    assert(math.abs(z - 2.162 * math.sin(fallbackPitch) - 0.71375 * math.cos(fallbackPitch) - 0.36 - 10) < 0.0001)
    assert(math.abs(probes[before + 2] - 2.144) < 0.0001 and math.abs(probes[before + 3] + 2.162) < 0.0001)
    ready = true
    deliver("onClientElementStreamIn", vehicle)
    z, pitch = groundNPCTrafficRail(vehicle, 0, 10, 10.6, 1, 0, 0.6)
    local angle = math.rad(pitch)
    local frontBottom = z + 2.144 * math.sin(angle) - 0.71 * math.cos(angle) - 0.35 * 1.2
    local rearBottom = z - 2.162 * math.sin(angle) - 0.69 * math.cos(angle) - 0.36 * 1.1
    assert(math.abs(frontBottom - 10) < 0.0001 and math.abs(rearBottom - 10) < 0.0001)

    setElementData(vehicle, "npchlc_traffic:modelProvider", false)
    function getVehicleComponents()
        return {wheel_lf_dummy=false, wheel_rf_dummy=false, wheel_lb_dummy=false, wheel_rb_dummy=false}
    end
    function getVehicleComponentPosition(_, name)
        return name:sub(7,7) == "l" and -0.8 or 0.8, name:sub(8,8) == "f" and 1.5 or -1.5, -0.2
    end
    local crossfall, curb, streamed = 0.08, false, true
    function processLineOfSight(x, y, high, _, _, low)
        if not streamed then return false end
        local height = 10 - crossfall * y + (curb and x > 1 and y > 0 and 0.25 or 0)
        if high >= 14 and low <= 14 then height = 14 end
        if high < height or low > height then return false end
        return true, x, y, height, nil, 0, crossfall, 1
    end
    resetNPCTrafficRailGround(vehicle)
    local roll
    z, pitch, roll = groundNPCTrafficRail(vehicle, 0, 0, 10.6, 1, 0, 0.6)
    assert(math.abs(roll + math.deg(math.atan(0.08))) < 0.01 and math.abs(pitch) < 0.01)
    assert(z > 10.55 and z < 10.65)
    crossfall, curb = 0, true
    resetNPCTrafficRailGround(vehicle)
    z, pitch, roll = groundNPCTrafficRail(vehicle, 0, 0, 10.6, 1, 0, 0.6)
    local p, r = math.rad(pitch), math.rad(roll)
    for _, along in ipairs({1.5, -1.5}) do
        for _, side in ipairs({-0.8, 0.8}) do
            local wheelBottom = z + (along * math.sin(p) - 0.2 * math.cos(p)) * math.cos(r) - side * math.sin(r) - 0.4
            local height = along > 1 and side < 0 and 10.25 or 10
            assert(wheelBottom >= height - 0.001)
        end
    end
    now, streamed = now + 80, false
    assert(groundNPCTrafficRail(vehicle, 1, 0, 10.6, 1, 0, 0.6))
    now = now + 80
    assert(not groundNPCTrafficRail(vehicle, 1, 0, 10.6, 1, 0, 0.6))

    local collisionZ = 9.87
    function processLineOfSight(x, y, fromZ, _, _, toZ)
        local high, low = math.max(fromZ, toZ), math.min(fromZ, toZ)
        local upperDeck = 10.74
        if fromZ > toZ and low <= upperDeck and upperDeck <= high then
            return true, x, y, upperDeck, nil, 0, 0, 1
        end
        if high < collisionZ or low > collisionZ then return false end
        return true, x, y, collisionZ, nil, 0, 0, 1
    end
    resetNPCTrafficRailGround(vehicle)
    assert(math.abs(groundNPCTrafficRail(vehicle, -653.1, 636.6, 9.6, 1, 0, 0.6) - 10.47) < 0.001)
    collisionZ = 10.6
    resetNPCTrafficRailGround(vehicle)
    assert(math.abs(groundNPCTrafficRail(vehicle, 0, 0, 9.6, 1, 0, 0.6) - 11.2) < 0.001)

    local baseComponents, basePosition = getVehicleComponents, getVehicleComponentPosition
    function getVehicleComponents()
        local result = baseComponents()
        result.wheel_lm_dummy, result.wheel_rm_dummy = true, true
        return result
    end
    function getVehicleComponentPosition(v, name)
        if name:sub(8,8) == "m" then return name:sub(7,7) == "l" and -0.8 or 0.8, 0, -0.32 end
        return basePosition(v, name)
    end
    function processLineOfSight(x, y, high, _, _, low)
        local height = x == 0 and y > 0.7 and 10.30 or 10
        if height > high or height < low then return false end
        return true, x, y, height, nil, 0, 0, 1
    end
    resetNPCTrafficRailGround(vehicle)
    assert(math.abs(groundNPCTrafficRail(vehicle, 0, 0, 10.6, 1, 0, 0.6) - 11.02) < 0.001)

    local merge = {"driveTrafficRail", -10,0,0, 0,0,0, 30,5,0, 50,5,0, 16,0,0.6}
    local target = element("vehicle", 13)
    target.y, target.fx, target.fy = 2.3, 1, 0
    function getElementsWithinRange() return {vehicle, target} end
    assert(limitNPCTrafficRailMerge(vehicle, merge, 1, 0, {}, 16, 0, 0, 0, 1, 0, now) < 16)
    target.y = 9
    assert(limitNPCTrafficRailMerge(vehicle, merge, 1, 0, {}, 16, 0, 0, 0, 1, 0, now) == math.huge)
    target.x, target.y, target.vx = -3, 3.5, 0.45
    assert(limitNPCTrafficRailMerge(vehicle, merge, 1, 0, {}, 16, 0, 0, 0, 1, 0, now) < 16)

    -- Check both roles. In the angled case the corners project onto both
    -- axes of the first car, but the second car's side axis separates them.
    local car = {fx=1, fy=0, width=1, length=2}
    local facing = {fx=-1, fy=0, width=1, length=2}
    local diagonal = {fx=math.sqrt(0.5), fy=math.sqrt(0.5), width=1, length=2}
    local across = {fx=0, fy=1, width=1, length=2}
    local function contact(other, x, y, vx, vy, expected)
        local function check(actual)
            if expected then assert(actual and math.abs(actual-expected)<0.0001)
            else assert(not actual, "separated footprints reported contact") end
        end
        check(getNPCTrafficFootprintContact(x,y,vx,vy,1,0,1,2,other,2))
        check(getNPCTrafficFootprintContact(-x,-y,-vx,-vy,other.fx,other.fy,1,2,car,2))
    end
    contact(facing, 14,3.25, -10,0, nil)
    contact(diagonal, 3.8,-2.7, 0,0, nil)
    contact(facing, 14,0, -10,0, 1)
    contact(across, 0,-8, 0,5, 1)
    contact(across, 0,8, 0,5, nil)
    contact(car, 6,0, -2,0, 1)

    local road = {"driveTrafficRail", -10,0,0, 0,0,0, 30,0,0, 50,0,0, 16,0,0.6}
    target.x, target.y, target.vx, target.fx = 10, 3.25, -0.12, -1
    local function railLimit()
        return limitNPCTrafficRailMerge(vehicle,road,1,0,{},12,0,0,0,1,0,now)
    end
    local cap, _, blocker = railLimit()
    assert(cap==math.huge and not blocker)
    target.y = 0
    cap, _, blocker = railLimit()
    assert(cap<12 and blocker==target)
    target.fx, target.vx = 1, 0
    cap, _, blocker = railLimit()
    assert(cap<12 and blocker==target)
    target.y = 6
    assert(railLimit()==math.huge)
    vehicle.fx, vehicle.fy = 1, 0
    target.x, target.y = -3.9, 0
    assert(railLimit()==math.huge, "a touching follower must let the lead car pull away")
    target.x = 3.9
    assert(railLimit()==0, "the follower still brakes for the same bumper contact")
    """)
    load(client, VCS_VEHICLE, ["controllers/vehicle.lua","controllers/boat.lua"])
    client.execute("""
    exports={vcs_vehicle={
        steerBoatTraffic=function(_,...) return steerBoatTraffic(...) end,
        getBoatTrafficSpeedLimit=function(_,...) return getBoatTrafficSpeedLimit(...) end}}
    function getVehicleType() return "Boat" end
    function getElementBoundingBox() return -1,-3,-0.5,1,3,1 end
    function processLineOfSight() return false end  -- lateral merger misses the bow ray
    function getWaterLevel() return 0 end
    function getElementAngularVelocity() error("ambient boat read angular velocity") end
    function getElementRotation() return 0,0,270 end
    function setElementAngularVelocity() error("ambient boat wrote angular velocity") end
    function setElementVelocity(v,x,y,z) v.vx,v.vy,v.vz=x,y,z end
    function isElementFrozen() return false end
    function isElementStreamedIn() return true end
    function getElementCollisionsEnabled(v) return v.collision ~= false end
    local boat=element("vehicle")
    boat.fx,boat.fy,boat.vz,boat["npchlc_traffic:rail"]=1,0,0.07,true
    local ped=element("ped")
    ped.vehicle,boat.driver=boat,ped
    local crossing=element("vehicle",12)
    crossing.y,crossing.fx,crossing.fy,crossing.vy=-10,0,1,0.24
    function getElementsWithinRange() return {boat,crossing} end
    local path={"driveTrafficRail",-60,0,0, 0,0,0, 70,0,0, 140,0,0, 16,0,0}
    assert(getBoatTrafficSpeedLimit(boat,16)<16)
    local earlySpeed, speedAfterClearance, releasedAt
    local function stepHull()
        now=now+20
        performTask.driveTrafficRail(ped,path,20)
        assert(boat.vz==0.07)
        boat.x,boat.y=boat.x+boat.vx,boat.y+boat.vy
        crossing.x,crossing.y=crossing.x+(crossing.vx or 0),crossing.y+crossing.vy
    end
    for frame=1,375 do
        stepHull()
        assert(math.abs(crossing.x-boat.x)>=4 or math.abs(crossing.y-boat.y)>=4,"crossing hulls overlapped")
        if frame==25 then earlySpeed=boat.vx*50 end
        if not releasedAt and crossing.y-boat.y>=16 then
            assert(getBoatTrafficSpeedLimit(boat,16)==16)
            releasedAt,speedAfterClearance=frame,boat.vx*50
        elseif releasedAt and frame==releasedAt+50 then
            local gain=boat.vx*50-speedAfterClearance
            assert(gain>2.2 and gain<=2.501,"boat did not progressively recover cruise speed")
        end
    end
    assert(earlySpeed<2 and releasedAt and math.abs(boat.vx*50-16)<0.01)

    -- A second boat approaches the route diagonally from port and
    -- settles ahead at 4 m/s. The bow ray returns no hit throughout.
    boat,ped=element("vehicle"),element("ped")
    boat.fx,boat.fy,boat.vz,boat["npchlc_traffic:rail"]=1,0,0.07,true
    ped.vehicle,boat.driver=boat,ped
    crossing.x,crossing.y,crossing.vx,crossing.vy=12,6,0.08,-0.06
    crossing.fx,crossing.fy=0.8,-0.6
    local mergeLimit=getBoatTrafficSpeedLimit(boat,16)
    assert(mergeLimit<16*(1-0.2)/1.3,"merge did not predict hull contact")
    for frame=1,200 do
        if frame==101 then crossing.fx,crossing.fy,crossing.vy=1,0,0 end
        stepHull()
        -- Separating X projections suffice for these particular headings.
        local extent=3*math.abs(crossing.fx)+math.abs(crossing.fy)
        assert(crossing.x-boat.x>=3+extent,"merging hulls overlapped")
        if frame==100 then assert(math.abs(crossing.y)<0.001 and boat.vx*50<12) end
    end

    -- The broad-phase square and height filters have strict upper bounds.
    crossing.x,crossing.y,crossing.z=boat.x+6,boat.y,4.999
    assert(getBoatTrafficSpeedLimit(boat,16)<16)
    crossing.z=5
    assert(getBoatTrafficSpeedLimit(boat,16)==16)
    crossing.x,crossing.z=boat.x+15.999,0
    assert(getBoatTrafficSpeedLimit(boat,16)<16)
    crossing.x=boat.x+16
    assert(getBoatTrafficSpeedLimit(boat,16)==16)
    crossing.x,crossing.y=boat.x,boat.y+15.999
    assert(getBoatTrafficSpeedLimit(boat,16)<16)
    crossing.y=boat.y+16
    assert(getBoatTrafficSpeedLimit(boat,16)==16)
    crossing.x,crossing.y=boat.x-0.01,boat.y
    assert(getBoatTrafficSpeedLimit(boat,16)==16)
    crossing.x,crossing.y=boat.x+1,boat.y+10
    assert(math.abs(getBoatTrafficSpeedLimit(boat,16)-16*8/13)<0.0001)
    crossing.collision=false
    assert(getBoatTrafficSpeedLimit(boat,16)==16)

    -- A stopped rail vehicle only needs another velocity write if physics
    -- moved it horizontally. Preserve vertical speed when braking again.
    local stopped=element("vehicle")
    stopped.vx,stopped.vy,stopped.vz=0,0,0.07
    local writes=0
    function setElementVelocity(v,x,y,z) writes=writes+1;v.vx,v.vy,v.vz=x,y,z end
    local function brake() return 0,true end
    advanceNPCTrafficRail(stopped,path,20,brake,false)
    assert(writes==0)
    stopped.vy=0.1
    advanceNPCTrafficRail(stopped,path,20,brake,false)
    assert(writes==1 and stopped.vy==0 and stopped.vz==0.07)
    """)
    print("Boat hull sweeps prevented overlap in crossing and merging traffic and released the cruise limit")
    client.execute("""
    local winner, waiting, driver = element("vehicle"), element("vehicle"), element("ped")
    driver.vehicle, winner.driver = winner, driver
    winner.fx, winner.fy, waiting.fx, waiting.fy, waiting.y = 0, 1, 0, -1, 10
    local task = {"driveTrafficPhysics", 1, 12, {0,-5,0}, {{0,0,0,100,0,0,1,0,0}}}
    function getElementsWithinRange() return {winner, waiting} end
    function getVehicleType() return "Automobile" end
    function getVehicleHandling() return {steeringLock=35} end
    -- Asymmetric model bounds of the opposing 405/479 pair seen in MTA.
    function getElementBoundingBox(car)
        if car == winner then return -1.180,-3.175,-0.931,1.151,2.473,0.816 end
        return -1.121,-3.301,-0.681,1.127,2.389,1.220
    end
    local steer, throttle, brake, blocker
    function setNPCVehicleInputs(_, s, t, b) steer, throttle, brake = s, t, b end
    function reportNPCTrafficBlocker(_, vehicle) blocker = vehicle end
    local heading, speed, progress = 0, 0, {}
    beginNPCTrafficPhysicsFrame()
    performTask.driveTrafficPhysics(driver, task, 50, progress)
    assert(blocker == waiting and brake, "centered oncoming car did not retain its maneuvering space")
    task[6], winner["npchlc_traffic:headOnBlocker"] = 2, waiting
    -- A bicycle model integrates the production controller's steering, brake
    -- and throttle at 50 ms. The opposing vehicle keeps yielding throughout.
    for frame=1,200 do
        now = now + 50
        if frame == 21 then winner["npchlc_traffic:headOnBlocker"] = false end
        beginNPCTrafficPhysicsFrame()
        performTask.driveTrafficPhysics(driver, task, 50, progress)
        if frame == 1 then assert(math.abs(steer) > 0.5, "winner drove straight during the award") end
        local acceleration = throttle * (throttle > 0 and 4 or 9) - 0.08*speed - (brake and 12 or 0)
        speed = math.max(0, speed + 0.05*acceleration)
        heading = heading + 0.05*speed/2.5 * math.tan(0.6*steer)
        winner.fx, winner.fy = math.sin(heading), math.cos(heading)
        winner.x, winner.y = winner.x + 0.05*speed*winner.fx, winner.y + 0.05*speed*winner.fy
        winner.vx, winner.vy = winner.fx*speed/50, winner.fy*speed/50
        local a, b = getNPCTrafficFootprint(winner, now), getNPCTrafficFootprint(waiting, now)
        assert(not getNPCTrafficFootprintContact(b.x-a.x, b.y-a.y, 0, 0,
            a.fx, a.fy, a.width, a.length, b, 0), "head-on bypass overlapped")
        if winner.y > waiting.y + 5 then break end
    end
    assert(winner.y > waiting.y + 5 and winner.driver == driver, "winning NPC did not clear the opposing car")

    -- A recorded model 474 stopped for a model 480 directly behind it.
    -- Positions and headings are expressed in the lead car's local frame.
    function getElementBoundingBox(car)
        if car == winner then return -1.209,-3.166,-0.768,1.214,2.560,0.978 end
        return -1.142,-2.701,-0.754,1.114,2.423,0.808
    end
    winner.x, winner.y, winner.fx, winner.fy, winner.vx, winner.vy = 0,0, 0,1, 0,0
    waiting.x, waiting.y, waiting.fx, waiting.fy = -0.083,-5.524, 0.0243,0.9997
    task[6] = nil
    local function sampleQueueCar(car)
        driver.vehicle = car
        now = now + 100
        beginNPCTrafficPhysicsFrame()
        performTask.driveTrafficPhysics(driver, task, 50, {})
    end
    local front, rear = getNPCTrafficFootprint(winner,now), getNPCTrafficFootprint(waiting,now)
    assert(getNPCTrafficFootprintContact(rear.x-front.x,rear.y-front.y,0,0,0,1,front.width,front.length,rear,0)==0)
    sampleQueueCar(winner)
    assert(not blocker and throttle > 0, "lead car could not move away from the touching follower")
    sampleQueueCar(waiting)
    assert(blocker == winner and brake, "touching follower no longer yielded to the lead car")
    do
        -- An empty van occupies the route in the same direction as the NPC.
        local key = "npchlc_traffic:abandonedBlocker"
        waiting.x, waiting.y, waiting.fx, waiting.fy = 0, 6, 0, 1
        sampleQueueCar(winner)
        assert(brake and throttle==0, "ordinary traffic pushed the van before the wait")
        winner[key] = waiting
        sampleQueueCar(winner)
        assert(throttle>0 and not brake, "the released civilian still brakes for the empty van")
        local room, nearby = canNPCTrafficPhysicsAvoid, getElementsWithinRange
        canNPCTrafficPhysicsAvoid = function() return false end
        sampleQueueCar(winner)
        assert(steer==0 and throttle>0 and not brake, "closed sides prevented the slow push")
        local walker = element("ped")
        walker.y = 2.9
        function getElementsWithinRange(x,y,z,r,kind)
            if kind=="ped" then return {walker} end
            if kind=="vehicle" then return {winner,waiting} end
            return {}
        end
        for style=0,1 do
            task[6] = style
            sampleQueueCar(winner)
            assert(throttle==0 and brake, "driver pushed ahead with a pedestrian at the bumper")
        end
        task[6] = nil
        canNPCTrafficPhysicsAvoid, getElementsWithinRange = room, nearby
        waiting.driver = element("player")
        sampleQueueCar(winner)
        assert(brake and throttle==0, "native driver takeover did not cancel contact")
        waiting.driver, winner[key] = nil, false
    end
    waiting.x, waiting.y, waiting.vx, waiting.vy = -4,-10,0.04,0.16
    sampleQueueCar(winner)
    assert(blocker == waiting, "faster rear merge with future contact did not constrain the lead car")

    local siren = element("vehicle")
    function getElementsWithinRange() return {winner} end
    local key = "npchlc_traffic:sirenYield"
    for _, mode in ipairs({"left", "right"}) do
        local sign = mode == "left" and -1 or 1
        winner.x,winner.y,winner.fx,winner.fy,winner.vx,winner.vy = 0,0,0,1,0,0
        siren.x,siren.y,siren.vy = 0,-32,0.25
        winner[key] = {siren, mode, 2500, now, false, 0,1,sign*3.1}
        sampleQueueCar(winner)
        assert(sign*steer>0 and throttle>0 and not brake, "stopped driver failed to pull outward")
        local nearby = getElementsWithinRange
        local pedestrian = element("ped",sign*0.6)
        pedestrian.y = 2.7
        function getElementsWithinRange(x,y,z,r,kind)
            if kind=="ped" then return {pedestrian} end
            return kind=="vehicle" and {winner} or {}
        end
        sampleQueueCar(winner)
        assert(throttle==0 and brake, "driver accelerated into a pedestrian while making way")
        getElementsWithinRange=nearby
        -- A new sync owner receives the same world-space target. Once the
        -- car has reached it, later updates must not send it into the siren.
        winner.x,winner.vy = sign*3.1,0.14
        winner[key][5] = true
        sampleQueueCar(winner)
        assert(math.abs(steer)<0.1 and throttle<=0, "recipient crossed its cleared line")
    end
    winner.x,winner.vy = 0,0.2
    winner[key] = {siren, "wait", 2000, 200, false}
    sampleQueueCar(winner)
    assert(steer==0 and throttle==-0.2 and not brake)
    winner.vy = 0
    sampleQueueCar(winner)
    assert(throttle==0 and brake, "siren wait selected reverse at rest")
    winner["npchlc_traffic:rail"] = true
    local advance = advanceNPCTrafficRail
    local railLimit
    function advanceNPCTrafficRail(v, t, ms, limit) railLimit = limit(v) end
    performTask.driveTrafficRail(driver, {}, 50)
    assert(railLimit==0, "simple traffic advanced through siren wait")
    advanceNPCTrafficRail = advance
    winner[key] = false
    sampleQueueCar(winner)
    assert(throttle>0 and not brake, "traffic stayed stopped after siren action expired")

    -- At 4 m/s the half-cruise target of style 1 still asks for gas.
    -- The fully stopped leader occupies the original path in all seven cases.
    winner.x,winner.y,winner.vx,winner.vy=0,0,0,0.08
    waiting.x,waiting.y,waiting.fx,waiting.fy,waiting.vx,waiting.vy=0,5,0,1,0,0
    function getElementsWithinRange() return {winner,waiting} end
    local function styleSample(style)
        task[6]=style
        sampleQueueCar(winner)
        return throttle,steer
    end
    local full=styleSample(0)
    local slow=styleSample(1)
    local plough=styleSample(3)
    assert(full<0 and styleSample(4)==full and slow>0 and slow<plough)
    -- A car just right of centre leaves a gap on its left.
    waiting.x,waiting.y=1.8,10
    for _,style in ipairs({2,5,6}) do
        local pedal,angle=styleSample(style)
        assert(pedal>0 and angle<0, "vehicle bypass " .. style .. ": " .. pedal .. "/" .. angle)
    end

    -- A pedestrian blocks the straight bearing. Both alternate bearings are clear.
    local pedestrian=element("ped")
    function getElementsWithinRange() return {winner} end
    local oldCast=processLineOfSight
    function processLineOfSight(x,y,z,ex,ey)
        if math.abs(ex-x)<0.001 and ey>y then return true,x,y+1,z,pedestrian end
        return false
    end
    for _,style in ipairs({2,5}) do
        local pedal,angle=styleSample(style)
        assert(pedal>0 and math.abs(angle)>0.1, "pedestrian bypass " .. style)
    end
    local pedal,angle=styleSample(6)
    assert(pedal<0 and angle==0, "style 6 steered through the pedestrian")
    assert(styleSample(3)==plough)
    processLineOfSight=oldCast
    pedestrian.x,pedestrian.y,pedestrian.z,pedestrian.vx,pedestrian.vy=0.51,5,0,0,0
    function isPedDead(ped) return ped.dead end
    function getElementsWithinRange(_,_,_,_,kind,interior,dimension)
        if kind=="vehicle" then return {winner} end
        if kind=="ped" and interior==getElementInterior(winner)
            and dimension==(pedestrian.dimension or getElementDimension(winner)) then return {pedestrian} end
        return {}
    end
    assert(styleSample(6)<0, "style 6 missed the standing ped between its rays")
    pedestrian.x,pedestrian.vx=2.1,-0.03
    assert(styleSample(6)<0, "crossing pedestrian footprint missed the bumper")
    pedestrian.vehicle=waiting
    assert(styleSample(6)>0, "seated pedestrian blocked traffic")
    pedestrian.vehicle=nil
    pedestrian.z=6
    assert(styleSample(6)>0, "pedestrian on an overpass blocked traffic")
    pedestrian.z,pedestrian.dimension=0,35
    assert(styleSample(6)>0, "another dimension blocked traffic")
    function getElementsWithinRange() return {winner} end

    -- A standalone rail task exercises the same seven policies even without
    -- the world scheduler, which normally promotes avoiding cars to physics.
    local rail={"driveTrafficRail",0,-30,0, 0,0,0, 0,30,0, 0,60,0, 12,0,0}
    local cap,bearing
    function advanceNPCTrafficRail(v,t,ms,limit)
        local urgent
        cap,urgent,bearing=limit(v,0,0,0,0,5,0,0,1,nil,t,1,0,{},4,12)
    end
    function processLineOfSight(x,y,z,ex,ey)
        if math.abs(ex-x)<0.001 and ey>y then return true,x,y+1,z,pedestrian end
        return false
    end
    for style=0,6 do
        rail.style=style
        now=now+110
        beginNPCTrafficPhysicsFrame()
        performTask.driveTrafficRail(driver,rail,50)
        if style==0 or style==4 or style==6 then assert(cap==0 and not bearing)
        elseif style==1 then assert(cap==6 and not bearing)
        elseif style==3 then assert(cap==math.huge and not bearing)
        else assert(cap>0 and math.abs(bearing)>0.1) end
    end
    advanceNPCTrafficRail,processLineOfSight=advance,oldCast
    """)
    print("Centered opposing traffic reserved maneuvering space and passed without a footprint overlap")
    print("All seven road driving styles passed task validation, signals, traffic limits and pedestrian response")
    print("Client task ownership, stale revision rejection and stream-out cleanup passed")

    lua = make_server()
    lua.execute(LOAD)
    step = lua.globals().benchStep
    samples = []
    for _ in range(1200):
        start = perf_counter()
        step()
        samples.append((perf_counter() - start) * 1000)
    lua.execute("assert(benchActors[6].x > 4 and benchActors[600].x > 400)")
    print("100 simulated players, 600 active tasks, 60 simulated seconds")
    print(f"  Lua scheduler p95 {percentile(samples, 95):.3f} ms, p99 {percentile(samples, 99):.3f} ms")
    print("  MTA networking, native physics and client frames require live validation.")


def check_airtrain_bounds():
    assets = VCS_VEHICLE.parent / "vcs_model"
    col = (assets / "airtrain.col").read_bytes()
    signature, size = struct.unpack_from("<4sI", col)
    radius, cx, cy, cz, *bounds = struct.unpack_from("<10f", col, 32)
    assert signature == b"COLL" and size + 8 == len(col)
    assert (cx, cy, cz) == (0, 0, 0)
    for tier in ("hi", "lo", "vlo"):
        data = (assets / f"airtrain_{tier}.dff").read_bytes()
        start, end = 12, len(data)
        for kind in (0x1A, 0x0F, 0x01):
            start, end = next((a, b) for k, a, b in chunks(data, start, end) if k == kind)
        flags, triangles, vertices, targets = struct.unpack_from("<4I", data, start)
        assert flags == 0x10037 and targets == 1
        offset = start + 40 + (triangles + vertices) * 8
        for point in struct.iter_unpack("<3f", data[offset:offset + vertices * 12]):
            assert math.dist(point, (cx, cy, cz)) <= radius + 1e-5
            assert all(lo - 1e-5 <= x <= hi + 1e-5 for lo, x, hi in zip(bounds[:3], point, bounds[3:]))
    print("AIRTRAIN shared pivot, sphere and box enclose all three rendered meshes")


def check_gang_weapons(disc):
    # Compare both outcomes of a real brain attachment with the original SCM.
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
        exports = {npc_hlc={clearNPCTasks=function() end}}
        math.random = function(lo, hi)
            if lo == 0 and hi == 99 then draws = draws + 1; return roll end
            return lo
        end
        function giveWeapon(p, weapon, amount, equip)
            assert(equip and amount == 25001)
            p.gun, p.ammo = weapon, (p.ammo or 0) + amount
            return true
        end
        function setPedWeaponSlot(p, slot) assert(slot == 0); p.gun = 0 end
    """)
    load(lua, RUNTIME, ["ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_weapons.lua",
                        "ped_objectives.lua", "ped_ai_tasks.lua", "ped_ai.lua"])
    check = lua.eval("""
        function(model, index, sample, original, host)
            local p, player = element("ped"), element("player")
            roll, draws = sample, 0
            local brain = PedAI.attach(p, model, index+7)
            assert(brain.profile.statId == PedAIModels[model][2])
            assert(brain.profile.pedType == index+7 and draws == 1 and p.gun == host)
            assert((brain.tasks.originalWeapon or 0) == original)
            local ammo = p.ammo
            assert(PedAI.attach(p, model) == brain)
            PedAI.roadRage(p, player, {})
            assert(p.gun == host and ammo == p.ammo and draws == 1)
            if host == 28 then
                assert(PedAIRules.attackRange(host, brain.tasks.originalWeapon) == (original == 25 and 45 or 30))
            end
        end
    """)
    pairs = [(19,0), (19,6), (26,25), (28,28), (0,19), (19,25), (19,6), (3,3), (26,29)]
    if disc:
        script = (disc / "MAIN.SCM").read_bytes()
        startup = script[0xF6EA:0xF72F]
        assert startup == script[0x36863:0x368A8]
        records = iter(startup)
        def operand():
            tag = next(records)
            if tag == 1:
                return 0
            assert tag == 7
            return next(records)
        for _ in pairs:
            assert (next(records), next(records)) == (0x57, 1)
            index = operand()
            assert (operand(), operand()) == pairs[index]
        assert next(records, None) is None
    host = {0:0, 3:2, 6:5, 19:22, 25:28, 26:28, 28:31, 29:30}
    for index, pair in enumerate(pairs):
        model = (91, 93, 95, 97, 99, 101, 89, 105, 107)[index]
        for sample, original in zip((49, 50), pair):
            check(model, index, sample, original, host[original])
    lua.execute("""
        local pop = {gangModels = {}}
        for i = 1, 9 do pop.gangModels[i] = {200+i, 300+i} end
        local ids = {267, 265, 269, 209, 174, 231, 171, 184}
        for group, car in ipairs(ids) do
            local model, role = PedWeapons.gangOccupant(car, pop, function() return true end)
            assert(model == 200+group and role == 6+group)
            model, role = PedWeapons.gangOccupant(car, pop, function() return false end)
            assert(model == 14 and role == nil)
        end
        assert(PedWeapons.gangOccupant(207, pop) == nil)
        local golfer = PedAI.attach(element("ped"), 105)
        assert(golfer.profile.pedType == 4 and golfer.tasks.originalWeapon == nil)
    """)
    print("Verified both weapon draws for all nine gangs, combat ranges and persistence through road rage")


def check_ped_personalities(disc):
    game = zlib.decompress((disc / "PS2/GAME.DTZ").read_bytes())
    count, model_table = struct.unpack_from("<II", game, 0x38)
    stat_table, = struct.unpack_from("<I", game, 0x20 + 4 * 0x1B)
    stats = struct.unpack_from("<42I", game, stat_table)
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("exports = {npc_hlc = {}}")
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_model_bindings.lua", "ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_weapons.lua",
                        "ped_objectives.lua", "ped_ai_tasks.lua", "ped_ai.lua", "traffic_ambient.lua"])
    runtime = lua.globals()
    expected_ids = set()
    for model, record in enumerate(struct.unpack_from(f"<{count}I", game, model_table)):
        if not record or game[record + 0x10] != 7:
            continue
        expected_ids.add(model)
        ped_type, stat_id = struct.unpack_from("<II", game, record + 0x34)
        fear, temper = struct.unpack_from("<bb", game, stats[stat_id] + 0x16)
        profile = runtime.PedAIRules.profile(model)
        assert (profile.pedType, profile.statId, profile.fear, profile.temper) == (ped_type, stat_id, fear, temper), model
    assert set(runtime.PedAIModels.keys()) == expected_ids and len(expected_ids) == 161
    for stat_id, address in enumerate(stats):
        profile = runtime.PedAIStats[stat_id]
        assert struct.pack("<4f", profile.fleeDistance, profile.headingChangeRate, profile.attackStrength,
                           profile.damageScale) == game[address + 4:address + 0x14]
        assert (profile.flags, profile.fear, profile.temper, profile.law, profile.social) == struct.unpack_from(
            "<H4b", game, address + 0x14)
        assert profile.name == game[address + 0x1A:address + 0x32].split(b"\0", 1)[0].decode("ascii")
    lua.execute("""
        TrafficModelBindings.load({})
        assert(bindTrafficPedestrianModel(34, 7) and bindTrafficPedestrianModel(48, 7))
        local calm, hot = element("ped"), element("ped")
        calm.model, hot.model = TrafficAmbient.getPedestrianModel(34), TrafficAmbient.getPedestrianModel(48)
        assert(calm.model == hot.model and hot.model == 7)
        TrafficModelBindings.tag(calm, 34)
        TrafficModelBindings.tag(hot, 48)
        assert(PedAI.profile(calm).temper == 30 and PedAI.profile(hot).temper == 70)
        assert(PedAI.attach(calm, calm.model).profile.statId == 15)
        local profile = PedAI.attach(hot).profile
        assert(PedAI.setLeader(hot, calm))
        assert(bindTrafficPedestrianModel(48, 46))
        assert(PedAI.attach(hot, 34).profile == profile and profile.temper == 70)
        assert(TrafficAmbient.getPedestrianModel(48) == 46)
        local native = element("ped")
        function getValidPedModels() return {48} end
        TrafficModelBindings.load({modelIdSpace="mta"})
        TrafficModelBindings.tag(native, 48)
        assert(not PedAI.profile(native) and PedAI.attach(native).profile.statId == 13)
    """)
    print("Verified all 161 PS2 ped model assignments, 42 complete PEDSTATS records and visual skin overrides")


def check_rhino_wheels(mesh):
    clump = list(chunks(mesh, 12, len(mesh)))
    frame_list = next((a, b) for kind, a, b in clump if kind == 0xE)
    header, *frames = chunks(mesh, *frame_list)
    positions = {}
    for index, (_, start, end) in enumerate(frames):
        name = next((mesh[a:b].rstrip(b"\0").decode("ascii") for kind, a, b in chunks(mesh, start, end)
                     if kind == 0x253F2FE), "")
        positions[name] = struct.unpack_from("<3f", mesh, header[1] + 40 + index * 56)
    expected = set()
    for side, x in (("l", -1.55), ("r", 1.55)):
        for axle, y in (("f", 2.356), ("m", -0.757), ("b", -2.357)):
            visual = "vcs_wheel_" + side + axle
            expected.add(visual)
            for name in (visual, "wheel_" + side + axle + "_dummy"):
                assert all(math.isclose(a, b, abs_tol=0.001) for a, b in
                           zip(positions[name], (x, y, -0.45))), (name, positions[name])
    assert {name for name in positions if name.startswith("vcs_wheel_")} == expected
    geometries = {atomic_geometry(mesh, name.encode())[1] for name in expected}
    assert len(geometries) == 1
    _, wheel, _ = next(chunks(mesh, *geometries.pop()))
    assert struct.unpack_from("<I", mesh, wheel + 4)[0] == 203
    _, native_template = atomic_geometry(mesh, b"wheel")
    assert wheel_radius(mesh, native_template) == 0  # SA duplicates this mesh on slot 432.
    for _, _, radius in contact_geometry(mesh):
        assert math.isclose(radius, 0.75, abs_tol=0.001)


def check_assets(disc, vcs_pc):
    check_ped_personalities(disc)
    with TemporaryDirectory() as directory:
        rebuilt = Path(directory) / "traffic_collision_handling.lua"
        export_collision_handling(disc, rebuilt)
        export_service_sound(disc, rebuilt.parent)
        sound = rebuilt.with_name("sfx_service_suspension.wav")
        assert sound.read_bytes() == (RUNTIME / sound.name).read_bytes()
        assert rebuilt.read_text() == (RUNTIME / rebuilt.name).read_text()
        if vcs_pc:
            decisions = rebuilt.with_name("traffic_crash_decisions.lua")
            export_decisions(vcs_pc, decisions)
            assert decisions.read_text() == (RUNTIME / decisions.name).read_text()
    data, manifest = assemble(disc, vcs_pc)
    assert bake_jetski_rider(disc) == (VCS_VEHICLE / "data/jetski_rider.json").read_bytes()
    data_again, _ = assemble(disc, vcs_pc)
    model_resource = TRAFFIC.parent / "[model]" / "vcs_model"
    vehicle_archive = model_resource / "vehicle.img"
    if vehicle_archive.is_file():
        assets = read_archive(vehicle_archive)
        with vehicle_archive.open("rb") as archive:
            _, count = struct.unpack("<4sI", archive.read(8))
            directory = {}
            for _ in range(count):
                sector, size, _, raw_name = struct.unpack("<IHH24s", archive.read(32))
                directory[raw_name.rstrip(b"\0").decode("ascii")] = (sector, size)
            for name in ("speeder", "jetski", "marquis", "rio", "squalo", "scarab"):
                sector, size = directory[f"{name}.txd"]
                archive.seek(sector * 2048)
                kind, length, _ = struct.unpack("<III", archive.read(12))
                assert kind == 0x16 and 0 < length <= size * 2048 - 12
        provider = LuaRuntime()
        load(provider, model_resource, ["model_catalog.lua"])
        rhino = provider.globals().VCS_TRAFFIC_MODEL_CATALOG[246]
        assert rhino.base == 432 and rhino.name == "rhino" and not rhino.variant
        check_rhino_wheels(assets["rhino.dff"])
        for original, (name, parent) in POLICE_MODELS.items():
            entry = provider.globals().VCS_TRAFFIC_MODEL_CATALOG[original]
            assert entry.name == name and entry.base == parent and bool(entry.variant) == (original == 218)
            surfaces = vehicle_material_textures(assets[name + ".dff"])
            assert "vcsglass_66b6c24c" in surfaces
            lenses = {key for key in surfaces if key.startswith("vcssiren_")}
            expected = {191: {"vcssiren_right"}, 207: {"vcssiren_left", "vcssiren_right"}}
            assert lenses == expected.get(original, set())
            if original in (193, 204):
                assert {"vcspol_vehiclegeneric256", "vcspol_vehiclesteering128"} <= surfaces
        for original, name in ((215,"speeder"), (233,"jetski"), (248,"marquis"),
                               (249,"rio"), (257,"squalo"), (264,"scarab")):
            entry = provider.globals().VCS_TRAFFIC_MODEL_CATALOG[original]
            assert entry.variant and entry.name == name and entry.kind == "vehicle"
            assert assets[f"{name}.dff"]
            assert any(rule["originalId"] == original and 9 <= rule["trafficClass"] <= 12
                       for rule in data["vehicleModelRules"])
        for name, expected_axle in (("mule", 4.306), ("boxvil", 4.1525), ("benson", 3.9038),
                                    ("yankee", 5.3177), ("sanchez", 1.6396), ("pcj600", 1.6038)):
            front, rear = contact_geometry(assets[name + ".dff"])
            assert math.isclose(front[0] - rear[0], expected_axle, abs_tol=0.001)
            assert 0.25 < front[2] < 0.6 and 0.25 < rear[2] < 0.6
    ped_archive = model_resource / "ped.img"
    if ped_archive.is_file():
        check_pedestrian_jaw(read_archive(ped_archive), 75)
    street_assets = read_archive(RUNTIME / "ped_models/street.img")
    check_pedestrian_jaw(street_assets, 95)
    police_assets = read_archive(RUNTIME / "ped_models/police.img")
    assert set(police_assets) == {f"ped_{model}.dff" for model in (9, 10, 11, 117, 118, 119)}
    check_pedestrian_jaw(police_assets, 6)
    assert encode_json(data) == encode_json(data_again)
    assert manifest["counts"]["nodes"] == {"boat": 378, "pedestrian": 5308, "vehicle": 2701}
    assert manifest["counts"]["directedLinks"] == {"boat": 762, "pedestrian": 11298, "vehicle": 5592}
    lua = LuaRuntime()
    load(lua, VCS_VEHICLE, ["controllers/vehicle.lua","controllers/plane.lua"])
    load(lua, RUNTIME, ["traffic_lights.lua", "traffic_population.lua", "traffic_road_population.lua", "traffic_graph.lua"])
    graph = lua.globals().TrafficGraph.build(lua.table_from(data, recursive=True), lua.eval("function() end"))
    lua.execute("exports = {npc_hlc = {}}; function addEvent() end; function addEventHandler() end")
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_ambient.lua"])
    population = lua.globals().TrafficPopulation
    road_population = lua.globals().TrafficRoadPopulation
    pedestrian_budget = lua.globals().TrafficAmbient.zoneBudget
    for x, y, z, hour, rain, cars, peds in [
        (-598, 664, 10, 12, 0, 14, 25), (-598, 664, 10, 0, 0, 7, 16),
        (-598, 664, 10, 12, 1, 14, 5), (-1250, -890, 5, 12, 0, 9, 24),
        (-1250, -890, 2000, 12, 0, 7, 8),
    ]:
        profile = population.sample(graph.population, x, y, z, hour)
        assert road_population.zoneTarget(profile, 1) == cars
        assert math.floor(pedestrian_budget(profile, rain)) == peds
    assert road_population.resolveMode(graph, "auto") == "zone"
    screenshot = population.sample(graph.population, -674.375793, 572.030518, 11.033458, 16)
    assert screenshot.zoneId == 24 and road_population.zoneTarget(screenshot, 1) == 14
    approach = next(link for link in data["links"] if link["from"] == 212 and link["to"] == 214)
    roads, _ = road_surfaces(ROAD_MAP)
    x, y, z = lane_centres(data["nodes"], approach)[0]
    assert z == 9 and math.isclose(ground_height(roads, x, y, z), 9.87, abs_tol=0.01)
    assert manifest["script"]["additionalDisabledVehicleNodes"] == 83
    assert all(data["nodes"][i]["flags"] & 0x20 for i in (2992, 3002, 3013))
    for i in (202, 212, 213, 214):
        node = data["nodes"][i]
        assert not node["flags"] & 0x20
        assert math.isclose(ground_height(roads, node["x"], node["y"], 10), 9.87, abs_tol=0.01)
    if vcs_pc:
        assert len(manifest["vcsPcRoadPopulationSources"]) == 4
        assert len(data["roadPopulation"]["zones"]) == 180
        cap = lua.globals().TrafficRoadPopulation.cap
        assert cap(graph.roadPopulation, -400, 1000, 10, 0, 4, 1) == 9
        assert cap(graph.roadPopulation, -400, 1000, 10, 12, 4, 1) == 12
        assert cap(graph.roadPopulation, -1400, -800, 10, 0, 4, 1) == 5
        assert cap(graph.roadPopulation, -1400, -800, 10, 0, 4, 0.5) == 3
        assert cap(graph.roadPopulation, -598, 664, 10, 12, 4, 1) == 12
        assert road_population.resolveMode(graph, "scheduled") == "scheduled"
        legacy = {**data, "pcRoadPopulation": data["roadPopulation"]}
        del legacy["roadPopulation"]
        legacy_graph = lua.globals().TrafficGraph.build(lua.table_from(legacy, recursive=True), lua.eval("function() end"))
        assert legacy_graph.roadPopulation and road_population.resolveMode(legacy_graph, "auto") == "zone"
    light = lua.globals().TrafficLights.normalState
    for clock, expected in [(0, 0), (9999, 0), (10000, 1), (12000, 3), (22000, 4), (24000, 2), (32768, 0)]:
        state, delay = light(clock)
        assert state == expected and delay > 0
    signal = lua.globals().TrafficLights.state
    assert signal(10000, 1.1, False)[0] == 1
    assert signal(1023, 1.2, False) == (6, 1)
    assert signal(1024, 1.2, True) == (9, 1024)
    assert signal(1024, 0.7, True)[0] == 5
    assert graph.counts.populationZones == 168
    sample_population = lua.globals().TrafficPopulation.sample
    day = sample_population(graph.population, -1250, -890, 5, 12, 0)
    night = sample_population(graph.population, -1250, -890, 5, 2, 0)
    assert day.zoneId == night.zoneId == 1 and day.originalModelId == night.originalModelId == 34
    assert day.pedestrianGroupId == 51 and night.pedestrianGroupId == 52
    assert sample_population(graph.population, -1250, -890, 2000, 12, 0).zoneId == 0
    assert not sample_population(graph.population, 0, 0, 0, 24)
    assert len(data["dynamicRoutes"]) == 1
    assert graph.dynamicRoutes["police-helicopter"].originalModelId == 261
    assert graph.policeFlight.pilotModelId == 8
    load(lua, RUNTIME, ["traffic_model_bindings.lua"])
    lua.globals().customRoute = lua.table_from({**data["routes"][0], "id": "airport-loop"}, recursive=True)
    lua.execute(SERVER_MOCK)
    lua.execute("""
    function getValidPedModels() return {7, 14} end
    local native = TrafficGraph.build({
        schemaVersion=1, modelIdSpace="mta",
        nodes={{id=0, kind="pedestrian", x=2900, y=2800, z=5, flags=0, rawWidth=0, firstLink=0, linkCount=0}},
        links={}, routes={customRoute}
    }, function() end)
    assert(TrafficGraph.pedestrianAnchor(native, 2900, 2800, 5) == 0)
    assert(native.ambientFlight.id == "airport-loop" and not native.modelProvider)
    assert(CPlane.SampleFlight(native.ambientFlight, 0, 0))
    TrafficModelBindings.load(native)
    assert(TrafficModelBindings.getPedestrian(7) == 7 and not TrafficModelBindings.getPedestrian(34))
    assert(TrafficModelBindings.get(411) == 411 and not TrafficModelBindings.get(171))
    local provider = {}
    function getResourceFromName(name) return name == "custom_models" and provider end
    function getResourceState() return "running" end
    function call(resource, name, id, kind)
        assert(resource == provider and name == "getTrafficModelBase")
        if id == 7 and kind == "ped" then return 14 end
    end
    native.modelProvider = "custom_models"
    TrafficModelBindings.load(native, "auto")
    local ped = element("ped")
    assert(TrafficModelBindings.getPedestrian(7) == 14)
    TrafficModelBindings.tag(ped, 7)
    assert(getElementData(ped, "npchlc_traffic:modelProvider") == "custom_models")
    TrafficModelBindings.load(native, "none")
    local stock = element("ped")
    TrafficModelBindings.tag(stock, 7)
    assert(TrafficModelBindings.getPedestrian(7) == 7 and not getElementData(stock, "npchlc_traffic:modelProvider"))
    """)

    lane_point = lua.globals().TrafficGraph.lanePoint
    junction = {(link["from"], link["to"]): link for link in data["links"]}
    assert [junction[pair]["lanes"] for pair in [(210, 207), (207, 210), (207, 2956),
                                                (2956, 207), (2956, 212), (212, 2956)]] == [1, 0, 1, 0, 1, 0]
    can_turn = lua.globals().TrafficGraph.canDriveTransition
    to_junction = graph.links[junction[207, 2956]["id"] + 1]
    east_lane = graph.links[junction[2956, 212]["id"] + 1]
    west_lane = graph.links[junction[2956, 1250]["id"] + 1]
    assert manifest["convertedRoadCollision"]["turnsChecked"] >= 5700
    assert not can_turn(graph, to_junction, east_lane)
    assert can_turn(graph, to_junction, west_lane)
    assert can_turn(graph, graph.links[junction[1250, 2956]["id"] + 1], east_lane)
    lua.execute(SERVER_MOCK)
    lua.execute('exports = {npc_hlc = {}, server_coldata = {}}')
    load(lua, HLC, ["traffic_rail.lua"])
    lua.execute("exports.npc_hlc.getNPCTrafficRailDebugPoints = function(_, task) return getNPCTrafficRailDebugPoints(task) end")
    load(lua, RUNTIME, ["traffic_road.lua"])
    joins = lua.globals().TrafficRoad.debugConnections(graph, to_junction, 0)
    assert len(joins) == 1 and len(joins[1]) == 5
    assert math.dist(tuple(joins[1][1].values()), lane_point(graph, to_junction, 0)) < 1e-9
    assert math.dist(tuple(joins[1][5].values()), lane_point(graph, west_lane, 0)) < 1e-9
    assert math.dist(tuple(joins[1][5].values()), lane_point(graph, east_lane, 0)) > 1
    load(lua, RUNTIME, ["traffic_debug.lua"])
    lua.globals().TrafficDebug.setGraph(graph)
    lua.execute("""
    client = element("player", -680)
    client.y, client.z = 630, 10
    deliver("npchlc_traffic:debugRequest", resourceRoot, "road")
    local snapshot = packets[1][1]
    assert(snapshot[1] == "road" and #snapshot[4] > 0 and #snapshot[4] <= 128)
    """)
    one_way = two_way = 0
    for link in data["links"]:
        if "lanes" in link:
            assert link["speedClass"] == (data["nodes"][link["from"]]["flags"] >> 10) & 3
        if link.get("lanes", 0) == 0 or data["nodes"][link["from"]]["kind"] != "vehicle":
            continue
        start, end = (data["nodes"][link[node]] for node in ("from", "to"))
        dx, dy = end["x"] - start["x"], end["y"] - start["y"]
        length = math.hypot(dx, dy)
        if length == 0:
            continue
        x, y, z = lane_point(graph, graph.links[link["id"] + 1], 0)
        for lane, centre in enumerate(lane_centres(data["nodes"], link)):
            imported = lane_point(graph, graph.links[link["id"] + 1], lane)
            assert math.dist(centre, imported) < 1e-9
        center_x, center_y = (start["x"] + end["x"]) * 0.5, (start["y"] + end["y"]) * 0.5
        lateral = ((x - center_x) * dy - (y - center_y) * dx) / length
        if link["leftLanes"] and link["rightLanes"]:
            two_way += 1
            assert math.isclose(lateral, 2.5 + max(start["rawWidth"], end["rawWidth"]) / 16, abs_tol=1e-9)
        else:
            one_way += 1
            assert math.isclose(lateral, (1 - link["lanes"]) * 2.5, abs_tol=1e-9)
        assert z == (start["z"] + end["z"]) * 0.5
    assert two_way and one_way

    route = graph.routes["fake-plane"]
    sample = lua.globals().CPlane.SampleFlight
    assert len(route.points) == 260
    assert not sample(route, 0, 3)
    source = next(record for record in data["routes"] if record["id"] == "fake-plane")
    for slot in range(3):
        for clock in range(0, 0x80000, 997):
            pose = sample(route, clock, slot)
            phase = ((clock + slot * 0x2AAAA) & 0x7FFFF) / 0x80000 * source["clockDuration"]
            segment = next(section for section in source["motionSegments"] if phase <= section["end"])
            dt = phase - segment["start"]
            expected = segment["distance"] + segment["velocity"] * dt
            if segment["kind"] == 2:
                expected += segment["acceleration"] * dt**2
            assert math.isclose(pose.routeDistance, expected, abs_tol=1e-8)
            for axis in "xyz":
                assert math.isfinite(pose[axis])
            assert math.isclose(sum(pose["f"+axis]**2 for axis in "xyz"), 1, abs_tol=1e-9)
            assert math.isclose(sum(pose["r"+axis]**2 for axis in "xyz"), 1, abs_tol=1e-9)
            future = sample(route, clock + 0x80000, slot)
            assert math.isclose(pose.x, future.x, abs_tol=1e-9)
    print("PS2 importer determinism, graph and population loading, lane geometry, signal cycle and fixed-wing phases passed")


def check_reaction_latency():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
        local function noop() end
        exports={npc_hlc={isHLCEnabled=function() return true end,clearNPCTasks=function(_,p) p.task=nil end,setNPCWalkSpeed=function(_,p,pace) p.pace=pace end,
            addNPCTask=function(_,p,t) assert(p.task and not p.preview); p.preview=t; return true end,
            setNPCTask=function(_,p,t) p.task,p.issued=t,now; return true end}}
        TrafficVisibility={track=noop,pedestrianRange=100,pedestrianMaxScale=1,pedestrianScale=function() return 1 end}
        PedSocial={interrupt=noop}
        PedAmbientWait={cancel=noop}
        PedMugging={cancel=noop}
        PedTheft={cancel=noop}
        PedActivity={cancel=noop,leaveForThreat=noop}
        PedVoice={emit=noop}
        TrafficActors={isPolicePed=noop}
        exports.wanted={reportWantedEvent=noop}
        function getElementRotation() return 0,0,0 end
        function getPedRotation() return 0 end
        function isPedOnGround() return true end
        function getPedWeapon(p) return p.weapon or 0 end
        function getPedTotalAmmo() return 0 end
        TrafficGraph={pedestrianAnchor=noop}
    """)
    load(lua, RUNTIME, ["ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_weapons.lua", "ped_objectives.lua", "ped_ai_tasks.lua",
                        "ped_ai.lua", "traffic_world.lua", "traffic_ambient.lua"])
    lua.execute("""
        local player=element("player",-1)
        client=player
        function getElementsWithinRange(_,_,_,_,kind) return kind=="player" and {player} or {} end
        deliver("npchlc_traffic:worldProbeReady",resourceRoot)
        TrafficAmbient.start({population={},nodes={}},function() return 0 end)
        local crowd={}
        for i=1,80 do
            local p=element("ped")
            crowd[i],p.syncer=p,player
            local brain=PedAI.attach(p,40)
            brain.reactionDelay=999
            assert(TrafficAmbient.adoptDriver(p,nil,nil,40))
            assert(not TrafficAmbient.isRecovering(p))
            p.task={"walkTrafficToPoint",3,0,0,1}
            assert(brain:react("gunshot",player,22,"look",nil,1000))
        end
        for i=1,12 do tick() end -- finish adoption and visit the entire crowd
        local fighter,runner=crowd[79],crowd[80]
        local start=now
        for _,p in ipairs(crowd) do assert(p.task and not p.issued) end
        PedAI.brain(fighter).profile.fear=0
        deliver("npchlc_traffic:pedHit",resourceRoot,fighter,player,0,5)
        assert(fighter.task[1]=="killPed" and fighter.issued==start)
        deliver("onPedDamage",fighter,5)
        assert(fighter.task[1]=="killPed" and fighter.issued==start)
        player.weapon=22
        deliver("onPedDamage",runner,7)
        deliver("npchlc_traffic:pedHit",resourceRoot,runner,player,22,7)
        local probe=packets[#packets]
        assert(probe.name=="npchlc_traffic:worldProbe" and probe[1][3]==runner)
        local switched=crowd[77]
        deliver("npchlc_traffic:pedHit",resourceRoot,switched,player,22,6)
        local stale=packets[#packets]
        switched.syncer=element("player")
        deliver("npchlc_traffic:worldProbeResult",resourceRoot,stale[1][1],{-1})
        assert(switched.task[1]=="fleeFromPoint" and switched.issued==start)
        local changed=crowd[78]
        deliver("npchlc_traffic:pedHit",resourceRoot,changed,player,22,6)
        stale=packets[#packets]
        assert(PedAI.brain(changed):react("damage",player,0,"fight"))
        deliver("npchlc_traffic:worldProbeResult",resourceRoot,stale[1][1],{-1})
        assert(not changed.task and changed.issued==start)
        now=now+17
        deliver("npchlc_traffic:worldProbeResult",resourceRoot,probe[1][1],{-1})
        assert(runner.task[1]=="walkTrafficToPoint" and runner.issued==start+17 and runner.pace=="sprint")
        local ahead=packets[#packets]
        assert(ahead[1][3]==runner and ahead[1][5].x==runner.task[2])
        deliver("npchlc_traffic:worldProbeResult",resourceRoot,ahead[1][1],{-1})
        assert(runner.preview[2]>runner.task[2])
        for i=1,7 do tick() end
        assert(PedAI.brain(crowd[1]).event.consumed==nil)
        for i=1,12 do tick() end
        for i=1,76 do assert(PedAI.brain(crowd[i]).event.consumed) end
        assert(PedAI.brain(fighter).event.kind=="damage" and PedAI.brain(runner).event.kind=="damage")
        for _,latency in ipairs({50,150,300}) do
            local done=runner.task
            runner.x,runner.task,runner.preview=done[2],runner.preview,nil
            deliver("npc_hlc:onNPCTaskDone",runner,done)
            ahead=packets[#packets]
            assert(ahead[1][3]==runner and ahead[1][5].x==runner.task[2])
            now=now+latency
            runner.x=runner.x+2.5
            deliver("npchlc_traffic:worldProbeResult",resourceRoot,ahead[1][1],{-1})
            assert(runner.task and runner.preview and runner.preview[2]==runner.task[2]+6)
        end
    """)
    print("80-ped crowd: same-tick punch dispatch, same-tick flee probe and reply dispatch, staggered hearing passed")


def check_ambient():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute('exports = {npc_hlc = {}}')
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_visibility_s.lua", "traffic_model_bindings.lua", "ped_ai_profiles.lua",
                        "ped_social.lua", "ped_ambient_wait.lua", "ped_mugging.lua", "ped_theft.lua", "traffic_ambient.lua"])
    lua.execute("""
    local function noop() end
    local attached, damage, jacker = {}, {}, {}
    PedAI = {
        attach=function(p,id) attached[p]=id end, detach=function(p) attached[p]=nil end,
        damaged=function(p,loss) damage[p]=loss end, busy=function() return false end, sampleHealth=noop,
        carjacked=function(p,player) jacker[p]=player end,
    }
    PedActivity = {cancel=noop, stop=noop, onSpawn=noop, update=noop, active=noop, leaveForThreat=noop}
    function getElementRotation() return 0,0,90 end
    exports.npc_hlc.isHLCEnabled = function() return true end
    exports.npc_hlc.setNPCWalkSpeed = noop
    local ambient = TrafficAmbient
    local from = {id=0, x=45, y=0, z=0, flags=0, spawnThreshold=15, rawWidth=0,
        scene="outdoor", firstLink=0, linkCount=1}
    local to = {id=1, x=40, y=0, z=0, flags=0, spawnThreshold=8, rawWidth=0,
        scene="outdoor", firstLink=1, linkCount=0}
    local edge = {from=0, to=1, flags=0}
    assert(ambient.samplePedestrianEdge(from, to, edge, 0, 0, 60, 8, 128) == 42.5)
    assert(not ambient.samplePedestrianEdge(from, to, edge, 0, 0, 60, 9, 128))
    edge.flags = 0x8000
    assert(not ambient.samplePedestrianEdge(from, to, edge, 0, 0, 60, 8, 128))
    edge.flags = 0

    local row = {15,1,5,5,5,5,5,5,5,10,11,12,15,20,8,12,12,12,12,12,12,12,12,4}
    local zero = function() return 0 end
    local last = function(limit) return limit - 1 end
    local _, branch = ambient.vehicleClass(row, false, 3, zero)
    assert(branch == "police")
    local _, branch, index = ambient.vehicleClass(row, false, 9, zero)
    assert(branch == "territory" and index == 1)
    assert(ambient.vehicleClass(row, false, 99, zero) == 0)
    assert(ambient.vehicleClass(row, false, 99, last) == 8)
    assert(ambient.vehicleClass(row, true, 99, zero) == 9)
    assert(ambient.vehicleClass(row, true, 99, last) == 12)
    local rules = {{originalId=171, trafficClass=0, frequency=2}, {originalId=172, trafficClass=0, frequency=3}}
    local function all() return true end
    assert(ambient.pickVehicleModel(rules, 0, all, function() return 2 end) == 171)
    assert(ambient.pickVehicleModel(rules, 0, all, function() return 3 end) == 172)

    local player = element("player")
    local driver, car = element("ped"), element("vehicle")
    driver.vehicle = car
    TrafficRoad = {isManagedPed=function(ped) return ped == driver end}
    local created, probe = {}, nil
    local probeCount = 0
    local resumedTasks, reachResult = {}, nil
    local headingRoll, positionRoll, blockedEndpoint = 0, 0, nil
    sourceResource = {}
    function getResourceState() return "running" end
    function getElementsByType() return {player} end
    function getElementsWithinRange(_, _, _, _, kind)
        if kind == "player" then return {player} end
        local nearby = {driver}
        for _, ped in ipairs(created) do nearby[#nearby + 1] = ped end
        return nearby
    end
    function setElementInterior() end
    function setElementDimension() end
    function getTime() return 12 end
    function destroyElement(ped) ped.destroyed = true end
    function killTimer() end
    function removeEventHandler() end
    function createPed(model, x, y, z)
        local ped = {kind="ped", health=100, model=model, x=x, y=y, z=z}
        created[#created + 1] = ped
        return ped
    end
    function call(_, method, player, x, y, z, model, endpoints)
        if method == "getTrafficPedestrianReachable" then return reachResult end
        if method == "getTrafficPedestrianContext" then
            return {cap=1, streamingDistanceScale=1, groupChance=0, policeChance=0}
        end
        if method == "probeTrafficPedestrianSpawn" then
            probeCount = probeCount + 1
            if endpoints and type(probe) == "table" then
                for _, node in ipairs(endpoints) do
                    if node.id ~= blockedEndpoint and math.abs(node.x - x) > 1 then
                        return {groundZ=probe.groundZ, visible=true, clear=true, destination=node.id}
                    end
                end
                return false
            end
            return probe
        end
        return false
    end
    function math.random(lower, upper)
        if upper == 7 then return headingRoll end
        if upper == 255 then return positionRoll end
        return lower or 0
    end
    exports.npc_hlc.enableHLCForNPC = all
    exports.npc_hlc.getNPCTaskCount = function(_,ped) return ped.task and 1 or 0 end
    exports.npc_hlc.addNPCTask = function(_, ped, task) ped.task = task; resumedTasks[#resumedTasks+1]=task; return true end
    TrafficPopulation = {sample=function() return {originalModelId=34} end}
    TrafficGraph = {pedestrianAnchor=function() return false end,pedestrianStep=function(_,id) return id,0 end}
    local graph = {population={}, nodes={from,to}, links={edge}, pedestrianCells={[30]={[25]={from,to}}}}
    assert(registerTrafficPedestrianWorld())
    assert(bindTrafficPedestrianModel(34, 7))
    ambient.start(graph, function() return 1 end)
    do
        local sample, resolve = TrafficPopulation.sample, TrafficModelBindings.get
        TrafficPopulation.sample = function(_,x,y,z)
            assert(x==11 and y==22 and z==3)
            return {dayProfileId=0}
        end
        TrafficModelBindings.get = function(id) return ({[247]=473,[219]=430})[id] end
        graph.population.records = {{values=row}}
        graph.vehicleModelRules = {{originalId=247,trafficClass=9,frequency=1}}
        row[24]=0
        local model, id, class = ambient.chooseBoat(11,22,3,0,false)
        assert(model==473 and id==247 and class==9)
        model,id,class = ambient.chooseBoat(11,22,3,3,true)
        assert(model==430 and id==219)
        graph.vehicleModelRules = {}
        assert(not ambient.chooseBoat(11,22,3,0,false))
        row[24],TrafficPopulation.sample,TrafficModelBindings.get = 4,sample,resolve
    end
    driver.vehicle = nil
    tick()
    assert(probeCount == 0)
    driver.vehicle = car
    tick()
    assert(#created == 0 and probeCount == 1)
    probe = false
    tick()
    assert(#created == 0)
    probe = {groundZ=0, visible=true, clear=true}
    tick()
    driver.vehicle = nil
    tick()
    assert(#created == 0)
    driver.vehicle = car
    tick()
    tick()
    assert(#created == 1 and created[1].x == 45 and created[1].z == 0.7)
    assert(getElementData(created[1], "npchlc_traffic:originalModel") == 34)
    assert(ambient.isManagedPed(created[1]))
    assert(attached[created[1]] == 34)
    assert(created[1].task[1] == "walkTrafficToPoint" and created[1].task[2] == to.x)
    local ped = created[1]
    local grounded, anchorX = false, nil
    function isPedOnGround() return grounded end
    exports.npc_hlc.clearNPCTasks = function(_, actor) actor.task = nil end
    TrafficGraph.pedestrianEntryPoints = function(_, x) anchorX = x return {from,to} end
    reachResult={1}
    ped.vx = 0.15
    deliver("onPedDamage", ped, 20)
    assert(damage[ped] == 20)
    assert(not ped.task and ped.vx == 0.15)
    ped.x = 42
    now = now + 1000
    tick()
    assert(not anchorX and not ped.task)
    grounded = true
    for _ = 1, 4 do tick() end
    assert(anchorX == 42 and ped.task and ped.task[1]=="walkTrafficToPoint" and ped.task[2]==to.x)
    -- The same handoff must work for different owners, even with a stale walk count.
    local oldMeet=PedSocial.meet
    PedSocial.meet=noop
    PedMugging.update=noop
    PedTheft.update=noop
    graph.edition="SLUS-21590 USA v1.00"
    for _,owner in ipairs({"seat","medical"}) do
        local active=true
        local function claim() return active end
        PedActivity.active=owner=="seat" and claim or noop
        PedActivity.update=PedActivity.active
        PedServices={update=owner=="medical" and claim or noop}
        local before=#resumedTasks
        for i=1,4 do tick() end
        assert(#resumedTasks==before)
        ped.task,active=nil,false
        for i=1,4 do tick() end
        assert(#resumedTasks>before and ped.task[1]=="walkTrafficToPoint")
    end
    -- A separate script clearing HLC must not leave an imaginary queued walk.
    local before=#resumedTasks
    ped.task=nil
    now=now+600
    for i=1,4 do tick() end
    assert(#resumedTasks>before and ped.task[2]==to.x)
    -- A gunpoint wait released before this ped's next scheduler visit.
    ambient.suspend(ped)
    ambient.resumeWander(ped,3)
    assert(not ped.task)
    before,anchorX=#resumedTasks,nil
    for i=1,4 do tick() end
    assert(anchorX==ped.x and #resumedTasks>before and ped.task[1]=="walkTrafficToPoint")
    graph.edition=nil
    PedServices,PedSocial.meet=nil,oldMeet
    ped.health = 0
    deliver("onPedWasted", ped)
    assert(ambient.isManagedPed(ped) and not ped.destroyed and timers[2600])
    now = now + 2600
    timers[2600]()
    assert(not ped.destroyed)
    assert(getElementData(ped, TrafficVisibility.retiringKey) and timers[400])
    now = now + 400
    timers[400]()
    assert(ped.destroyed)
    deliver("onElementDestroy", ped)
    assert(not ambient.isManagedPed(ped))
    assert(not attached[ped])
    local enrollments = 0
    exports.npc_hlc.isHLCEnabled = function(_,p) return p.enrolled end
    exports.npc_hlc.enableHLCForNPC = function(_,p) enrollments=enrollments+1; p.enrolled=true; return true end
    assert(ambient.adoptDriver(driver, player, car, 34))
    assert(attached[driver]==34 and enrollments==1)
    assert(ambient.adoptDriver(driver, player, car, 34))
    assert(ambient.isManagedPed(driver) and jacker[driver] == player)
    assert(getTrafficAmbientStatus().pedestrians == 1)
    deliver("onElementDestroy", driver)
    ambient.stop()
    assert(getTrafficAmbientStatus().pedestrians == 0 and created[1].destroyed)

    to.linkCount = 1
    graph.links[2] = {from=1, to=0, flags=0}
    positionRoll = 128
    local function checkSpawn(heading, blocked, expected)
        created, headingRoll, blockedEndpoint = {}, heading, blocked
        ambient.start(graph, function() return 1 end)
        tick()
        tick()
        assert(#created == 1 and created[1].x == 42.5 and created[1].task[2] == expected)
        ambient.stop()
    end
    checkSpawn(6, nil, to.x)
    checkSpawn(2, nil, from.x)
    checkSpawn(2, from.id, to.x)
    from.scene,to.scene="underground","underground"
    from.z,to.z,player.z,player.dimension=-200,-200,-199.15,3090
    probe.groundZ=-200
    function setElementDimension(e,d) e.dimension=d end
    checkSpawn(2,nil,from.x)
    assert(created[1].dimension==3090 and math.abs(created[1].z+199.3)<0.001)
    -- The same XY coordinates on the street must not use the mall graph.
    player.z,player.dimension=17,0
    created={}
    ambient.start(graph,function() return 1 end)
    tick(); tick()
    assert(#created==0)
    ambient.stop()
    from.scene,to.scene="outdoor","outdoor"
    from.z,to.z,player.z,probe.groundZ=0,0,0,0
    graph.links[2].flags = 0x8000
    checkSpawn(2, nil, to.x)

    created = {}
    ambient.start(graph, function() return 1 end)
    tick()
    tick()
    local distant = assert(created[1])
    distant.x = 80
    player.vehicle, car.vx = car, 0.6
    tick()
    tick()
    assert(ambient.isManagedPed(distant) and not distant.destroyed)
    player.vehicle = nil
    tick()
    tick()
    assert(distant.destroyed and not ambient.isManagedPed(distant))
    ambient.stop()
    """)
    print("PS2 ambient edge and model selection, asynchronous spawn admission, cap and cleanup passed")


def check_car_service():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
    exports={npc_hlc={},server_coldata={}}
    function exports.npc_hlc:clearNPCTasks(p) p.task=nil end
    function exports.npc_hlc:setNPCTask(p,t) p.task=t return true end
    function exports.server_coldata:getModelBoundingBox() return -1,-2,-0.85,1,2,1 end
    function getElementModel() return 445 end
    function getVehicleType() return "Automobile" end
    function getVehicleOccupants(c) return {[0]=c.driver,[1]=c.passenger} end
    function getVehicleMaxPassengers() return 3 end
    function isVehicleLocked(c) return c.locked end
    function isVehicleBlown() return false end
    function getPedOccupiedVehicleSeat(p) return p.seat end
    function getVehicleVariant(c) return c.variant or 0, 255 end
    function getPlayerMoney(p) return p.cash end
    function takePlayerMoney(p,n) p.cash=p.cash-n return true end
    function getPedStat(p) return p.stat or 569 end
    function setPedStat(p,_,s) p.stat=s return true end
    function setElementHealth(p,h) p.health=math.min(h,getPedStat(p)*0.176) end
    function getVehicleHandling() return {turnMass=1000} end
    function getElementAngularVelocity() return 0,0,0 end
    function setElementAngularVelocity(c) c.rocked=true end
    function getVehicleName() return "Admiral" end
    PedActivity={active=function() return false end}
    PedVoice={emit=function(p,kind) p.line=kind end}
    TrafficPassengers={requestExit=function(p) p.exitRequested=true end}
    """)
    load(lua, RUNTIME, ["traffic_collision_handling.lua", "ped_car_service.lua"])
    lua.execute("""
    local ped,car,player,walk
    local function step(ms) now=now+ms timers[100]() end
    local function begin(model)
        now=now+12000
        ped,car,player=element("ped"),element("vehicle"),element("player")
        ped.x,ped.y=1.55,0.32
        walk={originalModelId=31}
        car.driver,car.syncer,player.vehicle,ped.syncer=player,player,car,player
        car["npchlc_traffic:originalModel"]=model or 171
        player.cash=500
        function getElementsWithinRange(_,_,_,_,kind) return kind=="vehicle" and {car} or {player} end
    end
    local function board()
        assert(PedCarService.update(ped,walk,now) and ped.line=="serviceOffer")
        step(1000)
        assert(not ped.vehicle)
        step(1)
        step(100)
        assert(packets[#packets].name=="npchlc_traffic:boardPassenger")
        car.passenger,ped.vehicle,ped.seat=ped,car,1
        step(100)
    end
    local function floor(material)
        local pkt=packets[#packets]
        assert(pkt.name=="npchlc_traffic:serviceFloor")
        client=element("player")
        deliver("npchlc_traffic:serviceFloorResult",resourceRoot,ped,car,pkt[1][3],material)
        client=player
        deliver("npchlc_traffic:serviceFloorResult",resourceRoot,ped,car,pkt[1][3],material)
        step(1)
    end
    begin()
    walk.originalModelId=26
    assert(not PedCarService.update(ped,walk,now))
    walk.originalModelId=31
    ped.x=5
    assert(not PedCarService.update(ped,walk,now))
    ped.x=1.55
    car.passenger=element("ped")
    assert(not PedCarService.update(ped,walk,now))
    car.passenger=nil
    player.cash=100
    assert(PedCarService.update(ped,walk,now))
    step(1001)
    assert(not PedCarService.update(ped,walk,now))
    begin()
    board()
    step(1000)
    assert(player.cash==500)
    step(1)
    assert(player.cash==499 and walk.cash==1)
    car.vx=0.01
    step(2000)
    assert(not car.rocked and player.cash==498)
    car.vx=0
    step(3001)
    floor(89)
    assert(not car.rocked)
    step(3001)
    floor(24)
    assert(car.rocked and player.health==101 and ped.line=="serviceAction")
    ped.vehicle,car.passenger=nil,nil
    local money,saved=player.cash,walk.cash
    deliver("onVehicleExit",car,ped,1)
    deliver("onVehicleExit",car,ped,1)
    assert(player.cash==money-100 and walk.cash==(saved+100)%65536)
    begin(266)
    car.variant=1
    board()
    step(3001)
    floor(24)
    step(1)
    assert(player.health==125 and player.line=="serviceEnd" and ped.exitRequested)
    local saved=walk.cash
    ped.vehicle,car.passenger=nil,nil
    deliver("onVehicleExit",car,ped,1)
    assert(walk.cash==saved and player.stat==711)
    player.health=85
    step(100)
    assert(player.stat==569)
    -- 1000 then 970 on an accepted site. A move during the 251..999
    -- interval reduces it to 250, so the next valid action ends the ride.
    begin()
    board()
    step(3001)
    floor(24)
    assert(player.health==101)
    step(1000)
    assert(player.health==101)
    step(1)
    floor(24)
    assert(player.health==102)
    car.vx=0.01
    step(971)
    car.vx=0
    step(3001)
    floor(24)
    assert(player.health==102 and player.line=="serviceEnd")
    -- The independent money clock leaves one dollar intact and shortens the interval.
    begin()
    board()
    player.cash=1
    step(1001)
    assert(player.cash==1 and not walk.cash)
    step(2000)
    floor(24)
    assert(player.line=="serviceEnd" and player.health==100)
    begin()
    board()
    car.driver=nil
    step(3001)
    step(1)
    assert(ped.exitRequested)
    """)
    print("Original service models, approach, seat confirmation, two clocks, surface, health and money passed")


def check_vehicle_pursuit():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, RUNTIME, ["traffic_vehicle_pursuit.lua", "traffic_pursuit_exit_c.lua", "traffic_passengers_c.lua"])
    lua.execute("""
    local car, ped, target = element("vehicle"), element("ped"), element("player", 6)
    local safe = true
    TrafficWorld = {pursuitExit = function() return safe end}
    local p = TrafficVehiclePursuit.new(target, 0)
    assert(not p:update(car, target, 0) and not p:update(car, target, 3999))
    assert(p:update(car, target, 4000) == "brake")
    car.vy = 0.06
    assert(not p:update(car, target, 4100))
    car.vy = 0.05
    assert(p:update(car, target, 4200) == "exit")
    target.x = 8
    assert(p:update(car, target, 4250) == "chase")
    -- Two unsuccessful passes count before the 4s no-progress timeout.
    p = TrafficVehiclePursuit.new(target, 0)
    car.vx, car.vy, car.fx, car.fy = 0.1, 0, 1, 0
    for n = 1, 2 do
        car.x = 4
        assert(not p:update(car, target, n*1000))
        car.x = 14
        local decision = p:update(car, target, n*1000+100)
        if n == 2 then assert(decision == "brake") else assert(not decision) end
    end
    -- A wall, an absent probe response, or an unreachable level cannot
    -- cause an exit or an endless series of new routes.
    for _, mode in ipairs({"blocked", "timeout"}) do
        p = TrafficVehiclePursuit.new(target, 0)
        safe = false
        if mode == "timeout" then safe = nil end
        p:update(car, target, 0)
        local decision = p:update(car, target, 4000)
        if mode == "timeout" then assert(not decision) decision = p:update(car, target, 5250) end
        assert(decision == "route")
        assert(p:update(car, target, 14000) == "end")
    end

    -- A committed driver can leave earlier at a reachable, stationary car.
    -- A change to a moving target invalidates the exit even after approval.
    car.x, car.vx, car.vy = 0, 0, 0
    local suspectCar = element("vehicle", 13)
    target.vehicle, safe = suspectCar, true
    p = TrafficVehiclePursuit.new(target, 0)
    p.committed = true
    assert(not p:update(car, target, 200))
    assert(p:update(car, target, 350) == "brake")
    assert(p:update(car, target, 500) == "exit")
    suspectCar.vx = 0.1
    assert(p:update(car, target, 750) == "chase")
    -- A player on foot can keep walking while the NPC checks its own exit.
    target.vehicle, target.vx = nil, 0.08
    assert(p:update(car, target, 850) == "brake")
    assert(p:update(car, target, 2100) == "exit")
    target.vx = 0

    local floorMode, clear, water = "flat", true, false
    function isElementStreamedIn(e) return not e.out end
    function isVehicleWheelOnGround(e) return not e.air end
    function isPedOnGround(e) return not e.air end
    function isElementInWater() return false end
    function getElementBoundingBox() return -1,-2,-0.5,1,2,1 end
    function getWaterLevel() return water end
    function isLineOfSightClear() return clear end
    function processLineOfSight(x,y,top)
        if floorMode == "hole" and x > 2 then return false end
        return true,x,y,0,nil,0,0, floorMode == "steep" and 0.1 or 1
    end
    car.x, car.fx, car.fy, car.vx = 0, 0, 1, 0
    assert(canTrafficPursuerExit(car,target))
    clear = false
    assert(not canTrafficPursuerExit(car,target))
    clear, water = true, 0.6
    assert(not canTrafficPursuerExit(car,target))
    water, floorMode = false, "hole"
    assert(not canTrafficPursuerExit(car,target))
    floorMode = "steep"
    assert(not canTrafficPursuerExit(car,target))
    floorMode = "flat"
    target.z = 4
    assert(not canTrafficPursuerExit(car,target))
    target.z = 0
    local occupied = element("vehicle", target.x)
    target.vehicle = occupied
    assert(canTrafficPursuerExit(car,target))
    occupied.air = true
    assert(not canTrafficPursuerExit(car,target))
    occupied.air = false
    ped.vehicle = car
    function getPedOccupiedVehicleSeat() return 0 end
    function isElementSyncer() return true end
    function setPedExitVehicle(who) who.exits = (who.exits or 0)+1 end
    local function request()
        deliver("npchlc_traffic:occupantExit",resourceRoot,ped,car,0,target,occupied,8,0,0)
    end
    car.vx=0.06
    request()
    assert(not ped.exits)
    car.vx=0
    request()
    assert(ped.exits == 1)
    occupied.x=9.1
    request()
    assert(ped.exits == 1)
    """)
    print("Vehicle pursuit passes, braking, native exit gates and bounded rerouting passed")


def check_road(disc=None, vcs_pc=None):
    client = LuaRuntime()
    client.execute(SERVER_MOCK)
    load(client, RUNTIME, ["traffic_visibility.lua", "traffic_world_c.lua"])
    client.execute("""
    localPlayer = element("player")
    local mine, victim = element("vehicle"), element("vehicle")
    local impulses = {}
    function isElementSyncer(e) return e.syncer == localPlayer end
    function getPlayerPing() return 25 end
    function triggerServerEvent(_, _, car, other, x, y, z, nx, ny, nz, impulse)
        assert(car == victim and other == mine and nx == 1)
        impulses[#impulses+1] = impulse
    end
    localPlayer.vehicle, mine.driver = mine, localPlayer
    setElementData(victim, TrafficVisibility.profileKey, "road")
    setElementData(victim, "npchlc_traffic:rail", true)
    -- A hit from the local driver gives the other car its own impulse.
    deliver("onClientVehicleCollision", mine, victim, 120, 0, 0,0,0,-1,0,0,22)
    assert(#impulses == 1 and impulses[1] == 22)
    victim.syncer = localPlayer
    deliver("onClientVehicleCollision", victim, mine, 50, 0, 0,0,0,1,0,0,120)
    assert(#impulses == 2 and impulses[2] == 50 and getElementData(victim,"npchlc_traffic:impactPending"))
    deliver("onClientVehicleCollision", mine, victim, 120, 0, 0,0,0,-1,0,0,50)
    assert(#impulses == 2)
    setElementData(victim, "npchlc_traffic:rail", false)
    now = now + 1000
    deliver("onClientVehicleCollision", victim, mine, 80, 0, 0,0,0,1,0,0,120)
    assert(#impulses == 3 and impulses[3] == 80)
    timers[350]()
    assert(not getElementData(victim,"npchlc_traffic:impactPending"))
    local walker=element("ped")
    setElementData(walker,TrafficVisibility.profileKey,"pedestrian")
    function getVehicleHandling() return {mass=1400} end
    function getElementBoundingBox() return -1,-2,-0.5,1,2,1 end
    function isLineOfSightClear() return true end
    local contacts={}
    function triggerServerEvent(name,_,ped,car,force,vertical)
        assert(name=="npchlc_traffic:pedRoadContact" and ped==walker and car==mine)
        contacts[#contacts+1]=force
    end
    mine.vy=0.15
    local function hit(nx,ny)
        deliver("onClientVehicleCollision",mine,walker,30,0,0,0,0,nx,ny,0,0)
    end
    hit(0,-1)
    assert(#contacts==1 and math.abs(contacts[1]-10)<0.00001)
    hit(-1,0)
    hit(0,1)
    walker.vy=mine.vy
    hit(0,-1)
    assert(#contacts==1)
    mine.vy,walker.vy=0.3,0
    mine.driver=nil
    hit(0,-1)
    assert(#contacts==1)
    walker.syncer=localPlayer
    hit(0,-1)
    assert(#contacts==2 and contacts[2]>12)
    mine.driver=localPlayer
    function isElementStreamedIn() return true end
    function getElementsWithinRange(x,y,z,r,kind) return kind=="vehicle" and {mine} or {walker} end
    function getPedControlState() return false end
    function setElementVelocity(e,x,y,z) e.vx,e.vy,e.vz=x,y,z end
    mine.vy=0.8
    deliver("onClientPreRender",root)
    mine.vy=0
    now=now+16
    hit(0,-1)
    assert(#contacts==3 and contacts[3]>12)
    deliver("onClientPreRender",root)
    assert(mine.vy>0.65 and mine.vy<0.8)
    -- Missing native callbacks: a moving bumper crosses the pedestrian.
    walker.y=4
    mine.vy=.8
    now=now+60
    deliver("onClientPreRender",root)
    mine.y,mine.vy=3,0
    now=now+60
    deliver("onClientPreRender",root)
    assert(#contacts==4 and contacts[4]>12)
    now=now+16
    deliver("onClientPreRender",root)
    assert(mine.vy>0.65)
    -- Parallel pass outside body width, different elevation, and wall occlusion.
    for scenario=1,3 do
        mine.y,mine.vy,walker.x,walker.z=0,.8,scenario==1 and 1.4 or 0,scenario==2 and 3 or 0
        function isLineOfSightClear() return scenario~=3 end
        now=now+60
        deliver("onClientPreRender",root)
        mine.y=3
        now=now+60
        deliver("onClientPreRender",root)
        assert(#contacts==4)
    end
    -- A real hood contact may report an upward normal even at high forward speed.
    walker.x,walker.z=0,0
    deliver("onClientVehicleCollision",mine,walker,30,0,0,5,0,0,0,1,0)
    assert(#contacts==5 and contacts[5]>12)

    -- Exercise the network entry point on the client. A waterway above a
    -- submerged terrain face must use its actual water surface.
    local surfaces = {[2]=0, [3]=7, [4]=7.01}
    function getWaterLevel(x) return surfaces[x] or false end
    function processLineOfSight() return false end
    function getScreenFromWorldPosition() return false end
    function getCameraMatrix() return 0, 0, 0, 1, 0, 0 end
    local reply
    function triggerServerEvent(name, _, id, values)
        assert(name=="npchlc_traffic:worldProbeResult" and id==44)
        reply = values[1]
    end
    deliver("npchlc_traffic:worldProbe",resourceRoot,44,"road",
        {{1,0,0,"boat"},{2,0,0,"boat"},{3,0,0,"boat"},{4,0,0,"boat"},{2,0,0}})
    assert(not reply[1] and reply[2][1]==0 and reply[3][1]==7 and not reply[4] and not reply[5])

    """)
    load(client, RUNTIME, ["traffic_passengers_c.lua"])
    client.execute("""
    local body = element("vehicle")
    setElementData(body, TrafficVisibility.profileKey, "road")
    local shooter, collider = element("ped"), element("vehicle")
    local reports = {}
    function triggerServerEvent(name, _, car, actor, weapon)
        assert(car == body)
        reports[#reports+1] = {name, actor, weapon}
    end
    local function damage(actor, weapon, loss, tire)
        deliver("onClientVehicleDamage", body, actor, weapon, loss, 0, 0, 0, tire)
    end
    damage(localPlayer, 22, 100)
    damage(localPlayer, 22, 120)
    damage(localPlayer, 22, 0, 0)
    damage(shooter, 5, 5)
    damage(nil, nil, 20)
    assert(#reports == 0)
    damage(localPlayer, 0, 0)
    shooter.syncer = localPlayer
    damage(shooter, 5, 5)
    damage(localPlayer, 22, 99)
    damage(localPlayer, 51, 20)
    collider.driver = localPlayer
    damage(collider, nil, 10)
    assert(#reports == 5 and reports[1][3] == 0 and reports[2][2] == shooter)
    assert(reports[3][3] == 22 and reports[4][3] == 51 and reports[5][1] == "npchlc_traffic:collisionDamage")
    """)
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute('exports = {npc_hlc = {}, server_coldata = {}}')
    lua.execute('exports.wanted={reportWantedEvent=function(_,p,e,v) assert(e==8 and not v.takenBy); v.takenBy=p end}')
    load(lua, HLC, ["traffic_rail.lua", "traffic_physics.lua"])
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_visibility_s.lua", "traffic_model_bindings.lua",
                        "traffic_graph.lua", "traffic_world.lua", "traffic_road_population.lua",
                        "ped_ai_profiles.lua", "ped_ai_rules.lua", "ped_weapons.lua", "ped_objectives.lua", "ped_ai_tasks.lua", "ped_ai.lua",
                        "ped_carjack.lua", "traffic_passengers.lua", "traffic_collision_handling.lua", "traffic_crash_decisions.lua",
                        "traffic_vehicle_collision.lua", "traffic_vehicle_pursuit.lua", "ped_road_injury.lua", "traffic_road.lua"])
    lua.execute("""
    local response = TrafficRoad.sirenResponse
    -- Siren travels north. The target's forward vector and its velocity are independent.
    assert(response(1,20,0,0,.1,0,1,0,1,.1) == "right")
    assert(response(-1,20,0,0,.1,0,1,0,1,.1) == "left")
    assert(response(0,20,0,0,.1,0,1,0,1,.1) == "left")
    assert(response(-1,20,0,0,-.1,0,-1,0,1,.1) == "right", "oncoming car failed to swerve outward")
    assert(response(1,20,0,0,-.1,0,-1,0,1,.1) == "wait")
    assert(response(-1,-20,0,0,-.1,0,-1,0,-1,.1) == "right") -- emitter reversing south
    assert(response(10,5,0,-.1,0,-1,0,0,1,.1) == "wait")
    local crossing, _, duration = response(2,18,0,-.1,0,-1,0,0,1,.2)
    assert(crossing=="wait" and duration==4000)
    crossing, _, duration = response(10,5,0,-.1,0,-1,0,0,1,.1)
    assert(crossing=="wait" and duration==2000)
    assert(not response(10,5,0,.1,0,1,0,0,1,.1))
    assert(not response(0,-10,0,0,.1,0,1,0,1,.1))
    assert(response(0,10,0,0,0,0,1,0,1,.1), "stationary queue did not make room")
    assert(not response(15,4,0,0,0,0,1,0,1,.1), "parked out of the approach corridor")
    assert(not response(4,20,0,0,.1,0,1,0,1,.2,3), "a car already clear of the corridor swerved again")
    assert(not response(0,10,0,0,.1,0,1,0,1,.099))
    assert(not response(0,10,5,0,.1,0,1,0,1,.1))
    assert(not response(0,44.5,0,0,.1,0,1,0,1,.1))
    assert(response(0,44.49,4.99,0,.1,0,1,0,1,.1))
    assert(not response(3,4,0,0,.1,0,1,0,1,.1)) -- cone dot exactly .8
    assert(not response(0,4,0,0,.1,0,.7,0,1,.1)) -- heading dot exactly .7
    """)
    load(lua,VCS_VEHICLE,["controllers/vehicle.lua","controllers/boat.lua","controllers/jetski_control.lua","data/paint.lua","vehicle_s.lua","boarding.lua","boarding_s.lua"])
    lua.execute('exports.vcs_vehicle={bindVcsVehicle=function(_,...) return bindVcsVehicle(...) end,bindVcsVehiclePaint=function(_,...) return bindVcsVehiclePaint(...) end,transferWatercraftSeat=function(_,...) return transferWatercraftSeat(...) end}; function cancelEvent() cancelled=true end; local trigger=triggerEvent; function triggerEvent(...) cancelled=false; trigger(...); return not cancelled end')
    if disc:
        data, _ = assemble(disc, vcs_pc)
        lua.globals().streetGraph = lua.table_from({
            "nodes": data["nodes"], "links": data["links"], "roadTurnClosures": {},
            "roadPopulation": data.get("roadPopulation"), "edition": data["edition"],
        }, recursive=True)
        for inbound, outbound in data["roadTurnClosures"]:
            closures = lua.globals().streetGraph.roadTurnClosures
            if not closures[inbound]:
                closures[inbound] = lua.table()
            closures[inbound][outbound] = True
    lua.execute("""
    local player, spectator = element("player"), element("player")
    local created, players = {}, {player}
    local seededRandom = math.random
    function math.random(lower) return lower or 0.5 end
    function getElementsByType() return players end
    function getElementsWithinRange(x, y, z, radius, kind, _, dimension)
        local result = {}
        for _, e in ipairs(kind == "player" and players or kind == "vehicle" and created or {}) do
            if not e.destroyed and (e.dimension or 0) == dimension
                and (e.x - x)^2 + (e.y - y)^2 + (e.z - z)^2 <= radius^2 then result[#result + 1] = e end
        end
        return result
    end
    function setElementDimension(e, dimension) e.dimension = dimension end
    function getTime() return 12, 59 end
    function getVehicleType() return "Automobile" end
    function isVehicleLocked() return false end
    function getVehicleDoorState() return 0 end
    function getVehicleDoorOpenRatio() return 0 end
    function isVehicleBlown() return false end
    function isElementInWater() return false end
    function setElementFrozen(e, value) e.frozen = value return true end
    function getElementRotation(e) return 0,0,e.rotation end
    function setElementVelocity(e, x, y, z) e.vx, e.vy, e.vz = x, y, z end
    function getElementAngularVelocity(e) return 0.01, -0.03, e.spin or 0 end
    function setElementAngularVelocity(e, x, y, z) assert(x == 0.01 and y == -0.03) e.spin = z end
    function getVehicleHandling(e) return {mass=e.mass or 1000, turnMass=2500} end
    function getVehicleOccupants(vehicle) return {[0]=vehicle.driver, vehicle.passenger} end
    function getVehicleMaxPassengers(vehicle) return vehicle.capacity or 0 end
    function getVehicleOccupant(vehicle, seat)
        if seat == 0 or seat == nil then return vehicle.driver end
        if seat == 1 then return vehicle.passenger end
    end
    function setVehicleEngineState(vehicle, enabled) vehicle.engine = enabled end
    function destroyElement(e) e.destroyed = true end
    function killTimer() end
    function removeEventHandler() end
    function createVehicle(model, x, y, z, _, _, rotation)
        local vehicle = {kind="vehicle", model=model, x=x, y=y, z=z, rotation=rotation}
        created[#created + 1] = vehicle
        return vehicle
    end
    function createPed(model, x, y, z)
        return {kind="ped", model=model, x=x, y=y, z=z}
    end
    function warpPedIntoVehicle(ped, vehicle, seat)
        if seat == 0 then vehicle.driver = ped else vehicle.passenger = ped end
        ped.vehicle = vehicle
        return true
    end
    exports.server_coldata.getModelBoundingBox = function() return -1, -2, -0.6, 1, 2, 0.8 end
    exports.npc_hlc.enableHLCForNPC = function() return true end
    exports.npc_hlc.setNPCTask = function(_, ped, task) ped.task = task return true end
    exports.npc_hlc.setNPCDriveSpeed = function(_, ped, speed) ped.speed = speed end
    exports.npc_hlc.projectNPCTrafficRailStart = function(_, ...) return projectNPCTrafficRailStart(...) end
    exports.npc_hlc.getNPCTrafficRailSegment = function(_, ...) return getNPCTrafficRailSegment(...) end
    exports.npc_hlc.isNPCTrafficRailWaitingForSignal = function(_, ...)
        return isNPCTrafficRailWaitingForSignal(...)
    end
    exports.npc_hlc.isNPCTrafficHeadOnBlocked = function(_, ...) return isNPCTrafficHeadOnBlocked(...) end
    exports.npc_hlc.clearNPCTasks = function(_, ped) ped.task = nil end
    exports.npc_hlc.getNPCTrafficPhysicsRejoin = function(_, ...) return getNPCTrafficPhysicsRejoin(...) end
    function chooseTrafficCivilianVehicle() return 400, 171, 0 end
    TrafficAmbient = {getPedestrianModel=function(id) return id == 34 and 7 or id == 14 and 23 end}
    TrafficAmbient.adoptDriver = function(ped, player, vehicle, model, road)
        assert(not ped.adopted and PedAI.profile(ped) and not ped.destroyed)
        assert(model == getElementData(ped, "npchlc_traffic:originalModel"))
        ped.adopted, ped.attacker, ped.previousCar, ped.road = true, player, vehicle, road
        TrafficVisibility.track(ped, "pedestrian")
        return true
    end
    TrafficPopulation = {sample=function(_, _, _, _, _, modelSlot)
        assert(modelSlot == nil, "clock minutes must not become a model slot")
        return {pedestrianGroupId=0, vehicleDensity=1}
    end}
    local from = {x=45, y=0, z=0, flags=0, spawnThreshold=15, rawWidth=0, firstLink=0, linkCount=1,
        kind="vehicle", scene="outdoor", speedClass=0}
    local to = {x=13, y=0, z=0, flags=0, spawnThreshold=15, rawWidth=0, firstLink=1, linkCount=1,
        kind="vehicle", scene="outdoor", speedClass=2}
    local nextNode = {x=7, y=0, z=0, flags=0, spawnThreshold=15, rawWidth=0, firstLink=2, linkCount=0,
        kind="vehicle", scene="outdoor"}
    local before = {x=70, y=0, z=0, flags=0, spawnThreshold=15, rawWidth=0, firstLink=2, linkCount=1,
        kind="vehicle", scene="outdoor", speedClass=0}
    local edge = {id=0, from=0, to=1, lanes=1, leftLanes=0, rightLanes=1, lightDirection=true, lightGroup=1,
        speedClass=0}
    local nextEdge = {id=1, from=1, to=2, lanes=1, leftLanes=0, rightLanes=1, speedClass=2}
    local approach = {id=2, from=3, to=0, lanes=1, leftLanes=0, rightLanes=1, speedClass=0}
    local graph = {population={pedGroups={{34}}}, pedestrianDriverMasks={['34']=1}, roadTurnClosures={},
        nodes={from,to,nextNode,before}, links={edge,nextEdge,approach}}
    local function copyRoad(dx, dy, nodeOffset, linkOffset)
        for index, node in ipairs({from,to,nextNode,before}) do
            local copy = {}
            for key, value in pairs(node) do copy[key] = value end
            copy.x, copy.y, copy.firstLink = node.x + dx, node.y + dy, node.firstLink + linkOffset
            graph.nodes[index + nodeOffset] = copy
        end
        for index, link in ipairs({edge,nextEdge,approach}) do
            local copy = {}
            for key, value in pairs(link) do copy[key] = value end
            copy.id, copy.from, copy.to = link.id + linkOffset, link.from + nodeOffset, link.to + nodeOffset
            graph.links[index + linkOffset] = copy
        end
    end
    copyRoad(500, 0, 4, 3)
    do
        -- The closest outgoing link is a dead end. A two-corner detour is
        -- required to reach the target street, and a closed turn blocks it.
        local roads={nodes={},links={},roadTurnClosures={}}
        local coords={{0,0},{10,0},{16,0},{10,12},{28,12},{28,0}}
        local exits={{1},{2,3},{},{4},{5},{}}
        for i,pt in ipairs(coords) do
            roads.nodes[i]={x=pt[1],y=pt[2],z=0,flags=0,scene="outdoor",
                firstLink=#roads.links,linkCount=#exits[i]}
            for _,dest in ipairs(exits[i]) do
                roads.links[#roads.links+1]={id=#roads.links,from=i-1,to=dest,lanes=1}
            end
        end
        local first,goal=roads.links[1],roads.links[5]
        local path,n=TrafficRoad.findPolicePath(roads,first,0,goal,true)
        assert(n<=5 and #path==4 and path[2].edge.to==3 and path[3].edge.to==4)
        roads.roadTurnClosures[0]={[2]=true}
        assert(not TrafficRoad.findPolicePath(roads,first,0,goal,true))
        assert(not TrafficRoad.findPolicePath(roads,goal,0,first,true))
        assert(not TrafficRoad.findPolicePath(roads,first,0,first,false))
        assert(#TrafficRoad.findPolicePath(roads,first,0,first,true)==1)
        local long={nodes={},links={},roadTurnClosures={}}
        for i=0,150 do
            long.nodes[i+1]={x=i,y=0,z=0,flags=0,scene="outdoor",firstLink=i,linkCount=i<150 and 1 or 0}
            if i<150 then long.links[i+1]={id=i,from=i,to=i+1,lanes=1} end
        end
        local missing,expanded=TrafficRoad.findPolicePath(long,long.links[1],0,long.links[150],true)
        assert(not missing and expanded==128)
    end
    assert(TrafficRoad.crossing(from, to, 0, 0, 40) == 5 / 32)
    assert(TrafficRoad.chooseDriver({34}, {['34']=1}, 1, 0, TrafficAmbient.getPedestrianModel, 14) == 14)
    local laneGraph = {nodes={{x=0,y=0,z=0}, {x=35,y=0,z=0}}}
    local laneEdge = {from=0, to=1, lanes=2, leftLanes=0, rightLanes=2}
    local x, y = TrafficGraph.lanePoint(laneGraph, laneEdge, 1)
    local fast = element("vehicle", x - 32.5)
    fast.y, fast.vx = y, 0.45
    created[1] = fast
    assert(not TrafficRoad.laneEntryClear(laneGraph, laneEdge, 1, 0, nil, 10))
    fast.vx = 0.2
    assert(TrafficRoad.laneEntryClear(laneGraph, laneEdge, 1, 0, nil, 10))
    fast.vx, fast.y = 0.45, -y
    assert(TrafficRoad.laneEntryClear(laneGraph, laneEdge, 1, 0, nil, 10))
    created[1] = nil
    do
        local water = {population={pedGroups={{34}}}, pedestrianDriverMasks={["34"]=2^9},
            nodes={}, links={edge,nextEdge,approach}, roadTurnClosures={}}
        for index, node in ipairs({from,to,nextNode,before}) do
            local copy = {}
            for key, value in pairs(node) do copy[key] = value end
            copy.kind, copy.flags, copy.x = "boat", 0x100, ({65,15,2,95})[index]
            water.nodes[index] = copy
        end
        -- The inclusion test compares dÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â² with 1.5RÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¾ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¾Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â¦ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â²; interpolation uses 1.5R.
        assert(math.abs(TrafficRoad.crossing(water.nodes[1],water.nodes[2],0,0,40)-0.1)<1e-8)
        water.nodes[1].x = 48
        assert(not TrafficRoad.crossing(water.nodes[1],water.nodes[2],0,0,40))
        water.nodes[1].x = 65
        water.nodes[3].y = 16
        water.nodes[3].firstLink, water.nodes[3].linkCount = 3, 1
        water.links[4] = {id=3,from=2,to=3,lanes=1,leftLanes=0,rightLanes=1,speedClass=0}
        local savedType = getVehicleType
        local previousRemove = removeEventHandler
        function removeEventHandler(name, _, callback)
            for i, registered in ipairs(events[name] or {}) do
                if registered == callback then table.remove(events[name],i) return true end
            end
        end
        function getVehicleType(v)
            local model = type(v)=="table" and v.model or v
            return (model==473 or model==493 or model==484) and "Boat" or "Automobile"
        end
        function getPlayerWantedLevel() return 0 end
        function TrafficAmbient.chooseBoat(x,y,z,wanted,available)
            assert(x==player.x and y==player.y and wanted==0 and not available)
            return 473,233,9
        end
        local function waterOnly(kind) return kind=="boats" and 1 or 0 end
        local function waterProbe(z)
            local packet = assert(packets[#packets],"water path did not reach the production probe")
            local values = {}
            for i,point in ipairs(packet[1][3]) do
                assert(point[4]=="boat")
                values[i]={z,false}
            end
            client = packet.owner
            deliver("npchlc_traffic:worldProbeResult",resourceRoot,packet[1][1],{values,0,1})
            tick()
            return packet[1][3][1][1]
        end
        local function startWater()
            packets, created = {}, {}
            TrafficRoad.start(water,waterOnly)
            client = player
            deliver("npchlc_traffic:worldProbeReady",resourceRoot)
            tick()
        end
        startWater()
        waterProbe(7.01)
        assert(#created==0,"server accepted an out-of-range water surface")
        TrafficRoad.stop()
        startWater()
        local obstruction = element("vehicle",packets[1][1][3][1][1]+31)
        created[1] = obstruction
        waterProbe(0)
        assert(#created==1 and getTrafficRoadStatus().boats==0)
        TrafficRoad.stop()
        startWater()
        waterProbe(0)
        local boat = assert(created[1],"no boat was created from a valid water path")
        local captain = assert(boat.driver)
        assert(boat.model==473 and boat["npchlc_traffic:originalModel"]==233 and captain.task)
        assert(getTrafficRoadStatus().boats==1 and getTrafficRoadStatus().boatSpawned==1)
        local inbound = captain.task
        deliver("npc_hlc:onNPCTaskDone",captain,inbound)
        assert(captain.task~=inbound and captain.task[1]=="driveTrafficRail")
        boat.syncer = spectator
        players[2] = spectator
        tick()
        assert(boat.driver==captain and getTrafficRoadStatus().boats==1)
        local rpc="vcs_vehicle:boardWatercraft"
        client=spectator
        function isControlEnabled() return true end
        function getPedContactElement() return false end
        function removePedFromVehicle(ped)
            ped.vehicle.driver,ped.vehicle=nil,nil
            return true
        end
        spectator.x,spectator.y,spectator.z = boat.x+5,boat.y,boat.z
        deliver(rpc,resourceRoot,boat)
        assert(boat.driver==captain)
        spectator.x,spectator.dimension=boat.x,47
        deliver(rpc,resourceRoot,boat)
        assert(boat.driver==captain)
        spectator.dimension=0
        local warp=warpPedIntoVehicle
        function warpPedIntoVehicle(ped,veh,index)
            if ped==spectator then return false end
            return warp(ped,veh,index)
        end
        deliver(rpc,resourceRoot,boat)
        assert(boat.driver==captain and captain.vehicle==boat and captain.task)
        warpPedIntoVehicle=warp
        deliver(rpc,resourceRoot,boat)
        assert(boat.driver==spectator and spectator.vehicle==boat and boat.syncer==spectator)
        client=player
        local previousX = player.x
        player.x = boat.x
        deliver(rpc,resourceRoot,boat)
        assert(boat.driver==spectator and not player.vehicle)
        player.x = previousX
        assert(getTrafficRoadStatus().boats==0 and not TrafficRoad.isManagedPed(captain))
        TrafficRoad.stop()
        assert(not boat.destroyed)
        spectator.vehicle,spectator.x,spectator.y,spectator.z = nil,0,0,0
        players[2], created, packets = nil, {}, {}
        -- Ordinary Jetmax boards through native MTA events. The displaced
        -- captain can exit before or after the player's seat notification.
        function TrafficAmbient.chooseBoat() return 493,258,12 end
        water.pedestrianDriverMasks["34"]=2^12
        for _, exitFirst in ipairs({true,false}) do
            startWater()
            waterProbe(0)
            local jetmax=assert(created[1])
            local skipper=assert(jetmax.driver)
            assert(jetmax.model==493 and jetmax["npchlc_traffic:originalModel"]==258)
            local claimant=element("player",jetmax.x)
            claimant.y,claimant.z=jetmax.y,jetmax.z
            -- A passenger must leave the skipper and the synchronizer alone.
            deliver("onVehicleStartEnter",jetmax,claimant,1)
            deliver("onVehicleEnter",jetmax,claimant,1)
            assert(skipper.task and jetmax.syncer==player and getTrafficRoadStatus().boats==1)
            deliver("onVehicleStartEnter",jetmax,claimant,0,skipper,0)
            assert(not skipper.task)
            claimant.x=jetmax.x+20
            now=now+600
            tick()
            assert(skipper.task and getTrafficRoadStatus().boats==1, "abandoned boarding stranded skipper")
            claimant.x=jetmax.x
            deliver("onVehicleStartEnter",jetmax,claimant,0,skipper,0)
            skipper.vehicle,jetmax.driver=nil,nil
            if exitFirst then deliver("onVehicleExit",jetmax,skipper,0,claimant) end
            jetmax.driver,claimant.vehicle=claimant,jetmax
            deliver("onVehicleEnter",jetmax,claimant,0,skipper)
            if not exitFirst then deliver("onVehicleExit",jetmax,skipper,0,claimant) end
            assert(skipper.adopted and skipper.attacker==claimant and not skipper.task)
            assert(not TrafficRoad.isManagedPed(skipper) and getTrafficRoadStatus().boats==0)
            assert(jetmax.syncer==claimant and not jetmax.frozen and not jetmax["npchlc_traffic:rail"])
            tick()
            TrafficRoad.stop()
            assert(not jetmax.destroyed and not skipper.destroyed and jetmax.driver==claimant)
        end
        -- Marquis has its helm over 5 m aft of the origin. The same RPC
        -- handles swimming up to the cockpit and reboarding an empty hull.
        function TrafficAmbient.chooseBoat() return 484,248,12 end
        startWater()
        waterProbe(0)
        local yacht=assert(created[1])
        local skipper=assert(yacht.driver)
        local swimmer=element("player",yacht.x)
        swimmer.y,swimmer.z=yacht.y-12,yacht.z
        local wasInWater=isElementInWater
        function isElementInWater(e) return e==swimmer end
        client=swimmer
        deliver(rpc,resourceRoot,yacht)
        assert(yacht.driver==skipper)
        swimmer.y=yacht.y-5
        local impostor=element("vehicle",yacht.x)
        impostor.model,impostor.y,impostor.z=484,yacht.y,yacht.z
        impostor["npchlc_traffic:originalModel"]=248
        deliver(rpc,resourceRoot,impostor)
        assert(not swimmer.vehicle)
        deliver(rpc,resourceRoot,yacht)
        assert(yacht.driver==swimmer and yacht.syncer==swimmer and skipper.adopted)
        removePedFromVehicle(swimmer)
        deliver("onVehicleExit",yacht,swimmer,0)
        deliver(rpc,resourceRoot,yacht)
        assert(yacht.driver==swimmer and not yacht["npchlc_traffic:rail"])
        TrafficRoad.stop()
        isElementInWater=wasInWater
        created,packets = {},{}
        getVehicleType, removeEventHandler = savedType, previousRemove
    end
    TrafficRoad.start(graph, function(kind) assert(kind == "cars" or kind == "boats") return 1 end)
    client = player
    deliver("npchlc_traffic:worldProbeReady", resourceRoot)
    tick()
    assert(#packets == 1 and #created == 0)
    assert(packets[1][1][2] == "road" and math.abs(packets[1][1][3][1][1] - 40) < 0.1)
    do
        local barrier={points={{x=35,y=2,z=0},{x=35,y=-2,z=0}}}
        local beforeX,beforeY=TrafficWorld.getRoadView(player)
        local ground
        assert(TrafficWorld.probeRoad(player,barrier,function(owner,plan,result)
            assert(owner==player and plan==barrier)
            ground=result.probes
        end,"roadblock"))
        local request=table.remove(packets)
        deliver("npchlc_traffic:worldProbeResult",resourceRoot,request[1][1],{{{1,true},{.5,true}},1,0})
        assert(ground[1].groundZ==1 and ground[2].groundZ==.5)
        local afterX,afterY=TrafficWorld.getRoadView(player)
        assert(beforeX==afterX and beforeY==afterY)
    end
    client = spectator
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[1][1][1], {{{0, false}}, 1, 0})
    assert(TrafficWorld.getRoadView(spectator) == nil)
    tick()
    assert(#created == 0)
    client = player
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[1][1][1], {{{0, false}}, 0, 1})
    local viewX, viewY = TrafficWorld.getRoadView(player)
    assert(viewX == 0 and viewY == 1)
    tick()
    local vehicle = assert(created[1])
    local driver = vehicle.driver
    assert(math.abs(vehicle.x - 40) < 0.1 and vehicle.z == 0.6 and vehicle.rotation == 90 and vehicle.engine)
    assert(getElementData(vehicle, "npchlc_traffic:originalModel") == 171)
    assert(driver.model == 7 and driver.speed == 0.22 and TrafficRoad.isManagedPed(driver))
    assert(not vehicle.frozen and driver.task[1] == "driveTrafficRail" and driver.task[8] == 29 and driver.task[15] == 1)
    assert(getElementData(vehicle, TrafficVisibility.profileKey) == "road"
        and getElementData(driver, TrafficVisibility.profileKey) == "road")
    assert(driver.task[2] == 57.5 and driver.task[5] == 57.5 and driver.task[21] == 2 and driver.task[22] == 2)
    vehicle.syncer = player
    local collider = element("vehicle", vehicle.x)
    collider.y, collider.z, collider.vy, collider.mass = -3, vehicle.z, 0.4, 2000
    collider.driver, collider.rotation, player.vehicle = player, 0, collider
    vehicle.x = vehicle.x - 0.4
    tick()
    collider.vy = 0.14 -- A slower post-contact sync arrives before the contact report.
    tick()
    client = spectator
    deliver("npchlc_traffic:railImpact", resourceRoot, vehicle, collider, vehicle.x - 1, -1, vehicle.z, 0, 1, 0)
    assert(driver.task[1] == "driveTrafficRail")
    client = player
    deliver("npchlc_traffic:railImpact", resourceRoot, vehicle, collider, vehicle.x - 1, -1, vehicle.z, 0, 99, 0)
    assert(driver.task[1] == "driveTrafficRail")
    deliver("onVehicleDamage", vehicle, 10)
    assert(driver.task[1] == "driveTrafficRail" and timers[150])
    -- Damage can switch tasks before the contact RPC arrives. The target
    -- already has forward motion and a partial lateral collision response.
    timers[150]()
    vehicle.vx, vehicle.vy, vehicle.vz = -0.22, 0.1, 0.03
    deliver("npchlc_traffic:railImpact", resourceRoot, vehicle, collider, vehicle.x - 1, -1, vehicle.z, 0, 1, 0)
    assert(not vehicle.frozen and vehicle.vx == -0.22 and vehicle.vz == 0.03
        and math.abs(vehicle.vy - 1.35 * 0.4 * 2 / 3) < 0.0001)
    assert(vehicle.spin < 0)
    player.vehicle = nil
    vehicle.vy = 0.12
    timers[150]()
    deliver("npchlc_traffic:railImpact", resourceRoot, vehicle, collider, vehicle.x - 1, -1, vehicle.z, 0, 1, 0)
    assert(vehicle.vy == 0.12)
    assert(driver.task[1] == "driveTrafficPhysics" and driver.task[2] == 1)
    assert(#driver.task[5] == 2 and driver.task[5][1][3] == 29 and driver.task[5][1][9] == 1)
    local oldTask = driver.task
    deliver("npc_hlc:onNPCTaskDone", driver, driver.task)
    assert(driver.task[2] == 2 and driver.task[5][1][3] == 10 and driver.task[5][1][8] == 2)
    deliver("npc_hlc:onNPCTaskDone", driver, oldTask)
    assert(driver.task[2] == 2)
    tick()
    assert(getTrafficRoadStatus().vehicles == 1 and #created == 1)
    local distant = element("player", 500)
    players[2] = distant
    client = distant
    deliver("npchlc_traffic:worldProbeReady", resourceRoot)
    tick()
    assert(#packets == 2 and packets[2].owner == distant and math.abs(packets[2][1][3][1][1] - 540) < 0.1)
    client = distant
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[2][1][1], {{{0, false}}})
    tick()
    assert(getTrafficRoadStatus().vehicles == 2 and math.abs(created[2].x - 540) < 0.1)
    local lost = created[2]
    assert(lost.syncer == distant)
    lost.syncer = nil
    tick()
    assert(lost.destroyed and lost.driver.destroyed and getTrafficRoadStatus().despawnNoSyncer == 1)
    vehicle.driver, driver.vehicle = player, nil
    deliver("onVehicleEnter", vehicle, player, 0, driver)
    deliver("onVehicleExit", vehicle, driver, 0, player)
    assert(driver.adopted and driver.attacker == player and driver.previousCar == vehicle and not driver.task)
    assert(not TrafficRoad.resumeDriver(driver.road))
    TrafficAmbient.releaseDriver = function(ped)
        assert(ped == driver and ped.adopted)
        ped.adopted = nil
        return true
    end
    vehicle.driver, driver.vehicle = driver, vehicle
    assert(TrafficRoad.resumeDriver(driver.road))
    assert(driver.task[1]=="driveTrafficPhysics" and driver.task[3]==25 and driver.task[6]==2)
    assert(driver.speed==0.5 and TrafficRoad.isManagedPed(driver))
    for _,lane in ipairs(driver.task[5]) do assert(lane[9]==0) end
    assert(not TrafficRoad.resumeDriver(driver.road))
    vehicle.driver, driver.vehicle = player, nil
    deliver("onVehicleEnter", vehicle, player, 0, driver)
    assert(not TrafficRoad.isManagedPed(driver) and not getElementData(vehicle, "npchlc_traffic:rail"))
    TrafficRoad.stop()
    assert(not driver.destroyed and not vehicle.destroyed and created[2].destroyed and getTrafficRoadStatus().vehicles == 0)
    assert(not getElementData(vehicle, TrafficVisibility.profileKey))

    copyRoad(0, 4, 8, 6)
    players, created, packets = {player}, {}, {}
    TrafficRoad.start(graph, function() return 1 end)
    tick()
    assert(#packets == 1 and #packets[1][1][3] >= 2)
    local alternate = packets[1][1][3][2]
    client = player
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[1][1][1], {{false, {0, false}}, 0, 1})
    tick()
    assert(#created == 1 and created[1].x == alternate[1] and created[1].y == alternate[2])
    TrafficRoad.stop()

    packets = {}
    local first, second = element("ped", 10), element("ped", 12)
    local destinations = {{id=5, x=10, y=0, z=0}}
    assert(TrafficWorld.reachable(player, first, 4, destinations) == nil)
    assert(TrafficWorld.reachable(player, second, 4, destinations) == nil and #packets == 2)
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[2][1][1], {5})
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, packets[1][1][1], {})
    now=now+6000 -- both replies arrived promptly, but the actor scheduler was busy
    assert(TrafficWorld.reachable(player, first, 4, destinations)[1] == nil)
    assert(TrafficWorld.reachable(player, second, 4, destinations)[1] == 5)

    local function answerProbe(packet)
        local values = {}
        for index in ipairs(packet[1][3]) do values[index] = {0, false} end
        client = packet.owner
        deliver("npchlc_traffic:worldProbeResult", resourceRoot, packet[1][1], {values, 0, 1})
    end

    do
        local picker=chooseTrafficCivilianVehicle
        local needed=true
        chooseTrafficCivilianVehicle=function() return 416,227,0 end
        PedServices={needsParkedVehicle=function() return needed end}
        players,created,packets={player},{},{}
        TrafficRoad.start(graph,function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local routeState={railRoute={{edge=edge,lane=0}},heightOffset=0.6}
        local route=assert(TrafficRoad.serviceRoute(routeState,22,5,0))
        assert(#route==1 and math.abs(route[1][1]-22)<0.01 and route[1][2]~=5)
        assert(not TrafficRoad.serviceRoute(routeState,22,5,40))
        local ambulance=assert(created[1])
        local medic=ambulance.driver
        ambulance.driver,medic.vehicle=nil,nil
        deliver("onVehicleExit",ambulance,medic,0)
        now=now+1000
        tick()
        assert(not ambulance.destroyed and medic.adopted)
        needed=false
        deliver("onVehicleStartEnter",ambulance,player,0)
        now=now+1000
        tick()
        assert(not ambulance.destroyed)
        ambulance.driver,player.vehicle=player,ambulance
        deliver("onVehicleEnter",ambulance,player,0)
        now=now+9000
        tick()
        assert(not ambulance.destroyed)
        ambulance.driver,player.vehicle=nil,nil
        deliver("onVehicleExit",ambulance,player,0)
        now=now+1000
        tick()
        assert(ambulance.destroyed)
        TrafficRoad.stop()
        chooseTrafficCivilianVehicle,PedServices=picker,nil
    end
    do
        players,created,packets={player},{},{}
        TrafficRoad.start(graph,function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local wreck=assert(created[1])
        deliver("onVehicleExplode",wreck)
        local blown=isVehicleBlown
        isVehicleBlown=function(e) return e==wreck end
        tick()
        assert(not wreck.destroyed)
        timers[2600]()
        assert(getElementData(wreck,TrafficVisibility.retiringKey) and not wreck.destroyed)
        timers[400]()
        assert(wreck.destroyed)
        isVehicleBlown=blown
        TrafficRoad.stop()
    end
    for _,seat in ipairs({0,1}) do
        players,created,packets={player},{},{}
        TrafficRoad.start(graph,function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local car=assert(created[1])
        local driver=car.driver
        if seat==0 then car.driver,driver.vehicle=player,nil else car.passenger=player end
        player.vehicle=car
        deliver("onVehicleEnter",car,player,seat)
        if seat==1 then
            car.driver,driver.vehicle=nil,nil
            deliver("onVehicleExit",car,driver,0)
        end
        now=now+31000
        tick()
        assert(not car.destroyed)
        car.driver,car.passenger,player.vehicle=nil,nil,nil
        if seat==0 then deliver("onVehicleExit",car,player,seat) end
        -- Passenger disconnect can remove the occupant without a seat-exit callback.
        now=now+1000
        tick()
        assert(not car.destroyed)
        now=now+30000
        tick()
        assert(car.destroyed)
        TrafficRoad.stop()
    end
    do
        local oldFlee, oldFight, originalRandom = PedAI.passengerThreat, PedAI.vehicleThreat, math.random
        local oldVoice = PedVoice
        PedAI.passengerThreat = function(ped, attacker) ped.fledFrom = attacker end
        PedAI.vehicleThreat = function(ped, attacker) ped.fought = attacker end
        PedVoice = {emit=function(ped, kind) ped.voice = kind end}
        function getPedWeapon(p) return p.weapon or 0 end
        for scenario = 1, 6 do
            player.x, player.y, player.z = 0, 0, 0
            players, created, packets = {player}, {}, {}
            TrafficRoad.start(graph, function() return 1 end)
            tick()
            answerProbe(assert(packets[1]))
            tick()
            local car = assert(created[1])
            local ped = car.driver
            ped.syncer = player
            local speed = ped.speed * 50
            if scenario == 3 then PedAI.profile(ped).pedType = 7 end
            -- Live MTA reports the ray's full reach past an impacted chassis.
            local function fireAtCar()
                TrafficRoad.noteGunfire(player, 22, car.x, car.y+26, car.z, car.x, car.y-5, car.z)
            end
            TrafficRoad.noteGunfire(player, 22, car.x, car.y+26, car.z, car.x, car.y+8, car.z)
            TrafficRoad.noteGunfire(player, 22, car.x+8, car.y+26, car.z, car.x+8, car.y-5, car.z)
            tick()
            assert(ped.task[1] == "driveTrafficRail" and not ped.voice)
            client = spectator
            deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, 22, 1000, 8)
            deliver("onVehicleDamage", car, 8)
            tick()
            assert(ped.task[1] == "driveTrafficRail" and not ped.voice)
            client = player
            deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, 22, 1000, 8)
            tick()
            assert(ped.task[1] == "driveTrafficRail" and not ped.voice)
            fireAtCar()
            if scenario == 2 then
                -- Report and accepted bullet can precede server health sync.
                now = now + 1250
                deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, 22, 1000, 8)
                fireAtCar()
                tick()
                assert(ped.task[1] == "driveTrafficRail" and not ped.voice)
                deliver("onVehicleDamage", car, 8)
            else
                deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, 22, 1000, 8)
            end
            math.random = function(lower) return lower or ({0.501, 0.500, 0.9, 0.499, 0.501, 0.5})[scenario] end
            if scenario >= 5 then
                player.x, player.y, player.z = car.x, car.y, car.z
                player.weapon = scenario == 5 and 5 or 0
                now = now + 1250
                deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, player.weapon, 1000, 0)
            end
            tick()
            if scenario == 1 or scenario == 5 then
                assert(normalizeNPCTrafficPhysics(ped.task)[6] == 3)
                assert(ped.task[1] == "driveTrafficPhysics" and ped.speed*50 == math.floor(speed*1.5))
                fireAtCar()
                deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, car, player, 22, 1000, 8)
                deliver("onVehicleDamage", car, 8)
                tick()
                assert(ped.speed*50 == math.floor(speed*1.5))
            else
                assert(not ped.task and (scenario == 3 or ped.voice == "fear"))
                tick()
                local packet = packets[#packets]
                assert(packet.name == "npchlc_traffic:occupantExit" and packet[1][1] == ped and packet[1][3] == 0)
                car.driver, ped.vehicle = nil, nil
                deliver("onVehicleExit", car, ped, 0)
                assert(ped.adopted and not ped.destroyed and not car.destroyed)
                assert((scenario ~= 3 and ped.fledFrom == player) or (scenario == 3 and ped.fought == player))
            end
            math.random = originalRandom
            TrafficRoad.stop()
        end
        player.x, player.y, player.z, player.weapon = 0, 0, 0, nil
        local oldPicker = chooseTrafficCivilianVehicle
        chooseTrafficCivilianVehicle = function() return 400, 261, 0 end
        players, created, packets = {player}, {}, {}
        TrafficRoad.start(graph, function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local special = assert(created[1])
        local driver = special.driver
        local npc = element("ped",special.x)
        npc.y,npc.z,npc.syncer = special.y,special.z,player
        player.x,player.y,player.z,client = special.x,special.y,special.z,player
        function getPlayerWantedLevel(p) return p.stars or 0 end
        function exports.wanted:raisePlayerWanted(p,n,why) assert(why=="vehicleAttack") p.stars=math.max(p.stars or 0,n) end
        deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, special, player, 0, 1000, 0)
        tick()
        assert(player.stars == 1 and driver.task[1] == "driveTrafficRail" and not driver.voice)
        -- The vehicle owner can supply a hit the attacker's machine missed.
        -- Two owners observing one strike request wanted only once.
        client, special.syncer, player.stars = spectator, spectator, 0
        deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, special, player, 0, 1000, 0)
        tick()
        assert(player.stars == 0)
        deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, special, player, 0, 999, 1)
        tick()
        assert(player.stars == 1)
        client = player
        player.stars = 3
        deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, special, player, 0, 1000, 0)
        tick()
        assert(player.stars == 3)
        math.random = function(lower) return lower or 0.5 end
        deliver("npchlc_traffic:vehicleBodyHit", resourceRoot, special, npc, 0, 1000, 0)
        tick()
        assert(not driver.task and driver.voice == "fear")
        TrafficRoad.stop()
        math.random, chooseTrafficCivilianVehicle = originalRandom, oldPicker
        player.x,player.y,player.z,player.stars = 0,0,0,nil
        PedAI.passengerThreat, PedAI.vehicleThreat, PedVoice = oldFlee, oldFight, oldVoice
    end

    do
        local oldVoice, oldRandom, oldPicker = PedVoice, math.random, chooseTrafficCivilianVehicle
        local oldRage = PedAI.roadRage
        local originalType, originalJack = getVehicleType,PedAI.carjacked
        local falls, thefts, fallenRoad = 0,0,nil
        function removePedFromVehicle(ped)
            local bike=ped.vehicle
            bike.driver,ped.vehicle=nil,nil
            deliver("onVehicleExit",bike,ped,0)
            return true
        end
        TrafficAmbient.bikeFall=function(ped,impact,launch,road)
            assert(ped.adopted and launch and road.driver==ped and impact.score>75)
            falls,fallenRoad=falls+1,road
        end
        PedAI.carjacked=function(ped,thief,bike,road)
            assert(ped.adopted and road.driver==ped and thief==player and bike==road.vehicle)
            thefts=thefts+1
        end
        getVehicleType=function() return "Bike" end
        for scenario=1,2 do
            players,created,packets,player.vehicle={player},{},{},nil
            TrafficRoad.start(graph,function() return 1 end)
            tick()
            answerProbe(assert(packets[1]))
            tick()
            local bike=assert(created[1])
            local ped=bike.driver
            if scenario==1 then
                removePedFromVehicle(ped)
                bike.driver,player.vehicle=player,bike
                deliver("onVehicleEnter",bike,player,0)
                deliver("onVehicleEnter",bike,player,0)
                assert(thefts==1)
            else
                bike.syncer,client=player,player
                local collider=element("vehicle",bike.x)
                collider.y,collider.z,collider.vy=bike.y-2,bike.z,0.5
                for _,impulse in ipairs({10,300,300}) do
                    deliver("npchlc_traffic:railImpact",resourceRoot,bike,collider,bike.x,bike.y,bike.z,0,1,0,impulse)
                    if impulse==10 then assert(bike.driver==ped and falls==0) end
                end
                assert(not bike.driver and falls==1 and thefts==1)
                local releaseDriver=TrafficAmbient.releaseDriver
                TrafficAmbient.releaseDriver=function(p) p.adopted=nil return true end
                bike.driver,ped.vehicle=ped,bike
                assert(TrafficRoad.resumeDriver(fallenRoad))
                local ride=getElementData(bike,"npchlc_traffic:ride")
                assert(ride==1)
                now=now+10000
                deliver("npchlc_traffic:railImpact",resourceRoot,bike,collider,bike.x,bike.y,bike.z,0,1,0,300,0)
                assert(bike.driver==ped and falls==1 and TrafficRoad.isDriving(ped,bike))
                deliver("npchlc_traffic:railImpact",resourceRoot,bike,collider,bike.x,bike.y,bike.z,0,1,0,300,ride)
                assert(not bike.driver and falls==2)
                TrafficAmbient.releaseDriver=releaseDriver
            end
            TrafficRoad.stop()
        end
        TrafficAmbient.bikeFall=nil
        getVehicleType,PedAI.carjacked=originalType,originalJack
        assert(TrafficVehicleCollision.damage(25, 1, "Bike") == 0)
        assert(TrafficVehicleCollision.damage(30, 1, "Bike") == 5)
        assert(TrafficVehicleCollision.damage(31, 1, "Bike") == 6)
        assert(TrafficVehicleCollision.damage(31, 1, "Automobile") < 5)
        PedVoice = {emit = function(ped, kind) assert(kind == "crash") ped.calls = (ped.calls or 0) + 1 end}
        local typeFor = getVehicleType
        local bike, rider, other = element("vehicle"), element("ped"), element("vehicle")
        bike.driver, other.driver = rider, element("ped")
        local bikeState = {vehicle=bike, driver=rider, originalVehicle=171}
        getVehicleType = function() return "Bike" end
        assert(not TrafficVehicleCollision.driverReaction(bikeState, other, 32, now, nil, 0,1,0))
        assert(TrafficVehicleCollision.driverReaction(bikeState, other, 33, now, nil, 0,1,0) and rider.calls == 1)
        getVehicleType = typeFor
        assert(not TrafficVehicleCollision.driverReaction(bikeState, other, 33, now+1000, nil, 0,1,0))
        PedAI.roadRage = function(ped, target, road)
            assert(ped.adopted and target == player and road.driver == ped)
            ped.angry = true
        end
        function getPlayerWantedLevel(p) return p.stars or 0 end
        function exports.wanted:raisePlayerWanted(p, stars, reason) assert(reason == "policeCollision") p.stars = math.max(p.stars or 0, stars) end
        local function crashScenario(model, roll, expect, police, nativeExit)
            chooseTrafficCivilianVehicle = function() return 400, 171, police and 13 or 0 end
            players, created, packets, player.vehicle = {player}, {}, {}, nil
            TrafficRoad.start(graph, function() return 1 end)
            tick()
            answerProbe(assert(packets[1]))
            tick()
            local car = assert(created[1])
            local ped, collider = car.driver, element("vehicle", car.x)
            ped.syncer, collider.driver, player.vehicle = player, player, collider
            collider.y, collider.z, collider.vy = car.y-2, car.z, 0.4
            PedAI.brain(ped).profile = PedAIRules.profile(model)
            client = player
            -- At or below the calculated-damage boundary there is only a native handoff.
            local function report(impulse)
                deliver("npchlc_traffic:railImpact", resourceRoot, car, collider, car.x, car.y-1, car.z, 0,1,0,impulse)
            end
            report(25)
            assert(ped.task[1] == "driveTrafficPhysics" and not ped.calls)
            report(26)
            assert(not ped.calls)
            local vy = car.vy
            if roll < 0.1 then deliver("npchlc_traffic:collisionDamage", resourceRoot, car, collider) end
            report(100)
            report(100)
            assert(ped.calls == 1 and car.vy == vy)
            math.random = function(n) return n or roll end
            tick()
            if roll >= 0.1 then assert(ped.task[1] == "driveTrafficPhysics") end
            deliver("onVehicleDamage", car, 5)
            if roll >= 0.1 then
                tick()
                assert(not getTrafficRoadStatus()[expect or "crashRoadRage"])
                deliver("npchlc_traffic:collisionDamage", resourceRoot, car, collider)
            end
            tick()
            local status = getTrafficRoadStatus()
            if police then
                assert(player.stars == 1 and not status.crashRoadRage and ped.task[1] == "driveTrafficPhysics")
            else
                assert(status[expect] == 1, expect)
                if expect == "crashRoadRage" then
                    assert(ped.task[1] == "stopVehicle")
                    tick()
                    assert(packets[#packets].name ~= "npchlc_traffic:occupantExit")
                    car.vx, car.vy, car.vz = 0, 0, 0
                    tick()
                    assert(packets[#packets].name == "npchlc_traffic:occupantExit")
                    car.driver, ped.vehicle = nil, nil
                    deliver("onVehicleExit", car, ped, 0)
                    assert(ped.angry and ped.adopted and not car.destroyed)
                elseif expect == "crashPursuit" or expect == "committedRoadRage" then
                    assert(ped.task[1] == "driveAtPed" and ped.task[2] == player)
                    if nativeExit then
                        car.vx,car.vy,car.vz,collider.vy = 0,0,0,0
                        tick()
                        now = now+4000
                        tick()
                        local function answerExit()
                            for n = #packets, 1, -1 do
                                local packet = packets[n]
                                if packet.name == "npchlc_traffic:worldProbe" and packet[1][2] == "pursuitExit" then
                                    client = packet.owner
                                    deliver("npchlc_traffic:worldProbeResult",resourceRoot,packet[1][1],true)
                                    return
                                end
                            end
                            error("missing pursuit walkability check")
                        end
                        answerExit()
                        tick()
                        assert(ped.task[1] == "stopVehicle")
                        tick()
                        answerExit()
                        tick()
                        local packet = packets[#packets]
                        assert(packet.name == "npchlc_traffic:occupantExit" and packet[1][4] == player)
                        local oldFight = PedAI.vehicleThreat
                        PedAI.vehicleThreat = function(driver,target,road)
                            assert(driver == ped and target == player and road.vehicle == car and driver.adopted)
                            driver.confronted = true
                        end
                        car.driver,ped.vehicle = nil,nil
                        deliver("onVehicleExit",car,ped,0)
                        assert(ped.confronted and not car.destroyed)
                        PedAI.vehicleThreat = oldFight
                    else
                        if expect == "committedRoadRage" then
                            player.vehicle = nil
                            deliver("onVehicleStartEnter",car,player,0,ped,0)
                            -- Abandon the jack and return to the original car.
                            player.vehicle = collider
                            now = now + 8100
                            tick()
                            assert(ped.task[1] == "driveAtPed" and ped.task[2] == player)
                        end
                        player.health = 0
                        tick()
                        assert(ped.task[1] == "driveTrafficPhysics")
                        player.health = 100
                        -- Release returns a script-owned road driver to a fresh lane task.
                        PedAI.brain(ped).scriptOwner = true
                        TrafficRoad.driverScriptChanged(ped,true)
                        ped.task = {"scriptTask"}
                        tick()
                        assert(ped.task[1] == "scriptTask")
                        PedAI.brain(ped).scriptOwner = nil
                        TrafficRoad.driverScriptChanged(ped,false)
                        assert(ped.task[1] == "driveTrafficPhysics")
                    end
                elseif expect == "crashFlee" then
                    assert(ped.task[3] == 40 and ped.task[6] == 2)
                else
                    assert(ped.task[1] == "driveTrafficPhysics" and ped.task[3] == 11)
                end
            end
            TrafficRoad.stop()
            math.random = oldRandom
        end
        assert(TrafficVehicleCollision.damage(35, 5/6, "Automobile") == 5)
        assert(TrafficVehicleCollision.damage(35.01, 5/6, "Automobile") > 5)
        assert(TrafficVehicleCollision.damage(35, 0.5, "Bike") == 5)
        assert(TrafficVehicleCollision.damage(35.01, 0.5, "Bike") > 5)
        crashScenario(34, 0.01, "crashContinue")
        crashScenario(34, 0.99, "crashFlee")
        crashScenario(91, 0.25, "crashRoadRage")
        crashScenario(48, 0.01, "committedRoadRage")
        crashScenario(48, 0.99, "committedRoadRage")
        crashScenario(91, 0.99, "crashPursuit", false, true)
        graph.pedestrianDriverMasks['34'] = 8193
        crashScenario(8, 0.72, nil, true)
        graph.pedestrianDriverMasks['34'] = 1
        assert(TrafficVehicleCollision.chooseResponse(PedAIRules.profile(91), 0.25) == 1031)
        local tie = {pedType=5, name="STAT_STREET_GIRL", fear=40, temper=40}
        assert(TrafficVehicleCollision.chooseResponse(tie, 0) == 200)
        assert(TrafficVehicleCollision.chooseResponse(tie, 0.99) == 726)
        player.vehicle = nil
        PedVoice, PedAI.roadRage, chooseTrafficCivilianVehicle = oldVoice, oldRage, oldPicker
    end

    do
        player.x, players, created, packets = 0, {player}, {}, {}
        TrafficRoad.start(graph, function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local civilian = assert(created[1])
        local driver = civilian.driver
        assert(TrafficRoad.driverStyle(driver)==0 and driver.task.style==0)
        assert(not setNPCTrafficDrivingStyle(driver,7) and not setNPCTrafficDrivingStyle(player,1))
        assert(setNPCTrafficDrivingStyle(driver,1) and driver.task.style==1 and driver.task[1]=="driveTrafficRail")
        assert(setNPCTrafficDrivingStyle(driver,4) and driver.task.style==4 and driver.task[15]==0)
        assert(setNPCTrafficDrivingStyle(driver,0) and driver.task.style==0)
        local emitter = element("vehicle",civilian.x-1)
        emitter.model, emitter.vy, emitter.y, emitter.z = 596,.25,civilian.y-12,civilian.z
        civilian.vy, civilian.fx, civilian.fy = .15,0,1
        local list = getElementsByType
        function getElementsByType(kind) return kind == "vehicle" and {emitter} or players end
        local key = "npchlc_traffic:sirenYield"
        local function advance(count) for _=1,count do tick() end end
        advance(7)
        assert(not getElementData(civilian,key))
        emitter.siren = true
        setElementData(emitter,"npchlc_traffic:originalModel",244)
        advance(7)
        assert(not getElementData(civilian,key))
        setElementData(emitter,"npchlc_traffic:originalModel",207)
        advance(7)
        local action = assert(getElementData(civilian,key))
        assert(action[1]==emitter and action[2]=="right" and action[3]==2500 and not action[5]
            and action[6]==0 and action[7]==1 and action[8]>civilian.x and civilian.driver.task[1]=="driveTrafficPhysics")
        emitter.x = civilian.x+1
        advance(7)
        assert(getElementData(civilian,key)[4]==action[4] and getElementData(civilian,key)[2]=="right")
        emitter.siren = false
        advance(22)
        assert(getElementData(civilian,key)[5] and getElementData(civilian,key)[4]==action[4])
        advance(26)
        assert(not getElementData(civilian,key))
        local sequence = driver.task[2]
        for style=0,6 do
            assert(setNPCTrafficDrivingStyle(driver,style) and TrafficRoad.driverStyle(driver)==style)
            assert(driver.task[1]=="driveTrafficPhysics" and driver.task[2]==sequence and driver.task[6]==style)
        end
        assert(setNPCTrafficDrivingStyle(driver,2))
        emitter.siren, emitter.x = true, civilian.x-1
        advance(7)
        assert(getElementData(civilian,key), "ordinary avoid-cars driver ignored an approaching siren")
        civilian.driver = nil
        assert(not TrafficRoad.driverStyle(driver) and not setNPCTrafficDrivingStyle(driver,1))
        civilian.driver = driver
        getElementsByType = list
        TrafficRoad.stop()
    end

    copyRoad(174, 0, 12, 9)
    player.x, players, created, packets = 0, {player}, {}, {}
    TrafficRoad.start(graph, function() return 1 end)
    tick()
    answerProbe(assert(packets[1]))
    tick()
    local edgeCar = assert(created[1])
    edgeCar.x, edgeCar.fx, edgeCar.fy = 32, -1, 0
    player.x = 174
    local signal = 2
    function getTrafficLightState() return signal end
    tick()
    for _ = 1, 53 do tick() end
    assert(getTrafficRoadStatus().vehicles == 1 and not getTrafficRoadStatus().despawnEdgeStalled)

    signal = 0
    local leader = element("vehicle", 27)
    leader.y, leader.z = edgeCar.y, edgeCar.z
    created[2] = leader
    for _ = 1, 53 do tick() end
    assert(getTrafficRoadStatus().vehicles == 1 and not getTrafficRoadStatus().despawnEdgeStalled)
    created[2] = nil
    for _ = 1, 53 do tick() end
    assert(getTrafficRoadStatus().vehicles == 0 and getTrafficRoadStatus().despawnEdgeStalled == 1)
    assert(getElementData(edgeCar, TrafficVisibility.retiringKey))
    assert(#packets > 1)
    answerProbe(packets[#packets])
    tick()
    local replacement = assert(created[2])
    assert(getTrafficRoadStatus().vehicles == 1 and replacement.syncer == player)

    player.x = replacement.x + 145
    spectator.x, spectator.y = replacement.x, replacement.y
    players[2] = spectator
    for _ = 1, 53 do tick() end
    assert(replacement.syncer == spectator and getTrafficRoadStatus().edgeSyncerHandoffs == 1)
    assert(replacement.driver.task and not getElementData(replacement, TrafficVisibility.retiringKey))
    do
        local ped = edgeCar.driver
        local oldRetire = assert(timers[TrafficVisibility.fadeOutMs + 50])
        deliver("onVehicleStartEnter", edgeCar, spectator, 0, ped)
        assert(not getElementData(edgeCar, TrafficVisibility.retiringKey) and not ped.task)
        oldRetire()
        assert(not edgeCar.destroyed and not ped.destroyed and TrafficRoad.isManagedPed(ped))
        edgeCar.driver, ped.vehicle = nil, nil
        deliver("onVehicleExit", edgeCar, ped, 0, spectator)
        tick()
        assert(ped.adopted and ped.attacker == spectator and not edgeCar.destroyed)
        edgeCar.driver = spectator
        deliver("onVehicleEnter", edgeCar, spectator, 0, ped)
        oldRetire()
        assert(not ped.destroyed and not edgeCar.destroyed)

        local originalTask = replacement.driver.task
        deliver("onVehicleStartEnter", replacement, spectator, 0, replacement.driver)
        assert(not replacement.driver.task)
        for i=1,11 do tick() end
        assert(not replacement.driver.task) -- the thief is still beside the door
        spectator.x = replacement.x + 9
        tick()
        assert(replacement.driver.task == originalTask and not replacement.driver.adopted)
        spectator.x = replacement.x
        replacement.passenger = spectator
        deliver("onVehicleEnter", replacement, spectator, 1)
        assert(TrafficRoad.isManagedPed(replacement.driver))

        local base = replacement.driver
        replacement.capacity = 1
        local roll = math.random
        math.random = function(low) return low or 0.12499 end
        assert(TrafficPassengers.count(3,171,math.random) == 3)
        assert(TrafficPassengers.count(3,182,math.random) == 1)
        assert(TrafficPassengers.count(3,230,math.random) == 0)
        assert(TrafficPassengers.count(3,174,math.random) == 0)
        assert(TrafficPassengers.count(3,175,math.random) == 1)
        assert(TrafficPassengers.count(1,171,math.random) == 1)
        assert(TrafficPassengers.count(3,171,function() return 0.125 end) == 0)
        replacement.passenger = nil
        TrafficPassengers.spawn({vehicle=replacement,originalDriver=34,dimension=0},
            {edition="SLUS-21590 USA v1.00",fallbackDriverModelId=14},{34},0,171)
        math.random = roll
        local passenger = assert(replacement.passenger)
        passenger.syncer = spectator
        assert(TrafficRoad.isManagedPed(passenger) and PedAI.profile(passenger))
        local brain = PedAI.brain(passenger)
        local packetCount = #packets
        brain.scriptOwner = true
        TrafficPassengers.vehicleUnderFire(replacement, player, true)
        brain.scriptOwner = nil
        brain.objectives.current = {id=8, target=player}
        TrafficPassengers.vehicleUnderFire(replacement, player, true)
        now = now + 300
        TrafficPassengers.update(now)
        assert(#packets == packetCount)
        brain.objectives.current = nil
        TrafficPassengers.vehicleUnderFire(replacement, player, true)
        now = now + 199
        TrafficPassengers.vehicleUnderFire(replacement, player, true)
        TrafficPassengers.update(now)
        assert(#packets == packetCount)
        now = now + 1
        TrafficPassengers.update(now)
        assert(#packets == packetCount + 1 and packets[#packets][1][1] == passenger)
        replacement.passenger, passenger.vehicle = nil, nil
        deliver("onVehicleExit", replacement, passenger, 1)
        math.random = function(low) return low or 0.12499 end
        TrafficPassengers.spawn({vehicle=replacement,originalDriver=34,dimension=0},
            {edition="SLUS-21590 USA v1.00",fallbackDriverModelId=14},{34},0,171)
        math.random = roll
        passenger = assert(replacement.passenger)
        passenger.syncer = spectator
        replacement.driver, base.vehicle = player, nil
        deliver("onVehicleEnter",replacement,player,0,base)
        now = now + 10000
        TrafficPassengers.update(now)
        assert(packets[#packets].name == "npchlc_traffic:occupantExit")
        local observed
        local oldThreat = PedAI.passengerThreat
        PedAI.passengerThreat = function(ped, attacker) observed = ped == passenger and attacker == player end
        replacement.passenger, passenger.vehicle = nil, nil
        deliver("onVehicleExit",replacement,passenger,1,nil)
        PedAI.passengerThreat = oldThreat
        assert(observed and passenger.adopted and not passenger.destroyed)

        -- Native seat loss without an exit request or onVehicleExit notification.
        math.random = function(low) return low or 0.12499 end
        TrafficPassengers.spawn({vehicle=replacement,originalDriver=34,dimension=0},
            {edition="SLUS-21590 USA v1.00",fallbackDriverModelId=14},{34},0,171)
        math.random = roll
        passenger = assert(replacement.passenger)
        replacement.passenger,passenger.vehicle=nil,nil
        now=now+500
        TrafficPassengers.update(now)
        assert(passenger.adopted and not TrafficPassengers.isManaged(passenger))
    end
    TrafficRoad.stop()
    player.x, signal = 0, 2

    -- A wedged car in the inner area occupies the last quota slot. A real
    -- signal hold must survive the same timeout, then a green frees the slot.
    players, created, packets = {player}, {}, {}
    TrafficRoad.start(graph, function() return 1 end)
    tick()
    answerProbe(assert(packets[1]))
    tick()
    local wedged = assert(created[1])
    wedged.x, wedged.fx, wedged.fy = 32, -1, 0
    for _ = 1, 130 do tick() end
    assert(getTrafficRoadStatus().vehicles == 1 and not getTrafficRoadStatus().despawnRailStalled)
    signal = 0
    for _ = 1, 125 do tick() end
    assert(getTrafficRoadStatus().despawnRailStalled == 1 and getTrafficRoadStatus().vehicles == 0)
    timers[TrafficVisibility.fadeOutMs + 50]()
    assert(wedged.destroyed and wedged.driver.destroyed)
    answerProbe(packets[#packets])
    tick()
    assert(getTrafficRoadStatus().vehicles == 1 and #created == 2)
    TrafficRoad.stop()
    signal = 2

    do
        players, created, packets = {player}, {}, {}
        TrafficRoad.start(graph, function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local first = assert(created[1])
        local secondOwner = element("player", 500)
        players[2] = secondOwner
        client = secondOwner
        deliver("npchlc_traffic:worldProbeReady",resourceRoot)
        tick()
        answerProbe(assert(packets[#packets]))
        tick()
        local second = assert(created[2])
        assert(first["npchlc_traffic:roadOrder"] < second["npchlc_traffic:roadOrder"])
        first.x, first.fx, first.fy = 32, -1, 0
        second.x, second.y, second.z, second.fx, second.fy = 27, first.y, first.z, 1, 0
        secondOwner.x = second.x
        local award = "npchlc_traffic:headOnBlocker"
        local function report(car, other)
            deliver(award,resourceRoot,car,other)
        end
        tick() -- both stopped poses first become visible to the server here
        signal = 0
        for _=1,300 do tick() end
        client = first.syncer
        report(first,second)
        assert(not first[award], "head-on recovery at exactly 15 seconds")
        second.x = second.x-0.8
        tick()
        for _=1,10 do tick() end
        report(first,second)
        assert(not first[award], "moving the blocker failed to restart its own timer")
        for _=1,300 do tick() end
        client = second.syncer
        report(second,first)
        assert(not second[award], "both sides may try to move")
        report(first,second)
        assert(not first[award], "remote syncer assigned a maneuver")
        client = first.syncer
        local driver = second.driver
        second.driver = player
        report(first,second)
        second.driver = driver
        assert(not first[award], "recovery against a player")
        second.y = first.y+3.25
        report(first,second)
        assert(not first[award], "adjacent lane accepted as a blocker")
        second.y = first.y
        for _=1,10 do tick() end
        signal = 2
        report(first,second)
        assert(not first[award], "red signal released the queue")
        for _=1,10 do tick() end
        signal = 0
        report(first,second)
        assert(first[award]==second and not second[award])
        assert(first.driver.task[1]=="driveTrafficPhysics" and first.driver.task[6]==2)
        assert(second.driver.task[1]=="driveTrafficRail" and getTrafficRoadStatus().headOnRecoveries==1)
        for _=1,20 do tick() end
        assert(not first[award] and first.driver.task[6]==2)
        -- While the winner is beside the yielding car, the forward leader
        -- check no longer sees it. The watchdog must retain the original car.
        first.x, first.y = second.x, second.y+3.25
        for _=1,180 do tick() end
        assert(not second.destroyed and not second[TrafficVisibility.retiringKey])
        assert(not getTrafficRoadStatus().despawnRailStalled)
        TrafficRoad.stop()
        players, signal = {player}, 2
    end

    -- The car at the front of a stopped queue has lost its driver. The
    -- observer reports the actual bumper obstruction, including at a light.
    do
        players, created, packets = {player}, {}, {}
        client = player
        TrafficRoad.start(graph, function() return 1 end)
        tick()
        answerProbe(assert(packets[1]))
        tick()
        local car = assert(created[1])
        car.x, car.fx, car.fy = 32, -1, 0
        local empty = createVehicle(482, 27, car.y, car.z)
        empty.fx, empty.fy = -1, 0
        -- Rail transforms can be stationary while MTA retains a velocity.
        car.vx = -0.08
        local key = "npchlc_traffic:abandonedBlocker"
        local reverseKey = "npchlc_traffic:abandonedReverse"
        local reverseStart, reverseEnd
        local function report() deliver(key,resourceRoot,car,empty) end
        local function wait(seconds)
            for i=1,seconds*20 do
                tick()
                if i%20==0 then report() end
                if reverseStart and not reverseEnd and now-reverseStart==400 then
                    assert(timers[400], "reverse deadline was not scheduled")()
                end
                if car[reverseKey] then reverseStart=reverseStart or now
                elseif reverseStart and not reverseEnd then reverseEnd=now end
            end
        end
        client = car.syncer
        signal = 2
        report()
        wait(17)
        assert(not car[key], "abandoned vehicle released a red-light queue")
        signal = 0
        wait(8)
        assert(not car[key], "red-light time counted toward the pass")
        empty.passenger = player
        wait(32)
        assert(not car[key], "driverless car carrying a player was treated as abandoned")
        empty.passenger = nil
        empty.driver = player
        wait(1)
        assert(not car[key], "a player took the empty driver's seat")
        empty.driver = nil
        wait(10)
        assert(not car[key], "a new obstruction inherited an old timer")
        signal = 2
        wait(16)
        assert(not car[key], "a signal cycle released the vehicle during red")
        signal = 0
        wait(19)
        assert(not car[key], "the thirty-second stalled-cruise interval was shortened")
        wait(4)
        assert(car[key]==empty and car.driver.task[1]=="driveTrafficPhysics" and car.driver.task[6]==2,
            "same-direction abandoned car never released the following driver")
        wait(1)
        assert(reverseStart and reverseEnd and reverseEnd-reverseStart==400,
            "cruise recovery did not apply the 400 ms reverse")
        empty.driver = player
        wait(1)
        assert(not car[key], "takeover left permission to push an occupied car")
        TrafficRoad.stop()
        players, signal = {player}, 2
    end

    copyRoad(0, 18, 12, 9)
    players, created, packets = {}, {}, {}
    for index = 1, 100 do
        client = element("player")
        players[index] = client
        deliver("npchlc_traffic:worldProbeReady", resourceRoot)
    end
    TrafficRoad.start(graph, function() return 4 end)
    tick()
    assert(#packets == 1 and #packets[1][1][3] <= 5)
    answerProbe(packets[1])
    tick()
    assert(#created == 2 and getTrafficRoadStatus().occupied >= 1)
    TrafficRoad.stop()

    created, packets = {}, {}
    for index, observer in ipairs(players) do observer.dimension = index end
    local distributedDensity = 1
    TrafficRoad.start(graph, function() return distributedDensity end)
    for _ = 1, 140 do
        for _, car in ipairs(created) do car.x = car.x + 0.015 end
        local first = #packets + 1
        tick()
        assert(#packets - first + 1 <= 4)
        for index = first, #packets do answerProbe(packets[index]) end
    end
    assert(#created == 100 and getTrafficRoadStatus().spawned == 100)
    local served = {}
    for _, car in ipairs(created) do
        assert(not served[car.dimension])
        served[car.dimension] = true
    end

    distributedDensity = 4
    for _ = 1, 140 do
        for _, car in ipairs(created) do car.x = car.x + 0.015 end
        local first = #packets + 1
        tick()
        for index = first, #packets do answerProbe(packets[index]) end
    end
    assert(getTrafficRoadStatus().vehicles == 160 and getTrafficRoadStatus().globalCapacity > 0)
    local retained = created[1]
    local watcher = element("player", retained.x)
    watcher.y, watcher.dimension = retained.y, retained.dimension
    retained.syncer = watcher
    for _, remote in ipairs(players) do remote.x = 500 end
    players[#players + 1] = watcher
    local firstNewProbe = #packets + 1
    for _ = 1, 4 do tick() end
    assert(not retained.destroyed and getTrafficRoadStatus().despawnOutOfRange >= 157)
    assert(#packets >= firstNewProbe)
    for index = firstNewProbe, #packets do answerProbe(packets[index]) end
    tick()
    assert(#created > 160)
    players[#players] = nil
    TrafficRoad.stop()

    local observer = players[1]
    players, created, packets = {observer}, {}, {}
    TrafficRoad.start(graph, function() return 1 end)
    tick()
    local expired = packets[1]
    for _ = 1, 21 do tick() end
    answerProbe(expired)
    tick()
    assert(#created == 0 and getTrafficRoadStatus().probeTimeout == 1)
    TrafficRoad.stop()

    local highway = {population=graph.population, pedestrianDriverMasks=graph.pedestrianDriverMasks,
        roadTurnClosures={}, nodes={}, links={}}
    for index = 0, 20 do
        highway.nodes[index + 1] = {id=index, x=20 * index - 200, y=0, z=0, flags=0, spawnThreshold=15,
            rawWidth=0, firstLink=index, linkCount=index < 20 and 1 or 0,
            kind="vehicle", scene="outdoor", speedClass=0}
        if index < 20 then
            highway.links[index + 1] = {id=index, from=index, to=index + 1,
                leftLanes=1, rightLanes=0, lanes=1, speedClass=0}
        end
    end
    local bike = element("vehicle")
    function getPlayerPing() return 250 end
    local bikeSpeed = 1.2
    function getElementVelocity() return bikeSpeed, 0, 0 end
    observer.x, observer.vehicle = 0, bike
    created, packets = {}, {}
    TrafficRoad.start(highway, function() return 4 end)
    tick()
    local front = assert(packets[1])
    assert(front[1][3][1][1] >= 125 and front[1][3][1][1] <= 130)
    observer.x, now, client = 18, now + 300, observer
    bike.x = observer.x
    -- Ahead in the direction of travel, outside the camera while looking sideways.
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, front[1][1], {{{0, false}}, 0, 1})
    tick()
    assert(#created == 1 and created[1].x - observer.x >= 100)
    local secondFront = assert(packets[2])
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, secondFront[1][1], {{false}, 1, 0})
    tick()
    local rear = assert(packets[3])
    assert(rear[1][3][1][1] < observer.x)
    observer.x, now = 36, now + 300
    bike.x = observer.x
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, rear[1][1], {{{0, false}}, 1, 0})
    tick()
    assert(#created == 2 and observer.x - created[2].x < 60)
    TrafficRoad.stop()

    -- PC profile, 216 km/h for sixty seconds, fixed 250 ms probe delay.
    for index = 20, 220 do
        highway.nodes[index + 1] = {id=index, x=20 * index - 200, y=0, z=0, flags=0, spawnThreshold=15,
            rawWidth=0, firstLink=index, linkCount=index < 220 and 1 or 0,
            kind="vehicle", scene="outdoor", speedClass=0}
        if index < 220 then
            highway.links[index + 1] = {id=index, from=index, to=index + 1, leftLanes=1, rightLanes=0, lanes=1, speedClass=0}
        end
    end
    local schedule = {}
    for i = 1, 24 do schedule[i] = 12 end
    highway.roadPopulation = {fallback=schedule, cells={}, cap=12}
    observer.x, created, packets = 0, {}, {}
    bike.x = observer.x
    highway.edition = "SLUS-21590 USA v1.00"
    TrafficRoad.start(highway, function() return 1 end)
    assert(getTrafficRoadStatus().densityProfile == "zone")
    TrafficRoad.stop()
    TrafficRoad.start(highway, function() return 1 end, "scheduled")
    local nextAnswer, lastSpawn, longestGap = 1, 0, 0
    local frontCount, lastFront, frontGap = 0, 0, 0
    for step = 1, 1200 do
        observer.x = step * 3
        bike.x = observer.x
        local before = #created
        tick()
        if #created > before then
            longestGap = math.max(longestGap, step - lastSpawn)
            lastSpawn = step
            for i = before + 1, #created do
                if created[i].x > observer.x then
                    frontCount = frontCount + 1
                    frontGap = math.max(frontGap, step - lastFront)
                    lastFront = step
                end
            end
        end
        local packet = packets[nextAnswer]
        if packet and not packet.step then packet.step = step end
        if packet and step - packet.step >= 5 then
            local values = {}
            for index, point in ipairs(packet[1][3]) do values[index] = {0, point[1] > observer.x} end
            client = observer
            deliver("npchlc_traffic:worldProbeResult", resourceRoot, packet[1][1], {values, 1, 0})
            nextAnswer = nextAnswer + 1
        end
    end
    local status = getTrafficRoadStatus()
    assert(status.densityProfile == "scheduled" and status.spawned >= 60 and status.despawnOutOfRange >= 48,
        tostring(status.spawned) .. "/" .. tostring(status.despawnOutOfRange))
    assert(longestGap * 50 <= 3500 and (1200 - lastSpawn) * 50 <= 3500, tostring(longestGap * 50))
    frontGap = math.max(frontGap, 1200 - lastFront)
    assert(frontCount > #created / 2 and frontGap * 50 <= 3500)
    assert(status.observerSquareUpdates >= 140 and status.refills > 0)
    print("PC highway simulation: spawned=" .. status.spawned .. " retired=" .. status.despawnOutOfRange
        .. " maximum spawn gap=" .. longestGap * 50 .. "ms; ahead=" .. frontCount .. " maximum forward gap=" .. frontGap * 50 .. "ms")
    TrafficRoad.stop()

    highway.edition = nil
    observer.x, created, packets = 0, {}, {}
    bike.x = observer.x
    TrafficRoad.start(highway, function() return 1 end)
    tick()
    local beforeTurn = assert(packets[1])
    bikeSpeed = -1.2
    tick()
    assert(getTrafficRoadStatus().squareProbeCancelled == 1 and #packets == 2)
    answerProbe(beforeTurn)
    tick()
    assert(#created == 0)
    TrafficRoad.stop()

    observer.x, observer.vehicle, created, packets = 0, nil, {}, {}
    TrafficRoad.start(highway, function() return 1 end)
    tick()
    local oldProbe = assert(packets[1])
    client = observer
    deliver("npchlc_traffic:worldProbeResult", resourceRoot, oldProbe[1][1], {{false}, 1, 0})
    tick()
    local pendingBeforeTeleport = assert(packets[2])
    assert(TrafficWorld.getRoadView(observer) == 1)
    observer.x = 800
    tick()
    local relocated = assert(packets[3])
    assert(getTrafficRoadStatus().observerRelocations == 1 and TrafficWorld.getRoadView(observer) == nil)
    for _, point in ipairs(relocated[1][3]) do assert(math.abs(point[1] - observer.x) < 160) end
    answerProbe(pendingBeforeTeleport)
    tick()
    assert(#created == 0)
    answerProbe(relocated)
    tick()
    assert(#created >= 1 and math.abs(created[1].x - observer.x) <= 60,
        ("spawned=%s cap=%s rejected=%s ground=%s x=%s"):format(tostring(#created),
            tostring(getTrafficRoadStatus().capacity), tostring(getTrafficRoadStatus().visibilityRejected),
            tostring(getTrafficRoadStatus().groundRejected), tostring(relocated[1][3][1][1])))
    TrafficRoad.stop()

    do
        local roads={nodes={},links={},roadTurnClosures={}}
        local coords={{0,0},{40,0},{80,0},{80,40},{40,40}}
        local exits={{1},{2,4},{3},{},{3}}
        for i,pt in ipairs(coords) do
            roads.nodes[i]={id=i-1,x=pt[1],y=pt[2],z=0,kind="vehicle",flags=0,scene="outdoor",
                rawWidth=0,firstLink=#roads.links,linkCount=#exits[i]}
            for _,dest in ipairs(exits[i]) do
                roads.links[#roads.links+1]={id=#roads.links,from=i-1,to=dest,lanes=1,
                    leftLanes=0,rightLanes=1,speedClass=0}
            end
        end
        roads.population=graph.population
        TrafficRoad.start(roads,function() return 0 end)
        local car,driver,suspect=element("vehicle",10),element("ped"),element("vehicle",70)
        function getElementVelocity(v) return v.vx or 0,v.vy or 0,v.vz or 0 end
        car.fx,car.fy=1,0
        local st={vehicle=car,driver=driver,heightOffset=0,patrol={mission=2},drivingStyle=2,cruiseSpeed=25}
        local function visit(at)
            tick()
            TrafficRoad.updatePursuitRoute(st,suspect,at)
        end
        visit(100)
        assert(driver.task[1]=="driveTrafficPhysics" and st.patrol.dest==roads.links[2])
        local first=st.physicsSequence
        visit(400)
        assert(st.physicsSequence==first and getTrafficRoadStatus().policeRouteCacheHits==1)
        -- The suspect turns north. Verify the actual assigned driving window changes.
        setElementPosition(suspect,40,20,0)
        visit(700)
        assert(st.patrol.dest==roads.links[3] and st.physicsSequence>first)
        assert(st.railRoute[#st.railRoute].edge==roads.links[3])
        first=st.physicsSequence
        visit(1000)
        car.x=14
        visit(4500)
        assert(st.physicsSequence==first,"forward progress must postpone the stuck timeout")
        visit(8550)
        assert(st.physicsSequence>first,"a stationary cruiser must obtain a replacement driving task")
        -- Close the only legal turn and occupy the shared search slot with a second cruiser.
        local other={vehicle=car,driver=element("ped"),heightOffset=0,patrol={mission=4},drivingStyle=2,cruiseSpeed=25}
        tick()
        TrafficRoad.updatePursuitRoute(other,suspect,8800)
        roads.roadTurnClosures[0]={[2]=true}
        TrafficRoad.updatePursuitRoute(st,suspect,8900)
        assert(st.patrol.waiting and driver.task[1]=="stopVehicle")
        visit(9200)
        assert(not st.patrol.path and getTrafficRoadStatus().policeRouteMisses==1)
        roads.roadTurnClosures[0]=nil
        visit(9500)
        assert(driver.task[1]=="stopVehicle","failed routes must respect retry backoff")
        visit(10300)
        assert(st.patrol.path and driver.task[1]=="driveTrafficPhysics")
        -- Cross a junction by less than the six-unit fast resnap threshold.
        setElementPosition(suspect,40,2,0)
        visit(10700)
        setElementPosition(suspect,42,0,0)
        visit(11000)
        assert(st.patrol.dest==roads.links[3])
        visit(11800)
        assert(st.patrol.dest==roads.links[2],"a short turn must not leave a stationary suspect on the old road")
        -- An impact can put the cruiser outside every road corridor. Stop
        -- until a valid road is available and then resume on its new street.
        setElementPosition(car,140,100,0)
        visit(12100)
        assert(not st.patrol.path and driver.task[1]=="stopVehicle")
        setElementPosition(car,41,0,0)
        visit(13200)
        assert(st.patrol.path and st.railRoute[1].edge==roads.links[2])
        TrafficRoad.stop()
        -- A wide inbound lane meets the midpoint of a short outbound link.
        -- Preserve the legal link but give the syncer distinct turning targets.
        coords={{0,0},{40,0},{40,-23},{40,-55}}
        roads={nodes={},links={},roadTurnClosures={},population=graph.population}
        for i,pt in ipairs(coords) do
            roads.nodes[i]={id=i-1,x=pt[1],y=pt[2],z=0,kind="vehicle",flags=0,scene="outdoor",
                rawWidth=i==1 and 144 or 0,firstLink=i-1,linkCount=i<#coords and 1 or 0}
            if i<#coords then roads.links[i]={id=i-1,from=i-1,to=i,lanes=1,
                leftLanes=1,rightLanes=1,speedClass=0} end
        end
        TrafficRoad.start(roads,function() return 0 end)
        setElementPosition(car,9,-11.5,0);setElementPosition(suspect,37.5,-47,0)
        st.patrol={mission=2};visit(14600)
        local r=st.railRoute
        assert(#r==4 and r[2].edge==roads.links[1] and r[3].edge==roads.links[2])
        assert(math.abs(r[2].point[1]-34.5)<.01 and math.abs(r[2].point[2]+11.5)<.01)
        assert(math.abs(r[3].point[1]-37.5)<.01 and math.abs(r[3].point[2]+20.5)<.01)
        TrafficRoad.stop()
    end
    if streetGraph then
        do
            local function road(a,b)
                local n=streetGraph.nodes[a+1]
                for offset=1,n.linkCount do
                    local e=streetGraph.links[n.firstLink+offset]
                    if e.to==b and e.lanes>0 then return e end
                end
            end
            local path,visited=TrafficRoad.findPolicePath(streetGraph,road(1383,1381),0,road(1677,1678),true)
            assert(path and visited<=128)
            local expected={1383,1381,1382,1380,1674,1675,1677,1678}
            assert(#path==#expected-1)
            for i,item in ipairs(path) do
                assert(item.edge.from==expected[i] and item.edge.to==expected[i+1])
            end
            local block=assert(TrafficRoad.findPolicePath(streetGraph,road(389,342),0,road(336,337),true))
            local around={389,342,340,341,310,336,337}
            assert(#block==#around-1 and block[4].lane==1)
            for i,item in ipairs(block) do
                assert(item.edge.from==around[i] and item.edge.to==around[i+1])
            end
        end
        streetGraph.population = graph.population
        streetGraph.pedestrianDriverMasks = graph.pedestrianDriverMasks
        math.random = seededRandom
        math.randomseed(27005)
        local route = {212,214,213,202,201,200,199,198,197,204,205,203,206,2660,2661,2662,2659,2663,
            87,88,211,106,112,111,110,109,108,107,113,122,121,120,119,118,117,116,115,114}
        local car = element("vehicle")
        observer.vehicle, car.driver = car, observer
        function getElementVelocity(v) return v.vx or 0, v.vy or 0, 0 end
        -- The occupied car advances in sync packets. The ped snapshot lags.
        observer.x, observer.y = -655, 629
        created, packets = {}, {}
        TrafficRoad.start(streetGraph, function() return 4 end, "zone")
        local sideways=TrafficRoad.nearestPursuitRoad(-590.2,746.1,11.1,0,-1)
        assert(sideways.from==2663 and sideways.to==87)
        assert(not TrafficRoad.nearestPursuitRoad(-590.2,746.1,90,0,-1))
        local steps, answered, firstSpawn = 0, 0, nil
        for i = 1, #route - 1 do
            local a,b = streetGraph.nodes[route[i]+1], streetGraph.nodes[route[i+1]+1]
            local dx,dy = b.x-a.x,b.y-a.y
            local length = math.sqrt(dx*dx+dy*dy)
            car.vx,car.vy = dx/length*1.2,dy/length*1.2
            for j = 1, math.ceil(length/3) do
                if steps % 8 == 0 or steps == 0 then
                    local t = math.min(1,j*3/length)
                    car.x,car.y,car.z = a.x+t*dx,a.y+t*dy,a.z+t*(b.z-a.z)
                end
                steps = steps + 1
                tick()
                if #created > 0 then firstSpawn = firstSpawn or steps end
                local packet = packets[answered+1]
                if packet then
                    packet.step = packet.step or steps
                    if steps-packet.step >= 4 then
                        local values = {}
                        for k,pt in ipairs(packet[1][3]) do
                            values[k] = {pt[3], (pt[1]-car.x)*car.vx+(pt[2]-car.y)*car.vy > 0}
                        end
                        client = observer
                        deliver("npchlc_traffic:worldProbeResult", resourceRoot, packet[1][1], {values,car.vx/1.2,car.vy/1.2})
                        answered = answered + 1
                    end
                end
            end
        end
        local status = getTrafficRoadStatus()
        assert(firstSpawn and firstSpawn < 60 and #created >= 4, tostring(firstSpawn).."/"..#created)
        assert((status.observerRelocations or 0) == 0)
        print(("Moving street graph: %d ms, first spawn %d ms, %d cars"):format(steps*50,firstSpawn*50,#created))
        TrafficRoad.stop()
    end
    """)
    load(lua, RUNTIME, ["traffic_passengers_c.lua"])
    lua.execute("""
    local ped, vehicle = element("ped"), element("vehicle")
    local attempts = 0
    function isElementSyncer(npc) return npc.localOwner end
    function getPedOccupiedVehicleSeat(npc) return npc.seat end
    function setPedExitVehicle(npc) assert(npc == ped) attempts = attempts + 1 end
    ped.vehicle, ped.seat = vehicle, 1
    deliver("npchlc_traffic:occupantExit", resourceRoot, ped, vehicle, 1)
    ped.localOwner = true
    deliver("npchlc_traffic:occupantExit", resourceRoot, ped, vehicle, 1)
    ped.seat = 0
    deliver("npchlc_traffic:occupantExit", resourceRoot, ped, vehicle, 1)
    ped.vehicle, ped.seat = nil, nil
    deliver("npchlc_traffic:occupantExit", resourceRoot, ped, vehicle, 1)
    assert(attempts == 1)
    """)
    print("Boat admission, water surfaces, route continuation and takeover passed")
    print("Carjack handoff, passenger exit ownership, collision tasks and road spawning passed for 100 observers")


def check_road_injuries():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, RUNTIME, ["ped_road_injury.lua", "ped_ai_profiles.lua"])
    lua.execute("""
    local injury=PedRoadInjury
    local matrix=getElementMatrix(element("vehicle"))
    assert(injury.bikeScore(170,10,800,matrix,0,1,0)==0)
    assert(injury.bikeScore(170,125,800,matrix,0,1,0)==75)
    assert(injury.bikeScore(170,126,800,matrix,0,1,0)>75)
    assert(injury.bikeScore(205,126,800,matrix,0,1,0)<75)
    assert(injury.pedDamage(3,-1)==0 and injury.pedDamage(3.1,-1)==30)
    assert(injury.pedDamage(6,0)==0 and injury.pedDamage(6.1,0)==30)
    assert(injury.pedDamage(12,0)==30 and injury.pedDamage(12.1,0)==1000)
    assert(PedAIStats[13].damageScale==1 and PedAIStats[17].damageScale==2.5)
    local ped,bike,driver=element("ped"),element("vehicle"),element("player")
    local walk={}
    local reactions=0
    PedAI={brain=function() return {health=100,sampled=now} end,
        isScriptControlled=function() return false end,
        afterRoadFall=function(p,who) assert(p==ped and who==driver); reactions=reactions+1 end}
    TrafficAmbient={suspend=function() end}
    PedVehicleEvasion={cancel=function() end}
    TrafficRoad={contactVelocity=getElementVelocity}
    function setPedAnimation(p,block,clip) p.clip=clip end
    function isPedOnGround(p) return p.grounded end
    function setElementVelocity(p,x,y,z) p.vx,p.vy,p.vz=x,y,z end
    function getVehicleOccupant() return driver end
    function killPed(p,attacker,weapon) assert(attacker==driver and weapon==50); p.health=0 end
    function getElementModel() return 400 end
    function getElementRotation() return 0,0,0 end
    exports={server_coldata={getModelBoundingBox=function() return -1,-2,-0.5,1,2,1 end}}
    TrafficActors={isPolicePed=function() return false end}
    exports.wanted={reportWantedEvent=function(_,p,e,v) assert(p==driver and e==9 and v==ped) end}
    local hit={score=100,impulse=200,mass=800,nx=0,ny=1,vx=0.1,vy=0.25,vz=0,attacker=driver}
    injury.startBike(ped,walk,hit,true,{vehicle=bike})
    assert(ped.health==95 and math.abs(ped.vy-0.1)<0.0001 and ped.vz>=8/70 and ped.vz<=15/70 and ped.clip=="BIKE_fall_off")
    injury.startBike(ped,walk,hit,true)
    assert(ped.health==95)
    injury.update(ped,walk,now+3000)
    assert(reactions==0 and ped.clip=="BIKE_fall_off")
    ped.grounded=true
    injury.update(ped,walk,now+3050)
    assert(ped.clip=="getup_front")
    injury.update(ped,walk,now+3950)
    assert(reactions==1 and not walk.roadFall)
    bike.vy,ped.health=0.25,85
    injury.strike(ped,walk,bike,9,0)
    assert(ped.vy>0.18 and ped.clip=="FALL_front")
    timers[120]()
    assert(ped.health==70)
    injury.strike(ped,walk,bike,9,0)
    assert(ped.health==70)
    injury.strike(ped,walk,bike,15,0)
    assert(isPedDead(ped))

    -- A synced native kill can reach the server after the contact report.
    TrafficModelBindings={nativeDamageScale=.33}
    ped.health,ped.syncer=33,driver
    ped["npchlc_traffic:spawnHealth"]=33
    PedAI.brain=function() return {health=33,sampled=now} end
    function getPlayerPing() return 50 end
    local kills=0
    function killPed(p,k,w) assert(k==driver and w==50); kills=kills+1; p.health=0 end
    walk={}
    injury.strike(ped,walk,bike,9,0)
    timers[170]()
    assert(math.abs(ped.health-23.1)<0.001)
    injury.strike(ped,walk,bike,15,0)
    local pending=timers[170]
    injury.strike(ped,walk,bike,15,0)
    assert(pending==timers[170] and kills==0)
    ped.health=0
    pending()
    assert(kills==0)
    ped.health=33
    injury.strike(ped,{},bike,15,0)
    timers[170]()
    assert(kills==1 and isPedDead(ped))
    """)
    print("Rider ejection, grounded recovery, pedestrian momentum and damage boundaries passed")


def check_pedestrian_avoidance():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, HLC, ["traffic_pedestrian_vehicles_c.lua", "traffic_pedestrians_c.lua"])
    lua.execute("""
    local a, b = element("ped"), element("ped", 2)
    a.fx, a.fy, a.vx = 1, 0, 0.025
    b.fx, b.fy, b.vx = -1, 0, -0.025
    a.z, b.z = 0.7, 0.7
    function isElementStreamedIn(e) return not e.virtual end
    local vehicles = {}
    local pedestrians = {a,b}
    function getElementsWithinRange(_, _, _, radius, kind, interior, dimension)
        assert(interior == 0 and dimension == 0)
        if kind == "vehicle" then
            assert(radius == 9)
            return vehicles
        end
        assert(radius == 3.2)
        return kind == "ped" and pedestrians or {}
    end
    local wall, drop
    function processLineOfSight(x, y)
        return true, x, y, drop and math.abs(y) > 0.5 and -0.5 or 0, nil, 0, 0, 1
    end
    function isLineOfSightClear(x, y, _, tx, ty)
        if wall then return wall(x, y, tx, ty) end
        return true
    end
    function makeNPCWalkToPos(ped, x, y) ped.target = {x,y} end
    function stopNPCWalkingActions(ped) ped.target = nil end
    local forward = {"walkTrafficToPoint", 8, 0, 0.7, 0.2}
    local backward = {"walkTrafficToPoint", -8, 0, 0.7, 0.2}
    -- Stair nodes can sit below collision after integer Z import. Movement
    -- may follow the treads but must not cross a solid wall at body height.
    local savedGround,savedSight=processLineOfSight,isLineOfSightClear
    local function slope(x) return .4*x end
    function processLineOfSight(x,y,top,_,__,bottom)
        local z=slope(x)
        return top>=z and bottom<=z,x,y,z,nil,0,0,.93
    end
    function isLineOfSightClear(x,y,z,tx,ty,tz) return z>slope(x) and tz>slope(tx) end
    pedestrians={a}
    local stairs={"walkTrafficToPoint",3,0,0,0.2}
    walkNPCTrafficAroundPeds(a,stairs,{})
    assert(a.target and a.target[1]==3)
    a.x,a.z=3,2.2
    local down={"walkTrafficToPoint",0,0,-.5,.2}
    walkNPCTrafficAroundPeds(a,down,{})
    assert(a.target and a.target[1]==0)
    steerNPCFlight(a,{},-1,0)
    assert(a.target and a.target[1]<2 and a.target[2]==0)
    a.x,a.z=0,.7
    steerNPCFlight(a,{},1,0)
    assert(a.target and a.target[1]>1 and a.target[2]==0)
    function isLineOfSightClear() return false end
    steerNPCFlight(a,{},1,0)
    assert(not a.target)
    processLineOfSight,isLineOfSightClear=savedGround,savedSight
    pedestrians={a,b}
    local pa, pb = {}, {}
    walkNPCTrafficAroundPeds(a, forward, pa)
    walkNPCTrafficAroundPeds(b, backward, pb)
    assert(a.target[2] < -0.7 and b.target[2] > 0.7)
    a.x, a.y = unpack(a.target)
    b.x, b.y = unpack(b.target)
    now = now + 200
    walkNPCTrafficAroundPeds(a, forward, pa)
    assert(a.target[1] > a.x and a.target[2] < -0.7)
    a.x, b.x = 2, 0
    now = now + 200
    walkNPCTrafficAroundPeds(a, forward, pa)
    walkNPCTrafficAroundPeds(b, backward, pb)
    assert(a.target[1] == 8 and a.target[2] == 0 and b.target[1] == -8 and b.target[2] == 0)

    a.x, a.y, b.x, b.y = 0, 0, 2, 0
    wall = function(_, _, _, ty) return ty <= 0 end
    walkNPCTrafficAroundPeds(a, forward, {})
    walkNPCTrafficAroundPeds(b, backward, {})
    assert(a.target and a.target[2] < 0 and not b.target)
    wall, drop = nil, true
    b.x = 2.6
    local waiting = {}
    walkNPCTrafficAroundPeds(a, forward, waiting)
    assert(not a.target)
    a.vx, b.vx, now = 0, 0, now + 200
    walkNPCTrafficAroundPeds(a, forward, waiting)
    assert(not a.target)
    b.virtual, now = true, now + 200
    walkNPCTrafficAroundPeds(a, forward, waiting)
    assert(a.target[1] == 8 and a.target[2] == 0)

    drop, b.z, b.virtual = false, 3, false
    walkNPCTrafficAroundPeds(a, forward, {})
    assert(a.target[1] == 8 and a.target[2] == 0)
    b.z, b.fx, b.vx = 0.7, 1, 0.025
    walkNPCTrafficAroundPeds(a, forward, {})
    assert(a.target[1] == 8 and a.target[2] == 0)

    -- An actor excluded from early passing must still clear physical contact.
    setElementData(a,"npchlc_traffic:passing",{16,0})
    b.x, b.fx, b.vx = 1.4,-1,0
    walkNPCTrafficAroundPeds(a, forward, {})
    assert(a.target[1] == 8)
    b.x = 0.5
    local bystander = element("ped",0.3)
    bystander.y, bystander.z = 0.85,0.7
    pedestrians[3] = bystander
    local crowd = {}
    walkNPCTrafficFormation(a,8,0,crowd)
    assert(a.target and a.target[2] < -0.7)
    now = now + 16
    walkNPCTrafficFormation(a,8.02,0,crowd)
    assert(crowd.detour and a.target[2] < -0.7)
    -- Advance at walking speed through the chosen gap. The two stationary
    -- actors occupy the original lane and its preferred passing side.
    for frame=1,160 do
        now = now + 50
        walkNPCTrafficAroundPeds(a, forward, crowd)
        if a.target then
            local dx, dy = a.target[1]-a.x, a.target[2]-a.y
            local step = math.min(1, 0.0625/math.sqrt(dx*dx+dy*dy))
            a.x, a.y = a.x+step*dx, a.y+step*dy
        end
        assert((a.x-bystander.x)^2+(a.y-bystander.y)^2 >= 0.4^2)
    end
    assert(a.x > 7.9 and math.abs(a.y) < 0.05)
    pedestrians[3] = nil
    a.x,a.y = 0,0

    -- Both shoulders are occupied. The runner must retreat to get around the group.
    b.x,b.y = 1.25,0
    local left,right = element("ped",0.25),element("ped",0.25)
    left.y,right.y,left.z,right.z = 0.85,-0.85,0.7,0.7
    pedestrians[3],pedestrians[4] = left,right
    for _,ped in ipairs(pedestrians) do setElementData(ped,"npchlc_traffic:passing",{16,16}) end
    -- A stationary group still occupies the corridor when the walker's
    -- personality mask excludes its members from anticipatory passing.
    setElementData(a,"npchlc_traffic:passing",{16,0})
    walkNPCTrafficAroundPeds(a,forward,{})
    assert(a.target and a.target[1]<a.x)
    setElementData(a,"npchlc_traffic:passing",{16,16})
    local escape = {}
    walkNPCTrafficAroundPeds(a,forward,escape)
    assert(a.target and a.target[1]<a.x, "take the open exit on the first crowd scan")
    local minX,maxSide = 0,0
    for frame=1,400 do
        now=now+50
        walkNPCTrafficAroundPeds(a,forward,escape)
        if a.target then
            local dx,dy=a.target[1]-a.x,a.target[2]-a.y
            local step=math.min(1,0.0625/math.max(0.001,math.sqrt(dx*dx+dy*dy)))
            a.x,a.y=a.x+dx*step,a.y+dy*step
        end
        minX,maxSide=math.min(minX,a.x),math.max(maxSide,math.abs(a.y))
        for _,other in ipairs({b,left,right}) do
            assert((a.x-other.x)^2+(a.y-other.y)^2 >= 0.45^2)
        end
    end
    assert(minX<0 and maxSide>0.85 and a.x>7.9)
    a.x,a.y=0,0
    pedestrians[3],pedestrians[4]=nil,nil

    local group, routes, states = {}, {}, {}
    for i=1,4 do
        local dir = i%2==1 and 1 or -1
        local walker = element("ped", -dir*(i<3 and 1.5 or 2.6))
        walker.y,walker.z,walker.fx,walker.fy = 0,0.7,dir,0
        setElementData(walker,"npchlc_traffic:passing",{16,16})
        group[i],routes[i],states[i] = walker,{"walkTrafficToPoint",dir*(i<3 and 8 or 6),0,0.7,0.2},{}
    end
    pedestrians = group
    for frame=1,260 do
        now = now + 50
        for i,walker in ipairs(group) do walkNPCTrafficAroundPeds(walker,routes[i],states[i]) end
        for _,walker in ipairs(group) do
            walker.vx,walker.vy=0,0
            if walker.target then
                local dx,dy=walker.target[1]-walker.x,walker.target[2]-walker.y
                local length=math.sqrt(dx*dx+dy*dy)
                if length>0.001 then
                    walker.fx,walker.fy=dx/length,dy/length
                    local sx,sy=walker.fx*math.min(length,0.0625),walker.fy*math.min(length,0.0625)
                    local clear=true
                    for _,peer in ipairs(group) do
                        if peer~=walker and (walker.x+sx-peer.x)^2+(walker.y+sy-peer.y)^2<0.45^2 then clear=false end
                    end
                    if clear then
                        walker.x,walker.y=walker.x+sx,walker.y+sy
                        walker.vx,walker.vy=sx/2.5,sy/2.5
                    end
                end
            end
        end
    end
    for i,walker in ipairs(group) do assert(math.abs(walker.x-routes[i][2])<0.2) end
    pedestrians = {a,b}

    b.virtual = true
    -- Cross a finite wall by walking around its end, then resume the original goal.
    wall = function(x,y,tx,ty)
        if x==tx or (x-3)*(tx-3)>0 then return true end
        local t=(3-x)/(tx-x)
        return math.abs(y+t*(ty-y))>2.2
    end
    local around, crossed = {}, false
    for frame=1,360 do
        now=now+50
        walkNPCTrafficAroundPeds(a,forward,around)
        if a.target then
            local dx,dy=a.target[1]-a.x,a.target[2]-a.y
            local step=math.min(1,0.075/math.max(0.001,math.sqrt(dx*dx+dy*dy)))
            local tx,ty=a.x+step*dx,a.y+step*dy
            assert(wall(a.x,a.y,tx,ty))
            if a.x<3 and tx>=3 then crossed=true end
            a.x,a.y=tx,ty
        end
    end
    assert(crossed and a.x>7.9 and math.abs(a.y)<0.05)
    a.x,a.y,wall=0,0,nil
    local car = element("vehicle", 4)
    car.fx, car.fy, car.z = 1, 0, 0.7
    vehicles[1] = car
    function isElementFrozen(e) return e.frozen end
    function getElementBoundingBox() return -0.9, -2, -0.6, 0.9, 2, 0.8 end
    local detour = {}
    walkNPCTrafficAroundPeds(a, forward, detour)
    assert(detour.action == "TASK_COMPLEX_WALK_ROUND_CAR" and math.abs(a.target[2]) > 1)
    for i = 1, #detour.carDetour.points do
        a.x, a.y = unpack(a.target)
        now = now + 250
        walkNPCTrafficAroundPeds(a, forward, detour)
    end
    assert(detour.action == "TASK_SIMPLE_GO_TO_POINT" and a.target[1] == 8 and a.target[2] == 0)

    -- A driver just outside the body can walk directly out of its safety margin.
    assert(not findNPCTrafficVehicleInPath(a,car.x,1.05,a.z,0,1,3))
    assert(findNPCTrafficVehicleInPath(a,car.x,1.05,a.z,0,-1,3)==car)
    a.x, a.y, car.vx = 0, 0, 0.1
    local moving = {}
    walkNPCTrafficAroundPeds(a, forward, moving)
    assert(moving.action == "Yield to moving vehicle" and not a.target)
    car.z, now = 5, now + 250
    walkNPCTrafficAroundPeds(a, forward, moving)
    assert(a.target[1] == 8 and a.target[2] == 0)
    """)
    print("Pedestrian head-on avoidance, vehicle detours, yielding and route resumption passed")


def check_pedestrian_crossing():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, HLC, ["task_progress.lua", "valid_tasks_s.lua", "tasks_c.lua"])
    lua.execute("""
    local ped = element("ped")
    local signal = 0
    function getTrafficLightState() return signal end
    function stopNPCWalkingActions(e) e.pace = "wait" end
    function walkNPCTrafficAroundPeds(e, task, _, pace)
        e.pace, e.goal = pace or "walk", task[2]
    end
    local crossing = normalizeNPCTask({"walkTrafficCrossing", 12, 0, 0, 0.45, 0, 0})
    assert(crossing and not normalizeNPCTask({"walkTrafficCrossing", 0, 0, 0, 0.45, 0, 0}))
    local state = {}
    performTask.walkTrafficCrossing(ped, crossing, 0, state)
    assert(ped.pace == "wait" and state.action == "TASK_SIMPLE_STAND_STILL")
    signal = 2
    performTask.walkTrafficCrossing(ped, crossing, 0, state)
    assert(ped.pace == "walk" and ped.goal == 12)
    signal, ped.x = 0, 3
    performTask.walkTrafficCrossing(ped, crossing, 0, state)
    assert(ped.pace == "run" and ped.goal == 12)
    performTask.walkTrafficCrossing(ped, crossing, 0, {})
    assert(ped.pace == "run" and ped.goal == 12)
    signal = 2
    performTask.walkTrafficCrossing(ped, crossing, 0, state)
    assert(ped.pace == "run" and ped.goal == 12)
    """)
    print("Signalized pedestrian crossing waits at the curb and runs after entry, including syncer handoff")


def check_pedestrian_jaw(assets, expected_count):
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
    ped = element("ped")
    head = {{1,0,0}, {0,1,0}, {0,0,1}, {1,2,3}}
    jaw = {{-0.3547,0.935,0}, {-0.935,-0.3547,0}, {0,0,1}, {0,0,0}}
    function Matrix() return {} end
    function Vector3(...) return {...} end
    function getElementModel() return 7 end
    function isElementOnScreen() return true end
    function getCameraMatrix() return 0, 0, 0 end
    function getElementBoneMatrix(_, bone) return bone == 5 and head or jaw end
    function setElementBoneMatrix(_, bone, matrix)
        assert(bone == 8)
        output = matrix
    end
    """)
    load(lua, Path(__file__).parent / "vcs_model", ["jaw_c.lua"])
    pivot_for = lua.globals().getTrafficJawBindPivot
    pivots = [pivot_for(data) for name, data in assets.items() if name.endswith(".dff")]
    assert len(pivots) == expected_count and all(pivot is not None for pivot in pivots)
    lua.globals().pivot = pivots[0]
    lua.execute("""
    trackTrafficJaw(ped, 7, pivot)
    deliver("onClientPedsProcessed", root)
    assert(output.right[3] == -1 and output.forward[2] > 0.999 and output.up[1] > 0.999)
    assert(output.position[1] == 1 + pivot[1] and output.position[3] == 3 + pivot[3])
    local rest = output.forward
    jaw[1], jaw[2] = {-0.935,-0.3547,0}, {0.3547,-0.935,0}
    deliver("onClientPedsProcessed", root)
    assert(math.abs(output.forward[1] - rest[1]) > 0.5 and output.position[3] == 3 + pivot[3])
    jaw = {output.right, output.forward, output.up, output.position}
    output = nil
    deliver("onClientPedsProcessed", root)
    assert(not output)
    deliver("onClientElementStreamOut", ped)
    jaw[3] = {0,0,1}
    deliver("onClientPedsProcessed", root)
    assert(not output)
    """)
    print(f"All {expected_count} mounted pedestrian rigs supply jaw pivots and preserve the facial rotation delta")


def check_jetski_controller():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, VCS_VEHICLE, ["controllers/vehicle.lua", "controllers/boat.lua",
                            "controllers/jetski_control.lua", "controllers/jetski_control_c.lua", "controllers/jetski_fall.lua"])
    lua.execute("""
    localPlayer=element("player")
    local hull=element("vehicle")
    hull["vcs_vehicle:originalModel"]=233
    hull.vx,hull.vy,hull.vz=0.3,0.4,0.01
    local control=CJetSki:New(hull)
    control:ProcessControlInputs(0,1,-1,0,false,1)
    assert(math.abs(control.throttle+0.03)<0.00001 and math.abs(control.steer+0.2)<0.00001)
    control:ProcessControlInputs(1,1,0,0,false,1)
    assert(control.throttle==0 and control.brake==0)
    hull.driver,localPlayer.vehicle=localPlayer,hull
    local bar,spinX,spinY
    local updates=0
    local water, engine=0.3,true
    function getWaterLevel() return water end
    function getVehicleEngineState() return engine end
    function getVehicleHandling() return {engineAcceleration=0} end
    function getGravity() return 0.008 end
    function getVehicleController(v) return v.driver end
    function getPedControlState() return false end
    function getVehicleComponents() return {handlebars=true} end
    function getVehicleComponentRotation() return 2,3,4 end
    function setVehicleComponentRotation(_,_,x,y,z) assert(x==2 and y==3) bar=z end
    function getAnalogControlState(name) return (name=="vehicle_left" or name=="steer_forward") and 1 or 0 end
    function isControlEnabled() return true end
    function setVehicleHandling(v,k,values) assert(v==hull and k=="centerOfMass"); centre=values end
    function isElementInWater() return true end
    function getElementAngularVelocity() return spinX or 0,spinY or 0,0.05 end
    function setElementAngularVelocity(_,x,y,z) spinX,spinY=x,y; assert(math.abs(z)<1) end
    function setElementVelocity(v,x,y,z) v.vx,v.vy,v.vz=x,y,z; updates=(updates or 0)+1 end
    deliver("onClientPreRender",root,20)
    assert(spinX and spinY and math.abs(spinX)<1 and math.abs(spinY)<1)
    assert(math.abs(bar-5.6)<0.0001 and hull.vx>0 and hull.vx<0.3 and hull.vy>0)
    local m = getElementMatrix(hull)
    control.throttle,control.steer=1,0
    hull.vx,hull.vy,hull.vz=0,0,0
    water=1
    control:ProcessThrust(m,1)
    assert(hull.vx==0 and math.abs(hull.vy-0.01024)<0.00001 and hull.vz==0)
    local afterThrust=updates
    water=-5
    control:ProcessThrust(m,1)
    water=1
    m[3][3]=-1
    control:ProcessThrust(m,1)
    m[3][3]=1
    engine=false
    control:ProcessThrust(m,1)
    assert(updates==afterThrust)
    hull.driver=element("ped")
    deliver("onClientPreRender",root,20)
    assert(bar==4 and updates==afterThrust)
    deliver("onClientPreRender",root,20)
    assert(updates==afterThrust)
    local banked={{0.8,0,0.6},{0,1,0},{-0.6,0,0.8},{0,0,0}}
    hull.vx,hull.vy,hull.vz=0.25,0.4,0
    control.immersion,control.nativeImmersion=0.3,0.3
    control:ApplyWaterResistance(banked,1)
    assert(hull.vz==0 and hull.vx<0.25, "banked sideslip injected a second heave impulse")
    local matrix = getElementMatrix(hull)
    assert(CJetSki.ImpactScore(320,1000,matrix,0,1,0,0.65) < 100)
    assert(CJetSki.ImpactScore(321,1000,matrix,0,1,0,0.65) > 100)
    assert(CJetSki.ImpactScore(321,1000,matrix,1,0,0,0.65) < 100)
    """)
    print("Standalone CJetSki player balance, handlebar, hull resistance and driver handoff passed")


def check_jetski_rider():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.globals().riderClips = lua.table_from(json.loads((VCS_VEHICLE/"data/jetski_rider.json").read_bytes()), recursive=True)
    lua.execute("""
    localPlayer=element("player")
    ski=element("vehicle")
    ski["npchlc_traffic:originalModel"]=233
    function fileOpen() return {} end
    function fileGetSize() return 1 end
    function fileRead() return "" end
    function fileClose() end
    function fromJSON() return riderClips end
    function getElementsByType() return {ski} end
    function getVehicleOccupants(v) return v.seats end
    function getVehicleComponents() return {} end
    function isElementOnScreen() return true end
    function isElementStreamedIn() return true end
    function getPedAnimation(p) return p.block end
    function setPedAnimation(p) p.block=nil end
    function getElementAngularVelocity() return 0,0,0 end
    function getPedAnalogControlState(p,control) return p[control] or 0 end
    function bindKey(name,state,fn) assert(name=="enter_exit" and state=="down") boardKey=fn end
    function addCommandHandler(name,fn) assert(name=="boardjetski" or name=="boardboat") boardCommand=fn end
    function isControlEnabled() return true end
    function isChatBoxInputActive() return false end
    function isConsoleActive() return false end
    function isMTAWindowActive() return false end
    function isVehicleLocked() return false end
    function isVehicleBlown() return false end
    function getVehicleType() return "Boat" end
    function isElementInWater() return true end
    function getPedContactElement() return false end
    function getElementsWithinRange() return {ski} end
    function triggerServerEvent(name,origin,vehicle)
        assert(name=="vcs_vehicle:boardWatercraft" and origin==resourceRoot and vehicle==ski)
        requested=true
    end
    function setElementBoneQuaternion(p,bone,x,y,z,w)
        assert(math.abs(x*x+y*y+z*z+w*w-1)<0.00001)
        p.pose[bone]={x,y,z,w}
    end
    function updateElementRpHAnim(p) p.updates=(p.updates or 0)+1 end
    """)
    load(lua, VCS_VEHICLE, ["controllers/vehicle.lua","controllers/boat.lua","controllers/jetski_control.lua","controllers/jetski_control_c.lua","boarding.lua","boarding_c.lua","controllers/jetski_rider_c.lua"])
    lua.execute("""
    local driver=element("ped")
    driver.pose,localPlayer.pose={},{}
    ski.seats,ski.driver,driver.vehicle={[0]=driver},driver,ski
    deliver("onClientResourceStart",resourceRoot)
    function isConsoleActive() return true end
    boardKey()
    assert(not requested)
    boardCommand()
    assert(requested)
    function isConsoleActive() return false end
    requested=false
    boardKey()
    assert(requested)
    local function frame() now=now+50 deliver("onClientPedsProcessed",root) end
    frame()
    assert(driver.updates==1 and driver.pose[21] and driver.pose[53])
    local shoulder=driver.pose[32][1]
    driver.vehicle_left=1
    frame()
    assert(math.abs(shoulder-driver.pose[32][1])>0.001)
    deliver("onClientVehicleExit",ski,driver)
    ski.seats,ski.driver,driver.vehicle={[0]=localPlayer},localPlayer,nil
    deliver("onClientVehicleStartEnter",ski,localPlayer,0,0)
    frame()
    local approach=localPlayer.pose[32][1]
    localPlayer.vehicle,localPlayer.block=ski,"SWIM"
    deliver("onClientVehicleEnter",ski,localPlayer,0)
    assert(not localPlayer.block and localPlayer.pose[32][1]==shoulder and approach~=shoulder)
    deliver("vcs_vehicle:jetSkiMounted",ski,localPlayer,false)
    frame()
    local mount=localPlayer.pose[32][1]
    now=now+800
    frame()
    assert(localPlayer.pose[32][1]==mount)
    localPlayer.vehicle,localPlayer.block=nil,"SWIM"
    deliver("vcs_vehicle:jetSkiMounted",ski,localPlayer,false)
    frame()
    assert(localPlayer.block=="SWIM")
    localPlayer.vehicle=ski
    frame()
    assert(not localPlayer.block and localPlayer.pose[32][1]==shoulder)
    now=now+1200
    frame()
    assert(localPlayer.pose[32][1]==shoulder and localPlayer.vehicle==ski and driver.updates==2)
    localPlayer.vehicle_left=1
    for i=1,30 do frame() end
    local left=localPlayer.pose[32][1]
    localPlayer.vehicle_left,localPlayer.vehicle_right=0,1
    local previous=localPlayer.pose[32]
    for i=1,30 do
        frame()
        local current=localPlayer.pose[32]
        local dot=0
        for k=1,4 do dot=dot+previous[k]*current[k] end
        assert(math.abs(dot)>0.95, "shoulder snapped during full-lock reversal")
        previous=current
    end
    assert(math.abs(left-previous[1])>0.001)
    deliver("onClientVehicleStartExit",ski,localPlayer,0,1)
    deliver("onClientVehicleExit",ski,localPlayer)
    localPlayer.vehicle=nil
    frame()
    local during=localPlayer.updates
    now=now+1200
    frame()
    assert(localPlayer.updates==during)
    ski["npchlc_traffic:originalModel"]=248
    localPlayer.y,localPlayer.z=-5,1
    function isElementInWater() return false end
    function getPedContactElement() return ski end
    local accepted=true
    function setPedEnterVehicle(ped,vehicle,passenger)
        assert(ped==localPlayer and vehicle==ski and passenger==false)
        return accepted
    end
    ski.driver=nil
    requested=false
    boardKey()
    timers[100]()
    assert(not requested, "an accepted native enter must retain control")
    deliver("onClientVehicleStartEnter",ski,localPlayer,0,0)
    now=now+900
    timers[900]()
    assert(not requested)
    accepted=false
    boardKey()
    timers[100]()
    assert(requested)
    """)
    print("JETSKI water boarding, seated swim reset, steering reversal and dismount passed")


def check_visibility():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_visibility_c.lua"])
    lua.execute("""
    localPlayer = element("player")
    local car, stock = element("vehicle"), element("vehicle")
    local cameraX = 0
    function getCameraMatrix() return cameraX, 0, 0 end
    function isElementStreamedIn(e) return e.streamed ~= false end
    function getElementAlpha(e) return e.alpha or 255 end
    function setElementAlpha(e, value) e.alpha = value end
    local function frame(ms)
        now = now + ms
        deliver("onClientPreRender", root)
    end
    local profile, retiring = TrafficVisibility.profileKey, TrafficVisibility.retiringKey
    car[profile], car.alpha = "road", 200
    deliver("onClientElementStreamIn", car)
    deliver("onClientElementStreamIn", stock)
    assert(car.alpha == 0 and stock.alpha == nil)
    frame(250)
    assert(car.alpha == 100)
    frame(249)
    assert(car.alpha == 200) -- Integer alpha rounds close to the end of the ramp.
    frame(1)
    assert(car.alpha == 200)
    car.x = 147
    frame(33)
    assert(car.alpha == 100)
    car.x = 160
    frame(33)
    assert(car.alpha == 0)
    car.x = 0
    frame(33)
    car[retiring] = true
    deliver("onClientElementDataChange", car, retiring)
    frame(175)
    assert(car.alpha == 100)
    frame(175)
    assert(car.alpha == 0)
    car[profile] = false
    deliver("onClientElementDataChange", car, profile)
    assert(car.alpha == 200)

    local ped, fastVehicle = element("ped", 65), element("vehicle")
    ped[profile] = "road"
    deliver("onClientElementStreamIn", ped)
    frame(500)
    assert(ped.alpha == 255)
    ped[profile] = "pedestrian"
    deliver("onClientElementDataChange", ped, profile)
    frame(1)
    assert(ped.alpha == 0)
    localPlayer.vehicle, fastVehicle.vx = fastVehicle, 0.6
    ped.x = 90
    frame(33)
    assert(ped.alpha == 255)
    ped.x = 97.5
    frame(33)
    assert(ped.alpha == 0)
    localPlayer.vehicle = nil

    resourceRoot[TrafficVisibility.roadRangeKey] = 130
    deliver("onClientElementDataChange", resourceRoot, TrafficVisibility.roadRangeKey)
    car[profile], car[retiring], car.x = "road", false, 130
    deliver("onClientElementStreamIn", car)
    frame(500)
    assert(car.alpha == 0)
    deliver("onClientElementStreamOut", car)

    car[profile], car[retiring], car.x = "aircraft", false, 0
    deliver("onClientElementStreamIn", car)
    frame(500)
    cameraX = 245
    frame(33)
    assert(car.alpha == 0)
    deliver("onClientElementStreamOut", car)
    assert(car.alpha == 200)
    cameraX = 0
    deliver("onClientElementStreamIn", car)
    assert(car.alpha == 0)
    frame(500)
    assert(car.alpha == 200)
    """)
    load(lua,VCS_VEHICLE,["controllers/vehicle.lua","controllers/plane.lua","controllers/plane_c.lua"])
    lua.execute("""function getThisResource() return resourceRoot end
    exports={vcs_vehicle=setmetatable({},{__index=function(_,k) return function(_,...) return _G[k](...) end end})}""")
    load(lua, RUNTIME, ["traffic_aircraft_c.lua"])
    lua.execute("""
    local slotKey = "npchlc_traffic:flightSlot"
    local vehicle = element("vehicle")
    vehicle[slotKey] = 0
    vehicle[TrafficVisibility.profileKey] = "aircraft"
    vehicle["npchlc_traffic:modelProvider"] = "vcs_model"
    vehicle.alpha = 255
    local px, pz, far, proxy = 0,450,1000,nil
    function getElementsByType() return {vehicle} end
    function getCameraMatrix() return px,0,pz end
    function isVehicleBlown(v) return v.blown end
    function getFarClipDistance() return far end
    function getVehiclesLODDistance() return 400,500 end
    function getResourceFromName() return {} end
    function getResourceState() return "running" end
    function getResourceExportedFunctions() return {"getTrafficFixedWingLOD"} end
    function call(_,name,id,tier)
        assert(name=="getTrafficFixedWingLOD" and id==280)
        return ({hi=652,lo=653,vlo=654})[tier]
    end
    function engineSetModelLODDistance() return true end
    function createObject(id)
        assert(id>=652 and id<=654 and not isElement(proxy))
        proxy=element("object")
        proxy.model=id
        return proxy
    end
    function destroyElement(e) e.destroyed=true end
    function setElementCollisionsEnabled() return true end
    function setElementStreamable(e,streamable) e.streamable=streamable return true end
    function isElementStreamable(e) return e.streamable~=false end
    function setElementMatrix(e, matrix) e.x,e.y,e.z = unpack(matrix[4]) return true end
    function isElementOnScreen() return true end
    local route={kind="fixedWing",instances=1,phaseStepMs=174762,clockPeriodMs=524288,originalModelId=280,
        clockDuration=1,length=50,takeoffDistance=10,landingDistance=30,
        points={{distance=0,x=0,y=0,z=0,flags=0},{distance=20,x=20,y=0,z=0,flags=0}},
        motionEnd={kind=0,distance=0}, motionSegments={{kind=1,start=0,["end"]=1,distance=0,velocity=1,acceleration=0}}}
    function CPlane.SampleFlight(_,clock,slot)
        assert(slot==0)
        return {x=0,y=0,z=450,aheadX=0,aheadY=30,rx=1,ry=0,rz=0,fx=0,fy=1,fz=0,ux=0,uy=0,uz=1}
    end
    deliver("onClientElementDataChange",vehicle,slotKey)
    deliver("onClientElementStreamIn",vehicle)
    deliver("npchlc_traffic:flightRoute",resourceRoot,route,0)
    local function frame()
        now=now+120
        deliver("onClientPreRender",root)
        return TrafficAircraftClient.debugSlots().slots[1].representation
    end
    assert(frame()=="near-model" and vehicle.alpha==0 and isElement(proxy) and proxy.model==652)
    vehicle.streamed=false
    assert(frame()=="near-model" and vehicle.alpha==0 and proxy.model==652)
    px=60
    assert(frame()=="middle-model" and vehicle.alpha==0 and proxy.model==653)
    px=150
    assert(frame()=="distant" and proxy.model==654)
    px,pz=0,0 -- ground observer below the high-altitude segment
    assert(frame()=="distant" and vehicle.alpha==0 and isElement(proxy) and proxy.z==450)
    vehicle.streamed=true
    px,pz=1,450
    assert(frame()=="near-model" and vehicle.alpha==0 and isElement(proxy) and proxy.model==652)
    far,pz=400,0
    assert(frame()=="none" and vehicle.alpha==0 and not isElement(proxy))
    far,localPlayer.dimension=1000,1
    assert(frame()=="none")
    localPlayer.dimension,pz=0,450
    assert(frame()=="near-model")
    resourceRoot["npchlc_traffic:flightHaltClock"]=760
    deliver("onClientElementDataChange",resourceRoot,"npchlc_traffic:flightHaltClock")
    assert(frame()=="none" and TrafficAircraftClient.debugSlots().phaseMs==760)
    resourceRoot["npchlc_traffic:flightHaltClock"]=false
    deliver("onClientElementDataChange",resourceRoot,"npchlc_traffic:flightHaltClock")
    assert(frame()=="near-model")
    """)
    print("Traffic visibility fade timing, pre-stream-out, retirement and restoration passed")


def check_debug_overlay():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
    localPlayer = element("player")
    commands, lines, rectangles, texts = {}, {}, {}, {}
    exports={npc_hlc={}}
    function isMainMenuActive() return false end
    function isPlayerMapVisible() return false end
    CWidescreenSupport={playerHud=function() return 0,1,1 end}
    function setTimer(callback,interval) timers[interval]=callback return callback end
    function guiGetScreenSize() return 1280,720 end
    function getElementsByType() return {} end
    function isElementStreamedIn() return true end
    function isElementOnScreen() return true end
    function getPedBonePosition() return 30,20,1 end
    function getPedArmor(ped) return ped.armor end
    function dxGetTextWidth(text) return #text*5 end
    function dxDrawRectangle(x,y,w,h,color) rectangles[#rectangles+1]={w,color,x,y} end
    function dxDrawLine3D(...) lines[#lines+1]={...} end
    function tocolor(r,g,b) return r*65536+g*256+b end
    function addCommandHandler(name, callback) commands[name] = callback end
    function removeEventHandler(name) events[name] = nil end
    function killTimer() end
    function dxDrawText(text,x,y,right,bottom,color) texts[text]={y=y,color=color} end
    function dxDrawLine(x, y, u, v) lines[#lines + 1] = {x,y,u,v} end
    function getCameraMatrix() return 0,0,0, 1,0,0 end
    function getScreenFromWorldPosition(x, y)
        if x < 0.24 then return false end
        return x * 10, y * 10
    end
    function triggerServerEvent(...) request = {...} end
    """)
    load(lua, TRAFFIC.parent / "[hud]" / "frontend", ["hud_c.lua"])
    lua.execute("exports.frontend={drawDebugLabels=function(_,labels) return drawDebugLabels(labels) end}")
    load(lua, RUNTIME, ["npc_debug_range.lua","npc_debug_c.lua","traffic_debug_c.lua"])
    lua.execute("""
    commands.trafficdebug("trafficdebug", "road")
    assert(request[3] == "road")
    deliver("npchlc_traffic:debugPaths", resourceRoot, "road", {}, {{-5,0,0, 5,0,0, "vehicle", false, 0}})
    deliver("onClientRender", root)
    assert(#lines == 1 and math.abs(lines[1][1] - 2.5) < 0.01 and lines[1][3] == 50)
    lines = {}
    deliver("npchlc_traffic:debugPaths", resourceRoot, "road", {}, {}, {{{1,0,0}, {2,1,0}, {3,2,0}}})
    deliver("onClientRender", root)
    assert(#lines == 2 and lines[1][3] == lines[2][1] and lines[1][4] == lines[2][2])
    local ped=element("ped")
    ped.health,ped.armor=25,50
    local row={ped,7,75,30,"fight",false,"killPed",localPlayer,50}
    row[13]="CIVMALE"
    function exports.npc_hlc:getNPCDebugExecution() return {"killPed",false,1,2,3,4,5,6} end
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row})
    lines={}
    TrafficNPCDebug.draw()
    assert(#rectangles==6 and rectangles[3][1]==25 and rectangles[3][2]==16777215)
    assert(rectangles[6][1]==25 and rectangles[6][2]==0xAF191E and #lines>=4)
    assert(texts["Hot temper 75"] and texts["fight > killPed"])
    assert(texts["[CIVMALE]"].y<texts["Hot temper 75"].y)
    assert(texts["Hot temper 75"].y<texts["fight > killPed"].y)
    assert(texts["fight > killPed"].y<texts["Sync: synchronized"].y)
    assert(texts["Sync: synchronized"].color==0x75E988)
    function exports.npc_hlc:getNPCDebugExecution() return {"killPed",false,false,false,false,false,false,false,true} end
    TrafficNPCDebug.draw()
    assert(texts["Sync: waiting for server"].color==0xFF5050)
    -- Two heads at the same projection must keep the same bar coordinates,
    -- even when one has armor and the other has a longer task label.
    local neighbor=element("ped")
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row,{neighbor,1,20,40,"pedestrian",false,"walkTrafficToPoint",false,100}})
    rectangles={}
    TrafficNPCDebug.draw()
    local bars=0
    for _,rect in ipairs(rectangles) do
        if rect[2]==0xAF191E then
            assert(rect[3]==275 and rect[4]==194)
            bars=bars+1
        end
    end
    assert(bars==2)
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row})
    rectangles,lines={},{}
    ped.armor=0
    function exports.npc_hlc:getNPCDebugExecution() return false end
    TrafficNPCDebug.draw()
    assert(#rectangles==3 and #lines==0)
    function tocolor(r,g,b,a) return a end
    ped.x=23.5
    rectangles={}
    TrafficNPCDebug.draw()
    assert(#rectangles==3 and rectangles[3][2]==128)
    ped.x=35
    rectangles={}
    TrafficNPCDebug.draw()
    assert(#rectangles==0 and #lines==0)
    localPlayer.x=35
    TrafficNPCDebug.draw()
    assert(#rectangles==3)
    ped.dimension=1
    rectangles={}
    TrafficNPCDebug.draw()
    assert(#rectangles==0)

    ped.dimension=0
    local car=element("vehicle")
    car.driver,ped.vehicle=ped,car
    row[2],row[8],row[11],row[12]=19,element("player"),0,car
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row})
    texts={};TrafficNPCDebug.draw()
    assert(texts["Driving style 0 - Stop for cars"])
    assert(texts["Driving style 0 - Stop for cars"].y>texts["Hot temper 75"].y)
    assert(texts["Driving style 0 - Stop for cars"].y<texts["fight > killPed"].y)
    assert(texts["Sync: waiting for executor"])
    local remoteSample={"killPed",false,false,false,false,false,false,false,true}
    deliver("npchlc_traffic:npcDebugDetails",resourceRoot,1,{{ped,19,remoteSample}})
    texts={};TrafficNPCDebug.draw()
    assert(texts["Sync: waiting for server"])
    now=now+651
    texts={};TrafficNPCDebug.draw()
    assert(texts["Sync: waiting for executor"])
    row[5],row[6]="Road rage","Approach driver door"
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row})
    remoteSample[2],remoteSample[9]="TASK_SIMPLE_STAND_STILL",false
    deliver("npchlc_traffic:npcDebugDetails",resourceRoot,1,{{ped,19,remoteSample}})
    texts={};TrafficNPCDebug.draw()
    assert(texts["Road rage > killPed > Approach driver door"] and texts["Sync: synchronized"])
    row[7],row[14]=false,"pending"
    texts={};TrafficNPCDebug.draw()
    assert(texts["Sync: waiting for executor"] and not texts["Sync: idle"])
    row[14]="active"
    texts={};TrafficNPCDebug.draw()
    assert(texts["Sync: native executor"])
    row[14]="blocked"
    texts={};TrafficNPCDebug.draw()
    assert(texts["Sync: waiting for server retry"])
    row[14]=false
    deliver("npchlc_traffic:npcDebugRevision",resourceRoot,1,ped,20,false,localPlayer,2,car)
    texts={};TrafficNPCDebug.draw()
    assert(texts["Driving style 2 - Avoid cars"] and not texts["Driving style 0 - Stop for cars"])
    car.driver=localPlayer
    texts={};TrafficNPCDebug.draw()
    assert(not texts["Driving style 2 - Avoid cars"]) -- passenger with an old driver snapshot
    ped.vehicle=nil
    texts={};TrafficNPCDebug.draw()
    assert(not texts["Driving style 2 - Avoid cars"])
    local replacement=element("vehicle")
    replacement.driver,ped.vehicle=ped,replacement
    texts={};TrafficNPCDebug.draw()
    assert(not texts["Driving style 2 - Avoid cars"]) -- now driving a different car
    commands.trafficdebug("trafficdebug")
    assert(not events.onClientRender)
    deliver("npchlc_traffic:npcDebugRows",resourceRoot,1,{row})
    texts={};TrafficNPCDebug.draw()
    assert(not next(texts))
    """)
    server = LuaRuntime()
    server.execute(SERVER_MOCK)
    server.execute("""
    viewer,owner,ped=element("player"),element("player"),element("ped")
    exports={npc_hlc={getNPCDebugAssignment=function() return "walkTrafficToPoint",7,owner end}}
    local brain={profile={pedType=4,temper=75,fear=30},objectives={}}
    PedAITypes={[4]={name="CIVMALE"}}
    PedAI={brain=function() return brain end}
    PedActivity={debugTask=function() return "seat","approach" end}
    function isPedInVehicle() return false end
    car=element("vehicle")
    ped.vehicle,car.driver=car,ped
    local style=0
    TrafficRoad={driverStyle=function(driver) assert(driver==ped and driver.vehicle.driver==driver);return style end}
    """)
    load(server,RUNTIME,["npc_debug_range.lua","npc_debug_s.lua"])
    server.execute("""
    client=viewer
    deliver("npchlc_traffic:npcDebugWatch",resourceRoot,1,{ped})
    assert(#packets==2 and packets[1].owner==viewer and packets[2].owner==owner)
    local row=packets[1][1][2][1]
    assert(row[1]==ped and row[2]==7 and row[3]==75 and row[5]=="seat" and row[6]=="approach")
    assert(row[11]==0 and row[12]==car and row[13]=="CIVMALE")
    local report={{ped,7,{"walkTrafficToPoint","detour",1,2,3,4,5,6,true}}}
    client=element("player")
    deliver("npchlc_traffic:npcDebugReport",resourceRoot,viewer,1,report)
    assert(#packets==2)
    client=owner
    deliver("npchlc_traffic:npcDebugReport",resourceRoot,viewer,1,report)
    assert(#packets==3 and packets[3].owner==viewer and packets[3][1][2][1][3][6]==4)
    assert(packets[3][1][2][1][3][9]==true)
    car.driver=owner
    deliver("npc_hlc:debugAssignmentChanged",ped,8,false,false)
    assert(#packets==4 and packets[4].name=="npchlc_traffic:npcDebugRevision")
    assert(packets[4][1][6]==false and packets[4][1][7]==false)
    deliver("npchlc_traffic:npcDebugReport",resourceRoot,viewer,1,report)
    assert(#packets==4)
    client=viewer
    deliver("npchlc_traffic:npcDebugWatch",resourceRoot,1,false)
    deliver("npc_hlc:debugAssignmentChanged",ped,9,false,false)
    assert(#packets==4)
    now=now+300
    car.driver=ped
    exports.npc_hlc.getNPCDebugAssignment=function() return "driveTrafficRail",10,owner,false,5 end
    deliver("npchlc_traffic:npcDebugWatch",resourceRoot,2,{ped})
    local scripted=packets[5][1][2][1]
    assert(scripted[11]==5 and scripted[12]==car)
    deliver("npc_hlc:debugAssignmentChanged",ped,11,"driveTrafficPhysics",owner,6)
    assert(packets[7][1][6]==6 and packets[7][1][7]==car)
    local event={kind="roadRage",maneuver="Pull driver out",extractId=17,extractOwner=owner}
    local brain=PedAI.brain(ped)
    brain.event,ped.syncer=event,owner
    local function nativeStatus()
        now=now+250
        local index=#packets+1
        deliver("npchlc_traffic:npcDebugWatch",resourceRoot,2,{ped})
        return packets[index][1][2][1][14]
    end
    assert(nativeStatus()=="pending")
    event.extractStatus="active"
    assert(nativeStatus()=="active")
    ped.syncer=viewer
    assert(nativeStatus()=="pending")
    ped.syncer,event.extractStatus=owner,"blocked"
    assert(nativeStatus()=="blocked")
    """)
    print("Traffic overlay, HP/armor bars, routing targets, owner-only relay and revision cleanup passed")


def available_port(kind):
    with socket.socket(socket.AF_INET, kind) as listener:
        listener.bind(("127.0.0.1", 0))
        return listener.getsockname()[1]


def check_native(disc, vcs_pc):
    data, manifest = assemble(disc, vcs_pc)
    with TemporaryDirectory(prefix="mta-vcs-traffic-") as directory:
        stage = Path(directory)
        destination = stage / "mods/deathmatch"
        resources = destination / "resources"
        resources.mkdir(parents=True)
        copy2(ROOT / "MTA Server64.exe", stage)
        copytree(ROOT / "x64", stage / "x64")
        for name in ("acl.xml", "vehiclecolors.conf"):
            copy2(ROOT / "mods/deathmatch" / name, destination)
        for name in ("server_coldata", "npc_hlc", "npchlc_traffic"):
            copytree(
                TRAFFIC / name, resources / name,
                ignore=lambda _directory, names: {"generated"} & set(names),
            )
        copytree(ROOT / "mods/deathmatch/resources/[model]/vcs_model", resources / "vcs_model")
        for category, name in (("[module]", "wanted"), ("[module]", "wasted"), ("[hud]", "frontend"),
                               ("[vcs]", "font"), ("[vendor]", "dgs")):
            copytree(ROOT / "mods/deathmatch/resources" / category / name, resources / name)
        copytree(VCS_VEHICLE, resources / "vcs_vehicle")
        generated = resources / "npchlc_traffic/paths/generated"
        generated.mkdir(parents=True)
        (generated / "vcs_traffic.json").write_bytes(encode_json(data))
        (generated / "vcs_traffic.manifest.json").write_bytes(encode_json(manifest))

        traffic_resource = resources / "npchlc_traffic"
        (traffic_resource / "native_medic_probe.lua").write_text(NATIVE_MEDIC_PROBE, encoding="utf-8")
        meta = ET.parse(traffic_resource / "meta.xml")
        ET.SubElement(meta.getroot(), "script", src="native_medic_probe.lua", type="server")
        ET.SubElement(meta.getroot(), "export", function="verifyNativeMedicHandoff", type="server")
        meta.write(traffic_resource / "meta.xml", encoding="utf-8")

        probe = resources / "traffic_native_probe"
        probe.mkdir()
        (probe / "meta.xml").write_text('<meta><script src="probe.lua" type="server"/></meta>', encoding="utf-8")
        (probe / "probe.lua").write_text(NATIVE_PROBE, encoding="utf-8")
        acl = ET.parse(destination / "acl.xml")
        probe_group = ET.SubElement(acl.getroot(), "group", name="FlightProviderTest")
        ET.SubElement(probe_group, "object", name="resource.traffic_native_probe")
        ET.SubElement(probe_group, "acl", name="FlightProviderTest")
        probe_rights = ET.SubElement(acl.getroot(), "acl", name="FlightProviderTest")
        for right in ("startResource", "stopResource", "restartResource"):
            ET.SubElement(probe_rights, "right", name=f"function.{right}", access="true")
        acl.write(destination / "acl.xml", encoding="utf-8")
        config = ET.parse(ROOT / "mods/deathmatch/mtaserver.conf")
        root = config.getroot()
        for node in root.findall("resource"):
            root.remove(node)
        settings = {
            "servername": "VCS traffic native regression", "serverip": "127.0.0.1",
            "serverport": available_port(socket.SOCK_DGRAM), "httpport": available_port(socket.SOCK_STREAM),
            "httpdownloadurl": "", "maxplayers": "100", "ase": "0", "scriptdebugloglevel": "3",
        }
        for key, value in settings.items():
            node = root.find(key)
            if node is None:
                node = ET.SubElement(root, key)
            node.text = str(value)
        for name in ("vcs_vehicle", "traffic_native_probe"):
            ET.SubElement(root, "resource", src=name, startup="1", protected="0")
        config.write(destination / "mtaserver.conf", encoding="utf-8")

        server_log = destination / "logs/server.log"
        script_log = destination / "logs/scripts.log"
        with subprocess.Popen(
            [str(stage / "MTA Server64.exe")], cwd=stage, creationflags=subprocess.CREATE_NO_WINDOW,
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ) as server:
            try:
                deadline = perf_counter() + 90
                while perf_counter() < deadline and server.poll() is None:
                    if server_log.exists():
                        for line in server_log.read_text(errors="replace").splitlines():
                            if "TRAFFIC_NATIVE_PASS" in line:
                                print(line)
                                return
                    sleep(0.2)
                for path in (server_log, script_log):
                    if path.exists():
                        print(path.read_text(errors="replace"))
                raise RuntimeError("Isolated MTA server did not pass the traffic probe.")
            finally:
                if server.poll() is None:
                    server.terminate()
                    server.wait(timeout=10)


def check_race_overtaking():
    lua = LuaRuntime()
    load(lua, HLC, ["traffic_physics.lua"])
    lua.execute("""
        -- Look through short links on a rounded corner before reaching it.
        local function lane(id,x,y,bearing)
            return {id,0,x,y,0,math.cos(bearing),math.sin(bearing),0,0}
        end
        assert(getNPCRaceSteeringInput(-0.125,0.2,0.5)==-0.5)
        assert(getNPCRaceSteeringInput(2,0.7,0.5)==1)
        local road={[5]={lane(1,0,0,0),lane(2,6,0,0),lane(3,12,1,.3),lane(4,18,4,.6)}}
        assert(getNPCRaceWindowSpeed(road,1,8,60)<30)
        assert(getNPCRaceWindowSpeed(road,1,250,60)==60)
        road[5][3],road[5][4]=lane(3,12,0,0),lane(4,18,0,0)
        assert(getNPCRaceWindowSpeed(road,1,8,60)==60)
        assert(getNPCRaceSteeringSpeed(60,18,1.4)<15)
        local own={vehicle={},x=0,y=0,z=0,fx=1,fy=0,length=2,width=1}
        local lead={vehicle={},x=20,y=0,z=0,fx=1,fy=0,vx=8,vy=0,length=2,width=1}
        assert(getNPCRaceLeadRange(0)==12 and getNPCRaceLeadRange(30)==24)
        local fx,fy,cap=getNPCRaceOvertake(own,{lead},1,0,20,24,function() return true end)
        assert(math.abs(math.atan2(fy,fx)-2.2/20)<.0001 and cap==math.huge)
        -- Already matching a slower leader above the standing-start threshold.
        lead.x,lead.vx=12,10
        assert(not findAngleToWeaveThroughTraffic(own,{lead},10,0))
        fx,fy,cap=getNPCRaceOvertake(own,{lead},1,0,10,24,function() return true end)
        assert(fx>0 and fy>0 and cap==math.huge)
        fx,fy,cap=getNPCRaceOvertake(own,{lead},1,0,10,24,function() return false end)
        assert(fx==1 and fy==0 and cap<24)
        assert(not getNPCRaceOvertake(own,{lead},1,0,10,10,function() return true end))
        lead.vx=26
        assert(not getNPCRaceOvertake(own,{lead},1,0,10,24,function() return true end))
        lead.vx=8
        lead.x=9
        fx,fy,cap=getNPCRaceOvertake(own,{lead},1,0,20,24,function() return false end)
        assert(fx>0 and fy==0 and cap<24)
        -- The streamed window starts ten metres ahead of this bike.
        local lane={5033,0,-1712,-314,13,-1,0,1,0,carriageway={-1704.5,-317,-1720.5,-317,-5,5,0}}
        local road={[5]={lane}}
        assert(isNPCRacePassingLane(road,-1694,-315.6,-.8,-.6,5,.4))
        assert(not isNPCRacePassingLane(road,-1694,-315.6,-.6,.8,6,.4))
        assert(isNPCRacePassingLane(road,-1712,-311,-.6,-.8,5,.4))
        assert(not isNPCRacePassingLane(road,-1712,-311,-.6,.8,5,.4))
        -- Brake at a closed queue, then steer out from a standstill.
        local bike={x=0,y=0,z=0,fx=1,fy=0,length=1,width=.4}
        lead.x,lead.vx=6,0
        local _,offset,limit=getNPCRaceOvertake(bike,{lead},1,0,0,18,function() return false end)
        assert(offset==0 and limit<18)
        _,offset,limit=getNPCRaceOvertake(bike,{lead},1,0,0,18,function(_,y,_,dy) return dy<0 or y<0 and dy==0 end)
        assert(offset<0 and limit==math.huge)
        -- There is space to pass and straighten, but holding the initial
        -- weave angle for the whole scan would hit the opposite curb.
        local queue={}
        for i=1,3 do
            queue[i]={x=6+6*i,y=0,z=0,fx=1,fy=0,width=1.2,length=2.5,vx=1,vy=0}
        end
        local function narrowRoad(_,y,_,dy,span)
            local finish=y+dy*span
            return math.min(y,finish)>=-.5 and math.max(y,finish)<=3.4
        end
        fx,fy,cap=getNPCRaceOvertake(bike,queue,1,0,12,22,narrowRoad)
        assert(fx>0 and fy>0 and cap==math.huge)
        -- A bike on the open flank can keep its heading through the link.
        -- Snapping to this waypoint's lane centre cuts back across the sedan.
        local link={1,0,15,2.5,0,1,0,0,0,carriageway={0,0,30,0,-5,5,0}}
        local sedan={x=-1,y=2,z=0,fx=1,fy=0,width=1,length=2,vx=1,vy=0}
        bike.y=-1
        local bearing=math.atan2(3.5,15)
        fx,fy,cap=getNPCRaceOvertake(bike,{sedan},math.cos(bearing),math.sin(bearing),
            10,22,function() return true end,nil,{[5]={link}},1)
        assert(fx>.99 and math.abs(fy)<.001 and cap==math.huge)
        -- reVC projects the obstacle box onto its bearing from the driver.
        local heading=-1.42906271
        own.fx,own.fy=math.cos(heading),math.sin(heading)
        local crossing={x=6.848816,y=-16.904208,z=0,fx=-.62875594,fy=-.77760270,
            width=1.687471,length=1.591361,vx=-4.085873,vy=-5.053131}
        assert(not findAngleToWeaveThroughTraffic(own,{crossing},24.100263,-1.47676872))
        local bearing=math.atan2(crossing.y,crossing.x)
        local angle=findAngleToWeaveThroughTraffic(own,{crossing},24.100263,bearing)
        local clearance=math.abs(crossing.length*math.sin(bearing-heading))
            +math.abs(crossing.width*math.cos(bearing-heading))+1.2*own.width
        assert(math.abs(angle-(bearing-clearance/math.sqrt(crossing.x^2+crossing.y^2)))<.0001)
    """)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disc", type=Path, help="Path to the local unpacked SLUS-21590 PS2 disc")
    parser.add_argument("--vcs-pc-dir", type=Path, help="Also validate the local VCS PC Edition road population")
    parser.add_argument("--native", action="store_true", help="Run the isolated Windows MTA server with 600 NPC tasks")
    args = parser.parse_args()
    if args.native and (not args.disc or not hasattr(subprocess, "CREATE_NO_WINDOW")):
        parser.error("--native requires Windows, the bundled MTA server, and --disc")
    check_hlc()
    check_race_overtaking()
    check_reaction_latency()
    check_ambient()
    check_car_service()
    check_ped_services()
    check_vehicle_pursuit()
    check_gang_weapons(args.disc)
    check_road(args.disc, args.vcs_pc_dir)
    check_road_injuries()
    check_pedestrian_avoidance()
    check_pedestrian_crossing()
    check_jetski_controller()
    check_jetski_rider()
    check_visibility()
    check_debug_overlay()
    if args.disc:
        with TemporaryDirectory() as folder:
            engine = Path(folder) / "jetski_engine.wav"
            extract_jetski_engine(args.disc, engine)
            assert engine.read_bytes() == (VCS_VEHICLE / "audio/jetski_engine.wav").read_bytes()
        check_airtrain_bounds()
        check_assets(args.disc, args.vcs_pc_dir)
    if args.native:
        check_native(args.disc, args.vcs_pc_dir)


if __name__ == "__main__":
    main()
