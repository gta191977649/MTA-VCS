"""Original VCS police materials on the SA vehicle component hierarchy."""
import struct

from vcs_model_assets import chunks, rw_chunk


POLICE_MODELS = {191: ("electrap", 523), 193: ("fbicar", 598), 204: ("vicechee", 597),
                 207: ("policem", 596), 218: ("barracks", 433), 234: ("enforce", 427),
                 268: ("fbiran", 490)}

# Offsets in inflated SLUS-21590 GAME.DTZ. The port renamed these source
# textures to standard SA atlases, which can resolve to another vehicle's art.
SHARED_SURFACES = {
    "vehiclegeneric256": ("xv_vehiclegeneric_sl", 0x55CB0),
    "vehiclegrunge256": ("xv_vehiclegrunge_sl", 0x55D10),
    "vehiclesteering128": ("xv_vehiclesteering_sl", 0x55D80),
    "xv_scratch_sl": ("xv_scratch_sl", 0x57920),
    "vehicleshatter128": ("xv_vc_crackedglassa_sl", 0x5F3E0),
}


def atomic_geometry(data, name):
    clump = list(chunks(data, 12, len(data)))
    frame_list = next((a, b) for kind, a, b in clump if kind == 0xE)
    frames = list(chunks(data, *frame_list))[1:]
    names = [next((data[s:e].split(b"\0")[0] for k, s, e in chunks(data, a, b)
                   if k == 0x253F2FE), b"") for _, a, b in frames]
    for kind, a, b in clump:
        if kind == 0x14:
            _, header, _ = next(chunks(data, a, b))
            frame, index = struct.unpack_from("<II", data, header)
            if names[frame] == name:
                geom_list = next((a, b) for k, a, b in clump if k == 0x1A)
                geometries = [field for field in chunks(data, *geom_list) if field[0] == 0xF]
                return geom_list, geometries[index][1:]
    raise ValueError(f"Missing vehicle atomic {name!r}")


def replace_geometry(data, geometry_list, shape, geometry):
    start, end = shape
    list_start, list_end = geometry_list
    payload = data[list_start:start-12] + geometry + data[end:list_end]
    return rw_chunk(0x10, data[12:list_start-12] + rw_chunk(0x1A, payload) + data[list_end:])


def lens_material(data, fields, alias):
    _, start, end = fields
    result = []
    for kind, lo, hi in chunks(data, start, end):
        body = data[lo:hi]
        if kind == 6:
            _, begin, stop = next(field for field in chunks(data, lo, hi) if field[0] == 2)
            value = alias.ljust((len(alias) + 4) & ~3, b"\0")
            body = data[lo:begin-12] + rw_chunk(2, value) + data[stop:hi]
        result.append(rw_chunk(kind, body))
    return rw_chunk(7, b"".join(result))


def lens_geometry(data, fields, header, materials, groups):
    struct.pack_into("<I", header, 0, struct.unpack_from("<I", header)[0] & ~1)
    count = len(materials)
    matlist = rw_chunk(8, rw_chunk(1, struct.pack("<I", count) + b"\xff"*4*count) + b"".join(materials))
    binmesh = struct.pack("<III", 0, count, sum(map(len, groups))) + b"".join(
        struct.pack("<II", len(group), i) + struct.pack(f"<{len(group)}I", *group)
        for i, group in enumerate(groups))
    extensions = b"".join(rw_chunk(kind, binmesh) if kind == 0x50E else data[start-12:end]
                          for kind, start, end in chunks(data, *fields[2][1:]))
    return rw_chunk(0xF, rw_chunk(1, header) + matlist + rw_chunk(3, extensions))


def source_siren_bar(mesh, original):
    """Restore the patrol car's PS2 sirens atomic and split only its coloured lenses."""
    _, shape = atomic_geometry(original, b"sirens")
    fields = list(chunks(original, *shape))
    _, start, end = fields[0]
    header = bytearray(original[start:end])
    flags, count, vertices, targets = struct.unpack_from("<4I", header)
    if (flags, count, targets) != (0x10037, 76, 1):
        raise ValueError("Unexpected PS2 policem lightbar geometry")
    tri = 16 + 8 * vertices
    positions = tri + count * 8 + 24
    groups = [[], [], [], []]
    for i in range(count):
        face = tri + i * 8
        b, a, material, c = struct.unpack_from("<4H", header, face)
        if material == 1:
            x = [struct.unpack_from("<f", header, positions + v * 12)[0] for v in (a, b, c)]
            # Source mesh has a central silver housing within +/-0.12,
            # then separate blue inner and red outer lenses on both sides.
            if max(x) < -0.12:
                material = 2
            elif min(x) > 0.12:
                material = 3
        struct.pack_into("<H", header, face + 4, material)
        groups[material].extend((a, b, c))
    if list(map(len, groups)) != [78, 30, 60, 60]:
        raise ValueError("Unexpected PS2 patrol lamp sections")
    material_fields = list(chunks(original, *fields[1][1:]))
    materials = [original[a-12:b] for _, a, b in material_fields[1:]]
    for alias in (b"vcssiren_left", b"vcssiren_right"):
        materials.append(lens_material(original, material_fields[-1], alias))
    geometry = lens_geometry(original, fields, header, materials, groups)
    return replace_geometry(mesh, *atomic_geometry(mesh, b"sirens"), geometry)


def source_motorcycle_beacon(mesh, original):
    """Recover original UVs lost when the port mapped the rear red beacon to vehiclelights128."""
    def layout(data, shape):
        fields = list(chunks(data, *shape))
        _, s, _ = fields[0]
        flags, faces, vertices, morphs = struct.unpack_from("<4I", data, s)
        if morphs != 1 or flags & 0xFF000000 or (flags >> 16 & 255) not in (0, 1):
            raise ValueError("Unexpected Electra mesh")
        uv = s + 16 + (4 * vertices if flags & 8 else 0)
        tri = uv + 8 * vertices
        pos = tri + 8 * faces + 24
        return fields, uv, tri, pos, faces

    def face(data, offset, pos):
        b, a, mat, c = struct.unpack_from("<4H", data, offset)
        parts = (a, b, c)
        points = [tuple(round(v, 3) for v in struct.unpack_from("<3f", data, pos + 12*i)) for i in parts]
        return parts, points, mat

    _, source_shape = atomic_geometry(original, b"chassis_hi")
    _, uv, tri, pos, faces = layout(original, source_shape)
    original_uv = {}
    for i in range(faces):
        indices, points, material = face(original, tri + i*8, pos)
        if (material == 0 and max(z for _, _, z in points) > .75
                and all(.23 < x < .39 and -.91 < y < -.69 and z > .72 for x, y, z in points)):
            original_uv[tuple(sorted(points))] = {
                point: original[uv+8*index:uv+8*index+8] for index, point in zip(indices, points)}
    if len(original_uv) != 16:
        raise ValueError("Unexpected number of PS2 Electra beacon faces")
    geometry_list, shape = atomic_geometry(mesh, b"chassis_hi")
    fields, uv, tri, pos, faces = layout(mesh, shape)
    _, start, end = fields[0]
    header = bytearray(mesh[start:end])
    material_fields = list(chunks(mesh, *fields[1][1:]))
    mat_count = len(material_fields) - 1
    groups = [[] for _ in range(mat_count + 1)]
    changes, untouched = {}, set()
    for i in range(faces):
        record = tri + i*8
        indices, points, material = face(mesh, record, pos)
        source = original_uv.get(tuple(sorted(points)))
        if source is None:
            untouched.update(indices)
        else:
            material = mat_count
            struct.pack_into("<H", header, record - start + 4, material)
            for index, point in zip(indices, points):
                value = source[point]
                if index in changes and changes[index] != value:
                    raise ValueError("Ambiguous original beacon UV")
                changes[index] = value
        groups[material].extend(indices)
    if len(groups[-1]) != 48 or changes.keys() & untouched:
        raise ValueError("Converted Electra does not isolate its 16 beacon faces")
    for index, value in changes.items():
        offset = uv + index * 8 - start
        header[offset:offset+8] = value
    # Copy the neutral source material used on the chassis. Its native surface
    # coefficients are retained, while the beacon gets a separate texture name.
    materials = [mesh[a-12:b] for _, a, b in material_fields[1:]]
    materials.append(lens_material(mesh, material_fields[1], b"vcssiren_right"))
    return replace_geometry(mesh, geometry_list, shape, lens_geometry(mesh, fields, header, materials, groups))
