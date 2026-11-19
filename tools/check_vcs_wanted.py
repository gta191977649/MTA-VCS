"""Run wanted-rule and MTA adapter smoke tests with Lupa's Lua 5.1 runtime."""

from pathlib import Path

from lupa.lua51 import LuaRuntime


def main():
    traffic = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"
    lua = LuaRuntime()
    lua.execute('''
        root, resourceRoot = {}, {}
        local registered, handlers, timers = {}, {}, {}
        local now = 0
        player, other = {level = 0}, {level = 3}
        policePed = {kind = "ped", police = true, x = 1}
        events = {}

        function isElement(element) return type(element) == "table" end
        function getElementType(element) return element.kind or "player" end
        function getElementInterior(element) return element.interior or 0 end
        function getElementDimension(element) return element.dimension or 0 end
        function getElementPosition(element) return element.x or 0, 0, 0 end
        function getPlayerWantedLevel(element) return element.level end
        function setPlayerWantedLevel(element, level) element.level = level return true end
        function setElementData(element, key, value, mode, policy)
            assert(policy == "deny")
            element[key] = value
            return true
        end
        function removeElementData(element, key) element[key] = nil end
        function getElementsByType() return {player, other} end
        function getTickCount() return now end
        function addEvent(name, remote) registered[name] = remote end
        function addEventHandler(name, target, handler)
            handlers[name] = handlers[name] or {}
            table.insert(handlers[name], handler)
        end
        function triggerEvent(name, element, old, new, reason)
            assert(registered[name] == false and name == "onPlayerWanted")
            table.insert(events, {element, old, new, reason})
            if onWanted then onWanted(element, old, new, reason) end
        end
        function setTimer(handler, delay, repeats)
            assert(delay == 200 and repeats == 0)
            table.insert(timers, handler)
        end
        function fire(name, element, ...)
            source = element
            for _, handler in ipairs(handlers[name]) do handler(...) end
            source = nil
        end
        function tick(ms)
            now = now + ms
            for _, timer in ipairs(timers) do timer() end
        end
        TrafficActors = {
            isPoliceNearby = function(_, radius) return policeDistance and policeDistance < radius or false end,
            isManagedPed = function(element) return element == policePed end,
            isPolicePed = function(element) return element.police end,
        }
    ''')
    for script in ("wanted_rules.lua", "wanted.lua"):
        lua.execute((traffic / script).read_text(encoding="utf-8"), name=script)

    lua.execute('''
        fire("onResourceStart", resourceRoot)
        assert(#events == 0 and getPlayerWanted(other) == 3)

        local rules = TrafficWantedRules
        for stars, points in ipairs({40, 180, 550, 1200, 2400, 4800}) do
            assert(rules.levelForPoints(points - 1) == stars - 1)
            assert(rules.levelForPoints(points) == stars)
            assert(rules.levelForPoints(rules.forLevel(stars)) == stars)
        end
        assert(rules.addCrime(0, 0, 16, true) == 166)
        assert(rules.addCrime(9599, 0, 16, false) == 9600)
        assert(rules.getPoliceResponse(0).policeHelicopters == 0)
        assert(rules.getPoliceResponse(3).undercover)
        assert(rules.getPoliceResponse(6).pursuitVehicleLimit == 4)
        assert(rules.getPoliceResponse(6).roadblockThreshold == 30)

        assert(setPlayerWanted(player, 2, "test"))
        assert(events[1][1] == player and events[1][2] == 0 and events[1][3] == 2 and events[1][4] == "test")
        assert(setPlayerWanted(player, 2) and #events == 1)
        assert(not setPlayerWanted(player, -1) and not setPlayerWanted(player, 2.5))
        assert(not setPlayerWanted(player, 1, {}) and not setPlayerWanted(player, "1"))
        setPlayerWantedLevel(player, 0)
        tick(200)
        assert(events[2][2] == 2 and events[2][3] == 0 and events[2][4] == "native")
        tick(200)
        assert(#events == 2)

        -- Two reported incidents through the timer path, with the second
        -- submission of the same incident sharing the original queue slot.
        policeDistance = 14
        assert(reportWantedCrime(player, 3, 100))
        assert(reportWantedCrime(player, 3, 100))
        tick(500)
        assert(getPlayerWanted(player) == 0)
        tick(200)
        assert(getPlayerWanted(player) == 1 and events[3][4] == "crime")
        policeDistance = 13.9
        assert(reportWantedCrime(player, 12, 200))
        assert(getPlayerWanted(player) == 2)
        tick(200)
        tick(1001)
        assert(getPlayerWanted(player) == 3)

        -- Queued or immediate zero-point reports restore saved parole score.
        assert(suspendPlayerWanted(player))
        assert(player["nspray:paroleStars"] == 3 and getPlayerWanted(player) == 0)
        fire("onPlayerWeaponFire", player)
        assert(getPlayerWanted(player) == 3 and player["nspray:paroleStars"] == nil)
        tick(20001)
        assert(player["nspray:paroleStars"] == nil)

        assert(setPlayerWanted(player, 1))
        policeDistance = 17.9
        for _ = 1, 22 do tick(1001) end
        assert(getPlayerWanted(player) == 1)
        policeDistance = 18
        for _ = 1, 21 do tick(1001) end
        assert(getPlayerWanted(player) == 0 and events[#events][4] == "decay")

        assert(setPlayerWanted(player, 1))
        assert(suspendPlayerWanted(player))
        tick(20001)
        assert(player["nspray:paroleStars"] == nil)
        assert(reportWantedCrime(player, 1, 301, true))
        assert(getPlayerWanted(player) == 0)

        -- Re-entrant listeners see transitions in order, and an unchanged
        -- native observation must not send the same event again.
        onWanted = function(element, old, new)
            if new == 1 then assert(setPlayerWanted(element, 2, "listener")) end
        end
        local before = #events
        assert(setPlayerWanted(player, 1))
        assert(#events == before + 2 and events[before + 1][3] == 1 and events[before + 2][3] == 2)
        tick(200)
        assert(#events == before + 2)
        onWanted = nil

        fire("onPlayerWasted", player)
        fire("onPlayerSpawn", player)
        assert(getPlayerWanted(player) == 0 and events[#events][4] == "respawn")

        policeDistance = nil
        policePed.dimension = 1
        fire("onPedWasted", policePed, 0, player, 22)
        assert(getPlayerWanted(player) == 0)
        policePed.dimension = 0
        fire("onPedWasted", policePed, 0, player, 22)
        assert(getPlayerWanted(player) == 1)
    ''')
    print("VCS wanted rules and MTA adapter passed")


if __name__ == "__main__":
    main()
