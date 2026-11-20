"""Extract the USA PS2 boat curtain and airborne splash rasters for SkyGfx."""

import argparse
from pathlib import Path
import struct
import zlib

from import_vcs_frontend import encode_png
from import_vcs_traffic import GAME_DTZ, PS2_EXECUTABLE, verify_file, write_atomic
from vcs_model_assets import stored_vehicle_raster


OUTPUT = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[graphic]/skygfx/txd"
PARTICLE_DICTIONARY = 0x761F0
# SLUS_215.90 VA of lookup name and inflated GAME.DTZ RslTexture offset.
# 001E81C8 binds particles 0x2C and 0x2D. The wake curtain separately
# looks up boatwake; the water-surface trail uses the existing waterwake.
TEXTURES = {
    "carsplash_01": (0x486D30, 0x798F0),
    "carsplash_02": (0x486D3E, 0x77780),
    "carsplash_03": (0x486D4C, 0x79060),
    "carsplash_04": (0x486D5A, 0x790C0),
    "boatwake2": (0x4AAD00, 0x7A750),
    "boatwake": (0x4AFE28, 0x77D80),
}


def extract(disc, output):
    executable = verify_file(disc, "SLUS_215.90", PS2_EXECUTABLE)
    game = zlib.decompress(verify_file(disc, "PS2/GAME.DTZ", GAME_DTZ))
    output.mkdir(parents=True, exist_ok=True)
    for name, (address, offset) in TEXTURES.items():
        label = name.encode("ascii") + b"\0"
        if executable[address - 0xFF000:address - 0xFF000 + len(label)] != label:
            raise ValueError(f"Unexpected executable texture name at {address:#x}")
        if struct.unpack_from("<I", game, offset + 4)[0] != PARTICLE_DICTIONARY:
            raise ValueError(f"{name} has the wrong PS2 texture dictionary")
        width, height, rgba = stored_vehicle_raster(game, name, offset)
        write_atomic(output / f"vcs-{name}.png", encode_png(width, height, rgba))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path, help="extracted SLUS-21590 disc directory")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    extract(args.disc, args.output)
