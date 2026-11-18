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
    ("Subtitle", "showCaptionForPlayer('We have to get out of here.', 0)", "gametext", .61),
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
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
