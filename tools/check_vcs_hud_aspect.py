#!/usr/bin/env python3
"""Render the VCS HUD aspect-ratio check using Lua 5.1, Pillow and imported disc assets."""

import argparse
import json
import math
from pathlib import Path

from lupa.lua51 import LuaRuntime
from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
HUD = ROOT / "mods/deathmatch/resources/[hud]"
FRONTEND = HUD / "frontend"
ASSETS = FRONTEND / "ps2"
SIZES = ((960, 720), (1280, 1024), (720, 576), (1440, 900), (1920, 1080), (2560, 1080))


def load_lua():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("""
        localPlayer, root, resourceRoot = {}, {}, {}
        local startup = {}
        function addEventHandler(name, _, handler)
            if name == "onClientResourceStart" then table.insert(startup, handler) end
        end
        function start() for _, handler in ipairs(startup) do handler() end end
        function guiGetScreenSize() return screenWidth, screenHeight end
        function getResourceFromName(name) return name == "mradar" and "mradar" or false end
        function getResourceState() return "running" end
        function getElementData() return false end
        function getElementHealth() return armed and 55 or 80 end
        function getPedArmor() return armed and 0 or 60 end
        function getPlayerWantedLevel() return armed and 0 or 2 end
        function getTime() return 3, 14 end
        function getPlayerMoney() return 150 end
        function getPedStat(_, stat) return stat == 24 and 569 or 0 end
        function getPedOxygenLevel() return submerged and 500 or 1000 end
        function getPedOccupiedVehicle() return false end
        function isElementInWater() return submerged == true end
        function getPedWeapon() return armed and 22 or 0 end
        function getPedWeaponSlot() return armed and 2 or 0 end
        function getPedTotalAmmo() return 36 end
        function getPedAmmoInClip() return 17 end
        function isPlayerHudComponentVisible() return true end
        function setPlayerHudComponentVisible() end
        function tocolor(r,g,b,a) return {r,g,b,a or 255} end
        CHud = {}
        Hud = {onRender = function() end, clamp = function(v) return math.max(0,math.min(1,v)) end}
        RADAR_SPRITE = setmetatable({}, {__index = function(_, name) return name end})
        HUD_SPRITE, WEAPON_ID = RADAR_SPRITE, RADAR_SPRITE
    """)
    lua.execute((FRONTEND / "widescreen_c.lua").read_text(encoding="utf-8"))
    lua.execute("""
        exports = {
            frontend = {getVcsHudViewport = function(_, w, h) return getVcsHudViewport(w,h) end},
            mradar = {getVcsWeaponHudInfo = function() return {name = "beretta", clipped = true} end}
        }
        function dxCreateTexture(path) return path:match("^ps2/(.+)%.png$") end
        function fileOpen() return "{}" end
        function fileRead(file) return file end
        function fileGetSize(file) return #file end
        function fileClose() end
        function fromJSON() return assetManifest end
        utf8 = {byte = function(char) return char:byte() end}
    """)
    lua.globals().assetManifest = lua.table_from(json.loads((ASSETS / "manifest.json").read_bytes()), recursive=True)
    lua.execute((FRONTEND / "font_atlas_c.lua").read_text(encoding="utf-8"))
    lua.execute((HUD / "mradar/mradar_vcs_client.lua").read_text(encoding="utf-8"))
    lua.execute((FRONTEND / "player_hud_c.lua").read_text(encoding="utf-8"))
    lua.globals().start()
    return lua


def reference_layout(width, height):
    # Independent transcription of VCSPC's automatic-mode denominators.
    reference_width = width / height * 480
    reference_height = 448
    if (width, height) == (720, 576):
        reference_width = 640
    elif reference_width < 640:
        reference_width = 640
        reference_height = height / width * (640 / (480 / 448))
    scale_x, scale_y = width / reference_width, height / reference_height
    return scale_x, scale_y, 26 * scale_x, height - 64.4 * scale_y, 99.2 * scale_x


def render_radar(assets, diameter):
    # The circular mask in mradar has a four-texel inset at a 64px reference size.
    mask = Image.new("L", (diameter, diameter))
    radius = diameter * (0.5 - 4 / 64)
    center = (diameter - 1) / 2
    ImageDraw.Draw(mask).ellipse((center - radius, center - radius, center + radius, center + radius), fill=255)
    tiles = Image.new("RGBA", (256, 256))
    for index, name in enumerate(("radar27", "radar28", "radar35", "radar36")):
        tiles.paste(assets[name], (index % 2 * 128, index // 2 * 128))
    radar = tiles.resize(mask.size, Image.Resampling.BILINEAR)
    radar.putalpha(mask)
    radar.alpha_composite(assets["radardisc"].resize(mask.size, Image.Resampling.BILINEAR))
    return radar, mask


def render_view(lua, assets, width, height, armed=False, submerged=False):
    globals_ = lua.globals()
    globals_.screenWidth, globals_.screenHeight = width, height
    globals_.armed = armed
    globals_.submerged = submerged
    scale_x, scale_y, ref_left, ref_center_y, ref_diameter = reference_layout(width, height)
    viewport = globals_.getVcsHudViewport(width, height)
    assert math.isclose(viewport[0], scale_x) and math.isclose(viewport[1], scale_y)
    x, y, w, h = globals_.getVcsRadarRect(width, height)
    assert abs(x - ref_left) <= 0.5 and abs(y + h / 2 - ref_center_y) <= 0.5
    assert abs(w - ref_diameter) <= 0.5 and w == h
    assert x >= 0 and y >= 0 and x + w <= width and y + h <= height
    radar, mask = render_radar(assets, round(w))
    bounds = radar.getchannel("A").point(lambda a: 255 if a >= 128 else 0).getbbox()
    mask_bounds = mask.getbbox()
    diameter_x, diameter_y = bounds[2] - bounds[0], bounds[3] - bounds[1]
    assert diameter_x == diameter_y
    assert abs(diameter_x - w * 60 / 64) <= 1.5
    assert mask_bounds[2] - mask_bounds[0] == mask_bounds[3] - mask_bounds[1]
    assert abs(mask_bounds[0] + mask_bounds[2] - w) <= 2

    canvas = Image.new("RGBA", (width, height), "#22323c")
    canvas.alpha_composite(radar, (round(x), round(y)))
    draws = []

    def image(dx, dy, dw, dh, name, source=None, tint=None):
        texture = assets[name]
        if source:
            texture = texture.crop(source)
        if tint:
            r, g, b = (tint[index] for index in (1, 2, 3))
            red, green, blue, alpha = texture.split()
            texture = Image.merge("RGBA", (red.point(lambda v: round(v * r / 255)),
                green.point(lambda v: round(v * g / 255)), blue.point(lambda v: round(v * b / 255)), alpha))
        texture = texture.resize((max(1, round(dw)), max(1, round(dh))), Image.Resampling.BILINEAR)
        canvas.alpha_composite(texture, (round(dx), round(dy)))
        draws.append((name, dx, dy, dw, dh))

    def image_section(dx, dy, dw, dh, u, v, uw, vh, name, _r=0, _rx=0, _ry=0, tint=None):
        image(dx, dy, dw, dh, name, (u, v, u + uw, v + vh), tint)

    globals_.dxDrawImage, globals_.dxDrawImageSection = image, image_section
    lua.execute("CHud:drawPlayer(1000)")
    weapon = "weapon_beretta" if armed else "fist"
    _, weapon_x, weapon_y, weapon_w, weapon_h = next(draw for draw in draws if draw[0] == weapon)
    assert math.isclose(width - weapon_x, 85.6 * scale_x) and math.isclose(weapon_y, 17.3 * scale_y)
    assert math.isclose(weapon_w, 76 * scale_x) and math.isclose(weapon_h, 72 * scale_y)
    clock = [draw for draw in draws if draw[0] == "hudnumbers" and math.isclose(draw[2], 19.3 * scale_y)]
    money = [draw for draw in draws if draw[0] == "hudnumbers" and math.isclose(draw[2], 78.3 * scale_y)]
    assert len(clock) == 5 and len(money) == 9
    assert math.isclose(clock[0][1], money[0][1])
    _, bx, by, bw, bh = next(draw for draw in draws if draw[0] == "bar_outline" and math.isclose(draw[2], 58.3 * scale_y))
    assert abs(bx - clock[0][1]) <= 1.31 * scale_x and bx + bw < weapon_x
    assert math.isclose(by + bh, 75.1 * scale_y)
    if not armed or submerged:
        bar_y = round((38.3 + 8.4) * scale_y)
        samples = tuple(canvas.getpixel((round(bx + bw * portion), bar_y))[:3] for portion in (0.25, 0.75))
        expected = ((0, 30, 117), (0, 15, 58)) if submerged else ((9, 255, 250), (0, 51, 49))
        assert samples == expected, (submerged, samples)
    weapon_visible_right = weapon_x + weapon_w * 46 / 64
    assert abs(money[-1][1] + money[-1][3] - weapon_visible_right) <= 2 * scale_x
    assert weapon_y + weapon_h * 51 / 64 < money[0][2]
    if armed:
        ammo = [draw for draw in draws if draw[0] == "pagertext"]
        assert len(ammo) == 5
        ammo_left = min(draw[1] for draw in ammo)
        ammo_right = max(draw[1] + draw[3] for draw in ammo)
        assert weapon_x < ammo_left < ammo_right < weapon_visible_right
        assert 0.5 < (ammo_right - ammo_left) / (weapon_w * 45 / 64) < 0.65
    for _, dx, dy, dw, dh in draws:
        assert dx >= 0 and dy >= 0 and dx + dw <= width and dy + dh <= height
    print(f"{width}x{height}: radar rect {w}x{h}, visible {diameter_x}x{diameter_y} px; player HUD in bounds")
    return canvas


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--detail-output", type=Path)
    args = parser.parse_args()
    names = ("radardisc", "radar27", "radar28", "radar35", "radar36", "fist", "weapon_beretta", "hudnumbers", "pagertext",
             "bar_inside1", "bar_inside1dark", "bar_inside2", "bar_inside2dark", "bar_outline")
    assets = {name: Image.open(ASSETS / f"{name}.png").convert("RGBA") for name in names}
    lua = load_lua()
    sheet = Image.new("RGB", (1140, 930), "#10181d")
    labels = ImageDraw.Draw(sheet)
    for index, (width, height) in enumerate(SIZES):
        view = render_view(lua, assets, width, height)
        view.thumbnail((550, 262), Image.Resampling.LANCZOS)
        left, top = 10 + index % 2 * 570, 10 + index // 2 * 310
        labels.text((left, top), f"{width} x {height}", fill="white")
        sheet.paste(view, (left, top + 27))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(args.output)
    render_view(lua, assets, 1920, 1080, submerged=True)
    print("Oxygen and armour bar colors verified")
    if args.detail_output:
        frame = render_view(lua, assets, 1920, 1080, armed=True)
        frame.crop((1540, 15, 1900, 242)).save(args.detail_output)


if __name__ == "__main__":
    main()
