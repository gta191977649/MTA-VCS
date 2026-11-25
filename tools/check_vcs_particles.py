"""Verify the installed particle tables and atlas against the unpacked USA PS2 disc."""

import argparse
import re
import struct
import tempfile
from pathlib import Path

from import_vcs_particles import RESOURCE, extract
from import_vcs_traffic import PS2_EXECUTABLE, verify_file


def raster_binding(exe, address):
    # SLUS-21590 at 001E8AEC dispatches through a 90-entry jump table.
    # The case places a raster-array address in v0 (a0 for BIRD_FRONT).
    # Empty cases skip the store or explicitly store zero.
    while 0x1E8AF4 <= address < 0x1E8E20:
        instruction, = struct.unpack_from("<I", exe, address - 0xFF000)
        if instruction == 0xACA0007C:  # sw zero, 0x7c(a1)
            break
        if instruction >> 26 == 9 and (instruction >> 16 & 31) in (2, 4) and instruction & 0x8000:
            return f"{instruction & 0xFFF:03x}"
        address += 4
    return "---"


def check(disc):
    exe = verify_file(disc, "SLUS_215.90", PS2_EXECUTABLE)
    data = (RESOURCE / "pipeline/particleData.lua").read_text()
    rows = re.findall(r'^define\((\d+),"([^"]+)","([^"]+)"', data, re.MULTILINE)
    if [int(row[0]) for row in rows] != list(range(90)):
        raise ValueError("Expected particle IDs 0 through 89 in disc order")
    targets = struct.unpack_from("<90I", exe, 0x4AAE50 - 0xFF000)
    for (index, name, installed), target in zip(rows, targets):
        original = raster_binding(exe, target)
        if original != installed:
            raise ValueError(f"{index} {name}: installed raster {installed}, executable selects {original}")
    with tempfile.TemporaryDirectory() as temp:
        output = Path(temp)
        extract(disc, output)
        for asset in ("pipeline/particleData.lua", "txd/vcs-particles.png"):
            if (output / asset).read_bytes() != (RESOURCE / asset).read_bytes():
                raise ValueError(f"{asset} differs from the regenerated disc asset")
    print("All 90 raster selections match the PS2 dispatch. Definitions, frame lists and atlas match the disc import.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    check(parser.parse_args().disc)
