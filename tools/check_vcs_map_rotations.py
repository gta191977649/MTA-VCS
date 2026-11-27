"""Compare shipped MTA world-space vertices with the US PS2 map and prop meshes."""

import argparse
import math
import mmap
import re
import struct
import sys
import xml.etree.ElementTree as ET
from collections import Counter, defaultdict
from contextlib import ExitStack
from functools import lru_cache
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
DISC = Path(r"D:\ps2_game\Grand Theft Auto - Vice City Stories (USA)")
RESOURCE = ROOT / "mods/deathmatch/resources/[vcs]/vcs"


def transform_ps2(points, matrix):
    frame = np.asarray(matrix).reshape(4, 4)
    return points @ frame[:3, :3] + frame[3, :3]


def transform_mta(points, rotation, position):
    # CPlaceable::SetOrientation / CMatrix::SetRotate. Compose actual rotations
    # independently of the converter's basis extraction and inverse vertex bake.
    x, y, z = map(math.radians, rotation)
    axis_x = [[1, 0, 0], [0, math.cos(x), -math.sin(x)], [0, math.sin(x), math.cos(x)]]
    axis_y = [[math.cos(y), 0, math.sin(y)], [0, 1, 0], [-math.sin(y), 0, math.cos(y)]]
    axis_z = [[math.cos(z), -math.sin(z), 0], [math.sin(z), math.cos(z), 0], [0, 0, 1]]
    return points @ (np.asarray(axis_z) @ axis_x @ axis_y).T + position


def same_cloud(points, reference):
    # DFF seams and degenerate strip vertices can repeat the same position.
    # Look in overlapping 4 mm cells so a rounded float on a cell boundary
    # still matches. Check both directions to catch missing and extra vertices.
    if (
        np.max(abs(points.min(0) - reference.min(0))) > 0.004
        or np.max(abs(points.max(0) - reference.max(0))) > 0.004
    ):
        return False
    found = np.zeros(len(points), bool)
    covered = np.zeros(len(reference), bool)

    def keys(vertices, shift):
        xyz = np.floor(vertices * 250 + shift).astype(np.int64)
        return xyz[:, 0] + (xyz[:, 1] << 22) + (xyz[:, 2] << 44)

    for index in range(8):
        shift = np.array([(index >> axis) & 1 for axis in range(3)]) * 0.5
        left, right = keys(points, shift), keys(reference, shift)
        found |= np.isin(left, right)
        covered |= np.isin(right, left)
        if found.all() and covered.all():
            return True
    return False


def matches_basis(actual, matrix):
    native = np.asarray(matrix).reshape(4, 4)[:3, :3]
    basis = native / np.linalg.norm(native, axis=1)[:, None]
    if np.linalg.det(basis) < 0:
        basis[2] *= -1
    return np.max(abs(actual - basis)) < 0.00001


def indexed_meshes(root, stack, index_img, chunks):
    entries = {}
    for path in sorted((root / "imgs").glob("dff*.img")):
        archive = stack.enter_context(path.open("rb"))
        for key, (offset, length) in index_img(path).items():
            if key in entries:
                raise ValueError(f"Duplicate IMG entry {key}")
            entries[key] = archive, offset, length

    @lru_cache(maxsize=512)
    def vertices(name):
        archive, offset, size = entries[name + ".dff"]
        archive.seek(offset)
        data = archive.read(size)
        end = 12 + struct.unpack_from("<I", data, 4)[0]
        children = {k: (a, b) for k, a, b in chunks(data, 12, end)}
        (frame,) = (a for k, a, b in chunks(data, *children[14]) if k == 1)
        matrix = np.frombuffer(data, "<f4", 12, frame + 4).reshape(4, 3)
        if struct.unpack_from("<I", data, frame)[0] != 1:
            raise ValueError(f"Unexpected frame hierarchy in {name}")
        parts = []
        for k, a, b in chunks(data, *children[26]):
            if k != 15:
                continue
            (geo,) = (start for k, start, end in chunks(data, a, b) if k == 1)
            _, faces, count, morphs = struct.unpack_from("<4I", data, geo)
            if morphs != 1:
                raise ValueError(f"Unexpected morph target count in {name}")
            offset = geo + 16 + 12 * count + 8 * faces + 24
            points = np.frombuffer(data, "<f4", count * 3, offset).reshape(-1, 3)
            parts.append(points.astype(float) @ matrix[:3] + matrix[3])
        return np.concatenate(parts)

    return vertices


def coordinate_key(model, point):
    return (model, *[round(float(v), 6) for v in point])


def source_positions(meshes):
    return np.concatenate([np.asarray(points, dtype=float) for _, (points, _, _) in meshes])


def verify(root, disc, converter):
    sys.path.insert(0, str(converter))
    from convert import linked_models, local_rotation
    from leeds import damaged_atomic, geometry, simple_model
    from modeldata import traffic_light_spec
    from portals import shop_routes
    from ps2 import LEVELS, MALL_SCOPE, GameData, Level, interior_dimension
    from verify import chunks, index_img

    # Exercise both poles and a reflected, nonuniformly scaled source with
    # off-axis test vertices. A normalized matrix alone cannot encode reflection.
    test = np.array([[2.0, 3.0, 5.0], [-3.0, 7.0, 11.0]])
    for pitch in (90, -90, 89.99, -89.99, 36):
        frame = np.eye(4)
        frame[:3, :3] = transform_mta(np.eye(3), (pitch, 31, 54), (0, 0, 0))
        for sign in (1, -1):
            source = frame.copy()
            source[:3, :3] *= np.array([[2.0], [3.0], [sign * 4.0]])
            basis, angles = local_rotation(source.ravel())
            expected = transform_ps2(test, source)
            baked = expected @ np.array(basis).T
            assert np.allclose(transform_mta(baked, angles, (0, 0, 0)), expected, atol=0.00001)

    game = GameData(disc)
    entities = {e: (m, mat) for e, m, mat, _ in game.entities()}
    links = linked_models(game)
    candidates = defaultdict(list)
    counts = Counter()
    failures = []
    with ExitStack() as stack:
        dff = indexed_meshes(root, stack, index_img, chunks)
        archive = stack.enter_context((disc / "GTA3PS2.IMG").open("rb"))
        levels = {name: Level(disc, name) for name in LEVELS}
        libraries = {}
        for level_id, (name, level) in enumerate(levels.items(), 1):
            handle = stack.enter_context(level.img.open("rb"))
            mapped = stack.enter_context(mmap.mmap(handle.fileno(), 0, access=mmap.ACCESS_READ))
            libraries[name] = level, mapped, level.resources()
            origins, interiors = level.sector_origins(), level.interior_sectors()
            groups = defaultdict(dict)
            for sector, data in level.sectors():
                if sector >= level.valid_sector_count():
                    break
                if sector in interiors:
                    x, y, slot, state = interiors[sector]
                    origin = (-2337.5 + 125 * x - 62.5 * (y % 2), -1945.875 + 108.25 * y)
                    scope = (1, interior_dimension(name, slot, state))
                else:
                    origin = origins[sector]
                    scope = MALL_SCOPE if name == "MALL" else (0, 0)
                for inst in level.instances(sector, data):
                    entity, model = links[(level_id << 16) | inst.identity]
                    mode = (
                        ("superlod", "underwater", "lod")[inst.render_pass]
                        if inst.render_pass < 3
                        else "high"
                    )
                    matrix = list(inst.matrix)
                    matrix[12] += origin[0]
                    matrix[13] += origin[1]
                    group = groups[(scope, entity, model, mode)]
                    previous = group.setdefault(inst.geometry, matrix)
                    if not np.allclose(
                        np.array(previous).reshape(4, 4)[:, :3],
                        np.array(matrix).reshape(4, 4)[:, :3],
                        rtol=0,
                        atol=0.001,
                    ):
                        raise ValueError(
                            f"{name}/{inst.identity}/{inst.geometry}: conflicting repeated-sector transforms"
                        )
            for (_, entity, model, _), parts in groups.items():
                primary = next(iter(parts.values()))
                for frame in (primary, entities.get(entity, (None, primary))[1]):
                    key = coordinate_key(model, frame[12:15])
                    record = (name, parts, tuple(frame))
                    if record not in candidates[key]:
                        candidates[key].append(record)

        @lru_cache(maxsize=256)
        def mesh(name, rid):
            level, mapped, sources = libraries[name]
            data, pointer = level.resource_buffer(mapped, sources[rid])
            return source_positions(geometry(data, pointer))

        @lru_cache(maxsize=400)
        def prop(model, damaged):
            raw = game.stream_asset(archive, model)
            if raw[:4] != b"ldm\0":
                return None
            return source_positions(simple_model(raw, damaged_atomic(raw, model) if damaged else None))

        prop_frames = defaultdict(list)
        palms = {}
        for entity, (model, frame) in entities.items():
            position = np.array(frame[12:15])
            if (
                model == 574
                and 300 < position[0] < 600
                and 900 < position[1] < 1400
                and -205 < position[2] < -150
            ):
                palms[coordinate_key(model, position[:2])] = frame
            signal = traffic_light_spec(game, model)
            if signal:
                forward = np.array(frame[4:7])
                position += forward / np.linalg.norm(forward) * signal[1] / 128
            prop_frames[coordinate_key(model, position)].append(frame)
        # The garage controller deploys working shutters in the open pose.
        # Use its authored lift, allowing the same check on the initial export.
        garage_lifts = {}
        garage_data = (ROOT / "mods/deathmatch/resources/[module]/garage/catalog.lua").read_text()
        for label, coords, lift in re.findall(r'"(\w+)",\s*\{([^{}]+)\},\s*([\d.]+)', garage_data):
            garage_lifts[label] = (tuple(float(v) for v in coords.split(",")), float(lift))
        # SCM places shop furniture independently of the world's building pool.
        script = (disc / "MAIN.txt").read_text(encoding="utf-8", errors="replace")
        for route in shop_routes(disc, script, levels):
            for item in route["furniture"]:
                x, y, z, heading = item["transform"]
                frame = np.eye(4)
                frame[:3, :3] = transform_mta(np.eye(3), (0, 0, heading), (0, 0, 0))
                frame[3, :3] = (x, y, z)
                prop_frames[coordinate_key(item["model"], (x, y, z))].append(frame.ravel())

        for path in sorted(root.glob("zones/*/*.map")):
            defs = {e.get("id"): e for e in ET.parse(path.with_suffix(".definition")).getroot()}
            for row in ET.parse(path).getroot():
                pos = tuple(float(row.get("pos" + a)) for a in "XYZ")
                rot = tuple(float(row.get("rot" + a)) for a in "XYZ")
                orientation = transform_mta(np.eye(3), rot, (0, 0, 0))
                variants = [(row.get("id"), False)]
                if row.get("damageModel"):
                    variants.append((row.get("damageModel"), True))
                for key_id, damaged in variants:
                    definition = defs[key_id]
                    model = int(definition.get("sourceModelId"))
                    key = coordinate_key(model, pos)
                    observed = transform_mta(dff(definition.get("dff")), rot, pos)
                    valid = False
                    for name, parts, frame in candidates.get(key, ()):
                        if not matches_basis(orientation, frame):
                            continue
                        reference = np.concatenate(
                            [transform_ps2(mesh(name, rid), mat) for rid, mat in parts.items()]
                        )
                        if same_cloud(observed, reference):
                            valid = True
                            break
                    if not valid:
                        frames = prop_frames.get(key, [])
                        # The converter seats the original mall palms on the planter COL.
                        if path.stem == "mall" and coordinate_key(model, pos[:2]) in palms:
                            frame = list(palms[coordinate_key(model, pos[:2])])
                            frame[14] = pos[2]
                            frames = [frame]
                        if key_id in garage_lifts:
                            closed, lift = garage_lifts[key_id]
                            if np.allclose(
                                pos, (closed[0], closed[1], closed[2] + lift), rtol=0, atol=0.00001
                            ):
                                frames = []
                                for source in prop_frames[coordinate_key(model, closed)]:
                                    frame = list(source)
                                    frame[14] += lift
                                    frames.append(frame)
                        for frame in frames:
                            points = prop(model, damaged)
                            if (
                                matches_basis(orientation, frame)
                                and points is not None
                                and same_cloud(observed, transform_ps2(points, frame))
                            ):
                                valid = True
                                break
                    if not valid:
                        failures.append((path.stem, key_id, model, pos, rot))
                    counts["placements" if not damaged else "damaged variants"] += 1
                    counts["DFF vertices"] += len(observed)
        if failures:
            raise ValueError(f"{len(failures)} world-transform mismatches: {failures[:20]}")
    print("Verified", ", ".join(f"{n:,} {k}" for k, n in counts.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource", type=Path, default=RESOURCE)
    parser.add_argument("--disc", type=Path, default=DISC)
    parser.add_argument("--converter", type=Path, default=ROOT.parent / "mta_map_tools")
    args = parser.parse_args()
    verify(args.resource, args.disc, args.converter)
