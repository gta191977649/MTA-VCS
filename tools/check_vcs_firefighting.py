"""Run the Fire Fighter and Fire Copter mission state machines under Lua 5.1."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
MISSION = ROOT / "mods/deathmatch/resources/[mission]/mission"


def check_client_effects():
    lua = LuaRuntime()
    lua.execute("""
        events,fx,root,resourceRoot,localPlayer={},{},{},{},{}
        function addEventHandler(name,host,cb) events[name]=cb end
        function event(name,e,...) source=e events[name](...) end
        function isElement(e) return type(e)=="table" and not e.gone end
        function destroyElement(e) assert(isElement(e)) e.gone=true end
        function isElementStreamedIn(e) return e.stream end
        function getElementType(e) return e.kind end
        function getElementDimension(e) return 0 end
        function getElementInterior(e) return 0 end
        function getElementPosition(e) assert(isElement(e)) return 0,0,0 end
        function getElementData(e,k) return e[k] end
        pipeline=true
        particles={}
        exports={skygfx={
            AreParticlesEnabled=function() return pipeline end,
            AddParticle=function(_,...) particles[#particles+1]={...} end
        }}
        now,draws=100,0
        function getTickCount() return now end
        function dxCreateTexture() texture={} return texture end
        function dxDrawMaterialLine3D(_,_,z) draws=draws+1;lowest=math.min(lowest or z,z) end
        function tocolor() return 0 end
        function setElementPosition() end
        function setElementDimension() end
        function setElementInterior() end
        function getDistanceBetweenPoints3D() return 1 end
        function createEffect(name) local e={name=name} fx[#fx+1]=e return e end
        function setTimer(cb) timer={fn=cb} return timer end
        function isTimer(t) return t and not t.stopped end
        function killTimer(t) assert(isTimer(t)) t.stopped=true end
        function getPedOccupiedVehicle() return false end
    """)
    lua.execute((MISSION / "firefighting_c.lua").read_text(encoding="utf8"))
    lua.execute("""
        MissionRunToken="first"
        local target,tag,spray="mission:fireTarget","mission:airRescueCable","mission:bucketSpraying"
        local m={kind="marker",stream=true,[target]={"first",false}}
        local n={kind="marker",stream=true,[target]={"second",false}}
        local b={kind="object",stream=true,[tag]=7350,[spray]=true}
        for _,e in ipairs({m,n,b}) do event("onClientElementStreamIn",e) end
        timer.fn()
        event("onClientPreRender",root)
        assert(#fx==1 and fx[1].name=="fire_med" and draws==0 and #particles==20)
        for i=1,20 do
            local p=particles[i]
            if i<=8 then assert(p[1]==28 and p[4]==-2 and p[7]==.03 and p[8]==1)
            elseif i<=14 then assert(p[1]==78 and p[4]==-2 and p[7]<0)
            else assert(p[1]==78 and p[4]==-2.2 and p[7]<0 and p[8]==.5) end
        end
        assert(particles[1][5]==.05 and particles[1][6]==0 and particles[13][6]==.01 and particles[19][6]==.031)
        pipeline=false
        now=now+34
        event("onClientPreRender",root)
        assert(draws==2 and #particles==20,"fallback should draw two droplets per release")
        now=now+180
        event("onClientPreRender",root)
        assert(draws>2 and lowest < -1,"the spray must fall below the bucket")
        m[target][3]=7
        pipeline=true
        timer.fn()
        assert(fx[1].gone and #fx==1,"managed fire must remove the native fallback")
        pipeline=false
        timer.fn()
        assert(#fx==2 and not fx[2].gone,"a disabled graphics pipeline requires the fallback")
        pipeline=true
        timer.fn()
        assert(fx[2].gone)
        table.remove(fx,2)
        m[target]=false
        event("onClientElementDataChange",m,target)
        assert(fx[1].gone)
        b[tag]=false
        event("onClientElementDataChange",b,tag)
        local before=draws
        event("onClientPreRender",root)
        assert(before==draws and texture.gone)
        MissionRunToken="second"
        b[tag]=7350
        event("onClientElementStreamIn",b)
        timer.fn()
        pipeline=false
        event("onClientPreRender",root)
        assert(#fx==2 and not fx[2].gone and draws>before)
        event("mission:end",resourceRoot,false,false,"first")
        assert(not fx[2].gone)
        event("mission:end",resourceRoot,false,false,"second")
        assert(fx[2].gone)
        event("onClientElementStreamOut",n)
        event("onClientElementDestroy",b)
        assert(timer.stopped)
        event("onClientElementStreamIn",b)
        timer.fn()
        event("onClientPreRender",root)
        event("onClientResourceStop",resourceRoot)
        before=draws
        event("onClientPreRender",root)
        assert(timer.stopped and draws==before and texture.gone)
    """)


def check_fire_release():
    lua = LuaRuntime()
    lua.execute("""
        root,resourceRoot,localPlayer={}, {}, {}
        local gfx={}
        exports={skygfx=gfx}
        function gfx:AreParticlesEnabled() return true end
        function gfx:PlayFireSound() started=started+1 return 23 end
        function gfx:MoveFireSound() return true end
        function gfx:StopFireSound(id) assert(id==23) stopped=stopped+1 return true end
        function gfx:AddLight() end
        function gfx:AddParticle() end
        callbacks={}
        function addEvent() end
        function addEventHandler(event,el,cb) callbacks[event]=cb end
        function getResourceFromName(name) return name end
        function getResourceState() return "running" end
        function getElementPosition() return 0,0,1 end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getCameraMatrix() return 0,-7,2 end
        function getPedOccupiedVehicle() return false end
        function getPedWeapon() return 0 end
        function getElementsByType() return {} end
        function isElement(e) return type(e)=="table" end
        function isElementStreamedIn() return true end
        function getElementType() return "ped" end
        function cancelEvent() cancelled=true end
        function getTickCount() return 120 end
        started,stopped=0,0
    """)
    lua.execute((MISSION.parents[1] / "[module]/fire/Fire.lua").read_text())
    lua.execute("""
        local ped={}
        callbacks["fire:start"](9,"ped",ped,0,0,1,0.8,110,1,0,0,0)
        callbacks["onClientPreRender"]()
        callbacks["fire:start"](9,"ped",ped,0,0,1,0.8,110,1,0,0,0)
        callbacks["onClientPreRender"]()
        assert(started==1 and stopped==0)
        source=ped
        callbacks.onClientPedDamage(nil,37)
        assert(cancelled)
        callbacks["fire:stop"](9)
        callbacks["fire:stop"](9)
        callbacks.onClientPreRender()
        assert(started==1 and stopped==1,"released fire must stop its existing voice exactly once")
        cancelled=false
        callbacks.onClientPedDamage(nil,37)
        assert(not cancelled,"release must restore native damage for the ped")
    """)


def check_fire_manager():
    lua = LuaRuntime()
    lua.execute("""
        root,resourceRoot,handlers,timers,messages={},{},{},{},{}
        now=10000
        function getTickCount() return now end
        function addEvent() end
        function addEventHandler(name,host,callback) handlers[name]=callback end
        function triggerClientEvent(...) messages[#messages+1]={...} end
        function isElement(e) return type(e)=="table" and not e.gone end
        function getElementType(e) return e.kind end
        function getElementPosition(e) return e.x or 0, e.y or 0, e.z or 0 end
        function getElementDimension(e) return e.dimension or 0 end
        function getElementInterior(e) return e.interior or 0 end
        function getResourceFromName() return false end
        function isPedDead(e) return e.dead end
        function isElementInWater(e) return e.wet end
        function getPedOccupiedVehicle(e) return false end
        function getElementData(e,k) return e[k] end
        function isElementOnFire(e) return e.burning end
        function setElementOnFire(e,burning) e.burning=burning end
        function getPedArmor(e) return e.armour end
        function setPedArmor(e,v) e.armour=v end
        function getElementHealth(e) return e.health end
        function setElementHealth(e,v) e.health=v end
        function killPed(e,killer,weapon) e.dead,e.killer,e.weapon=true,killer,weapon end
        function getElementsWithinRange() return {} end
        function setTimer(callback,msec) timers[msec]=callback end
        function wasEventCancelled() return false end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function ready(player)
            client,source=player,resourceRoot
            handlers["fire:ready"]()
            client=nil
        end
    """)
    lua.execute((MISSION.parents[1] / "[module]/fire/FireManager.lua").read_text())
    lua.execute("""
        local owner,viewer,other={kind="marker"},{kind="player"},{kind="player"}
        local host={kind="vehicle"}
        local id=StartScriptFire(owner,host,viewer,0.8)
        assert(id and messages[1][1]==viewer and messages[1][4]==id)
        assert(StartScriptFire(owner,host,viewer,0.8)==id and #messages==1)
        source={dimension=12,interior=3}
        handlers.onExplosion(4,8,3,1)
        assert(messages[2][1]==root and messages[2][5]=="molotov")
        now=10525
        ready(other)
        assert(#messages==3 and messages[3][1]==other and messages[3][5]=="molotov")
        assert(messages[3][11]==525 and messages[3][13]==3 and messages[3][14]==12)
        ready(other)
        assert(#messages==3,"repeat snapshot throttled")
        ready(viewer)
        assert(#messages==5)
        local viewerKinds={[messages[4][5]]=true,[messages[5][5]]=true}
        assert(viewerKinds.molotov and viewerKinds.script)
        assert(not ExtinguishPointWithWater(4,8,3,4,3,13,100),"water across dimensions")
        assert(ExtinguishPointWithWater(4,8,3,4,3,12,100))
        assert(messages[#messages][2]=="fire:water" and math.abs(messages[#messages][5]-0.94)<0.000001)
        source=owner
        handlers.onElementDestroy()
        assert(messages[#messages][2]=="fire:stop" and messages[#messages][4]==id)
        now=20001
        timers[100]()
        assert(messages[#messages][2]=="fire:stop")
        local player={kind="player",dimension=25,health=100,armour=10}
        source=player
        handlers.onPlayerDamage(other,37)
        assert(player.burning)
        now=now+1000
        timers[100]()
        assert(player.armour==0 and math.abs(player.health-90.2)<0.00001)
        now=now+2400
        timers[100]()
        assert(not player.burning and math.abs(player.health-(110-3333*0.06*0.33))<0.00001)
        player["mission:fireproof"]=true
        handlers.onPlayerDamage(other,37)
        assert(not player.burning)
        player["mission:fireproof"]=nil
        handlers.onPlayerDamage(other,37)
        assert(player.burning)
        function getResourceFromName(name) return name=="debug" and "debug" end
        function getResourceState() return "running" end
        exports={debug={isPlayerInGodMode=function(_,ped) return ped==player end}}
        local before=player.health
        player.armour=15
        now=now+500
        timers[100]()
        assert(not player.burning and player.health==before and player.armour==15)
        source=player
        handlers.onPlayerDamage(other,37)
        assert(not player.burning,"godmode prevents a new ignition")
        for n=1,40 do assert(StartScriptFire({kind="marker"},false,viewer,0.8)) end
        assert(not StartScriptFire({kind="marker"},false,viewer,0.8))
        assert(StartScriptFire({kind="marker",dimension=1},false,viewer,0.8))
    """)


def main():
    lua = LuaRuntime()
    lua.globals().waterFile = (MISSION.parents[1] / "[vcs]/vcs/water.dat").read_text()
    lua.execute("""
        function getResourceFromName() return {} end
        function getResourceState() return "running" end
        math.randomseed(35)
        events,defs,runs,sites={},{},{},{}
        root,resourceRoot,t={},{},100
        function addEvent() end
        function addEventHandler(name,host,cb) events[name]=cb end
        function getTickCount() return t end
        function getTime() return 12,0 end
        function isElement(e) return type(e)=="table" and not e.gone end
        function getElementPosition(e) assert(isElement(e)) return e.x,e.y,e.z end
        function getElementMatrix(e) return {{1,0,0},{0,1,0},{0,0,1},{e.x,e.y,e.z}} end
        function getElementHealth(e) return e.health or 1000 end
        function setElementHealth(e,h) e.health=h end
        function setElementData(e,k,v) e[k]=v end
        function attachElements(e,parent) e.parent=parent return true end
        function destroyElement(e) assert(isElement(e)) e.gone=true end
        function fileOpen(path) assert(path=="water.dat") return {} end
        function fileRead() return waterFile end
        function fileGetSize() return #waterFile end
        function fileClose() end
        local function noop() end
        setElementFrozen,setElementInterior,setElementDimension=noop,noop,noop
        setVehicleEngineState,setElementSyncer,setElementVelocity=noop,noop,noop
        function removeElementData(e,k) e[k]=nil end
        function getElementInterior() return 0 end
        function getElementDimension() return 0 end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function setElementPosition(e,x,y,z) e.x,e.y,e.z=x,y,z end
        setElementAlpha,setElementCollisionsEnabled=noop,noop
        function getDistanceBetweenPoints2D(x,y,px,py) return math.sqrt((x-px)^2+(y-py)^2) end
        function createObject(model,x,y,z) return {model=model,x=x,y=y,z=z} end
        function isVehicleBlown(e) return e.blown end
        function isPedDead(e) return e.dead end
        function killPed(e) e.dead=true end
        function isElementInWater(e) return e.wet end
        function getVehicleOccupant(e,seat) return e[seat] end
        function getPedOccupiedVehicle(e) return e.vehicle end
        function warpPedIntoVehicle(p,e,seat) e[seat]=p p.vehicle=e p.seat=seat return true end
        function removePedFromVehicle(p) p.vehicle[p.seat]=nil p.vehicle=nil end
        local traffic={}
        function traffic:getTrafficPopulationAt() return {originalModelId=55} end
        function traffic:getMissionTrafficRoad(x,y,z) return x,y,z,0 end
        function traffic:createTrafficScriptPed(skin,x,y,z) return createObject(skin,x,y,z) end
        function traffic:assignTrafficPedObjective(p,job)
            if job=="exitVehicle" then removePedFromVehicle(p) end
            p.job=job return true
        end
        exports={npchlc_traffic=traffic,vcs_vehicle={},marker={setMarkerVisibleTo=function(_,m,p,v) m.visible=v end}}
        exports.fire={}
        function exports.fire:StartScriptFire(marker,host,owner,size)
            assert(marker and owner and size==0.8)
            marker.fireOwner,marker.fireHost=owner,host
            return 1
        end
        function exports.vcs_vehicle:createVcsVehicle(...) return createObject(...) end
        Mission={driverOf=function(v) return getVehicleOccupant(v,0) end,register=function(id,d) defs[id]=d end,track=noop,message=noop,hud=noop}
        function Mission.showReturnVehicle(r,v) r.indicator=v end
        function Mission.clearReturnVehicle(r) r.indicator=nil end
        function Mission.participants(r) return {r.player} end
        function Mission.fail(r,text) r.error=text r.active=false end
        function Mission.claimSite(r,k)
            if sites[k] then return false end
            sites[k]=r return true
        end
        function Mission.releaseSites(r) for k,v in pairs(sites) do if v==r then sites[k]=nil end end end
        function Mission.model(v) return v.model end
        function Mission.switchVehicle(r,v) r.vehicle=v return true end
        function Mission.active(r) return r.active end
        function Mission.marker(r,x,y,z) return createObject(0,x,y,z) end
        function Mission.checkpointCue(r) r.cues=(r.cues or 0)+1 end
        function Mission.finishLevel(r,amount)
            r.pay=(r.pay or 0)+amount
            if r.air and r.level==5 then r.active=false end
            r.level=r.level+1
        end
        function Mission.forParticipant(p,token,id)
            local r=runs[p]
            if r and r.active and r.token==token and r.id==id then return r end
        end
        function start(id,level)
            local d=defs[id]
            local v=createObject(d.models[1],-783.38,923.28,11.09)
            local p=createObject(1,v.x,v.y,v.z)
            warpPedIntoVehicle(p,v,0)
            local r={token=tostring(p),id=id,vehicle=v,player=p,level=level or 1,
                     dimension=0,interior=0,active=true}
            runs[p]=r d.start(r,t)
            assert(not r.error,r.error)
            return r
        end
        function tick(r,ms) t=t+(ms or 200) if r.sling then r.sling.received=t end defs[r.id].tick(r,t) end
        function input(r,pressed,other,deep)
            source,client=resourceRoot,other and other.player or r.player
            events["mission:fireControls"](r.token,r.id,pressed,0,1,0,deep)
        end
        function pos(v,x,y,z) v.x,v.y,v.z=x,y,z end
    """)
    lua.execute((MISSION.parents[1] / "[vcs]/vcs/water_s.lua").read_text())
    lua.execute("""
        events["onResourceStart"]()
        exports.vcs={getVcsWaterQuadLevel=function(_,x,y) return getVcsWaterQuadLevel(x,y) end}
        assert(getVcsWaterQuadLevel(1048,-437)==6)
        assert(not getVcsWaterQuadLevel(-783.38,923.28))
    """)
    for script in ("sling.lua", "firefighting_data.lua", "firefighting.lua"):
        lua.execute((MISSION / script).read_text())
    check_client_effects()
    check_fire_manager()
    check_fire_release()
    lua.execute("""
        local a,b=start("firefighter"),start("firefighter")
        assert(a.fires[1].entity~=b.fires[1].entity)
        local f=a.fires[1]
        assert(f.marker.fireOwner==a.player and f.marker.fireHost==f.entity and f.marker["mission:fireTarget"][3])
        pos(a.player,f.x,f.y-12,f.z)
        source,client=resourceRoot,b.player
        events["mission:fireRoadReady"](a.token,f.entity,f.z+1.5)
        assert(not f.grounded)
        client=a.player
        events["mission:fireRoadReady"](a.token,f.entity,f.z+100)
        assert(not f.grounded)
        events["mission:fireRoadReady"](a.token,f.entity,f.z+1.5)
        assert(f.grounded and math.abs(f.entity.z-f.z-2.35)<0.0001)
        pos(a.vehicle,f.x,f.y-12,f.z)
        input(a,true,b)
        tick(a)
        assert(not f.done and not a.sprayUntil and b.level==1)
        input(a,true)
        tick(a)
        assert(a.level==2 and a.pay==20 and f.done and not b.fires[1].done)
        tick(a,5100)
        f=a.fires[1]
        assert(#f.crew==1)
        pos(a.vehicle,f.x,f.y-12,f.z)
        input(a,true) tick(a)
        local victim=a.fires[2]
        assert(victim and victim.entity.job=="exitVehicle" and a.level==2)
        input(a,true) tick(a)
        assert(a.level==3 and a.pay==60 and victim.done and a.cues==3 and not b.cues)
        local expected={0,1,2,3,4,4,4,5,5,5,6,9,9,9,10}
        for level,n in ipairs(expected) do
            local run=start("firefighter",level)
            local occupants=0
            for _,fire in ipairs(run.fires) do occupants=occupants+#fire.crew end
            assert(occupants==n)
            Mission.releaseSites(run)
        end
        local lost=start("firefighter",2)
        local car=lost.fires[1]
        pos(lost.vehicle,car.x,car.y-12,car.z)
        input(lost,true) tick(lost)
        input(lost,false) tick(lost)
        local burned=lost.fires[2]
        assert(burned.entity.job=="ignite")
        tick(lost,22001)
        assert(lost.pay==20 and burned.entity.dead and not lost.perfect)
        local aborted=start("firefighter",2)
        local dispatch=aborted.fires[1]
        pos(aborted.vehicle,dispatch.x,dispatch.y-12,dispatch.z)
        input(aborted,true) tick(aborted)
        input(aborted,false) tick(aborted)
        assert(aborted.fires[2].entity.job=="ignite")
        defs.firefighter.stop(aborted)
        assert(aborted.fires[2].entity.job=="extinguish")
        local high=start("firefighter",15)
        assert(#high.fires==3 and #high.fires[1].crew==4 and #high.fires[3].crew==2)
        removePedFromVehicle(high.player)
        tick(high)
        assert(high.indicator==high.vehicle and high.fires[1].marker.visible==false)
        high.vehicle.blown=true
        tick(high)
        assert(not high.indicator)
        tick(high,30001)
        assert(high.error)
        local c,d=start("firecopter"),start("firecopter")
        assert(defs.firecopter.canStart(c.player,c.vehicle))
        assert(#FireCopterSites==79 and #c.fires==12)
        assert(c.bucket["mission:airRescueCable"]==7350)
        removePedFromVehicle(d.player)
        tick(d)
        assert(d.indicator==d.vehicle and d.fires[1].marker.visible==false)
        warpPedIntoVehicle(d.player,d.vehicle,0)
        tick(d)
        assert(not d.indicator and d.fires[1].marker.visible)
        local first=c.fires[1]
        pos(c.vehicle,first.x,first.y,first.z+6)
        assert(not defs.firecopter.canStart(c.player,c.vehicle))
        input(c,true,d) tick(c)
        assert(c.water==100 and not first.done and not d.fires[1].done)
        c.sling.ox=4
        pos(c.vehicle,first.x+3,first.y,first.z+6)
        input(c,true) tick(c)
        assert(not first.done,"bucket swung clear of the fire")
        pos(c.vehicle,first.x-7,first.y,first.z+6)
        input(c,true) tick(c)
        c.sling.ox=0
        assert(c.water==88 and first.done and not d.fires[1].done)
        for level,n in ipairs({12,17,19,19,12}) do
            assert(c.level==level and #c.fires==n)
            for _,fire in ipairs(c.fires) do
                if not fire.done then
                    if c.water<=6 then
                        pos(c.vehicle,-2800,0,12)
                        for i=1,5 do input(c,false,nil,true) tick(c) end
                        assert(c.water>0)
                    end
                    pos(c.vehicle,fire.x,fire.y,fire.z+7)
                    input(c,true) tick(c)
                    assert(fire.done)
                end
            end
            assert(c.returning and c.level==level and c.active)
            pos(c.vehicle,-742.272,858.7609,11.781)
            tick(c)
            assert(c.level==level+1 and c.pay>0)
            if level<5 then tick(c,5100) end
        end
        assert(not c.active and d.active and d.water==100 and not d.fires[1].done)
        defs.firecopter.stop(c)
        assert(not c.bucket["mission:bucketSpraying"] and not c.bucket["mission:airRescueCable"])
        assert(d.bucket["mission:airRescueCable"]==7350)
        d.water=60
        pos(d.vehicle,-783.38,923.28,12)
        input(d,false,nil,true) tick(d)
        assert(d.water==60,"land refill")
        pos(d.vehicle,-2800,0,12) input(d,false,nil,true) tick(d)
        assert(d.water==65)
        input(d,false,nil,true) tick(d) assert(d.water==65)
    """)
    print("Fire Fighter and Fire Copter gameplay and concurrent-run isolation checks passed")


if __name__ == "__main__":
    main()
