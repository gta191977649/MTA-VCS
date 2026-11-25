"""Exercise hospital timing and weapon recovery with the production server scripts."""
from pathlib import Path
from lupa.lua51 import LuaRuntime


def main():
    resource = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[module]/wasted"
    lua = LuaRuntime()
    lua.execute("""
        root, resourceRoot = {}, {}
        local handlers, now = {}, 0
        function addEvent() end
        function addEventHandler(event, _, fn)
            handlers[event] = handlers[event] or {}
            table.insert(handlers[event], fn)
        end
        function emit(event, element, ...)
            local previous = source
            source = element
            for _, fn in ipairs(handlers[event] or {}) do fn(...) end
            source = previous
        end
        function isElement(p) return type(p) == "table" end
        function getElementType() return "player" end
        function getElementPosition(p) return p.x, p.y, p.z end
        function getElementDimension(p) return p.dim end
        function getElementInterior(p) return p.int end
        function getElementModel(p) return p.skin end
        function getPlayerTeam(p) return p.team end
        function getTickCount() return now end
        function setTimer(fn, _, _, p) p.timer = {fn=fn}; return p.timer end
        function isTimer(t) return t and not t.killed end
        function killTimer(t) t.killed=true end
        function step(p, time)
            now = time
            if isTimer(p.timer) then p.timer.fn(p) end
        end
        function triggerClientEvent(p, event, _, key, token)
            if event == "wasted:help" then p.help, p.token = key, token end
            if event == "wasted:showMessage" then p.title = key end
        end
        function getPedWeaponSlot(p) return p.slot end
        function setPedWeaponSlot(p, slot) p.slot=slot end
        local slots = {[22]=2, [29]=4}
        function getPedWeapon(p, slot) return p.ids[slot] or 0 end
        function getPedTotalAmmo(p, slot) return p.ammo[slot] or 0 end
        function takeAllWeapons(p) p.ids,p.ammo={},{}; return true end
        function giveWeapon(p, id, ammo)
            local slot=assert(slots[id])
            p.ids[slot],p.ammo[slot]=id,(p.ammo[slot] or 0)+ammo
            return true
        end
        function fadeCamera(p, visible, time, r, g, b)
            if not visible then assert(time==2 and r==200 and g==200 and b==200) end
            p.visible=visible
        end
        function spawnPlayer(p,x,y,z,r,model,int,dim,team)
            assert(model==p.skin and dim==p.dim and team==p.team)
            p.x,p.y,p.z,p.heading,p.int,p.dead=x,y,z,r,int,false
            p.spawnCount=p.spawnCount+1
            emit("onPlayerSpawn",p)
            return true
        end
        function isPedDead(p) return p.dead end
        function isElementFrozen() return false end
        function setCameraTarget(p,target) assert(p==target) end
        function setPedArmor(p,a) p.armor=a end
        function getPedStat() return 569 end
        function setElementHealth(p,h) p.health=h end
        function getPlayerMoney(p) return p.money end
        function takePlayerMoney(p,m) p.money=p.money-m; return true end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c)
            return math.sqrt((x-a)^2 + (y-b)^2 + (z-c)^2)
        end
        function player(money)
            return {x=-882,y=-470,z=12,dim=3,int=0,skin=7,team={},spawnCount=0,
                    money=money,ids={[2]=22,[4]=29},ammo={[2]=17,[4]=82},slot=4}
        end
        function die(p)
            p.dead=true
            emit("onPlayerWasted",p)
            takeAllWeapons(p) -- MTA clears the loadout after the event returns.
        end
    """)
    for name in ("restart.lua", "buyback_s.lua", "hospital.lua"):
        lua.execute((resource / name).read_text(encoding="utf-8"))
    lua.execute("""
        local p=player(2100)
        die(p)
        step(p,2047)
        assert(p.title and p.visible==nil and p.dead)
        step(p,2048)
        assert(p.visible==false and p.dead)
        step(p,4096)
        assert(p.spawnCount==1 and not p.dead and p.health==100 and p.armor==0)
        assert(p.x==-884.49 and p.y==-470.41 and p.z==13.0774 and p.heading==270)
        assert(p.money==2000 and next(p.ids)==nil)
        step(p,4608)
        step(p,9000)
        assert(p.visible and p.spawnCount==1 and not isTimer(p.timer))

        p.x,p.y,p.z=-874.3393,-457.9409,11.1083
        client=p
        emit("wasted:collect",resourceRoot,1)
        assert(p.help=="RE_WEP" and p.token)
        emit("wasted:answer",resourceRoot,p.token,false)
        assert(p.money==2000 and p.ids[2]==nil)
        emit("wasted:collect",resourceRoot,1)
        local token=p.token
        emit("wasted:answer",resourceRoot,token,true)
        emit("wasted:answer",resourceRoot,token,true)
        assert(p.money==0 and p.ammo[2]==17 and p.ammo[4]==82)
        emit("wasted:collect",resourceRoot,1)
        assert(p.help=="RE_WEPE")

        local q=player(35)
        assert(setPlayerFreeHealthCare(q,true))
        die(q)
        step(q,13096)
        assert(q.money==35 and q.ammo[2]==17 and q.ammo[4]==82)
        step(q,13608)
        die(q)
        step(q,17704)
        assert(q.money==0 and q.ids[2]==nil)
        step(q,18216)
        die(q)
        emit("onPlayerSpawn",q)
        step(q,24216)
        assert(q.spawnCount==2 and not q.title)

        -- Free bail changes the pickup locations while keeping the earlier buyback.
        local b=player(2100)
        die(b)
        step(b,28312)
        step(b,28824)
        giveWeapon(b,22,5,true)
        takeAllWeapons(b)
        ActivateWeaponBuyback(b,"busted")
        client=b
        b.x,b.y,b.z=-874.3393,-457.9409,11.1083
        emit("wasted:collect",resourceRoot,1)
        assert(not b.token)
        b.x,b.y,b.z=-865.1029,-669.1772,11.2617
        emit("wasted:collect",resourceRoot,1)
        assert(b.token and b.money==2000)
        emit("wasted:answer",resourceRoot,b.token,true)
        assert(b.money==0 and b.ammo[2]==17 and b.ammo[4]==82)

        local r=player(2100)
        die(r)
        emit("onResourceStop",resourceRoot)
        assert(r.spawnCount==1 and r.money==2100 and r.ammo[2]==17 and r.ammo[4]==82)
        assert(not isTimer(r.timer))
    """)
    print("Hospital restart, one-shot treatment, mixed loadout and single-charge buyback passed")


if __name__ == "__main__":
    main()
