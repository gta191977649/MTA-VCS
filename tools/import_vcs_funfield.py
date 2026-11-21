"""Convert the original US PS2 Ferris carriage, collision and rider clips."""
import argparse
from collections import Counter
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import zlib

from import_vcs_traffic import GAME_DTZ, PS2_EXECUTABLE, verify_file
from vcs_traffic_animations import GROUP, block_trees, name_of, read_animation, rotation_sampler, u32, write_ifp

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("converter", type=Path)
    parser.add_argument("--map-tools", type=Path, default=ROOT.parent / "mta_map_tools")
    parser.add_argument("--output", type=Path, default=ROOT / "mods/deathmatch/resources/[feature]/funfield/assets")
    args = parser.parse_args()
    verify_file(args.disc, "SLUS_215.90", PS2_EXECUTABLE)
    game = zlib.decompress(verify_file(args.disc, "PS2/GAME.DTZ", GAME_DTZ))
    sys.path.insert(0, str(args.map_tools.resolve()))
    from modeldata import serialize_collision, load_collisions
    from ps2 import GameData

    models = u32(game, 0x3C)
    model = u32(game, models + 7069 * 4)
    streaming = u32(game, 0x7C)
    entries = u32(game, streaming + 0xC8)
    textures = u32(game, streaming + 8)
    texture_slot = struct.unpack_from("<h", game, model + 0x1E)[0]
    outputs = {}
    manifest = {"edition": "SLUS-21590 USA v1.00", "model": 7069,
                "executableSha256": PS2_EXECUTABLE, "gameDtzSha256": GAME_DTZ,
                "animations": {}, "assets": {}}
    with tempfile.TemporaryDirectory(prefix="vcs-funfield-assets-") as folder:
        work = Path(folder)
        (work / "game.dat").write_bytes(game)
        with (args.disc / "GTA3PS2.IMG").open("rb") as archive:
            for index, source_ext, target_ext in ((7069, "mdl", "dff"), (textures + texture_slot, "tex", "txd")):
                sector, count = struct.unpack_from("<II", game, entries + index * 24 + 16)
                archive.seek(sector * 2048)
                raw = archive.read(count * 2048)
                source = work / ("carriage." + source_ext)
                target = work / ("carriage." + target_ext)
                source.write_bytes(raw)
                result = subprocess.run([str(args.converter.resolve()), "-v", "36003", "-g",
                                         str(work / "game.dat"), str(source), str(target)],
                                        capture_output=True, timeout=60)
                if result.returncode or not target.exists():
                    raise RuntimeError(result.stderr.decode(errors="replace"))
                outputs[target.name] = target.read_bytes()
                manifest["assets"][target.name] = {"sector": sector, "sectors": count,
                                                   "sourceSha256": hashlib.sha256(raw).hexdigest()}
    col = serialize_collision("ferris_carriage", game, u32(game, model + 0x14), Counter())
    if not col:
        source_game = GameData(args.disc)
        with (args.disc / "GTA3PS2.IMG").open("rb") as archive:
            candidates = load_collisions(source_game, archive).get(7069, ())
        if not candidates:
            raise ValueError("Original carriage has no collision")
        data, pointer, slot = candidates[0]
        col = serialize_collision("ferris_carriage", data, pointer, Counter())
        manifest["collisionStream"] = slot
    outputs["carriage.col"] = col
    manager = u32(game, 0x80)
    associations = manager + 200 * GROUP.size
    trees, blocks = struct.unpack_from("<II", game, associations + 990 * 56 + 12)
    count = u32(game, associations + 990 * 56 + 24)
    ped_block = next(i for i in range(count) if name_of(game[blocks+i*48:blocks+i*48+20]) == "ped")
    data, addresses = block_trees(game, args.disc / "GTA3PS2.IMG", ped_block, blocks+ped_block*48, trees)
    offsets = {name_of(data[a + 4:a + 28]): a for a in addresses}
    animations = {}
    for index in (156, 164):
        name = name_of(game[associations + index * 56 + 4:associations + index * 56 + 48])
        animations[name] = read_animation(data, offsets[name])
        manifest["animations"][str(index)] = name
    # The native hands-up association is partial. MTA's custom-animation task
    # replaces the whole pose, so retain the seat's pelvis and leg chains.
    gesture={bone:list(frames) for bone,frames in animations["handsup"].items()}
    end_tick=max(frames[-1][0] for frames in gesture.values())
    for bone in (0,1,41,42,43,44,51,52,53,54):
        if bone in animations["seat_idle"]:
            _,rotation,position=animations["seat_idle"][bone][0]
            gesture[bone]=[(0,rotation,position),(end_tick,rotation,position)]
    animations["seat_handsup"]=gesture
    manifest["derivedAnimations"]={"seat_handsup":"handsup upper body with seat_idle pelvis and legs"}
    outputs["riders.ifp"] = write_ifp(animations)
    for clip,filename in (("seat_idle","seat_pose.json"),("seat_handsup","greeting_pose.json")):
        tracks=animations[clip]
        duration=max(frames[-1][0] for frames in tracks.values())
        samplers={bone:rotation_sampler(frames) for bone,frames in tracks.items()}
        bones=sorted(tracks)
        pose={"bones":bones,"frames":[],"root":[],"rate":30}
        for tick in range(0,duration+1,2):
            pose["frames"].append([round(v*4096) for bone in bones for v in samplers[bone](tick)])
            root=tracks[0]
            left=next(f for f in reversed(root) if f[0]<=tick)
            right=next((f for f in root if f[0]>=tick),root[-1])
            t=(tick-left[0])/(right[0]-left[0]) if right[0]>left[0] else 0
            pose["root"].append([a+(b-a)*t for a,b in zip(left[2],right[2])])
        outputs[filename]=(json.dumps(pose,separators=(",",":"))+"\n").encode()
    args.output.mkdir(parents=True, exist_ok=True)
    for name, content in outputs.items():
        (args.output / name).write_bytes(content)
        manifest["assets"].setdefault(name, {}).update(size=len(content), sha256=hashlib.sha256(content).hexdigest())
    (args.output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
