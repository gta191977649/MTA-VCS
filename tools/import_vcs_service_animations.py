"""Build the Air Rescue and Beach Patrol animation bank from the VCS USA disc."""
import argparse
import struct
import zlib
from pathlib import Path

from import_vcs_traffic import GAME_DTZ, verify_file
from vcs_traffic_animations import GROUP, TREE, block_trees, name_of, read_animation, u32, write_ifp

ASSETS = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission/assets"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    args = parser.parse_args()
    image = zlib.decompress(verify_file(args.disc, "PS2/GAME.DTZ", GAME_DTZ))
    manager = u32(image, 0x80)
    associations = manager + 200 * GROUP.size
    trees, blocks, _, count = struct.unpack_from("<4I", image, associations + 990 * 56 + 12)
    names = {name_of(GROUP.unpack_from(image, manager + group * GROUP.size)[1]) for group in (78, 87)}
    names.add("swim")
    clips = {}
    for index in range(count):
        address = blocks + index * 48
        name = name_of(image[address:address + 20])
        if name not in names:
            continue
        data, entries = block_trees(image, args.disc / "GTA3PS2.IMG", index, address, trees)
        for entry in entries:
            _, raw, _, duration = TREE.unpack_from(data, entry)
            clip = name_of(raw)
            if name == "swim" and clip != "swim_idle":
                continue
            clips[clip] = (round(duration * 60), read_animation(data, entry, upper_body=True))

    # The original overlays upper-body tracks on a tread-water or standing base.
    # Bake the missing tracks so MTA can evaluate a single full-body association.
    for clip, base in (("oj_swim_wave", "swim_idle"), ("amb_ls_thw_float", "amb_ls_float"),
                       ("amb_ls_thw_floatl", "amb_ls_float")):
        end, overlay = clips[clip]
        base_end, base_tracks = clips[base]
        for bone, frames in base_tracks.items():
            if bone not in overlay:
                overlay[bone] = [(round(tick * end / base_end), rotation, translation)
                                 for tick, rotation, translation in frames]

    # Mission swimmers are already placed relative to the water surface. Keep
    # the breathing motion relative to the first frame of the swim cycle.
    root = clips["oj_swim_wave"][1][0]
    base_z = root[0][2][2]
    clips["oj_swim_wave"][1][0] = [(tick, rotation, (x, y, z - base_z))
                                     for tick, rotation, (x, y, z) in root]

    bank = {name: tracks for name, (_, tracks) in clips.items() if name not in {"swim_idle", "amb_ls_float"}}
    (ASSETS / "service_animations.ifp").write_bytes(write_ifp(bank, b"vcs_service"))


if __name__ == "__main__":
    main()
