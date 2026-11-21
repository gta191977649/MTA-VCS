"""Keep the VCS Rhino's three axles on SA's special tracked-vehicle parent."""
import struct
import subprocess

from vcs_model_assets import build_texture_dictionary, chunks, native_textures, rw_chunk, vehicle_native_raster
from vcs_police_materials import atomic_geometry


def read_uint(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def original_wheel(game, model_table, workspace, executable):
    rhino = read_uint(game, model_table + 246 * 4)
    model, = struct.unpack_from("<H", game, rhino + 0x270)
    diameter, rear = struct.unpack_from("<2f", game, rhino + 0x58)
    wheel = read_uint(game, model_table + model * 4)
    if (model, read_uint(game, wheel + 8), diameter, rear) != (328, 0x51AF7528, 1.5, 1.5):
        raise ValueError("Unexpected Rhino wheel definition")
    # The two wheel LODs are resident RslElements. Give vcsconv an ordinary
    # simple-model entry point while retaining their original relocation table.
    raw = bytearray(game)
    raw[:4] = b"ldm\0"
    struct.pack_into("<2H", raw, 28, 0, 2)
    lods = read_uint(game, wheel + 0x28)
    raw[32:40] = game[lods:lods + 8]
    for element in struct.unpack_from("<2I", game, lods):
        geometry = read_uint(game, element + 0x14)
        materials, count = struct.unpack_from("<2I", game, geometry + 12)
        material = read_uint(game, materials)
        texture = read_uint(game, material)
        if count != 1 or game[texture + 16:texture + 22] != b"tyres\0":
            raise ValueError("Unexpected wheel_lighttruck material")
        # Streamed RslMaterials contain a texture-name pointer. Resident ones
        # contain an RslTexture pointer whose name starts at byte 16.
        struct.pack_into("<I", raw, material, texture + 16)
    source = workspace / "wheel_lighttruck.mdl"
    output = source.with_suffix(".dff")
    source.write_bytes(raw)
    result = subprocess.run([str(executable), "-v", "36003", "-g", str(workspace / "game.dat"),
                             str(source), str(output)], cwd=workspace, capture_output=True, timeout=60)
    if result.returncode or not output.is_file():
        raise ValueError(f"wheel_lighttruck conversion failed: {result.stderr!r}")
    converted = output.read_bytes()
    _, bounds = atomic_geometry(converted, b"object_L0")
    fields = list(chunks(converted, *bounds))
    _, start, end = fields[0]
    header = bytearray(converted[start:end])
    flags, triangles, vertices, morphs = struct.unpack_from("<4I", header)
    if (flags, triangles, morphs) != (0x10037, 203, 1):
        raise ValueError("Unexpected wheel_lighttruck high-detail geometry")
    sphere = 16 + vertices * 8 + triangles * 8
    # SA scales only its native wheel dummies. Bake the PS2 wheel diameter
    # into the independent renderable component, including its bounds.
    for offset, count in ((sphere, 4), (sphere + 24, vertices * 3)):
        values = struct.unpack_from(f"<{count}f", header, offset)
        struct.pack_into(f"<{count}f", header, offset, *(value * diameter for value in values))
    mesh = rw_chunk(0xF, rw_chunk(1, header) + converted[end:bounds[1]])
    return mesh, vehicle_native_raster(game, "tyres", texture)


def native_template(material):
    # SA's Rhino code explicitly renders its middle-wheel template eight more
    # times. Keep a valid atomic for that code with a single degenerate face.
    vertices = bytes(3 * 12)
    normals = struct.pack("<3f", 1, 0, 0) * 3
    header = (struct.pack("<4I", 0x10036, 1, 3, 1) + bytes(3 * 8) + struct.pack("<4H", 1, 0, 0, 2)
              + struct.pack("<4fII", 0, 0, 0, 0.01, 1, 1) + vertices + normals)
    indices = struct.pack("<8I", 0, 1, 3, 3, 0, 0, 1, 2)
    return rw_chunk(0xF, rw_chunk(1, header) + material + rw_chunk(3, rw_chunk(0x50E, indices)))


def restore_rhino(geometry, dictionary, game, model_table, workspace, executable):
    wheel, raster = original_wheel(game, model_table, workspace, executable)
    clump = list(chunks(geometry, 12, len(geometry)))
    frames = next((a, b) for k, a, b in clump if k == 0xE)
    frame_fields = list(chunks(geometry, *frames))
    _, first, last = frame_fields[0]
    matrices = bytearray(geometry[first:last])
    extensions = bytearray(geometry[last:frames[1]])
    names = [next((geometry[s:e].split(b"\0")[0].decode("ascii") for k, s, e in chunks(geometry, a, b)
                   if k == 0x253F2FE), "") for _, a, b in frame_fields[1:]]
    first_new = len(names)
    for side in ("lf", "rf", "lm", "rm", "lb", "rb"):
        row = 4 + 56 * names.index(f"wheel_{side}_dummy")
        matrix = bytearray(matrices[row:row + 56])
        if struct.unpack_from("<i", matrix, 48)[0] != 0:
            raise ValueError("Rhino wheel dummy is not a root child")
        if side[0] == "l":
            struct.pack_into("<9f", matrix, 0, -1, 0, 0, 0, -1, 0, 0, 0, 1)
        matrices.extend(matrix)
        extensions.extend(rw_chunk(3, rw_chunk(0x253F2FE, f"vcs_wheel_{side}".encode())))
    struct.pack_into("<I", matrices, 0, first_new + 6)
    frame_list = rw_chunk(0xE, rw_chunk(1, matrices) + extensions)
    geoms, native = atomic_geometry(geometry, b"wheel")
    shapes = [geometry[a-12:b] for k, a, b in chunks(geometry, *geoms) if k == 0xF]
    template = next(i for i, (_, a, b) in enumerate(list(chunks(geometry, *geoms))[1:]) if (a, b) == native)
    material = next(geometry[a-12:b] for k, a, b in chunks(geometry, *native) if k == 8)
    shapes[template] = native_template(material)
    shapes.append(wheel)
    shape_list = rw_chunk(0x1A, rw_chunk(1, struct.pack("<I", len(shapes))) + b"".join(shapes))
    output = []
    for kind, start, end in clump:
        value = geometry[start-12:end]
        if kind == 1:
            value = rw_chunk(1, struct.pack("<I", read_uint(geometry, start) + 6) + geometry[start+4:end])
        elif kind == 0xE:
            value = frame_list
        elif kind == 0x1A:
            value = shape_list
        elif kind == 0x14:
            _, header, _ = next(chunks(geometry, start, end))
            frame = names[read_uint(geometry, header)]
            if frame == "wheel":
                for i in range(6):
                    atom = bytearray(value)
                    struct.pack_into("<2I", atom, header - start + 12, first_new + i, len(shapes) - 1)
                    output.append(bytes(atom))
        output.append(value)
    textures = native_textures(dictionary)
    textures["tyres"] = raster
    return rw_chunk(0x10, b"".join(output)), build_texture_dictionary(textures, dictionary[26:28])
