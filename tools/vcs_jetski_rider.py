"""Bake the US PS2 BIKES rider tracks for MTA's post-animation bone API."""

import argparse
import json
from pathlib import Path
import struct
import zlib

from import_vcs_traffic import GAME_DTZ, verify_file
from vcs_traffic_animations import GROUP, block_trees, multiply, name_of, read_animation, rotation_sampler, u32


OUTPUT = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[model]/vcs_vehicle/data/jetski_rider.json"
PARENT = {0: None, 1: 0, 2: 1, 3: 2, 4: 3, 5: 4, 21: 3, 31: 3, 41: 1, 51: 1}
for shoulder in (21, 31, 41, 51):
    for i in range(1, 5 if shoulder < 40 else 3):
        PARENT[shoulder+i] = shoulder+i-1
ASSOCIATIONS = {0xD0: "jetski_on", 0xD1: "jetski_on", 0xD2: "jetski_back",
                0xD3: "bikes_ride", 0xD4: "jetski_getoff", 0xD5: "jetski_getoff",
                0xBD: "bikes_left", 0xBE: "bikes_right", 0xBF: "bikes_back",
                0xC0: "bikes_fwd", 0xCC: "bikes_passenger"}


def inverse(q):
    x, y, z, w = q
    return -x, -y, -z, w


def absolute(pose):
    result = {}
    for bone in sorted(pose):
        parent = PARENT[bone]
        result[bone] = multiply(result[parent], pose[bone]) if parent is not None else pose[bone]
    return result


def mirror(pose, neutral):
    # Reflect the animated rotation around the rider's sagittal plane, using
    # the opposite limb's neutral basis. The two arms have distinct bind axes.
    world = absolute(pose)
    target = {}
    for bone, q in world.items():
        other = bone + 10 if 21 <= bone <= 25 or 41 <= bone <= 43 else bone - 10 if bone >= 31 else bone
        x, y, z, w = multiply(q, inverse(neutral[bone]))
        target[other] = multiply((x, -y, -z, w), neutral[other])
    return {bone: multiply(inverse(target[PARENT[bone]]), q) if PARENT[bone] is not None else q
            for bone, q in target.items()}


def bake(disc):
    image = zlib.decompress(verify_file(disc, "PS2/GAME.DTZ", GAME_DTZ))
    manager = u32(image, 0x80)
    assoc = manager + 200 * GROUP.size
    group, block_name, first, count = GROUP.unpack_from(image, manager + 3 * GROUP.size)
    assert name_of(group) == name_of(block_name) == "bikes"
    for index, expected in ASSOCIATIONS.items():
        record = assoc + index * 56
        assert first <= index < first + count and name_of(image[record+4:record+48]) == expected
        assert bool(u32(image, record + 52) & 0x8000) == (index in (0xD1, 0xD5))
    trees, blocks, _, count = struct.unpack_from("<4I", image, assoc + 990 * 56 + 12)
    index = next(i for i in range(count) if name_of(image[blocks+i*48:blocks+i*48+20]) == "bikes")
    data, offsets = block_trees(image, disc / "GTA3PS2.IMG", index, blocks + index*48, trees)
    tracks = {name: read_animation(data, off, upper_body=name == "jetski_back") for off in offsets
              if (name := name_of(data[off+4:off+28])) in ASSOCIATIONS.values()}
    neutral = absolute({b: frames[0][1] for b, frames in tracks["bikes_ride"].items()})
    out = {}
    for name, channels in tracks.items():
        samplers = {bone: rotation_sampler(frames) for bone, frames in channels.items()}
        duration = max(frames[-1][0] for frames in channels.values())
        for flip in (False, True) if name in ("jetski_on", "jetski_getoff") else (False,):
            poses = []
            for tick in range(0, duration+1, 2):
                pose = {b: sample(tick) for b, sample in samplers.items()}
                if flip:
                    pose = mirror(pose, neutral)
                poses.append([round(component * 4096) for bone in sorted(pose) for component in pose[bone]])
            clip = {"bones": sorted(channels), "frames": poses}
            if name in ("bikes_ride", "bikes_left", "bikes_right", "bikes_fwd", "bikes_back"):
                root = channels[0]
                positions = []
                for tick in range(0, duration+1, 2):
                    right = next((frame for frame in root if frame[0] >= tick), root[-1])
                    left = next(frame for frame in reversed(root) if frame[0] <= tick)
                    t = (tick-left[0]) / (right[0]-left[0]) if right[0] > left[0] else 0
                    positions.append([round((a+(b-a)*t)*4096) for a,b in zip(left[2], right[2])])
                clip["root"] = positions
            out[name + ("_mirror" if flip else "")] = clip
    return (json.dumps(out, separators=(",", ":")) + "\n").encode()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--disc", required=True, type=Path)
    args = parser.parse_args()
    OUTPUT.write_bytes(bake(args.disc))
