"""Extract resident marker meshes and textures from the verified US PS2 VCS disc.

The marker table is GAME.DTZ root slot 0x2a (003321f0 -> 0016bf08).
0016b9a8 retains the final atomic of each clump; 0016b9b8 clones that atomic.
The existing local vcsconv tool converts the original resident PS2 VIF mesh.
"""

import argparse
import hashlib
import json
from pathlib import Path
import struct
import subprocess
import tempfile
import zlib

from import_vcs_frontend import encode_png
from vcs_model_assets import chunks, stored_vehicle_raster


GAME_HASH = "570a7504048e8a0187b04b20fec63fc57c404c74b84e7d3ee19df8daab1a365b"
EXE_HASH = "3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547"
OUTPUT = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[module]/marker/assets"
TYPES = (1, 2, 3, 6, 7, 8)
TEXTURES = {"xv_white_sl": 0x578C0, "zonewhite64": 0xA8AD0, "ringborderblur": 0x63960,
            "coronaringa": 0x82D70}


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def verified(path, expected):
    data = path.read_bytes()
    if hashlib.sha256(data).hexdigest() != expected:
        raise ValueError(f"Unexpected USA v1.00 source: {path}")
    return data


def final_atomic(game, clump):
    head = clump + 8
    cursor = u32(game, head)
    seen = set()
    atomic = None
    while cursor != head:
        if cursor in seen or cursor < 28 or cursor + 8 > len(game):
            raise ValueError("Invalid marker atomic list")
        seen.add(cursor)
        atomic = cursor - 28
        cursor = u32(game, cursor)
    if atomic is None:
        raise ValueError("Empty marker clump")
    return atomic


def mesh_from_dff(data):
    clump = list(chunks(data, 12, 12 + u32(data, 4)))
    geometry_list = next((a, b) for kind, a, b in clump if kind == 0x1A)
    geometries = [(a, b) for kind, a, b in chunks(data, *geometry_list) if kind == 0xF]
    if len(geometries) != 1:
        raise ValueError("Expected one cloned marker atomic")
    fields = list(chunks(data, *geometries[0]))
    _, start, end = fields[0]
    flags, faces, count, morphs = struct.unpack_from("<4I", data, start)
    if morphs != 1 or not flags & 4 or flags & 0xFF0000 != 0x10000:
        raise ValueError(f"Unexpected marker geometry format: {flags:#x}")
    color_start = start + 16
    uv_start = color_start + (count * 4 if flags & 8 else 0)
    tri_start = uv_start + count * 8
    sphere = tri_start + faces * 8
    has_positions, has_normals = struct.unpack_from("<2I", data, sphere + 16)
    if has_positions != 1:
        raise ValueError("Marker has no positions")
    positions = sphere + 24
    expected_end = positions + count * 12 * (1 + bool(has_normals))
    if expected_end != end:
        raise ValueError("Unexpected marker geometry payload size")
    vertices = []
    for index in range(count):
        xyz = struct.unpack_from("<3f", data, positions + index * 12)
        uv = struct.unpack_from("<2f", data, uv_start + index * 8)
        rgba = struct.unpack_from("<4B", data, color_start + index * 4) if flags & 8 else (255,) * 4
        normals = struct.unpack_from("<3f", data, positions + count * 12 + index * 12) if has_normals else (0, 0, 1)
        vertices.append((*xyz, *uv, *rgba, *normals))
    indices = []
    for face in range(faces):
        second, first, material, third = struct.unpack_from("<4H", data, tri_start + face * 8)
        if material != 0 or max(first, second, third) >= count:
            raise ValueError("Invalid marker face")
        indices.extend((first + 1, second + 1, third + 1))
    bounds = [[min(v[axis] for v in vertices), max(v[axis] for v in vertices)] for axis in range(3)]
    material_list = next((a, b) for kind, a, b in fields if kind == 8)
    material = next((a, b) for kind, a, b in chunks(data, *material_list) if kind == 7)
    material_struct = next(chunks(data, *material))[1]
    material_color = struct.unpack_from("<4B", data, material_struct + 4)
    return vertices, indices, bounds, flags, material_color


def extract(disc, converter, output):
    verified(disc / "SLUS_215.90", EXE_HASH)
    game = zlib.decompress(verified(disc / "PS2/GAME.DTZ", GAME_HASH))
    if game[:8] != b"GATG\x01\0\0\0" or u32(game, 8) != len(game):
        raise ValueError("Invalid GAME.DTZ container")
    table = u32(game, 0x20 + 0x2A * 4)
    if table != 0x3B2DBC:
        raise ValueError("Unexpected marker model table")
    output.mkdir(parents=True, exist_ok=True)
    manifest = {"edition": "SLUS-21590 USA v1.00", "executableSha256": EXE_HASH,
                "gameDtzSha256": GAME_HASH, "tableOffset": table, "models": {}, "textures": {}}
    lua = ["-- Generated from verified original PS2 resident marker models by tools/import_vcs_markers.py.",
           "-- vertices: {x,y,z,u,v,r,g,b,a,nx,ny,nz}; indices: one-based triangle-list indices.",
           "-- Native 0016bc58 replaces material RGBA each frame; original materialColor is provenance only.",
           "VCSMarkerMeshes = {"]
    with tempfile.TemporaryDirectory(prefix="vcs-marker-assets-") as temp:
        workspace = Path(temp)
        game_path = workspace / "game.dat"
        game_path.write_bytes(game)
        for marker_type in TYPES:
            clump = u32(game, table + marker_type * 4)
            atomic = final_atomic(game, clump)
            geometry = u32(game, atomic + 20)
            materials, material_count = struct.unpack_from("<2I", game, geometry + 12)
            if material_count != 1:
                raise ValueError("Expected one marker material")
            material = u32(game, materials)
            texture = u32(game, material)
            name = game[texture + 16:texture + 48].split(b"\0", 1)[0].decode("ascii")
            if TEXTURES.get(name) != texture:
                raise ValueError("Unexpected marker texture")
            raw = bytearray(game)
            raw[:4] = b"ldm\0"
            struct.pack_into("<2H", raw, 28, 0, 1)
            struct.pack_into("<I", raw, 32, atomic)
            # Resident materials refer to RslTexture; the streamed model reader
            # expects its name. All other resident data and relocations survive.
            struct.pack_into("<I", raw, material, texture + 16)
            source, target = workspace / f"{marker_type}.mdl", workspace / f"{marker_type}.dff"
            source.write_bytes(raw)
            result = subprocess.run([str(converter), "-v", "36003", "-g", str(game_path),
                                     str(source), str(target)], cwd=workspace, capture_output=True, timeout=60)
            if result.returncode or not target.is_file():
                raise ValueError(f"Marker conversion failed: {marker_type}: {result.stderr!r}")
            vertices, indices, bounds, flags, material_color = mesh_from_dff(target.read_bytes())
            color_lua = ",".join(map(str, material_color))
            lua.append(f'    [{marker_type}] = {{texture="{name}", materialColor={{{color_lua}}}, vertices={{')
            lua.extend("        {" + ",".join(format(x, ".9g") for x in vertex) + "}," for vertex in vertices)
            lua.append("    }, indices={" + ",".join(map(str, indices)) + "}},")
            manifest["models"][str(marker_type)] = {"clumpOffset": clump, "atomicOffset": atomic,
                "geometryOffset": geometry, "texture": name, "vertices": len(vertices),
                "triangles": len(indices) // 3, "bounds": bounds, "geometryFlags": flags,
                "hasPrelight": bool(flags & 8), "hasNormals": bool(flags & 16),
                "originalMaterialColor": material_color,
                "vertexColorRanges": [[min(v[axis] for v in vertices), max(v[axis] for v in vertices)]
                                      for axis in range(5, 9)]}
    lua.append("}")
    (output / "meshes.lua").write_text("\n".join(lua) + "\n", encoding="utf-8")
    for name, offset in TEXTURES.items():
        width, height, rgba = stored_vehicle_raster(game, name, offset)
        png = encode_png(width, height, rgba)
        (output / f"{name}.png").write_bytes(png)
        manifest["textures"][name] = {"offset": offset, "width": width, "height": height,
                                     "sha256": hashlib.sha256(png).hexdigest()}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("converter", type=Path, help="Existing Win32 vcsconv executable")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()
    extract(args.disc.resolve(strict=True), args.converter.resolve(strict=True), args.output)
