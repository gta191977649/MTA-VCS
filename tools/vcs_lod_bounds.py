"""Check or repair map visibility bounds for the native HD-to-LOD handoff."""

import argparse
import json
from math import cos, dist, radians, sin
from pathlib import Path
import struct
import tempfile
import xml.etree.ElementTree as ET

from vcs_model_assets import chunks
from vcs_vehicle_ground import read_archive


WORLD = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[vcs]/vcs"
HEADER = struct.Struct("<10f")


def placement_frame(element):
    x, y, z = (radians(float(element.attrib["rot" + a])) for a in "XYZ")
    sx, sy, sz, cx, cy, cz = sin(x), sin(y), sin(z), cos(x), cos(y), cos(z)
    basis = ((cz*cy - sz*sx*sy, sz*cy + cz*sx*sy, -cx*sy),
             (-sz*cx, cz*cx, sx),
             (cz*sy + sz*sx*cy, sz*sy - cz*sx*cy, cx*cy))
    return basis, tuple(float(element.attrib["pos" + axis]) for axis in "XYZ")


def relative_transform(source, target):
    source_axes, source_origin = placement_frame(source)
    target_axes, target_origin = placement_frame(target)

    def dot(u, v):
        return sum(x * y for x, y in zip(u, v))

    delta = tuple(x - y for x, y in zip(source_origin, target_origin))
    rows = [tuple(dot(axis, s) for s in source_axes) + (dot(axis, delta),) for axis in target_axes]

    def transform(point):
        x, y, z = point
        return tuple(a*x + b*y + c*z + translation for a, b, c, translation in rows)

    return transform


def mesh_bounds(data):
    # The converter bakes world geometry into one identity-frame atomic.
    span = (0, len(data))
    for target in (0x10, 0x1A, 0x0F, 1):
        (span,) = [(a, b) for kind, a, b in chunks(data, *span) if kind == target]
    start, end = span
    flags, faces, vertices, morphs = struct.unpack_from("<4I", data, start)
    if flags != 0x1004E or morphs != 1 or not vertices:
        raise ValueError("Unsupported VCS map geometry")
    sphere = start + 16 + 12 * vertices + 8 * faces
    if sphere + 24 + vertices * 12 != end:
        raise ValueError("Invalid VCS map vertex range")
    center_radius = struct.unpack_from("<4f", data, sphere)
    points = set(struct.iter_unpack("<3f", data[sphere + 24:end]))
    return center_radius, points


def check_downtown(rows, models, pairs):
    # Tower 56 is listed twice as normal scenery on the PS2. Its simplified
    # shell should participate in the same handoff as the other skyline towers.
    towers = {"doontoon22": "lodntoon22", "doontoon39": "lodntoon39",
              "doontoon55": "lodntoon55", "doontoon56": "lodntoon56"}
    native = {(high.attrib["id"], low.attrib["id"]) for high, low, _, _ in pairs}
    for high, low in towers.items():
        if (high, low) not in native:
            raise ValueError(f"Missing Downtown tower LOD: {high}/{low}")
    if {float(models[low].attrib["lodDistance"]) for low in towers.values()} != {3500.0}:
        raise ValueError("Downtown tower 56 must use the long-distance skyline tier")

    # One PS2 atomic carries both antennae under tower 56's two columns of
    # red lights. Check its original frame and uninterrupted near/far coverage.
    masts = [row for _, row in rows if models[row.attrib["id"]].get("sourceModelId") == "3003"]
    if len(masts) != 1:
        raise ValueError("Expected one twin-antenna placement on Downtown tower 56")
    mast = masts[0]
    frame = tuple(float(mast.attrib[key]) for key in ("posX", "posY", "posZ", "rotX", "rotY", "rotZ"))
    if (mast.tag != "object" or mast.get("lowLOD") != "true"
            or any(mast.get(key) for key in ("lodParent", "uniqueID", "lodNear"))
            or (mast.get("interior"), mast.get("dimension")) != ("0", "0")
            or dist(frame, (-388.014648, 1181.741821, 259.264343, 0, 0, -19.516857)) > .001
            or models[mast.attrib["id"]].get("lodDistance") != models["lodntoon56"].get("lodDistance")):
        raise ValueError("Tower 56 antennae must cover the same skyline range as the tower")

    mall_gantry = False
    for path, row in rows:
        model = models[row.attrib["id"]]
        if model.get("sourceModelId") not in {"6468", "7940"}:
            continue
        pos = tuple(float(row.attrib["pos" + a]) for a in "XYZ")
        if row.get("dimension") == "0" and dist(pos, (-585.747, 1047.271, 190.754)) < 1:
            raise ValueError("DIAC5B's skyline background is visible during ordinary gameplay")
        if path.stem == "mall" and row.get("dimension") == "3090" and model.get("sourceModelId") == "7940":
            mall_gantry = True
    if not mall_gantry:
        raise ValueError("Missing original North Point Mall gantry")


def read_placements(root, fix):
    targets, children, models = {}, {}, {}
    rows, zones = [], {}
    for zone in (root / "eagleZones.txt").read_text().splitlines():
        zone = zone.strip()
        if not zone or zone.startswith("#"):
            continue
        path = root / "zones" / zone / zone
        for model in ET.parse(path.with_suffix(".definition")).getroot():
            models[model.attrib["id"]] = model
        map_path = path.with_suffix(".map")
        zones[map_path] = ET.parse(map_path)
        for row in zones[map_path].getroot():
            rows.append((map_path, row))
            if row.get("uniqueID") is None:
                continue
            parent = row.get("lodParent")
            group = children if parent else targets
            key = (row.get("interior"), row.get("dimension"), parent or row.attrib["id"], row.attrib["uniqueID"])
            if key in group:
                raise ValueError(f"Duplicate LOD placement {key} in {zone}")
            group[key] = row
    if children.keys() != targets.keys():
        raise ValueError(f"Unmatched LOD placements: {children.keys() ^ targets.keys()}")
    # Overlapping PS2 sectors sometimes yield multiple exported instances of
    # the same coarse geometry. A native owner already handles the near range.
    copies = {}
    for path, row in rows:
        if row.get("lodParent") or not (row.get("uniqueID") or row.get("lodNear")):
            continue
        key = (row.attrib["id"], row.get("interior"), row.get("dimension"),
               *(float(row.attrib[name]) for name in ("posX", "posY", "posZ", "rotX", "rotY", "rotZ")))
        copies.setdefault(key, []).append((path, row))
    edited = set()
    for placements in copies.values():
        if len(placements) < 2:
            continue
        native = [pair for pair in placements if pair[1].get("uniqueID")]
        ranges = [pair for pair in placements if pair[1].get("lodNear")]
        if len(native) > 1 or len(native) + len(ranges) != len(placements):
            raise ValueError(f"Ambiguous native LOD ownership for {placements[0][1].attrib}")
        if not fix:
            raise ValueError(f"Duplicate coarse placement: {placements[0][1].attrib}")
        # For an unpaired mesh the earliest fade already renders this geometry.
        if not native:
            ranges.remove(min(ranges, key=lambda entry: float(entry[1].attrib["lodNear"])))
        for path, redundant in ranges:
            zones[path].getroot().remove(redundant)
            edited.add(path)
    pairs = []
    for key, high in children.items():
        low = targets[key]
        hd, lod = models[high.attrib["id"]], models[low.attrib["id"]]
        if (hd.get("timeIn"), hd.get("timeOut")) != (lod.get("timeIn"), lod.get("timeOut")):
            # The daylight Downtown gate has no time restriction on its
            # small HD proxy. Its far facade still owns its own schedule.
            window_detail = (high.attrib["id"].endswith("_lod_detail")
                             and high.get("uniqueID") == "window_" + lod.attrib["sourceModelId"])
            if (high.tag != "object" or low.tag != "object"
                    or (hd.get("timeIn") is None and not window_detail) or lod.get("timeIn") is None
                    or any(abs(float(high.get("pos" + a)) - float(low.get("pos" + a))) > 0.01 for a in "XYZ")):
                raise ValueError(f"Incompatible LOD time windows for {key}")
        pairs.append((high, low, hd.attrib["col"] + ".col", lod.attrib["dff"] + ".dff"))
    check_downtown(rows, models, pairs)
    return pairs, zones, edited


def save_placements(root, zones, edited, link_count):
    for path in edited:
        ET.indent(zones[path], space="    ")
        zones[path].write(path, encoding="utf-8", xml_declaration=True)
    report_path = root / "conversion-report.json"
    if report_path.is_file():
        report = json.loads(report_path.read_text(encoding="utf8"))
        report["lod_links"] = link_count
        report["range_lods"] = sum(1 for tree in zones.values() for e in tree.getroot() if e.get("lodNear"))
        for path, tree in zones.items():
            if path.stem in report["zones"]:
                report["zones"][path.stem]["placements"] = len(tree.getroot())
        previous = report_path.read_bytes()
        updated = json.dumps(report, indent=2).encode("utf8")
        if b"\r\n" in previous:
            updated = updated.replace(b"\n", b"\r\n")
        if updated != previous:
            report_path.write_bytes(updated)


def check(root, fix=False):
    pairs, zones, edited = read_placements(root, fix)
    wanted = {mesh for _, _, _, mesh in pairs}
    meshes = {}
    for img in sorted((root / "imgs").glob("dff*.img")):
        for name, data in read_archive(img).items():
            if name in wanted:
                meshes[name] = mesh_bounds(data)

    path = root / "imgs/col.img"
    original = path.read_bytes()
    magic, count = struct.unpack_from("<4sI", original)
    if magic != b"VER2":
        raise ValueError(f"Invalid IMG header in {path}")
    offsets = {}
    for sector, _, _, name in struct.iter_unpack("<IHH24s", original[8:8+32*count]):
        start = sector * 2048
        if original[start:start+4] != b"COL3":
            raise ValueError(f"Invalid COL3 file at {start}")
        offsets[name.rstrip(b"\0").decode().lower()] = start + 32
    result = bytearray(original)
    changed = set()
    for hd, lod, col, mesh in pairs:
        offset = offsets[col]
        bounds = list(HEADER.unpack_from(result, offset))
        # Keep the existing center: other instances, original physical shapes
        # and 2DFX remain covered when growing a shared model's bounds.
        center = bounds[6:9]
        transform = relative_transform(lod, hd)
        sphere, vertices = meshes[mesh]
        radius = dist(center, transform(sphere[:3])) + sphere[3]
        if radius > bounds[9] + 0.0001:
            bounds[9] = radius + 0.001
        for vertex in vertices:
            for axis, value in enumerate(transform(vertex)):
                if value < bounds[axis] - 0.0001:
                    bounds[axis] = value - 0.0001
                if value > bounds[axis + 3] + 0.0001:
                    bounds[axis + 3] = value + 0.0001
        header = HEADER.pack(*bounds)
        if header != result[offset:offset+HEADER.size]:
            result[offset:offset+HEADER.size] = header
            changed.add(col)

    if changed and fix:
        with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as file:
            temp = Path(file.name)
            file.write(result)
        try:
            if path.read_bytes() != original:
                raise RuntimeError(f"{path} changed during conversion")
            temp.replace(path)
        finally:
            temp.unlink(missing_ok=True)
    if changed and not fix:
        raise ValueError(f"{len(changed)} HD colliders do not cover their native LOD: {sorted(changed)[:12]}")
    if fix:
        save_placements(root, zones, edited, len(pairs))
    print(f"Checked {len(pairs)} LOD pairs across the map; updated {len(changed)} COL3 headers.")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource", type=Path, default=WORLD)
    parser.add_argument("--fix", action="store_true")
    args = parser.parse_args()
    check(args.resource, args.fix)
