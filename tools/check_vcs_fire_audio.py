"""Verify the PS2 fire mixer, bank declarations, slot arbitration and release timing."""

from pathlib import Path
from xml.etree import ElementTree
import wave

from lupa.lua51 import LuaRuntime


SKY = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[graphic]/skygfx"


def check():
    declared = {f.get("src") for f in ElementTree.parse(SKY / "meta.xml").findall("file")}
    for path in (SKY / "audio").glob("*.wav"):
        assert f"audio/{path.name}" in declared
        with wave.open(str(path)) as sound:
            assert sound.getnchannels() == 1 and sound.getsampwidth() == 2 and sound.getnframes() > 0
    lua = LuaRuntime()
    lua.execute("""
        root={}; localPlayer={}; sourceResource="fire"; hooks={}; sounds={}
        tick=5000; cameraX=0; cameraZ=0; dimension=0
        function addEventHandler(e,_,f) hooks[e]=f end
        function isElement(s) return type(s)=="table" and s.active end
        function getTickCount() return tick end
        function getCameraMatrix() return cameraX,0,cameraZ end
        function getCameraInterior() return 0 end
        function getElementDimension() return dimension end
        function playSound3D(path,x,y,z)
            local s={active=true,path=path,x=x,y=y,z=z}
            sounds[#sounds+1]=s
            return s
        end
        function setSoundVolume(s,v) s.volume=v end
        function setSoundSpeed(s,v) s.speed=v end
        function getSoundLength() return 4 end
        function setSoundPosition(s,v) s.phase=v end
        function setElementDimension() end
        function setElementInterior() end
        function setSoundMinDistance() end
        function setSoundMaxDistance() end
        function setElementPosition(s,x,y,z) s.x,s.y,s.z=x,y,z end
        function stopSound(s) s.active=false end
    """)
    lua.execute((SKY / "audio/fire.lua").read_text())
    lua.execute("""
        local frame=hooks.onClientPreRender
        local ground=assert(PlayFireSound("ground",0,0,0,0,0,1,500))
        local ped=assert(PlayFireSound("ped",0,0,0,0,0,0))
        frame()
        assert(#sounds==1 and sounds[1].path=="audio/ped_fire.wav" and sounds[1].volume==60/127)
        StopFireSound(ped)
        frame()
        assert(#sounds==2 and sounds[2].path=="audio/fire.wav" and sounds[2].phase>0.5)
        tick=tick+34; frame(); assert(sounds[1].active and sounds[1].volume==54/127)
        tick=tick+310; frame(); assert(not sounds[1].active)
        cameraX=48; frame(); assert(sounds[2].volume==20/127)
        sourceResource="other"; assert(not MoveFireSound(ground,5,0,0) and not StopFireSound(ground))
        sourceResource="fire"; dimension=1; frame(); assert(not sounds[2].active)
        dimension=0; cameraX=0; cameraZ=100; frame(); assert(sounds[3].volume==4/127)
        cameraZ=0; assert(ReportWaterExtinguish(ground,.75)); frame()
        local hiss=sounds[4]; assert(hiss.path=="audio/extinguish.wav" and hiss.volume==44/127)
        assert(hiss.speed==(23000+89)/22050)
        tick=tick+400; frame(); assert(hiss.active and hiss.volume<44/127)
        tick=tick+400; frame(); assert(not hiss.active)
        assert(MoveFireSound(ground,1,2,3) and sounds[3].x==1)
        assert(not PlayFireSound(12,0,0,0))
        local id=assert(PlayFireSound(7,0,0,0))
        assert(sounds[5].path=="audio/explosion.wav" and sounds[5].speed<0.821)
        assert(PlayFireSound(8,0,0,0) and sounds[6].path=="audio/mine.wav")
        sounds[5].active=false; frame(); assert(not StopFireSound(id))
        StopFireSound(ground); hooks.onClientResourceStop("fire")
        for _,s in ipairs(sounds) do assert(not s.active) end
    """)


if __name__ == "__main__":
    check()
    print("Fire audio bank, pitch, gain, release, water and owner lifecycle checks passed")
