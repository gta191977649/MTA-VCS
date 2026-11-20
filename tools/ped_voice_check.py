"""Check speech arbitration against the PS2 intervals and ship every referenced sample."""
from pathlib import Path

from lupa.lua51 import LuaRuntime


RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[traffic]/npchlc_traffic"


def main():
    vm = LuaRuntime(unpack_returned_tuples=True)
    vm.execute((RESOURCE / "ped_voice/catalog.lua").read_text(encoding="utf-8"))
    samples = set()
    banks = vm.globals().PedVoiceClips
    def clips(model, event):
        return {clip for _, variant in banks[model].items() if variant[event]
                for _, clip in variant[event].items()}

    assert sum(bool(clips(model, "evade")) for model in banks) == 97
    assert clips(23, "evade") == {"ped_voice/1861.wav", "ped_voice/1862.wav"}
    assert not clips(9, "evade")
    assert sum(bool(clips(model, "crash")) for model in banks if model != 0) == 122
    assert clips(23, "crash") == {"ped_voice/1859.wav", "ped_voice/1860.wav"}
    assert not clips(9, "crash")
    assert len(clips(0, "arrested")) == 5 and len(clips(0, "serviceOffer")) == 3
    assert len(clips(0, "serviceAction")) == 3 and len(clips(31, "serviceAction")) == 11
    assert len(clips(12, "treat")) == len(clips(12, "arrive")) == 8
    assert not any(clips(model, "reclaim") for model in banks)
    assert len(banks[12]) == 2 and len(banks[8]) == 5
    assert clips(45, "pain").isdisjoint(clips(46, "pain"))
    assert "ped_voice/2201.wav" in clips(90, "chat")
    assert "ped_voice/0992.wav" in clips(91, "chat")
    assert clips(90, "chat").isdisjoint(clips(91, "chat"))
    for _, variants in banks.items():
        for _, events in variants.items():
            for _, pool in events.items():
                samples.update(pool.values())
    assert samples and all((RESOURCE / name).is_file() for name in samples)
    vm.execute("""
        root, resourceRoot, timers, heard, players = {}, {}, {}, {}, {1,2}
        time, hooks = 10000, {}
        PedVoiceClips = {[23]={{pain={"pain1","pain2"},fear={"fear1","fear2"},evade={"dodge1","dodge2"},
                               crash={"crash1","crash2"}}},
                         [9]={{fear={"fear3"}}}, [24]={pain={"legacyPain"}}, [25]={}}
        function addEventHandler(name, _, fn) hooks[name] = fn end
        function getElementType(p) return "ped" end
        function getElementData(p) return p.model or 23 end
        function isElement(p) return p and not p.destroyed end
        function getElementPosition() return 0,0,0 end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getElementsWithinRange() return players end
        function getTickCount() return time end
        function isPedDead(p) return p.dead end
        function setTimer(fn,ms,_,p)
            local timer = {fn=fn, at=time+ms, ped=p}
            timers[#timers+1]=timer
            return timer
        end
        function isTimer(t) return t and not t.killed end
        function killTimer(t) t.killed=true end
        function advance(ms)
            time=time+ms
            for _,t in ipairs(timers) do
                if not t.killed and time>=t.at then t.killed=true; t.fn(t.ped) end
            end
        end
        function triggerClientEvent(to,_,_,ped,clip)
            heard[#heard+1]={to=to,ped=ped,clip=clip}
            return true
        end
    """)
    vm.execute((RESOURCE / "ped_voice.lua").read_text(encoding="utf-8"))
    vm.execute("""
        local a,b = {},{}
        assert(PedVoice.emit(a,"fear") and PedVoice.emit(a,"pain"))
        assert(not PedVoice.emit(a,"fear"))
        advance(50)
        assert(#heard==1 and heard[1].clip:match("pain") and #heard[1].to==2)
        PedVoice.emit(b,"pain")
        advance(50)
        assert(#heard==1)
        advance(1000)
        PedVoice.emit(a,"pain")
        advance(50)
        assert(#heard==2 and heard[1].clip~=heard[2].clip)
        PedVoice.emit(b,"fear")
        advance(50)
        assert(#heard==3 and heard[3].clip:match("fear"))
        players={2,3}
        PedVoice.emit(a,"fear")
        advance(150)
        assert(#heard==4 and #heard[4].to==1 and heard[4].to[1]==3)
        advance(5000)
        PedVoice.emit(b,"pain")
        source=b
        hooks.onElementDestroy()
        advance(500)
        assert(#heard==4)
        local c,d,e = {},{},{model=9}
        assert(PedVoice.emit(c,"evade"))
        advance(50)
        assert(#heard==5 and heard[5].clip:match("dodge"))
        assert(not PedVoice.emit(c,"evade") and PedVoice.emit(d,"evade"))
        advance(2999)
        assert(#heard==5)
        assert(PedVoice.emit(d,"evade"))
        advance(50)
        assert(#heard==6 and heard[6].clip:match("dodge"))
        advance(5000)
        PedVoice.emit(e,"evade")
        advance(50)
        assert(#heard==6)
        local driver, otherDriver = {},{}
        assert(PedVoice.emit(driver,"crash"))
        advance(50)
        assert(#heard==7 and heard[7].clip:match("crash"))
        assert(not PedVoice.emit(driver,"crash") and PedVoice.emit(otherDriver,"crash"))
        advance(2999)
        assert(#heard==7)
        advance(2000)
        assert(not PedVoice.emit(driver,"crash"))
        advance(1001)
        assert(PedVoice.emit(driver,"crash"))
        advance(50)
        assert(#heard==8 and heard[7].clip~=heard[8].clip)
        local legacy={model=24}
        assert(PedVoice.emit(legacy,"impact"))
        advance(50)
        assert(#heard==9 and heard[9].clip=="legacyPain")
        assert(PedVoice.emit({model=25},"fear"))
        advance(50)
        assert(#heard==9)
    """)
    client = LuaRuntime()
    client.execute("""
        root,resourceRoot,localPlayer={},{},{}
        local hooks={}
        function addEvent() end
        function addEventHandler(name,element,fn) hooks[element]=hooks[element] or {}; hooks[element][name]=fn end
        function isElement(e) return type(e)=="table" and not e.stopped end
        function getCameraMatrix() return listenerX,0,0.65 end
        function getElementPosition(e) return e.x,0,0 end
        function getElementDimension(e) return e.dim or 0 end
        function getElementInterior(e) return 0 end
        function isElementStreamedIn() return true end
        function isLineOfSightClear() return clear end
        function getDistanceBetweenPoints3D(x,y,z,a,b,c) return math.sqrt((x-a)^2+(y-b)^2+(z-c)^2) end
        function playSound3D(clip,x,y,z,loop)
            assert(clip=="test.wav" and x==0 and y==0 and z==0.65 and not loop)
            sound={}; return sound
        end
        function setSoundVolume(s,v) s.volume=v end
        function stopSound(s) s.stopped=true end
        function setSoundMaxDistance(s,v) s.range=v end
        function setSoundMinDistance() end
        function setElementDimension() end
        function setElementInterior() end
        function attachElements(s,p) s.speaker=p; return true end
        function setTimer(fn) update=fn end
        function speak(p) hooks[resourceRoot]["npchlc_traffic:pedVoice"](p,"test.wav",40) end
    """)
    client.execute((RESOURCE / "ped_voice_c.lua").read_text(encoding="utf-8"))
    client.execute("""
        local ped={x=0}
        listenerX,clear=0,true
        speak(ped)
        assert(sound.speaker==ped and sound.volume==1 and sound.range==40)
        listenerX=24
        update()
        assert(sound.volume==0.25)
        clear=false
        update()
        assert(math.abs(sound.volume-.25*31/127)<1e-6)
        ped.x=24
        clear=true
        update()
        assert(sound.volume==1)
        listenerX=65
        update()
        assert(sound.volume==0)
        ped.dim=1
        update()
        assert(sound.stopped)
    """)
    print(f"Verified {len(samples)} packaged speech samples, priority, repeat avoidance and listener cooldowns")


if __name__ == "__main__":
    main()
