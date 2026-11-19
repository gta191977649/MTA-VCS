"""Regression checks for the VCS graph, fixed-wing math and NPCHLC ownership."""

import argparse
import math
from pathlib import Path
from shutil import copy2, copytree
import socket
from statistics import quantiles
import subprocess
from tempfile import TemporaryDirectory
from time import perf_counter, sleep
import xml.etree.ElementTree as ET

from lupa.lua51 import LuaRuntime

from import_vcs_traffic import ROAD_MAP, assemble, encode_json
from vcs_road_collision import ground_height, lane_centres, road_surfaces
from vcs_vehicle_ground import contact_geometry, read_archive

ROOT = Path(__file__).resolve().parents[1]
TRAFFIC = ROOT / "mods/deathmatch/resources/[traffic]"
HLC = TRAFFIC / "npc_hlc"
RUNTIME = TRAFFIC / "npchlc_traffic"

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
function getElementHealth(e) return e.health end
function isPedDead(e) return e.health == 0 end
function getPedOccupiedVehicle(e) return e.vehicle end
function isPedInVehicle(e) return e.vehicle ~= nil end
function getVehicleOccupant(e) return e.driver end
function getElementSyncer(e) return e.syncer end
function setElementSyncer(e, owner) e.syncer = owner return true end
function getElementDimension(e) return e.dimension or 0 end
function getElementInterior(e) return e.interior or 0 end
function getElementPosition(e) return e.x, e.y, e.z end
function getElementMatrix(e)
    local fx, fy = e.fx or 0, e.fy or 1
    return {{fy,-fx,0}, {fx,fy,0}, {0,0,1}, {e.x,e.y,e.z}}
end
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
    assert(setNPCTask(npc, {"walkToPos", 12, 0, 0, 0.01}))
end)
assert(setNPCTask(npc, {"walkToPos", 0.1, 0, 0, 0.01}))
tick()
assert(all_npcs[npc].tasks[1][2] == 12 and #completed == 3)
deliver("onElementDestroy", npc)
assert(not all_npcs[npc])
"""

CLIENT_OWNERSHIP = """
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
deliver("onClientPreRender", root)
assert(issued == 3)
vehicle.x, vehicle.z = 10, 4
deliver("onClientPreRender", root)
assert(issued == 3 and released == 3 and stopped == 0)

npc.vehicle = nil
npc.x, npc.z = 0, 0
local first = {"walkTrafficToPoint", 2, 0, 0, 0.25}
local nextWalk = {"walkTrafficToPoint", 4, 0, 0, 0.25}
local targets = {}
function makeNPCWalkToPos(_, x) targets[#targets + 1] = x end
deliver("npc_hlc:control", resourceRoot, npc, 5, first, npc, nextWalk)
deliver("onClientPreRender", root)
npc.x = 2
deliver("onClientPreRender", root)
npc.x = 3
deliver("onClientPreRender", root)
deliver("npc_hlc:control", resourceRoot, npc, 6, nextWalk, npc)
deliver("onClientPreRender", root)
assert(table.concat(targets, ",") == "2,4,4,4" and released == 3 and stopped == 0)
deliver("onClientPedDamage", npc, false, 49, 3, 5)
deliver("onClientPreRender", root)
assert(#targets == 4 and released == 4)
now = now + 350
deliver("onClientPreRender", root)
assert(#targets == 5)
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

NATIVE_PROBE = """
local traffic = exports.npchlc_traffic
local hlc = exports.npc_hlc
local loadTimer
loadTimer = setTimer(function()
    local status, counts, failure = traffic:getTrafficStatus()
    if status == "loading" then return end
    killTimer(loadTimer)
    assert(status == "ready", tostring(failure))
    assert(counts.peds == 5308 and counts.cars == 2701 and counts.boats == 378 and counts.links == 17652)
    assert(traffic:getTrafficRoadStatus().range == 160, "configured traffic sync range was not applied")
    assert(traffic:sampleTrafficFlight("fake-plane", 0, 2))
    assert(traffic:getTrafficDynamicRoute("police-helicopter").spawnAttemptMs == 15000)
    -- Stock MTA plane is a fixture for the matrix and lifecycle APIs only.
    assert(not traffic:bindTrafficFixedWingModel(411))
    assert(traffic:bindTrafficFixedWingModel(577))
    local slots = {}
    for _, vehicle in ipairs(getElementsByType("vehicle")) do
        local slot = getElementData(vehicle, "npchlc_traffic:flightSlot", false)
        if slot ~= false then
            assert(not slots[slot] and isElementFrozen(vehicle))
            local matrix = getElementMatrix(vehicle)
            assert(matrix and matrix[4][3] > 0)
            slots[slot] = vehicle
        end
    end
    assert(slots[0] and slots[1] and slots[2])
    assert(traffic:bindTrafficFixedWingModel(false))
    for _, vehicle in pairs(slots) do assert(not isElement(vehicle)) end

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
            local stats = hlc:getNPCSchedulerStats()
            local moved = getElementPosition(actors[600])
            assert(moved > 50 and stats.activeTasks == 600 and stats.samples >= 100)
            assert(stats.p95Ms <= 3 and stats.p99Ms <= 8,
                ("scheduler p95=%d ms, p99=%d ms, exhausted=%d"):format(
                    stats.p95Ms, stats.p99Ms, stats.budgetExhaustions))
            outputServerLog(("TRAFFIC_NATIVE_PASS tasks=%d samples=%d p95=%dms p99=%dms exhausted=%d")
                :format(stats.activeTasks, stats.samples, stats.p95Ms, stats.p99Ms, stats.budgetExhaustions))
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
    route[5][1][7] = 2
    assert(not normalizeNPCTask(route))
    route[5][1][7] = 1
    moving.x, moving.y = 0, 7
    function getTrafficLightState() return 2 end
    assert(not isNPCTaskComplete(nil, moving, route, true))
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
    assert(not getNPCTrafficPhysicsRejoin(route, moving))
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
    function processLineOfSight(x, y, z, ex, ey)
        if ey < y and rearBlocker then return true, x, y - 0.5, z, rearBlocker end
        if ey > y and frontBlocked and (not rightClear or ex - x <= 0.2) then
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
    render(100)
    render(1000)
    assert(inputs.brake_reverse == 0 and inputs.handbrake)
    lead.vy = 0.08
    render(100)
    assert(inputs.accelerate > 0 and not inputs.handbrake)
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

    local long = {"driveTrafficPhysics", 4, 12, {0,0,0}, {{3,0,0,1000,0,0,1,0,1}}}
    frontBlocked, vehicle.y, vehicle.vy = false, 0, 0.2
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
    """)
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


def check_assets(disc, vcs_pc):
    data, manifest = assemble(disc, vcs_pc)
    data_again, _ = assemble(disc, vcs_pc)
    model_resource = TRAFFIC.parent / "[model]" / "vcs_model"
    vehicle_archive = model_resource / "vehicle.img"
    if vehicle_archive.is_file():
        assets = read_archive(vehicle_archive)
        for name, expected_axle in (("mule", 4.306), ("boxvil", 4.1525), ("benson", 3.9038),
                                    ("yankee", 5.3177), ("sanchez", 1.6396), ("pcj600", 1.6038)):
            front, rear = contact_geometry(assets[name + ".dff"])
            assert math.isclose(front[0] - rear[0], expected_axle, abs_tol=0.001)
            assert 0.25 < front[2] < 0.6 and 0.25 < rear[2] < 0.6
    ped_archive = model_resource / "ped.img"
    if ped_archive.is_file():
        check_pedestrian_jaw(read_archive(ped_archive))
    assert encode_json(data) == encode_json(data_again)
    assert manifest["counts"]["nodes"] == {"boat": 378, "pedestrian": 5308, "vehicle": 2701}
    assert manifest["counts"]["directedLinks"] == {"boat": 762, "pedestrian": 11298, "vehicle": 5592}
    lua = LuaRuntime()
    load(lua, RUNTIME, ["traffic_flight.lua", "traffic_lights.lua", "traffic_population.lua", "traffic_road_population.lua", "traffic_graph.lua"])
    graph = lua.globals().TrafficGraph.build(lua.table_from(data, recursive=True), lua.eval("function() end"))
    lua.execute("exports = {npc_hlc = {}}")
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
    assert(TrafficFlight.sample(native.ambientFlight, 0, 0))
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
    sample = lua.globals().TrafficFlight.sample
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


def check_ambient():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute('exports = {npc_hlc = {}}')
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_visibility_s.lua", "traffic_model_bindings.lua", "traffic_ambient.lua"])
    lua.execute("""
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
        if method == "getTrafficPedestrianContext" then
            return {cap=1, streamingDistanceScale=1, groupChance=0, policeChance=0}
        end
        if method == "probeTrafficPedestrianSpawn" then
            probeCount = probeCount + 1
            if endpoints and type(probe) == "table" then
                for _, node in ipairs(endpoints) do
                    if node.id ~= blockedEndpoint and math.abs(node.x - x) > 1 then
                        return {groundZ=0, visible=true, clear=true, destination=node.id}
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
    exports.npc_hlc.addNPCTask = function(_, ped, task) ped.task = task return true end
    TrafficPopulation = {sample=function() return {originalModelId=34} end}
    TrafficGraph = {pedestrianAnchor=function() return false end}
    local graph = {population={}, nodes={from,to}, links={edge}, pedestrianCells={[30]={[25]={from,to}}}}
    assert(registerTrafficPedestrianWorld())
    assert(bindTrafficPedestrianModel(34, 7))
    ambient.start(graph, function() return 1 end)
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
    assert(created[1].task[1] == "walkTrafficToPoint" and created[1].task[2] == to.x)
    local ped = created[1]
    local grounded, anchorX = false, nil
    function isPedOnGround() return grounded end
    exports.npc_hlc.clearNPCTasks = function(_, actor) actor.task = nil end
    TrafficGraph.pedestrianAnchor = function(_, x) anchorX = x return false end
    ped.vx = 0.15
    deliver("onPedDamage", ped, 20)
    assert(not ped.task and ped.vx == 0.15)
    ped.x = 42
    now = now + 1000
    tick()
    assert(not anchorX and not ped.task)
    grounded = true
    for _ = 1, 4 do tick() end
    assert(anchorX == 42)
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


def check_road(disc=None, vcs_pc=None):
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute('exports = {npc_hlc = {}, server_coldata = {}}')
    load(lua, HLC, ["traffic_rail.lua", "traffic_physics.lua"])
    load(lua, RUNTIME, ["traffic_visibility.lua", "traffic_visibility_s.lua", "traffic_model_bindings.lua",
                        "traffic_graph.lua", "traffic_world.lua", "traffic_road_population.lua", "traffic_road.lua"])
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
    function isVehicleBlown() return false end
    function isElementInWater() return false end
    function setElementFrozen(e, value) e.frozen = value return true end
    function getElementRotation(e) return 0,0,e.rotation end
    function setElementVelocity(e, x, y, z) e.vx, e.vy, e.vz = x, y, z end
    function getElementAngularVelocity(e) return 0.01, -0.03, e.spin or 0 end
    function setElementAngularVelocity(e, x, y, z) assert(x == 0.01 and y == -0.03) e.spin = z end
    function getVehicleHandling(e) return {mass=e.mass or 1000, turnMass=2500} end
    function getVehicleOccupants(vehicle) return {[0]=vehicle.driver, vehicle.passenger} end
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
    function warpPedIntoVehicle(ped, vehicle)
        vehicle.driver = ped
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
    exports.npc_hlc.clearNPCTasks = function(_, ped) ped.task = nil end
    exports.npc_hlc.getNPCTrafficPhysicsRejoin = function(_, ...) return getNPCTrafficPhysicsRejoin(...) end
    function chooseTrafficCivilianVehicle() return 400, 171, 0 end
    TrafficAmbient = {getPedestrianModel=function(id) return id == 34 and 7 or id == 14 and 23 end}
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
    TrafficRoad.start(graph, function(kind) assert(kind == "cars") return 1 end)
    client = player
    deliver("npchlc_traffic:worldProbeReady", resourceRoot)
    tick()
    assert(#packets == 1 and #created == 0)
    assert(packets[1][1][2] == "road" and math.abs(packets[1][1][3][1][1] - 40) < 0.1)
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
    vehicle.passenger = player
    TrafficRoad.stop()
    assert(driver.destroyed and not vehicle.destroyed and created[2].destroyed and getTrafficRoadStatus().vehicles == 0)
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
    assert(TrafficWorld.reachable(player, first, 4, destinations)[1] == nil)
    assert(TrafficWorld.reachable(player, second, 4, destinations)[1] == 5)

    local function answerProbe(packet)
        local values = {}
        for index in ipairs(packet[1][3]) do values[index] = {0, false} end
        client = packet.owner
        deliver("npchlc_traffic:worldProbeResult", resourceRoot, packet[1][1], {values, 0, 1})
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
    wedged.destroyed = true -- native fade completes before replacement admission
    answerProbe(packets[#packets])
    tick()
    assert(getTrafficRoadStatus().vehicles == 1 and #created == 2)
    TrafficRoad.stop()
    signal = 2

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

    if streetGraph then
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
    print("Collision task handoff and road spawning passed for 100 co-located and 100 distributed observers")


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
    function getElementsWithinRange(_, _, _, radius, kind, interior, dimension)
        assert(interior == 0 and dimension == 0)
        if kind == "vehicle" then
            assert(radius == 9)
            return vehicles
        end
        assert(radius == 3.2)
        return kind == "ped" and {a,b} or {}
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

    b.virtual = true
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

    a.x, a.y, car.vx = 0, 0, 0.1
    local moving = {}
    walkNPCTrafficAroundPeds(a, forward, moving)
    assert(moving.action == "TASK_SIMPLE_STAND_STILL" and not a.target)
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


def check_pedestrian_jaw(assets):
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
    assert len(pivots) == 75 and all(pivot is not None for pivot in pivots)
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
    print("All 75 mounted pedestrian rigs supply jaw pivots and preserve the facial rotation delta")


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
    ped[profile] = "pedestrian"
    deliver("onClientElementStreamIn", ped)
    frame(500)
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
    print("Traffic visibility fade timing, pre-stream-out, retirement and restoration passed")


def check_debug_overlay():
    lua = LuaRuntime()
    lua.execute(SERVER_MOCK)
    lua.execute("""
    localPlayer = element("player")
    commands, lines = {}, {}
    function tocolor() return 0 end
    function addCommandHandler(name, callback) commands[name] = callback end
    function removeEventHandler(name) events[name] = nil end
    function killTimer() end
    function dxDrawText() end
    function dxDrawLine(x, y, u, v) lines[#lines + 1] = {x,y,u,v} end
    function getCameraMatrix() return 0,0,0, 1,0,0 end
    function getScreenFromWorldPosition(x, y)
        if x < 0.24 then return false end
        return x * 10, y * 10
    end
    function triggerServerEvent(...) request = {...} end
    """)
    load(lua, RUNTIME, ["traffic_debug_c.lua"])
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
    commands.trafficdebug("trafficdebug")
    assert(not events.onClientRender)
    """)
    print("Traffic debug filters, screen-space line clipping and toggle passed")


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
        generated = resources / "npchlc_traffic/paths/generated"
        generated.mkdir(parents=True)
        (generated / "vcs_traffic.json").write_bytes(encode_json(data))
        (generated / "vcs_traffic.manifest.json").write_bytes(encode_json(manifest))

        probe = resources / "traffic_native_probe"
        probe.mkdir()
        (probe / "meta.xml").write_text('<meta><script src="probe.lua" type="server"/></meta>', encoding="utf-8")
        (probe / "probe.lua").write_text(NATIVE_PROBE, encoding="utf-8")
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
        for name in ("server_coldata", "npc_hlc", "npchlc_traffic", "traffic_native_probe"):
            ET.SubElement(root, "resource", src=name, startup="1", protected="0")
        config.write(destination / "mtaserver.conf", encoding="utf-8")

        server_log = destination / "logs/server.log"
        script_log = destination / "logs/scripts.log"
        with subprocess.Popen(
            [str(stage / "MTA Server64.exe")], cwd=stage, creationflags=subprocess.CREATE_NO_WINDOW,
            stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        ) as server:
            try:
                deadline = perf_counter() + 30
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disc", type=Path, help="Path to the local unpacked SLUS-21590 PS2 disc")
    parser.add_argument("--vcs-pc-dir", type=Path, help="Also validate the local VCS PC Edition road population")
    parser.add_argument("--native", action="store_true", help="Run the isolated Windows MTA server with 600 NPC tasks")
    args = parser.parse_args()
    if args.native and (not args.disc or not hasattr(subprocess, "CREATE_NO_WINDOW")):
        parser.error("--native requires Windows, the bundled MTA server, and --disc")
    check_hlc()
    check_ambient()
    check_road(args.disc, args.vcs_pc_dir)
    check_pedestrian_avoidance()
    check_pedestrian_crossing()
    check_visibility()
    check_debug_overlay()
    if args.disc:
        check_assets(args.disc, args.vcs_pc_dir)
    if args.native:
        check_native(args.disc, args.vcs_pc_dir)


if __name__ == "__main__":
    main()
