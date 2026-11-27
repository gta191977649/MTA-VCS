"""Pair the PS2 island's complementary distant light meshes with native MTA details."""
import argparse
from collections import Counter
import json
from math import dist
import os
from pathlib import Path
import struct
import sys
import tempfile
import xml.etree.ElementTree as ET

from vcs_model_assets import chunks
from vcs_vehicle_ground import read_archive

ROOT = Path(__file__).resolve().parents[1]
# GAME.DTZ model IDs: detail, linked distant mesh, complementary distant mesh.
# Each distant mesh covers a different part of the same lit facade.
WINDOWS = (
    (2574, 2665, 2694), (2882, 3019, 3067), (2883, 3021, 3068),
    (6111, 6110, 6112), (6104, 6105, 6119), (6092, 6093, 6120),
    (6078, 6091, 6109), (6077, 6090, 6113), (5835, 5849, 5850),
    (5833, 5847, 5848), (5830, 5834, 5846), (4228, 4238, 4230),
    (4201, 4237, 4234), (4200, 4236, 4233), (4229, 4235, 4231),
    (4199, 4232, 4239), (4850, 4856, 4876), (4847, 4855, 4873),
    (4851, 4857, 4871),
)


def descendants(data, path):
    spans = [(0, len(data))]
    for target in path:
        spans = [(a, b) for start, end in spans for tag, a, b in chunks(data, start, end)
                 if target == tag]
    return spans


def decode(data):
    (start, end), = descendants(data, (16, 26, 15, 1))
    flags, count, vertices, morphs = struct.unpack_from("<4I", data, start)
    if flags != 0x1004e or morphs != 1:
        raise ValueError("Unexpected window geometry format")
    rgba_start = start + 16
    uv_start = rgba_start + 4 * vertices
    face_start = uv_start + 8 * vertices
    bounds_start = face_start + 8 * count
    colors = list(struct.iter_unpack("<4B", data[rgba_start:uv_start]))
    uv = list(struct.iter_unpack("<2f", data[uv_start:face_start]))
    faces = [(a, b, c, material) for b, a, material, c in
             struct.iter_unpack("<4H", data[face_start:bounds_start])]
    sphere = struct.unpack_from("<4f", data, bounds_start)
    points = list(struct.iter_unpack("<3f", data[bounds_start + 24:end]))
    textures = []
    for a, b in descendants(data, (16, 26, 15, 8, 7, 6)):
        nodes = list(chunks(data, a, b))
        filter_mode = struct.unpack_from("<I", data, nodes[0][1])[0] & 255
        textures.append((data[nodes[1][1]:nodes[1][2]].rstrip(b"\0").decode(), filter_mode))
    return points, uv, colors, faces, textures, sphere


def centres(mesh):
    points, _, _, faces, _, _ = mesh
    return [tuple(sum(points[i][axis] for i in face[:3]) / 3 for axis in range(3)) for face in faces]


def triangles(mesh):
    pts, uv, colors, faces, textures, _ = mesh
    return Counter((textures[m], tuple((pts[i], uv[i], colors[i]) for i in (a, b, c))) for a, b, c, m in faces)


def split_geometry(data, main, extra, stem, dff):
    mesh = decode(data)
    pts, uv, colors, faces, textures, sphere = mesh
    coarse = (centres(decode(main)), centres(decode(extra)))
    subsets = ([], [])
    for face, center in zip(faces, centres(mesh)):
        distances = [min(dist(center, p) for p in layer) for layer in coarse]
        subsets[int(distances[1] < distances[0])].append(face)
    if not all(subsets):
        raise ValueError(f"{stem}: cannot separate distant facade sections")
    outputs = [dff(stem + suffix, pts, uv, colors, subset, textures, bounds=(None, None, sphere))
               for suffix, subset in zip(("a", "b"), subsets)]
    if sum((triangles(decode(out)) for out in outputs), Counter()) != triangles(mesh):
        raise ValueError(f"{stem}: lost or duplicated a detail triangle")
    return outputs


def write_xml(path, node):
    ET.indent(node, "    ")
    ET.ElementTree(node).write(path, encoding="utf-8", xml_declaration=True)


def append_models(path, models):
    # Make room for the longer VER2 directory by moving only the entries it
    # would overwrite. Other assets keep their original offsets and bytes.
    blob = bytearray(path.read_bytes())
    signature, count = struct.unpack_from("<4sI", blob)
    if signature != b"VER2" or len(blob) % 2048:
        raise ValueError(f"Invalid IMG archive {path}")
    directory = list(struct.iter_unpack("<IHH24s", blob[8:8 + count * 32]))
    entries = {raw.rstrip(b"\0").decode(): (sector, size) for sector, size, _, raw in directory}
    new = {}
    for name, data in models.items():
        if name in entries:
            sector, size = entries[name]
            if blob[sector * 2048:(sector + size) * 2048] != data.ljust(size * 2048, b"\0"):
                raise ValueError(f"Conflicting existing mesh {name}")
        else:
            new[name] = data
    if not new:
        return
    first_sector = (8 + 32 * (count + len(new)) + 2047) // 2048
    updated = []
    for sector, size, packed, raw in directory:
        if sector < first_sector:
            contents = blob[sector * 2048:(sector + size) * 2048]
            sector = len(blob) // 2048
            blob.extend(contents)
        updated.append((sector, size, packed, raw))
    for name, data in sorted(new.items()):
        size = (len(data) + 2047) // 2048
        updated.append((len(blob) // 2048, size, 0, name.encode()))
        blob.extend(data.ljust(size * 2048, b"\0"))
    header = struct.pack("<4sI", b"VER2", len(updated))
    header += b"".join(struct.pack("<IHH24s", *row) for row in sorted(updated))
    blob[:len(header)] = header
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as staged:
        staged.write(blob)
    os.replace(staged.name, path)


def process(root, fix, converter):
    sys.path.insert(0, str(converter))
    from renderware import dff
    folder = root / "imgs"
    images = {}
    for path in sorted(folder.glob("dff*.img")):
        images.update(read_archive(path))
    files, models = {}, {}
    for zone in ("beach", "mainla"):
        prefix = root / "zones" / zone / zone
        defs_file, map_file = prefix.with_suffix(".definition"), prefix.with_suffix(".map")
        defs, world = ET.parse(defs_file).getroot(), ET.parse(map_file).getroot()
        files[defs_file], files[map_file] = defs, world
        definitions = {d.get("id"): d for d in defs}
        for row in world:
            definition = definitions[row.get("id")]
            index = int(definition.get("sourceModelId"))
            if not row.get("id").endswith("_lod_detail"):
                models[index] = defs, world, definition, row

    def geometry(definition):
        return images[definition.get("dff") + ".dff"]

    # BEACH's western LOD reused the east sign. Check both originals by
    # their transformed mesh points, independent of packed DFF names.
    for high, low in ((2659, 2664), (2687, 2688)):
        _, _, near, near_row = models[high]
        _, _, far, far_row = models[low]
        if (near_row.get("lodParent") != far_row.get("id")
                or any(near_row.get(key) != far_row.get(key)
                       for key in ("posX", "posY", "posZ", "rotX", "rotY", "rotZ"))):
            raise ValueError(f"{low}: misplaced Rockstar sign LOD")
        details, coarse = decode(geometry(near)), decode(geometry(far))
        near_points, far_points = set(details[0]), set(coarse[0])
        if (details[4] != coarse[4] or len(details[3]) != len(coarse[3])
                or any(min(dist(p, v) for v in dst) > 0.001
                       for src, dst in ((near_points, far_points), (far_points, near_points)) for p in src)):
            raise ValueError(f"{low}: Rockstar sign LOD does not match its detailed facade")

    created = {}
    for high, low, extra in WINDOWS:
        defs, world, detail, row = models[high]
        _, _, primary, primary_row = models[low]
        _, _, extra_def, extra_row = models[extra]
        name = detail.get("id") + "_lod_detail"
        stem = "window_" + str(high)
        uid = "window_" + str(extra)
        # All three source models share one pivot. SA measures the handover
        # from this pivot using the client's camera, draw distance and far clip.
        for key in ("posX", "posY", "posZ"):
            if max(abs(float(row.get(key)) - float(other.get(key))) for other in (primary_row, extra_row)) > .01:
                raise ValueError(f"{high}: source pivots differ")
        if row.get("lodParent") != primary_row.get("id"):
            raise ValueError(f"{high}: missing primary native LOD")
        existing = next((d for d in defs if d.get("id") == name), None)
        if existing is not None:
            original = images[existing.attrib["sourceDetailDff"] + ".dff"]
            if triangles(decode(geometry(detail))) + triangles(decode(geometry(existing))) != triangles(decode(original)):
                raise ValueError(f"{high}: defective near window reconstruction")
            addition = next(p for p in world if p.get("id") == name)
            if (extra_row.get("uniqueID") != addition.get("uniqueID")
                    or extra_row.get("id") != addition.get("lodParent")
                    or any(detail.get(k) != existing.get(k) for k in ("col", "txd", "timeIn", "timeOut", "lodDistance"))):
                raise ValueError(f"{high}: mismatched auxiliary LOD")
            continue
        if not fix:
            raise ValueError(f"{high}: unpaired distant facade")
        original_name = detail.get("dff")
        a, b = split_geometry(geometry(detail), geometry(primary), geometry(extra_def), stem, dff)
        created[stem + "a.dff"], created[stem + "b.dff"] = a, b
        detail.set("dff", stem + "a")
        extra_detail = dict(detail.attrib, id=name, dff=stem + "b", sourceDetailDff=original_name)
        ET.SubElement(defs, "definition", extra_detail)
        ET.SubElement(world, row.tag, dict(row.attrib, id=name, lodParent=extra_row.get("id"), uniqueID=uid))
        extra_row.attrib.pop("lowLOD", None)
        extra_row.set("uniqueID", uid)

    # The second North Beach West window set is already separate in GAME.DTZ.
    _, _, detail, row = models[5540]
    _, _, _, target = models[5537]
    if fix:
        detail.set("lodDistance", "299.00")
        row.attrib.pop("lowLOD", None)
        target.attrib.pop("lowLOD", None)
        row.set("lodParent", target.get("id"))
        row.set("uniqueID", "window_5537")
        target.set("uniqueID", "window_5537")
    if row.get("lodParent") != target.get("id") or row.get("uniqueID") != target.get("uniqueID"):
        raise ValueError("Missing North Beach West window pair")

    # MAINLA keeps this 32-triangle sign in its daytime distant sectors. BEACH
    # loads the same mesh only in 19-05 overlays. The 19-05 primary (3015)
    # already draws these exact triangles. Its 20-09 detail must remain timed.
    defs, world, daylight, daylight_row = models[3066]
    _, _, near_def, _ = models[3013]
    gate = "dt22_day_lod_detail"
    if not any(d.get("id") == gate for d in defs):
        if not fix:
            raise ValueError("Missing Downtown daytime distant sign range")
        # An empty raster footprint gives the far-only sign its native near
        # boundary even during hours when the detailed neon is switched off.
        pts, uv, colors, _, tex, sphere = decode(geometry(near_def))
        created["dt22_day_detail.dff"] = dff("dt22_day_detail", pts, uv, colors,
                                              [(0, 0, 0, 0)], tex, bounds=(None, None, sphere))
        attrs = dict(near_def.attrib, id=gate, dff="dt22_day_detail", txd=daylight.get("txd"))
        for key in ("timeIn", "timeOut"):
            attrs.pop(key, None)
        ET.SubElement(defs, "definition", attrs)
        daylight.set("timeIn", "5")
        daylight.set("timeOut", "19")
        daylight_row.tag = "object"
        daylight_row.set("forceObject", "true")
        daylight_row.set("uniqueID", "window_3066")
        ET.SubElement(world, "object", dict(daylight_row.attrib, id=gate, lodParent=daylight_row.get("id")))
    if (daylight.get("timeIn"), daylight.get("timeOut")) != ("5", "19"):
        raise ValueError("Duplicate nighttime facade")
    if {p.name for p in folder.glob("*.img")} != {"dff.img", "dff_1.img", "col.img", "txd.img"}:
        raise ValueError("Expected the four mounted VCS world archives")
    if not created:
        print(f"Verified {len(WINDOWS)} partitioned light facades, the North Beach West pair and Downtown daytime LOD.")
        return

    append_models(folder / "dff_1.img", created)
    for path, node in files.items():
        write_xml(path, node)
    report_path = root / "conversion-report.json"
    report = json.loads(report_path.read_text())
    report["dff"] += len(created)
    report["split_window_details"] = len(WINDOWS)
    for path, node in files.items():
        if path.suffix in (".definition", ".map"):
            key = "definitions" if path.suffix == ".definition" else "placements"
            report["zones"][path.stem][key] = len(node)
    report_path.write_text(json.dumps(report, indent=2), encoding="utf8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--resource", type=Path, default=ROOT / "mods/deathmatch/resources/[vcs]/vcs")
    parser.add_argument("--converter", type=Path, default=ROOT.parent / "mta_map_tools")
    parser.add_argument("--fix", action="store_true")
    args = parser.parse_args()
    process(args.resource, args.fix, args.converter)
