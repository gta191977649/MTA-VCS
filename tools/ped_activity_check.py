"""Exercise the activity controller with deterministic MTA event and movement stubs."""

import struct
from pathlib import Path

from lupa.lua51 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def check():
    lua = LuaRuntime()
    lua.execute((ROOT / "ped_activity_sites.lua").read_text())
    contents = (ROOT / "ped_activity/activities.ifp").read_bytes()
    assert contents[:4] == b"ANP3" and struct.unpack_from("<I", contents, 4)[0] == len(contents) - 8
    assert struct.unpack_from("<I", contents, 32)[0] == 19
    for clip in lua.globals().PedActivityClips:
        assert clip.encode().ljust(24, b"\0") in contents
    roots = {}
    cursor = 36
    for _ in range(19):
        name, count, _, _ = struct.unpack_from("<24s3i", contents, cursor)
        cursor += 36
        for _ in range(count):
            _, kind, frames, tag = struct.unpack_from("<24s3i", contents, cursor)
            cursor += 36
            stride = 16 if kind == 4 else 10
            if tag == 0 and kind == 4:
                roots[name.rstrip(b"\0")] = tuple(struct.unpack_from("<3h", contents, cursor + 10 + k * stride)
                                                  for k in (0, frames - 1))
            cursor += frames * stride
    assert cursor == len(contents)
    assert roots[b"seat_down"][1] == roots[b"seat_idle"][0] == roots[b"seat_idle"][1] == roots[b"seat_up"][0]
    assert roots[b"seat_up"][1] == roots[b"seat_down"][0]
    assert roots[b"beach_lower"] == roots[b"sunbathe_stand"][::-1]
    assert roots[b"beach_recline"] == roots[b"sunbathe_to_sit"][::-1]
    assert roots[b"sunbathe_stand"][1][:2] == (0, 0)
    assert len(lua.globals().PedActivitySites) > 100
    lua.execute("""
        tick, requests, replies = 0, {}, {}
        root, resourceRoot, owner = {}, {}, {x=0,y=0,z=1}
        function addEvent() end
        function addEventHandler(name, _, handler) replies[name] = handler end
        function getTickCount() return tick end
        function isElement(ped) return type(ped) == "table" end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function isPedDead(ped) return ped.dead end
        function isPedInVehicle() return false end
        function getTime() return 12 end
        function getRainLevel() return rain or 0 end
        function getElementSyncer(ped) return ped.syncer or owner end
        function getElementPosition(ped) return ped.x,ped.y,ped.z end
        function setElementPosition() error("Activity controller relocated a pedestrian") end
        function getElementRotation(ped) return 0,0,ped.angle or 180 end
        function setElementRotation(ped,_,_,angle) assert(ped.ackAngle == angle) ped.angle = angle end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function triggerClientEvent(peer,event,_,ped,token,site,initial)
            if event == "npchlc_traffic:activityProbe" then requests[ped] = {token=token,site=site,initial=initial}
            elseif event == "npchlc_traffic:activityObserveTurn" then ped.revision = token end
            return true
        end
        function setElementData(ped,key,data)
            if key == "npchlc_traffic:activityMotion" then ped.clip = data[1] else ped.desired = data[1] end
        end
        function removeElementData(ped,key)
            if key == "npchlc_traffic:activityMotion" then ped.clip = nil else ped.desired = nil end
        end
        exports = {npc_hlc = {
            clearNPCTasks = function(_,ped) ped.task = nil end,
            addNPCTask = function(_,ped,task) ped.task = task return true end,
        }}
        PedAI = {profile = function(ped) return {pedType=4,name=ped.stat} end}
        PedActivitySites = {{"seat","parkbench1",0,0,0,0,0,0,0,48},
                            {"work","chairsntable",45,0,0,45,0,0,0,-1},
                            {"atm","atm",145,0,0,145,0,0,0,76,1,0,0},
                            {"shelter","shelter",200,0,0,200,0,0,0,100,0,1,0}}
        PedActivityBeaches = {{95,-3,-5,110,3,5}}
        function npc(x,stat) return {x=x,y=0,z=0.85,stat=stat,walk={queued=1,owner=owner}} end
        function reply(ped,value,who)
            client = who or owner
            replies["npchlc_traffic:activityReply"](ped,requests[ped].token,value)
        end
        function arrive(ped)
            local t = ped.task
            ped.x,ped.y,ped.z = t[2],t[3],t[4] -- simulate the HLC walker reaching its goal
            assert(PedActivity.update(ped,ped.walk,tick))
        end
        function align(ped, migrate)
            assert(ped.desired ~= nil and not ped.clip)
            local ev = replies["npchlc_traffic:activityTurned"]
            client = owner
            local old = ped.revision
            ev(ped,old,(ped.desired + 45) % 360)
            assert(PedActivity.update(ped,ped.walk,tick) and not ped.clip)
            if migrate then
                ped.syncer = {x=0,y=0,z=1}
                PedActivity.update(ped,ped.walk,tick)
                assert(ped.revision ~= old)
                ev(ped,old,ped.desired)
                assert(PedActivity.update(ped,ped.walk,tick) and not ped.clip)
                client = ped.syncer
                reply(ped,0,ped.syncer)
            end
            -- Native scripted yaw has not replicated back to the server.
            ped.ackAngle = ped.desired
            ev(ped,ped.revision,ped.desired)
            assert(PedActivity.update(ped,ped.walk,tick) and not ped.clip)
            tick = tick + 1200
            assert(PedActivity.update(ped,ped.walk,tick) and ped.clip and not ped.desired)
        end
    """)
    lua.execute((ROOT / "ped_activity.lua").read_text())
    lua.execute("""
        local p,q = npc(2), npc(3)
        assert(PedActivity.onSpawn(p,p.walk))
        assert(not PedActivity.onSpawn(q,q.walk))
        assert(PedActivity.stats().seat == 1)
        reply(p,false,{})
        assert(PedActivity.stats().seat == 1)
        reply(p,false)
        assert(PedActivity.stats().seat == 0 and p.walk.queued == 1)
        assert(PedActivity.onSpawn(q,q.walk))
        reply(q,0)
        assert(PedActivity.update(q,q.walk,tick) and q.task[1] == "walkToPos")
        arrive(q)
        assert(q.task[2] == 0 and q.task[3] == 0 and q.walk.queued == 0)
        arrive(q)
        align(q,true)
        assert(q.clip == "seat_down" and q.angle == 0)
        tick = tick + 4000
        PedActivity.update(q,q.walk,tick)
        assert(q.clip == "seat_idle")
        reply(q,false,q.syncer) -- streamed prop disappeared
        assert(PedActivity.stats().seat == 0 and not q.clip and q.walk.queued == 0)
        q = npc(1)
        assert(PedActivity.onSpawn(q,q.walk))
        reply(q,0)
        PedActivity.update(q,q.walk,tick)
        arrive(q)
        arrive(q)
        align(q)
        local entryX,entryY = q.x,q.y
        for _ = 1,42 do
            tick = tick + 1000
            PedActivity.update(q,q.walk,tick)
            if requests[q] and not requests[q].initial then reply(q,0) end
            if q.clip == "seat_up" then sawStandUp = true end
            if PedActivity.stats().seat == 0 then break end
        end
        assert(sawStandUp and not q.clip and q.x == entryX and q.y == entryY)
        assert(PedActivity.onSpawn(p,p.walk))
        tick = tick + 2500
        assert(not PedActivity.update(p,p.walk,tick)) -- no sync peer response
        p = npc(45)
        assert(PedActivity.onSpawn(p,p.walk))
        reply(p,0)
        PedActivity.update(p,p.walk,tick)
        arrive(p)
        align(p)
        assert(p.clip == "emp_bar_idle")
        tick = tick + 2633
        PedActivity.update(p,p.walk,tick)
        assert(p.clip == "emp_bar_clean")
        PedActivity.cancel(p) -- damage takes ownership
        assert(not p.clip and PedActivity.stats().work == 0)
        p = npc(100,"STAT_BEACH_GUY")
        assert(PedActivity.onSpawn(p,p.walk))
        reply(p,0)
        PedActivity.update(p,p.walk,tick)
        align(p)
        assert(p.clip == "beach_lower")
        tick = tick + 1333
        PedActivity.update(p,p.walk,tick)
        assert(p.clip == "beach_recline")
        tick = tick + 1433
        PedActivity.update(p,p.walk,tick)
        reply(p,0)
        assert(p.clip == "sunbathe")
        q = npc(101,"STAT_BEACH_GIRL")
        assert(not PedActivity.onSpawn(q,q.walk))
        rain = 1
        PedActivity.update(p,p.walk,tick)
        assert(p.clip == "sunbathe_to_sit")
        tick = tick + 1433
        PedActivity.update(p,p.walk,tick)
        assert(p.clip == "sunbathe_stand")
        tick = tick + 1333
        assert(not PedActivity.update(p,p.walk,tick) and not p.clip)
        assert(not PedActivity.onSpawn(q,q.walk))
        rain = 0
        assert(PedActivity.onSpawn(q,q.walk))
        PedActivity.stop()
        assert(PedActivity.stats().beach == 0)
        p = npc(1)
        assert(PedActivity.onSpawn(p,p.walk))
        reply(p,0)
        PedActivity.update(p,p.walk,tick)
        arrive(p)
        arrive(p)
        align(p)
        tick = tick + 4000
        PedActivity.update(p,p.walk,tick)
        reply(p,0)
        assert(p.clip == "seat_idle")
        assert(PedActivity.leaveForThreat(p,p.walk,tick) and p.clip == "seat_up")
        tick = tick + 3999
        assert(PedActivity.leaveForThreat(p,p.walk,tick) and p.clip == "seat_up")
        reply(p,0)
        tick = tick + 1
        assert(not PedActivity.leaveForThreat(p,p.walk,tick) and not p.clip)
        local queue = {}
        for i=1,5 do
            local a = npc(150+i*0.6)
            queue[i]=a
            assert(PedActivity.onSpawn(a,a.walk))
            assert(requests[a].site[6] == 145+i-1)
        end
        assert(not PedActivity.onSpawn(npc(150),{queued=1,owner=owner}))
        assert(PedActivity.stats().atm == 5)
        PedActivity.cancel(queue[1])
        assert(PedActivity.update(queue[2],queue[2].walk,tick))
        assert(requests[queue[2]].site[6] == 145)
        reply(queue[2],0)
        PedActivity.update(queue[2],queue[2].walk,tick)
        arrive(queue[2])
        align(queue[2])
        assert(queue[2].clip=="atm")
        tick=tick+PedActivityClips.atm
        assert(not PedActivity.update(queue[2],queue[2].walk,tick))
        assert(queue[2].walk.cash>=20 and queue[2].walk.cash<=1000)
        local r=npc(201)
        rain=0.19
        assert(not PedActivity.onSpawn(r,r.walk))
        rain=0.2
        assert(PedActivity.onSpawn(r,r.walk) and PedActivity.stats().shelter==1)
        rain=0.19
        assert(not PedActivity.update(r,r.walk,tick) and PedActivity.stats().shelter==0)
        PedActivity.stop()
    """)
    client = LuaRuntime()
    client.execute("""
        handlers, root, resourceRoot = {}, {}, {}
        function addEvent() end
        function addEventHandler(name,_,fn) handlers[name] = fn end
        function getElementType() return "ped" end
        function isElementStreamedIn() return true end
        function getElementRotation(ped) return 0,0,ped.angle end
        function setElementRotation(ped,_,_,value) ped.angle = value % 360 end
        function setElementPosition() error("Client moved the world-space root") end
        function getElementData(ped,key) return ped[key] end
        function isElement(ped) return type(ped) == "table" end
        function setPedAnimationProgress(ped,clip,value) ped.progress = value end
        function triggerServerEvent(event,_,ped,revision,angle)
            assert(event == "npchlc_traffic:activityTurned" and revision == 5)
            assert(math.abs((angle - 25 + 180) % 360 - 180) <= 1)
            ped.confirmations = (ped.confirmations or 0) + 1
        end
    """)
    client.globals().activityBytes = contents
    client.globals().streetBytes = (ROOT / "ped_models/street.ifp").read_bytes()
    client.execute("""
        local files={["ped_activity/activities.ifp"]=activityBytes,["ped_models/street.ifp"]=streetBytes}
        function getThisResource() return resourceRoot end
        function getResourceName() return "npchlc_traffic" end
        function getTickCount() return 100 end
        function fileOpen(path,ro) assert(ro); return files[path] end
        function fileGetSize(data) return #data end
        function fileRead(data,size) assert(size==#data); return data end
        function fileClose() end
        banks={}
        function engineLoadIFP(data,block)
            assert(not banks[block])
            assert(data==(block==TrafficAnimationBanks.activity and activityBytes or streetBytes))
            banks[block]={}
            return banks[block]
        end
    """)
    client.execute((ROOT / "ped_animation_banks_c.lua").read_text())
    client.execute("""
        local block=TrafficAnimationBanks.street
        assert(TrafficAnimationBanks.load(block,"ped_models/street.ifp")==banks[block])
        assert(TrafficAnimationBanks.load(block,"ped_models/street.ifp")==banks[block])
    """)
    client.execute((ROOT / "ped_activity_c.lua").read_text())
    client.execute("""
        source = {angle=358}
        local key = "npchlc_traffic:activityHeading"
        source[key] = {25,5}
        handlers.onClientElementDataChange(key)
        handlers["npchlc_traffic:activityObserveTurn"](source,5)
        handlers.onClientPreRender(16)
        assert(source.angle > 0 and source.angle < 1)
        handlers.onClientPreRender(500) -- clamp a long frame
        assert(source.angle < 9)
        for _ = 1,12 do handlers.onClientPreRender(16) end
        assert(math.abs(source.angle - 25) <= 0.05 and source.confirmations == 1)
        source[key] = nil
        handlers.onClientElementDataChange(key)
        source.angle = 90
        handlers.onClientPreRender(16)
        assert(source.angle == 90) -- interrupted turns relinquish rotation
        source["npchlc_traffic:activityMotion"] = {"seat_down",false,8,4000}
        handlers["npchlc_traffic:activityElapsed"](source,8,2000)
        assert(source.progress == 0.5)
        handlers["npchlc_traffic:activityElapsed"](source,7,3000)
        assert(source.progress == 0.5) -- obsolete phase response
        function getElementsByType() return {} end
        function getElementType(ped) return ped.kind or "ped" end
        function isElementStreamedIn(element)
            assert(element.kind ~= "building","buildings do not have MTA streaming state")
            return true
        end
        local prop = {kind="building",name="stonebench1"}
        function getElementID(obj) return obj.name end
        function getElementsWithinRange(x,y,z,radius,kind)
            if kind == "building" and prop then return {prop} end
            return {}
        end
        function getElementPosition() return 0,0,0.85 end
        function isLineOfSightClear() return true end
        local material = 0
        function processLineOfSight() return true,0,0,0,false,0,0,1,material end
        function getWaterLevel() return false end
        local result
        function triggerServerEvent(_,_,ped,token,value) result=value end
        handlers.onClientResourceStart()
        local probe = handlers["npchlc_traffic:activityProbe"]
        local site = {"seat","stonebench1",0,0,0,0,0,0,0}
        probe({},1,site,true)
        assert(result == 0)
        prop = nil
        probe({},2,site,false)
        assert(result == false)
        site[1] = "beach"
        probe({},3,site,true)
        assert(result == false)
        material = 33
        probe({},4,site,true)
        assert(result == 0)
        material = 12
        probe({},5,site,true)
        assert(result == 0)
        material = 30
        probe({},6,site,true)
        assert(result == false)
    """)


if __name__ == "__main__":
    check()
    print("VCS activity catalog, animation archive, arbitration and lifecycle checks passed")
