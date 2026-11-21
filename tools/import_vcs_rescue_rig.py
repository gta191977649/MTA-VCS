"""Convert the VCS Air Rescue rope end from the original PS2 disc."""
import argparse
from collections import Counter
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "mods/deathmatch/resources/[mission]/mission/assets"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    props = parser.add_mutually_exclusive_group()
    props.add_argument("--bucket", action="store_true", help="Convert the Fire Copter type-3 bucket")
    props.add_argument("--lifesaver", action="store_true", help="Convert the Beach Patrol life preserver")
    parser.add_argument("--converter", type=Path, default=ROOT.parent / "mta_map_tools")
    args = parser.parse_args()
    sys.path.insert(0, str(args.converter))
    from convert import StreamAssets, make_model
    from modelnames import NameRegistry
    from ps2 import GameData, Instance, u32
    from renderware import txd

    game = GameData(args.disc)
    # CRope::CreatePickupObject reads the type-4 model from ModelIndices + 0x8e.
    indices = u32(game.data, 0x5c)
    offset = indices + (0x8c if args.bucket else 0x8e)
    model = int.from_bytes(game.data[offset:offset+2], "little")
    name = "ndc_helibucket" if args.bucket else "ndc_helirescuerig"
    expected = 0x65252501 if args.bucket else 0xD7BD7ED2
    if args.lifesaver:
        model, name, expected = 7375, "dr_lifesaver", 0x95F9ADAF
    if u32(game.data, game.model(model)+8) != expected:
        raise ValueError(f"Unexpected {name} model name hash in GAME.DTZ")
    shared = u32(game.data, u32(game.data, u32(game.data, 96))+2*28)
    matrix = (1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
    instance = Instance(0,4,-1,0,(),matrix,False)
    parts = {0: (instance,matrix,(model,matrix,0),None)}
    report = dict(missing_prop_textures={}, empty_render_models=[], effects=Counter(), surfaces=Counter())
    with (args.disc / "GTA3PS2.IMG").open("rb") as archive:
        assets = StreamAssets(game, archive, model, report, shared_dictionary=shared)
        result = make_model(game, ((0,0),-1,model,"high"), parts, assets, {}, report, NameRegistry(), name)
        _, _, _, mesh, _, bounds, _, textures, _ = result
        if not textures or report["missing_prop_textures"]:
            raise ValueError("Incomplete rescue rig texture dictionary")
        OUTPUT.mkdir(exist_ok=True)
        (OUTPUT / (name+".dff")).write_bytes(mesh)
        (OUTPUT / (name+".txd")).write_bytes(txd([assets.hashes[t] for t in textures]))
        print(f"Converted model {model} ({name}), {len(textures)} materials, bounds {bounds}")


if __name__ == "__main__":
    main()
