"""Extract wheel contact geometry from the converted VCS vehicle archive."""

import argparse
import math
from pathlib import Path
import re
import struct

from vcs_model_assets import chunks, compose


def wheel_radius(data, geometry):
    _, start, end = next(chunks(data, *geometry))
    flags, triangles, vertices, morphs = struct.unpack_from("<4I", data, start)
    if flags & 0x01000000 or not morphs:
        return None
    uv_sets = (flags >> 16) & 255 or (2 if flags & 0x80 else int(bool(flags & 4)))
    target = start + 16 + vertices * (4 * bool(flags & 8) + 8 * uv_sets) + triangles * 8
    if target + 24 + vertices * 12 > end or not struct.unpack_from("<I", data, target + 16)[0]:
        return None
    return max((math.hypot(y, z) for _, y, z in struct.iter_unpack(
        "<3f", data[target + 24:target + 24 + vertices * 12])), default=0)


def contact_geometry(data):
    _, start, end = next(chunks(data, 0, len(data)))
    clump = list(chunks(data, start, end))
    frame_list = next((item[1:] for item in clump if item[0] == 0xE), None)
    geometry_list = next((item[1:] for item in clump if item[0] == 0x1A), None)
    if not frame_list or not geometry_list:
        return None
    frames = iter(chunks(data, *frame_list))
    _, frame_start, _ = next(frames)
    frame_count, = struct.unpack_from("<I", data, frame_start)
    poses, names = [], []
    for index, (_, extension_start, extension_end) in enumerate(frames):
        matrix = struct.unpack_from("<12f", data, frame_start + 4 + index * 56)
        parent, = struct.unpack_from("<i", data, frame_start + 52 + index * 56)
        if parent == -1:
            matrix = (1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
        poses.append(compose(matrix, poses[parent]) if parent >= 0 else matrix)
        name = next((data[a:b].split(b"\0", 1)[0].decode("ascii", errors="replace")
                     for kind, a, b in chunks(data, extension_start, extension_end) if kind == 0x253F2FE), "")
        names.append(name.lower())
    if len(poses) != frame_count:
        raise ValueError("Invalid vehicle frame list")
    geometries = [item[1:] for item in chunks(data, *geometry_list) if item[0] == 0xF]
    radii = {}
    for kind, start, end in clump:
        if kind != 0x14:
            continue
        _, atom, _ = next(chunks(data, start, end))
        frame, geometry = struct.unpack_from("<2I", data, atom)
        if names[frame].startswith(("wheel", "vcs_wheel_")):
            # Some authored wheel atomics are displaced inside a dummy. The
            # radius alone cannot describe those meshes at runtime.
            if names[frame] == "wheel":
                local = struct.unpack_from("<3f", data, frame_start + 40 + frame * 56)
                if any(abs(axis) > 0.01 for axis in local):
                    continue
            radius = wheel_radius(data, geometries[geometry])
            if radius and radius > 0 and math.isfinite(radius):
                radii[names[frame]] = radius
    axles = []
    for side, prefix in (("front", "f"), ("rear", "b")):
        candidates = ("wheel_l" + prefix + "_dummy", "wheel_r" + prefix + "_dummy", "wheel_" + side)
        axle = next((name for name in candidates if name in names), None)
        if not axle:
            return None
        y, z = poses[names.index(axle)][10:12]
        radius = radii.get("vcs_wheel_r" + prefix, radii.get(axle, radii.get("wheel")))
        axles.append((y, z, radius))
    return axles if axles[0][0] > axles[1][0] else None


def ground_catalog(bindings, dffs):
    lines = ["-- Generated from the locally converted vehicle DFFs.", "VCS_VEHICLE_GROUND = {"]
    for original, name in sorted(bindings.items()):
        data = dffs.get(name + ".dff")
        contacts = data and contact_geometry(data)
        if contacts:
            axles = ", ".join("{" + f"{y:.9g}, {z:.9g}, " + (f"{radius:.9g}" if radius else "false") + "}"
                              for y, z, radius in contacts)
            lines.append(f"    [{original}] = {{{axles}}}, -- {name}")
    return ("\n".join([*lines, "}", ""])).encode("utf-8")


def read_archive(path):
    models = {}
    with path.open("rb") as stream:
        signature, count = struct.unpack("<4sI", stream.read(8))
        if signature != b"VER2":
            raise ValueError("Expected a VER2 vehicle IMG")
        entries = [struct.unpack("<IHH24s", stream.read(32)) for _ in range(count)]
        for sector, size, _, filename in entries:
            name = filename.split(b"\0", 1)[0].decode("ascii").lower()
            if name.endswith(".dff"):
                stream.seek(sector * 2048)
                container, length, _ = struct.unpack("<III", stream.read(12))
                if container != 0x10 or length + 12 > size * 2048:
                    raise ValueError(f"Invalid IMG entry {name}")
                stream.seek(sector * 2048)
                models[name] = stream.read(length + 12)
    return models


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("resource", type=Path)
    resource = parser.parse_args().resource
    catalog = (resource / "model_catalog.lua").read_text(encoding="utf-8")
    models = {int(id): name for id, name in re.findall(r'\[(\d+)\] = \{kind = "vehicle", base = \d+, name = "([^"]+)"', catalog)}
    (resource / "vehicle_ground_catalog.lua").write_bytes(ground_catalog(models, read_archive(resource / "vehicle.img")))
