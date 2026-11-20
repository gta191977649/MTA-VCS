"""Exercise VCS ambient encounters through the controller update entry points."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def check():
    lua = LuaRuntime()
    lua.execute("""
        exports = {npc_hlc={setNPCTask=function(_,p,t) p.task=t return true end,
            clearNPCTasks=function(_,p) p.task=nil end}}
        function addEventHandler() end
        function isElement(e) return type(e)=="table" and not e.gone end
        function isPedDead(p) return p.dead end
        function isPedInVehicle(p) return p.car ~= nil end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getElementRotation(p) return 0,0,p.heading or 0 end
        function setElementRotation(p,_,_,value) p.heading=value end
        function getElementPosition(p) return p.x,p.y or 0,0 end
        function getElementVelocity() return 0,0,0 end
        function setElementData(p,k,v) p[k]=v end
        function removeElementData(p,k) p[k]=nil end
        function getElementData(p) return p.id end
        function getPedWeapon() return 0 end
        function setPedAnimation(p,_,clip) p.clip=clip end
        function getVehicleOccupants(v) return v.occupants end
        function getVehicleOccupant(v,s) return v.occupants[s] end
        function getPedOccupiedVehicle(p) return p.car end
        function getElementHealth(v) return v.hp end
        function isVehicleLocked(v) return v.locked end
        function isVehicleBlown() return false end
        function getVehicleType() return "Automobile" end
        function getTickCount() return 0 end
        function getElementSyncer() return {} end
        function triggerClientEvent(_,name,_,p) p.lastEvent=name end
        function getElementsWithinRange(_,_,_,_,kind)
            if kind=="ped" then return peds elseif kind=="vehicle" then return cars end
            return {}
        end
        PedAI={setLeader=function() return true end, busy=function() return false end,
            isScriptControlled=function(p) return p.script end,brain=function(p) return p end}
        PedActivity={active=function() return false end}
        function react(self,kind,other,weapon,intent) self.event={kind=kind,target=other,intent=intent or "fight"} return true end
        function pedestrian(id,x) return {id=id,x=x,react=react}, {originalModelId=id,queued=1} end
        function car(x,hp) return {id=171,x=x,hp=hp,occupants={}} end
    """)
    for name in ("ped_ai_profiles","ped_activity_sites","ped_social","ped_ambient_wait","ped_mugging","ped_theft"):
        lua.execute((RESOURCE / (name+".lua")).read_text())
    lua.execute("""
        local curb,w = {},{}
        local resumed = 0
        local function advance() resumed=resumed+1 end
        PedAmbientWait.start(curb,w,1,23499,{2})
        assert(PedAmbientWait.update(curb,w,23999,advance) and resumed==0)
        assert(PedAmbientWait.update(curb,w,24000,advance) and resumed==1)
        PedAmbientWait.start(curb,w,1,29500,{2})
        assert(PedAmbientWait.update(curb,w,30768,advance) and resumed==1)
        PedAmbientWait.cancel(curb,w)
        PedAmbientWait.start(curb,w,8,500)
        assert(PedAmbientWait.update(curb,w,1501,advance) and w.wait.scratched)
        assert(PedAmbientWait.update(curb,w,3501,advance) and not w.wait)
        local group = {18,54,24}
        local function first() return 1 end
        local m,f=PedSocial.pickPair(group,function() return true end,first)
        assert(m==18 and f==24)
        local draws=0
        assert(not PedSocial.pickPair({24},function() return true end,function() draws=draws+1 return 1 end))
        assert(draws==8)
        local p,s=pedestrian(55,0)
        local v,t=pedestrian(24,7)
        local actors={[p]=s,[v]=t}
        peds,cars={p,v},{}
        local random=math.random
        math.random=function(lo,hi) return hi==65535 and 30 or 0 end
        assert(PedMugging.update(p,s,actors,100))
        v.x=1.39
        assert(PedMugging.update(p,s,actors,200))
        assert(p["npchlc_traffic:activityMotion"][1]=="fucku")
        assert(PedMugging.update(p,s,actors,1480) and not p.dropCash)
        assert(PedMugging.update(p,s,actors,1481) and p.dropCash and v.event.target==p)
        assert(p.event.intent=="flee" and not s.mug)
        math.random=random
        local robber,walk=pedestrian(55,0)
        local empty,full,edge,scrap=car(4,801),car(2,1000),car(10,1000),car(1,800)
        full.occupants[0]=v
        cars={edge,full,scrap,empty}
        walk.theftModels={[171]=true}
        for i=1,8 do assert(not PedTheft.update(robber,walk,i)) end
        assert(PedTheft.update(robber,walk,9) and walk.theft.car==empty)
        robber.x=2
        assert(PedTheft.update(robber,walk,10) and robber.lastEvent=="npchlc_traffic:reclaimDriverSeat")
        empty.occupants[0]=robber
        TrafficRoad={driveStolenCar=function(p,c,id) return p==robber and c==empty and id==55 end}
        assert(PedTheft.update(robber,walk,20) and not walk.theft)
        cars={full}
        local rich,r=pedestrian(55,0)
        assert(PedTheft.seekOccupied(rich,r,50) and r.theft.driver==v)
        local leader,a=pedestrian(17,0)
        local follower,b=pedestrian(24,1.1)
        function PedAI.profile(p) return {pedType=PedAIModels[p.id][1],social=1} end
        math.random=function() return 0 end
        for _,id in ipairs({8,12,13,119,24}) do
            local one,w1=pedestrian(id,0)
            local two,w2=pedestrian(24,1)
            one.heading,two.heading=270,90
            peds={one,two}
            local pair={[one]=w1,[two]=w2}
            if id==24 then
                math.random=function() return 0.5 end
                assert(not PedSocial.meet(one,w1,pair,500))
                assert(not PedSocial.meet(one,w1,pair,600))
                math.random=function() return 0 end
                assert(not PedSocial.meet(one,w1,pair,800))
                one.task,two.task={"walkTrafficToPoint"},{"walkTrafficToPoint"}
                assert(PedSocial.meet(one,w1,pair,801))
                assert(not one.task and not two.task and w1.queued==0 and w2.queued==0)
                assert(w1.facingTarget==two and w2.facingTarget==one)
            else
                assert(not PedSocial.meet(one,w1,pair,600) and not PedSocial.meet(two,w2,pair,600))
                assert(not PedSocial.bind(one,two,pair,true) and not w1.partner and not w2.leader)
            end
        end
        math.random=random
        actors={[leader]=a,[follower]=b}
        PedSocial.bind(leader,follower,actors,true)
        assert(PedSocial.update(follower,b,500,actors) and follower["npchlc_traffic:activityMotion"][6]=="PED")
        PedSocial.interrupt(leader,a)
        assert(PedSocial.update(follower,b,600,actors) and not follower["npchlc_traffic:activityMotion"] and follower.task[2]==leader)
        local enemy=pedestrian(24,3)
        leader.event={intent="fight",target=enemy}
        assert(PedSocial.update(follower,b,610,actors) and follower.event.target==enemy and follower.event.kind=="ally")
        follower.event=nil
        PedSocial.bind(leader,follower,actors,true)
        PedSocial.interrupt(leader,a)
        assert(PedSocial.update(follower,b,620,actors) and follower.event.target==enemy and follower.event.kind=="damage")
        local function recruit(count)
            local chief,l=pedestrian(91,0)
            local host,h=pedestrian(91,1)
            local newcomer,n=pedestrian(91,2)
            l.partner=chief
            h.gatherLeader=chief
            peds={host,newcomer}
            local group={[chief]=l,[host]=h,[newcomer]=n}
            for i=1,count do
                local visitor,w=pedestrian(91,i)
                w.gatherLeader=chief
                group[visitor]=w
                peds[#peds+1]=visitor
            end
            assert(PedSocial.update(host,h,0,group))
            return n.gatherLeader==chief
        end
        assert(recruit(4) and not recruit(5))
        leader.dead=true
        assert(not PedSocial.update(follower,b,700,actors) and not b.leader)
    """)
    lua.execute("""
        handlers={}
        TrafficAnimationBanks={activity="test_activity"}
        function addEvent() end
        function addEventHandler(name,_,fn) handlers[name]=fn end
        function getElementType() return "ped" end
        function isElementStreamedIn() return true end
        function getElementData(p,k) return p[k] end
        function getPedAnimation(p) return p.block,p.clip end
        function setPedAnimation(p,block,clip) p.block,p.clip=block,clip end
        function setPedAnimationProgress(p,_,t) p.progress=t end
        function triggerServerEvent(_,_,p,revision) p.revision=revision end
    """)
    lua.execute((RESOURCE / "ped_activity_c.lua").read_text())
    lua.execute("""
        local key="npchlc_traffic:activityMotion"
        source={[key]={"idle_chat",false,401,4000,401,"PED"}}
        handlers.onClientElementStreamIn()
        assert(source.block=="PED" and source.clip=="IDLE_chat" and source.revision==401)
        handlers["npchlc_traffic:activityElapsed"](source,401,2000)
        assert(source.progress==0.5)
        source[key]=nil
        handlers.onClientElementDataChange(key)
        assert(not source.block)
        source[key]={"xpressscratch",false,4900,3067,4900,"PED"}
        handlers.onClientElementDataChange(key)
        assert(source.clip=="XPRESSscratch")
        source.block,source.clip,source[key]="PED","FALL_front",nil
        handlers.onClientElementDataChange(key)
        assert(source.clip=="FALL_front")
    """)
    lua.execute((RESOURCE / "ped_social_c.lua").read_text())
    hlc = RESOURCE.parent / "npc_hlc"
    lua.execute((hlc / "task_progress.lua").read_text())
    lua.execute((hlc / "tasks_c.lua").read_text())
    lua.execute("""
        local key="npchlc_traffic:socialFacing"
        function getElementMatrix(p)
            local r=math.rad(p.heading)
            return {{math.cos(r),math.sin(r),0},{-math.sin(r),math.cos(r),0},{0,0,1},{p.x,p.y,0}}
        end
        function setPedRotation(p,heading,fix) assert(fix); p.heading=heading%360 end
        function getElementVelocity(p) return p.vx or 0,p.vy or 0,0 end
        function stopNPCWalkingActions(p) p.target=nil end
        function walkNPCTrafficFormation(p,x,y) p.target={x,y} end
        local function aligned(a,b) return math.abs((a-b+180)%360-180)<=0.51 end
        for heading=0,315,45 do
            local r=math.rad(heading)
            local fx,fy=-math.sin(r),math.cos(r)
            local a={x=0,y=0,heading=heading+180}
            local b={x=fx,y=fy,heading=heading}
            a[key],b[key]=b,a
            for _,p in ipairs({a,b}) do source=p; handlers.onClientElementStreamIn() end
            for i=1,60 do handlers.onClientPreRender(16) end
            assert(aligned(a.heading,heading) and aligned(b.heading,heading+180))
            for _,p in ipairs({a,b}) do source=p; p[key]=nil; handlers.onClientElementDataChange(key) end
            a.heading=heading+120
            handlers.onClientPreRender(50)
            assert(a.heading==heading+120)
            local task={"walkFormation",a,0.45,1.8,0}
            a.heading=heading
            b.x,b.y=getNPCFormationSlot(task)
            for i=1,60 do performTask.walkFormation(b,task,16,{}) end
            assert(aligned(b.heading,a.heading) and not b.target)
            a.vx,a.vy=fx*0.025,fy*0.025
            performTask.walkFormation(b,task,16,{})
            assert(math.abs(b.target[1]-b.x-fx)<0.001 and math.abs(b.target[2]-b.y-fy)<0.001)
        end
    """)


if __name__ == "__main__":
    check()
    print("VCS pair selection, formation interruption, mugging and vehicle theft passed")
