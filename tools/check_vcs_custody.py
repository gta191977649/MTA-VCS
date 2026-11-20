"""Exercise the production Busted controller with a deterministic Lua 5.1 clock."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


def main():
    traffic = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"
    lua = LuaRuntime()
    lua.execute("""
        root, resourceRoot = {}, {}
        local handlers = {}
        now, timerCount = 0, 0
        function addEventHandler(event, _, fn) handlers[event] = fn end
        function emit(event, p) source = p; handlers[event](); source = nil end
        function setTimer(fn, interval)
            assert(interval == 50)
            timerCount = timerCount + 1
            timer = {run = fn}
            return timer
        end
        function killTimer(t) t.killed = true end
        function isTimer(t) return t and not t.killed end
        function step(t) now = t; timer.run() end
        function getTickCount() return now end
        function newPlayer()
            return {x = -657, y = 760, z = 11, money = 1000, dim = 7, interior = 1,
                disabled = {crouch = true}, weapons = 4, resets = 0}
        end
        function isElement(p) return type(p) == 'table' end
        function getElementData(p,key) return p[key] end
        function removeElementData(p,key) p[key]=nil end
        function getElementType() return 'player' end
        function getElementPosition(p) return p.x, p.y, p.z end
        function setElementPosition(p, x, y, z) p.x, p.y, p.z = x, y, z end
        function setElementRotation(p, _, _, heading) p.heading = heading end
        function getElementDimension(p) return p.dim end
        function getElementInterior(p) return p.interior end
        function setElementInterior(p, v) p.interior = v end
        function isPedDead(p) return p.dead end
        function isElementFrozen(p) return p.frozen end
        function setElementFrozen(p, v) p.frozen = v return true end
        function isControlEnabled(p, c) return not p.disabled[c] end
        function toggleControl(p, c, v) p.disabled[c] = not v end
        function fadeCamera(p, visible, seconds) p.black, p.fadeSeconds = not visible, seconds end
        function triggerClientEvent(p, name, _, visible)
            if name=="traffic:bustedText" then p.title = visible else assert(name=="traffic:bustedCameraEnd"); p.cameraEnded=true end
        end
        function getPedOccupiedVehicle(p) return p.vehicle end
        function getVehicleOccupant(car) return car.driver end
        function removePedFromVehicle(p) p.vehicle = nil end
        function setElementVelocity() end
        function setPedAnimation(p,_,clip) p.clip=clip; return true end
        function getPedStat() return 569 end
        function setPedArmor(p,v) p.armour = v end
        function setElementHealth(p,v) p.health = v end
        function getPlayerMoney(p) return p.money end
        function takePlayerMoney(p,v) p.money = p.money - v end
        function takeAllWeapons(p) p.weapons = 0 end
        exports = {wanted = {resetPlayerWanted = function(_, p, why)
            assert(why == 'arrest')
            p.resets = p.resets + 1
            return true
        end}}
    """)
    for name in ("custody_restarts.lua", "custody.lua"):
        lua.execute((traffic / name).read_text(encoding="utf-8"))
    lua.execute("""
        for level, fine in ipairs({100,200,400,600,900,1500}) do
            now = 0
            local p = newPlayer()
            local car={driver=p,alive=true}
            p.vehicle=car
            assert(TrafficCustody.begin(p, level) and not TrafficCustody.begin(p, level))
            assert(car.frozen and p.vehicle==car)
            step(2048)
            assert(not p.black and p.title and p.resets == 0)
            step(2049)
            assert(p.black and p.fadeSeconds==2 and p.disabled.fire and p.disabled.change_camera and p.disabled.action)
            step(4095)
            assert(p.money == 1000 and p.vehicle==car and car.frozen)
            step(4096)
            assert(p.resets == 1 and p.money == math.max(0, 1000 - fine))
            assert(not car.frozen)
            assert(p.weapons == 0 and p.health == 100 and p.armour == 0 and not p.vehicle and p.cameraEnded and p.black)
            assert(p.x == -657.34 and p.heading == 135 and p.dim == 7 and p.interior == 0)
            step(4608)
            assert(p.frozen and p.disabled.fire and p.disabled.change_camera and not p.black and p.fadeSeconds==3)
            step(7607)
            assert(p.frozen and p.disabled.fire)
            step(7608)
            assert(p.resets == 1 and not p.frozen and not p.disabled.fire and p.disabled.crouch)
            assert(not p.black and not TrafficCustody.isActive(p) and timer.killed)
        end
        local x = TrafficCustody.restartPoint(-200,-600,12)
        assert(x == -872.66) -- western region despite the shorter distance to Washington Beach
        local p,q = newPlayer(),newPlayer()
        local previous = timerCount
        now = 4294967290
        p.frozen = true
        assert(setTrafficPlayerFreeBail(p, true))
        assert(TrafficCustody.begin(p,6) and TrafficCustody.begin(q,2))
        assert(timerCount == previous + 1)
        q.dead = true
        emit("onPlayerWasted",q)
        assert(not q.frozen and not q.title and q.weapons == 4)
        step(5000)
        assert(p.black and p.resets==0)
        step(7000)
        step(7512)
        step(10512)
        assert(p.money == 1000 and p.resets == 1 and p.frozen and timer.killed)
        assert(TrafficCustody.begin(p,6))
        step(12561)
        step(14608)
        step(15120)
        step(18120)
        assert(p.money == 0 and p.resets == 2)
        assert(TrafficCustody.begin(p,1))
        p.dim = 9
        step(19120)
        assert(p.resets == 2 and not p.title and timer.killed)
        local cop, suspect = {}, newPlayer()
        now=18000
        assert(TrafficCustody.begin(suspect,1,cop) and TrafficCustody.isArresting(cop))
        assert(not TrafficCustody.begin(newPlayer(),1,cop) and suspect.clip=="handsup")
        step(20049)
        assert(suspect.black and suspect.frozen and suspect.disabled.enter_passenger)
        suspect.interior=2
        step(20100)
        assert(not suspect.clip and not suspect.black and not suspect.frozen and not TrafficCustody.isArresting(cop))
        assert(suspect.disabled.crouch and not suspect.disabled.change_camera)
    """)
    frontend = traffic.parent.parent / "[hud]" / "frontend"
    lua.execute("""
        function addEvent() end
        localPlayer = {}
        function getResourceName(r) return r end
        function getResourceFromName(r) return r end
        function getResourceState() return 'running' end
        function getThisResource() return 'frontend' end
    """)
    for script in (frontend / "hud_c.lua", frontend / "gametext_c.lua"):
        lua.execute(script.read_text(encoding="utf-8"))
    lua.execute("""
        exports.frontend = {
            getVcsText=function(_, key) assert(key=="BUSTED"); return "Localized Busted" end,
            showGameTextForPlayer=function(_,...) return showGameTextForPlayer(...) end,
            hideGameText=function(_,...) return hideGameText(...) end
        }
        sourceResource="npchlc_traffic"
        TrafficCustodyCamera={begin=function() camera=true end, finish=function() camera=false end}
    """)
    # Replay the custody client's event through the shared game-text renderer.
    lua.execute("function addEventHandler(name,_,fn) if name=='traffic:bustedText' then custodyClient=fn end end")
    lua.execute((traffic / "custody_c.lua").read_text(encoding="utf-8"))
    lua.execute("""
        custodyClient(true)
        local entry=Hud.message("big2",now)
        assert(entry.text=="Localized Busted" and entry.duration==5000 and entry.owner=="npchlc_traffic")
        assert(entry.style.face=="bigtext" and Hud.hasPriorityGameText(now))
        custodyClient(false)
        assert(not Hud.hasPriorityGameText(now))
        sourceResource="mission"
        showGameTextForPlayer("Mission announcement",2,5000)
        sourceResource="npchlc_traffic"
        custodyClient(false)
        assert(Hud.message("big2",now).text=="Mission announcement")
    """)
    print("Busted fees, station selection, timing, frontend game text, ownership and interruption passed")


if __name__ == "__main__":
    main()
