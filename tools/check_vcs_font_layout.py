#!/usr/bin/env python3
"""Render and measure the gameplay text using the PS2 glyph atlases and production Lua."""

import argparse
import hashlib
import json
import math
from pathlib import Path

from PIL import Image, ImageDraw

from check_vcs_hud_aspect import ASSETS, FRONTEND, load_lua, reference_layout


# Font indices and scales from the SLUS font setters. Font 0 is FancyText.
STYLES = (
    ("Radio", "showGameText('Emotion 98.3', 'radio', 0)", "fancytext", 1),
    ("Vehicle", "showGameText('Cheetah', 'VEHICLE_NAME', 0)", "fancytext", 1),
    ("Interior", "showGameText('Ocean View Hotel', 'LOCATION_NAME', 0)", "fancytext", 1),
    ("Help box", "showTextBox('Press ~X~ to enter the building.~n~Press again to leave.', 0, false)", "gametext", .6),
    ("Subtitle", "showCaptionForPlayer('We have to get out of here.', 0)", "gametext", .55),
    ("Mission passed", "showGameText('MISSION PASSED!', 'missionPassed', 2000)", "bigtext", 1),
    *((f"GameText {index}", f"showGameTextForPlayer('GameText {index}', {index}, 3000)", face, scale)
      for index, (face, scale) in enumerate((
          ("bigtext", 1), ("fancytext", 1.2), ("bigtext", 1), ("gametext", 1), ("gametext", 1),
          ("gametext", 1), ("fancytext", 1), ("gametext", 1), ("fancytext", 1)))),
)
RESOLUTIONS = ((1024, 768), (1366, 768), (1920, 768), (720, 576))


def make_runtime():
    lua = load_lua()
    lua.execute("""
        handlers, tick = {}, 0
        function addEventHandler(name, _, handler)
            if name == "onClientRender" then handlers.render = handler end
        end
        function addEvent() end
        function getThisResource() return 'frontend' end
        function getResourceName(name) return name end
        function getTickCount() return tick end
        function isMainMenuActive() return false end
        function isPlayerMapVisible() return false end
        utf8 = {}
    """)
    lua.globals().utf8.byte, lua.globals().utf8.char = ord, chr
    for name in ("hud_c.lua", "textbox_c.lua", "gametext_c.lua", "subtitle_c.lua"):
        lua.execute((FRONTEND / name).read_text(encoding="utf-8"))
    return lua


def render(lua, assets, viewport, style):
    name, trigger, expected_face, scale = style
    width, height = viewport
    sx, sy, _, _, _ = reference_layout(width, height)
    expected_x, expected_y = sx * 640 / 480 * scale, sy * 448 / 272 * scale
    frame = Image.new("RGBA", viewport)
    glyphs = []

    def rect(x, y, w, h, color):
        frame.alpha_composite(Image.new("RGBA", (round(w), round(h)), rgba(color)), (round(x), round(y)))

    def glyph(x, y, w, h, u, v, uw, vh, face, _rotation, _rx, _ry, color):
        assert face == expected_face, (name, face)
        # The controller button table stores a wider logical cell than its source UV rectangle.
        button = name == "Help box" and (u, v) == (22.5, 230)
        assert math.isclose(w / (uw + 1), expected_x * (1.33 if button else 1), rel_tol=1e-9), (name, w, uw)
        assert math.isclose(h / (vh + 0.5), expected_y, rel_tol=1e-9), (name, h, vh)
        assert x >= 0 and y >= 0 and x + w <= width and y + h <= height, (name, viewport, x, y, w, h)
        texture = assets[face].resize((max(1, round(w)), max(1, round(h))),
                                      Image.Resampling.BILINEAR, box=(u, v, u + uw, v + vh))
        r, g, b, a = rgba(color)
        channels = tuple(channel.point(lambda px, tint=tint: px * tint // 255)
                         for channel, tint in zip(texture.split(), (r, g, b, a)))
        frame.alpha_composite(Image.merge("RGBA", channels), (round(x), round(y)))
        if (r, g, b) != (0, 0, 0):
            glyphs.append((x, y, w, h, u, v, uw, vh, button))

    state = lua.globals()
    state.screenWidth, state.screenHeight = viewport
    state.dxDrawImageSection, state.dxDrawRectangle = glyph, rect
    state.tick += 10000
    lua.execute(f"assert({trigger})")
    state.tick += 850
    state.handlers.render()
    assert glyphs, name
    if name == "Help box":
        assert len({round(item[1], 6) for item in glyphs}) == 2
        assert any(item[-1] for item in glyphs)
        line_gap = sorted({round(item[1], 6) for item in glyphs})
        assert math.isclose(line_gap[1] - line_gap[0], 19 * expected_y, abs_tol=1e-5)
    return frame.crop(frame.getbbox())


def rgba(color):
    return tuple(color[i] for i in (1, 2, 3, 4))


def check_vehicle_mission_hud():
    """Run the mission event against frontend and measure the submitted atlas text."""
    lua = make_runtime()
    for name in ("user_display_c.lua", "lefttext_c.lua", "bar_c.lua"):
        lua.execute((FRONTEND / name).read_text(encoding="utf-8"))
    lua.execute("""
        local events = {}
        function addEventHandler(key, _, callback) events[key] = callback end
        function getElementDimension() return 0 end
        function getElementInterior() return 0 end
        function getResourceFromName(name) return name end
        exports.frontend = setmetatable({}, {__index=function(_, key)
            return function(_, ...) return _G[key](...) end
        end})
        function CFont:draw(text, name, x, y, size, color, shadow, aspect)
            recordText(text, x, y, x + self:width(text, size, name) * (aspect or 1))
        end
        function missionHud(...) events["mission:hud"](...) end
        function startMission() events["mission:start"]("Taxi Driver",17) end
        function endMission() events["mission:end"](false,false,17) end
    """)
    mission = FRONTEND.parents[1] / "[mission]/mission/main_c.lua"
    lua.execute(mission.read_text(encoding="utf-8"))
    state = lua.globals()
    state.startMission()
    state.tick += 10000
    face = json.loads((ASSETS / "manifest.json").read_bytes())["fonts"]["gametext"]
    pitch = math.ceil(face["lineHeight"] * .6)
    for width, height in RESOLUTIONS:
        state.screenWidth, state.screenHeight = width, height
        runs = []
        state.recordText = lambda text, x, y, end: runs.append((text, x, y, end))
        rects = []
        state.dxDrawRectangle = lambda x, y, w, h, *_: rects.append((x, y, w, h))
        sx, sy, *_ = reference_layout(width, height)
        sx, sy = sx * 640 / 480, sy * 448 / 272
        for seconds, fares in ((75, 3), (None, 123456)):
            runs.clear()
            rects.clear()
            state.missionHud("taxi", 1, seconds, "Fares", fares, "Tip", 80, 17)
            state.handlers.render()
            rows = ([("Time", "1:15")] if seconds else []) + [("Fares", str(fares)), ("Tip", "")]
            for row, (label, value) in enumerate(rows):
                y = (100 + 20 * row) * sy
                glyphs = sorted((run for run in runs if math.isclose(run[2], y)), key=lambda run: run[1])
                assert "".join(run[0] for run in glyphs) == label + value, (width, height, runs)
                label_width = sum(math.ceil(face["glyphs"][str(ord(c))][1] * .6) for c in label)
                label_end = width - max(75, 24 + len(value) * pitch + 4) * sx
                assert math.isclose(glyphs[0][1], label_end - label_width * sx, abs_tol=.01)
                if value:
                    for index, c in enumerate(value):
                        centered = (face["lineHeight"] - face["glyphs"][str(ord(c))][1]) * .3
                        x = width - (24 + (len(value) - index) * pitch - centered) * sx
                        assert math.isclose(glyphs[len(label)+index][1], x, abs_tol=.01)
            fill = (width - 66*sx, (101 + 20*(len(rows)-1))*sy, 41*.8*sx, 11*sy)
            assert any(all(math.isclose(a, b) for a, b in zip(rect, fill)) for rect in rects), rects
    lua.execute("""
        sourceResource = "garage"
        assert(showCaptionForPlayer("Servicing vehicle",0))
        assert(showGameText("Garage", "garage",10000))
        assert(showTextBox("Garage doors",10000,false))
        sourceResource = "mission"
        startMission()
        assert(Hud.message("big1",tick).owner=="mission")
        endMission()
        assert(not Hud.message("big1",tick))
        assert(Hud.message("caption",tick).owner=="garage")
        assert(Hud.message("garage",tick).owner=="garage")
        assert(Hud.message("help",tick).owner=="garage")
    """)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    check_vehicle_mission_hud()
    lua = make_runtime()
    lua.execute("""
        showGameText("MISSION PASSED!", "missionPassed", 2000)
        showCaptionForPlayer("Destination", 2000)
        for _, sample in ipairs({{0,0},{250,0.5},{500,1},{2499,1},{2750,0.5}}) do
            local entry, opacity = Hud.message("missionPassed",sample[1])
            assert(entry and opacity==sample[2])
            assert(entry.style.align=="center" and entry.style.valign=="center")
        end
        assert(not Hud.message("missionPassed",3000))
        for _, at in ipairs({0,1,250,1999}) do
            local entry, opacity = Hud.message("caption",at)
            assert(entry and opacity==1)
        end
        assert(not Hud.message("caption",2000))
    """)
    manifest = json.loads((ASSETS / "manifest.json").read_bytes())
    assert manifest["fonts"].keys() == {"fancytext", "gametext", "bigtext", "pagertext"}
    assets = {}
    for face in manifest["fonts"]:
        path = ASSETS / f"{face}.png"
        assert hashlib.sha256(path.read_bytes()).hexdigest() == manifest["textures"][face]["sha256"]
        with Image.open(path) as image:
            assert image.size == (256, 256)
            assets[face] = image.convert("RGBA")

    column, row = 294, 67
    sheet = Image.new("RGBA", (152 + column * len(RESOLUTIONS), 45 + row * len(STYLES)), "#253642")
    labels = ImageDraw.Draw(sheet)
    for i, viewport in enumerate(RESOLUTIONS):
        left = 152 + i * column
        labels.text((left + 8, 15), f"{viewport[0]} x {viewport[1]}", fill="#eef7fb")
        for j, style in enumerate(STYLES):
            top = 44 + j * row
            if i == 0:
                labels.text((15, top + 20), style[0], fill="#eef7fb")
            labels.rectangle((left, top, left + column - 8, top + row - 4), fill="#314955")
            # A separate HUD per case avoids overlap and priority masking between styles.
            crop = render(make_runtime(), assets, viewport, style)
            crop = crop.resize((max(1, crop.width // 2), max(1, crop.height // 2)), Image.Resampling.LANCZOS)
            sheet.alpha_composite(crop, (left + 8, top + (row - crop.height) // 2))
        print(f"{viewport[0]}x{viewport[1]}: verified {len(STYLES)} text layouts and their glyph scales")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.convert("RGB").save(args.output)


if __name__ == "__main__":
    main()
