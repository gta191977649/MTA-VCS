"""RenderWare compatibility and IMG packaging for locally converted VCS assets."""

import struct
import zlib


# The order and stack flags are those used by the SA MAN animation association.
# CAnimBlendAssociation copies its native per-bone nodes in this slot order.
SA_PED_BONES = (
    (0, 0), (1, 0), (2, 2), (3, 2), (4, 2), (5, 2), (8, 3), (6, 3), (7, 1),
    (31, 2), (32, 0), (33, 0), (34, 0), (35, 0), (36, 1),
    (21, 0), (22, 0), (23, 0), (24, 0), (25, 0), (26, 1),
    (302, 3), (301, 1), (201, 1), (41, 2), (42, 0), (43, 0), (44, 1),
    (51, 0), (52, 0), (53, 0), (54, 1),
)
SA_EXTRA_BONES = {6: (5, "L Brow"), 7: (5, "R Brow"), 36: (35, "L Finger01"),
                  26: (25, "R Finger01"), 302: (3, "L breast"),
                  301: (3, "R breast"), 201: (2, "Belly")}


def rw_chunk(kind, payload):
    return struct.pack("<III", kind, len(payload), 0x1803FFFF) + payload


def chunks(data, start, end):
    while start < end:
        kind, size, _ = struct.unpack_from("<III", data, start)
        payload = start + 12
        start = payload + size
        if start > end:
            raise ValueError("RenderWare chunk exceeds its parent")
        yield kind, payload, start


def native_textures(dictionary):
    end = 12 + struct.unpack_from("<I", dictionary, 4)[0]
    return {
        dictionary[start + 20:start + 52].split(b"\0", 1)[0].decode("ascii").lower():
        dictionary[start - 12:finish]
        for kind, start, finish in chunks(dictionary, 12, end) if kind == 0x15
    }


def stored_vehicle_raster(game_data, name, offset):
    """Read a paletted RslTexture in verified SLUS-21590 GAME.DTZ."""
    if game_data[offset + 16:offset + 48].split(b"\0", 1)[0] != name.encode("ascii"):
        raise ValueError(f"Unexpected stored texture at {offset:#x}: {name}")
    raster, = struct.unpack_from("<I", game_data, offset)
    pixels, flags = struct.unpack_from("<II", game_data, raster + 8)
    width, height = 1 << (flags & 63), 1 << (flags >> 6 & 63)
    depth, levels, swizzle = flags >> 12 & 63, flags >> 20 & 15, flags >> 24
    if depth not in (4, 8) or levels != 1 or swizzle:
        raise ValueError(f"Unexpected stored raster format: {name}")
    size = width * height * depth // 8
    texels = game_data[pixels:pixels + size]
    palette = game_data[pixels + size:pixels + size + (1 << depth) * 4]
    if depth == 8:
        indices = ((value & ~0x18) | ((value & 8) << 1) | ((value & 16) >> 1) for value in texels)
    else:
        indices = (index for value in texels for index in (value & 15, value >> 4))
    rgba = bytearray()
    for index in indices:
        red, green, blue, alpha = palette[index * 4:index * 4 + 4]
        rgba.extend((red, green, blue, min(alpha * 255 // 128, 255)))
    return width, height, rgba


def vehicle_native_raster(game_data, name, offset):
    width, height, rgba = stored_vehicle_raster(game_data, name, offset)
    return vehicle_rgba_raster(name, width, height, rgba)


def vehicle_rgba_raster(name, width, height, rgba):
    bgra = bytearray(rgba)
    bgra[0::4], bgra[2::4] = rgba[2::4], rgba[0::4]
    header = struct.pack("<II32s32sIIHHBBBBI", 9, 0x1102, name.encode("ascii"), b"",
                         0x0500, 21, width, height, 32, 1, 4, 1, len(bgra))
    return rw_chunk(0x15, rw_chunk(1, header + bgra) + rw_chunk(3, b""))


def vehicle_material_textures(data):
    def visit(start, end):
        for kind, payload, finish in chunks(data, start, end):
            if kind == 7:
                for child, lo, hi in chunks(data, payload, finish):
                    if child == 6:
                        for field, offset, text_end in chunks(data, lo, hi):
                            if field == 2:
                                name = data[offset:text_end].split(b"\0", 1)[0].decode("ascii").lower()
                                if name:
                                    yield name
                                break
            elif kind in (0x10, 0x1A, 0x0F, 8):
                yield from visit(payload, finish)

    return set(visit(0, 12 + struct.unpack_from("<I", data, 4)[0]))


def build_texture_dictionary(textures, device):
    return rw_chunk(0x16, rw_chunk(1, struct.pack("<H", len(textures)) + device)
                    + b"".join(textures.values()) + rw_chunk(3, b""))


def material_environment(data, fields):
    for kind, ext, ext_end in fields:
        if kind != 3:
            continue
        for plugin, start, end in chunks(data, ext, ext_end):
            if plugin == 0x120 and end - start >= 24:
                effect, slot, coefficient = struct.unpack_from("<IIf", data, start)
                if (effect, slot) == (2, 2):
                    return round(coefficient * 100), (ext, ext_end, start - 12, end)
    return 0, None


def vehicle_surface_key(rgba, tex):
    tex = {"xv_vehiclegrunge_sl": "vehiclegrunge256", "xv_vehiclegeneric_sl": "vehiclegeneric256",
           "vehiclescratch64": "xv_scratch_sl"}.get(tex, tex)
    return rgba, tex


def original_vehicle_reflections(data):
    candidates = {}

    def visit(start, end):
        for kind, body, finish in chunks(data, start, end):
            if kind in (0x10, 0x1A, 0x0F, 8):
                visit(body, finish)
            elif kind == 7:
                fields = list(chunks(data, body, finish))
                material = next(lo for tag, lo, _ in fields if tag == 1)
                rgba = data[material + 4:material + 8]
                for tag, lo, hi in fields:
                    if tag != 6:
                        continue
                    offset, text_end = next((a, b) for field, a, b in chunks(data, lo, hi) if field == 2)
                    tex = data[offset:text_end].split(b"\0", 1)[0].decode("ascii").lower()
                    weight, _ = material_environment(data, fields)
                    candidates.setdefault(vehicle_surface_key(rgba, tex), set()).add(weight)
                    # Retain a colour-only fallback for already reflective
                    # paint slots whose atlas was replaced by the SA port.
                    if weight and rgba[:3] in (b"\x3c\xff\x00", b"\xff\x00\xaf",
                                                b"\x00\xff\xff", b"\xff\x00\xff"):
                        candidates.setdefault((rgba, None), set()).add(weight)

    visit(0, len(data))
    return {key: next(iter(values)) for key, values in candidates.items() if len(values) == 1}


def complete_vehicle_textures(data, dictionary, shared, original, name, reflections):
    textures = native_textures(dictionary)
    common = {}
    # San Andreas selects the illuminated atlas by comparing the actual shared
    # texture pointer. A per-model copy of either lamp atlas breaks that switch.
    native = {"vehiclelights128", "vehiclelightson128"}
    if name == "hovercr":
        native.add("vortex128x64")  # The native Vortex model's local TXD.
    for texture in sorted(vehicle_material_textures(data) - textures.keys() - native):
        if texture in shared:
            common[texture] = shared[texture]
        elif texture in original:
            textures[texture] = original[texture]
        elif name == "admiral" and texture == "tablica":
            source = shared["backplate"]
            common[texture] = source[:32] + b"tablica".ljust(32, b"\0") + source[64:]
        else:
            raise ValueError(f"{name}: no raster for vehicle material {texture}")
    if textures.keys() & {"vehiclelights128", "vehiclelightson128"}:
        raise ValueError(f"{name}: lamp rasters must come from the native shared dictionary")
    def texture_name(value):
        encoded = value.encode("ascii")
        return rw_chunk(2, encoded.ljust((len(encoded) + 4) & ~3, b"\0"))

    def remap_texture(texture, atlas, prefix):
        alias = prefix + texture
        if len(alias) > 31:
            alias = f"{prefix}{zlib.crc32(texture.encode()):08x}"
        source = atlas[texture]
        atlas[alias] = source[:32] + alias.encode("ascii").ljust(32, b"\0") + source[64:]
        return alias

    def rebuild_material(start, end):
        fields = list(chunks(data, start, end))
        material = next(lo for kind, lo, _ in fields if kind == 1)
        rgb = tuple(data[material + 4:material + 7])
        alpha = data[material + 7]
        texture_chunk = next(((lo, hi) for kind, lo, hi in fields if kind == 6), None)
        if texture_chunk is None:
            # PS2 windscreens use translucent material colours. Bind the same
            # tint as a raster so the SA vehicle pipeline samples it, and keep
            # the material alpha used by its glass sorting and removal code.
            if 0 < alpha < 255 and rgb in ((102, 182, 194), (35, 62, 66), (54, 57, 89)):
                alias = "vcsglass_%02x%02x%02x%02x" % (*rgb, alpha)
                if alias not in textures:
                    # The model-local TXD owns this material's shader marker.
                    textures[alias] = vehicle_rgba_raster(alias, 1, 1, bytes((*rgb, alpha)))
                header = bytearray(data[material:material + 28])
                header[4:7] = b"\xff\xff\xff"
                struct.pack_into("<I", header, 12, 1)
                glass = rw_chunk(6, rw_chunk(1, struct.pack("<I", 0x1102))
                                 + texture_name(alias) + texture_name("") + rw_chunk(3, b""))
                return (data[start:material - 12] + rw_chunk(1, header) + glass
                        + data[material + 28:end])
            return data[start:end]

        lo, hi = texture_chunk
        offset, text_end = next((begin, stop) for kind, begin, stop in chunks(data, lo, hi) if kind == 2)
        texture = data[offset:text_end].split(b"\0", 1)[0].decode("ascii").lower()
        atlas = textures if texture in textures else common
        if texture not in atlas:
            return data[start:end]

        strength, reflection = material_environment(data, fields)
        original_strength = None
        if alpha == 255:
            rgba = bytes((*rgb, alpha))
            original_strength = reflections.get(vehicle_surface_key(rgba, texture))
            if original_strength is None and strength:
                original_strength = reflections.get((rgba, None))
            if original_strength is not None:
                strength = original_strength
        managed_reflection = strength in (5, 10, 20, 30, 50, 100)
        replace_effect = reflection and (managed_reflection or original_strength == 0)
        if managed_reflection:
            # Tag each reflective material independently of its base atlas.
            alias = remap_texture(texture, atlas, f"vcsenv_{strength:02d}_")
        elif texture in shared or atlas is common:
            # SA resolves textures in its global vehicle dictionary first.
            alias = remap_texture(texture, atlas, "vcstx_")
        elif not replace_effect:
            return data[start:end]
        else:
            alias = texture
        payload = data[lo:offset - 12] + texture_name(alias) + data[text_end:hi]
        tail = data[hi:end]
        if replace_effect:
            # SkyGfx draws this stage. Keep the other RenderWare extensions
            # and prevent SA from reinitializing this effect with its own frame.
            ext, ext_end, effect_start, effect_end = reflection
            tail = (data[hi:ext - 12] + rw_chunk(3, data[ext:effect_start] + data[effect_end:ext_end])
                    + data[ext_end:end])
        return data[start:lo - 12] + rw_chunk(6, payload) + tail

    def rebuild(start, end):
        result = bytearray()
        for kind, body, finish in chunks(data, start, end):
            payload = data[body:finish]
            if kind == 7:
                payload = rebuild_material(body, finish)
            elif kind in (0x10, 0x1A, 0x0F, 8):
                payload = rebuild(body, finish)
            result.extend(struct.pack("<II", kind, len(payload)))
            result.extend(data[body - 4:body])
            result.extend(payload)
        return bytes(result)

    data = rebuild(0, len(data))
    references = vehicle_material_textures(data)
    textures = {k: v for k, v in textures.items() if k not in shared or k in references}
    common = {k: v for k, v in common.items() if k in references}
    return data, build_texture_dictionary(textures, dictionary[26:28]), common


def compose(local, parent):
    # RenderWare matrices use row vectors and the final row is translation.
    result = [sum(local[row * 3 + axis] * parent[axis * 3 + col] for axis in range(3))
              for row in range(4) for col in range(3)]
    for col in range(3):
        result[9 + col] += parent[9 + col]
    return result


def apply_pedestrian_colours(data, model_info, palette, name):
    # 00329630 redraws the slots selected by the PS2 model's material table.
    # The four RGB tags below match the slot records in all exported models.
    tags = {b"\x00\xff\x3c": 0, b"\xff\x00\xaf": 1,
            b"\x3c\x00\xff": 2, b"\xff\x00\x3c": 3}
    slots = []
    for offset in range(0xB4, 0xE4, 8):
        pointer, slot = struct.unpack_from("<IB", model_info, offset)
        if pointer:
            slots.append(slot)

    def material_colours(start, end):
        for kind, payload, finish in chunks(data, start, end):
            if kind in (0x10, 0x1A, 0x0F, 8):
                yield from material_colours(payload, finish)
            elif kind == 7:
                struct_id, colour, _ = next(chunks(data, payload, finish))
                if struct_id != 1:
                    raise ValueError(f"{name}: invalid RenderWare material")
                yield colour + 4

    matched = []
    for offset in material_colours(0, len(data)):
        slot = tags.get(bytes(data[offset:offset + 3]))
        if slot is None:
            continue
        matched.append(slot)
        # Use the first original outfit. 00329668 resolves the index from
        # the shared RGB table or the model's six local RGB entries.
        colour_id = model_info[0x49 + slot]
        if model_info[0x47] == 0:
            rgb = b"\xff\xff\xff"
        elif colour_id < 0xF0:
            rgb = palette[colour_id * 3:colour_id * 3 + 3]
        else:
            start = colour_id * 3 - 0x237
            rgb = model_info[start:start + 3]
        if len(rgb) != 3:
            raise ValueError(f"{name}: invalid original pedestrian colour")
        data[offset:offset + 3] = rgb
    if matched != slots:
        raise ValueError(f"{name}: rendered material slots do not match the PS2 model")


def adapt_skin(data, vertex_count, old_indices, new_indices, name):
    bones, used_count, max_weights, _ = data[:4]
    indices_start = 4 + used_count
    weights_start = indices_start + vertex_count * 4
    matrices_start = weights_start + vertex_count * 16
    matrices_end = matrices_start + bones * 64
    if bones != len(old_indices) or data[matrices_end:] != bytes(12):
        raise ValueError(f"{name}: unsupported skin matrix table")

    remap = {old: new_indices[tag] for tag, old in old_indices.items()}
    indices = bytes(remap.get(index, 0) for index in data[indices_start:weights_start])
    matrices = bytearray()
    for tag, _ in SA_PED_BONES:
        original_tag = SA_EXTRA_BONES[tag][0] if tag in SA_EXTRA_BONES else tag
        start = matrices_start + old_indices[original_tag] * 64
        matrices.extend(data[start:start + 64])
    used = bytes(sorted(remap[index] for index in data[4:indices_start]))
    return (bytes((len(SA_PED_BONES), used_count, max_weights, 0)) + used + indices
            + data[weights_start:matrices_start] + matrices + data[matrices_end:])


def adapt_pedestrian(data, name, model_info, palette):
    data = bytearray(data)
    apply_pedestrian_colours(data, model_info, palette, name)
    _, clump, clump_end = next(chunks(data, 0, len(data)))
    _, frames, end = next(entry for entry in chunks(data, clump, clump_end) if entry[0] == 0x0E)
    frame_data, *extensions = list(chunks(data, frames, end))
    frame_base = frame_data[1] + 4
    tags = {}
    hierarchy = None
    corrections = {"jaw": 8, "l_finger": 35, "r_finger": 25, "l_toe0": 44, "r_toe0": 54}
    for index, (_, start, end) in enumerate(extensions):
        plugins = {kind: (begin, finish) for kind, begin, finish in chunks(data, start, end)}
        if 0x11E not in plugins:
            continue
        address, _ = plugins[0x11E]
        tag, count = struct.unpack_from("<ii", data, address + 4)
        if count:
            hierarchy = index, address, count
        begin, finish = plugins[0x253F2FE]
        frame_name = data[begin:finish].split(b"\0", 1)[0].decode("ascii").lower()
        replacement = corrections.get(frame_name, tag)
        if tag in tags:
            raise ValueError(f"{name}: duplicate VCS bone tag {tag}")
        tags[tag] = index, replacement
        struct.pack_into("<i", data, address + 4, replacement)
    if not hierarchy or len({tag for _, tag in tags.values()}) != len(tags):
        raise ValueError(f"{name}: invalid pedestrian hierarchy")

    # SA attaches the thighs to the pelvis. Compose the removed spine transform
    # into each thigh so the original bind-space skin matrices stay valid.
    pelvis, spine = tags[1][0], tags[2][0]
    for tag in (41, 51):
        offset = frame_base + tags[tag][0] * 56
        parent, = struct.unpack_from("<i", data, offset + 48)
        if parent == pelvis:
            continue
        spine_offset = frame_base + spine * 56
        if parent != spine or struct.unpack_from("<i", data, spine_offset + 48)[0] != pelvis:
            raise ValueError(f"{name}: unexpected thigh parent")
        thigh_matrix = struct.unpack_from("<12f", data, offset)
        spine_matrix = struct.unpack_from("<12f", data, spine_offset)
        struct.pack_into("<12fi", data, offset, *compose(thigh_matrix, spine_matrix), pelvis)

    hierarchy_frame, hierarchy_offset, count = hierarchy
    first = hierarchy_offset + 20
    old_indices = {tags[tag][1]: old for tag, old, _ in
                   struct.iter_unpack("<iii", data[first:first + count * 12])}
    new_indices = {tag: index for index, (tag, _) in enumerate(SA_PED_BONES)}
    if old_indices.keys() | SA_EXTRA_BONES.keys() != new_indices.keys():
        raise ValueError(f"{name}: unsupported pedestrian bone tags")
    new_hierarchy = bytearray(data[hierarchy_offset:first])
    struct.pack_into("<I", new_hierarchy, 8, len(new_indices))
    for index, (tag, flags) in enumerate(SA_PED_BONES):
        new_hierarchy.extend(struct.pack("<iii", tag, index, flags))

    frame_entries = bytearray(data[frame_base:frame_data[2]])
    extension_entries = bytearray()
    for index, (_, start, finish) in enumerate(extensions):
        if index != hierarchy_frame:
            extension_entries.extend(data[start - 12:finish])
            continue
        plugins = [rw_chunk(kind, new_hierarchy) if kind == 0x11E else data[payload - 12:limit]
                   for kind, payload, limit in chunks(data, start, finish)]
        extension_entries.extend(rw_chunk(3, b"".join(plugins)))
    frame_ids = {tag: index for index, tag in tags.values()}
    for tag, (parent, frame_name) in SA_EXTRA_BONES.items():
        # Additional SA nodes carry no VCS vertices. Attach them to their
        # standard parents without moving the original bind transforms.
        matrix = (1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0)
        frame_entries.extend(struct.pack("<12fiI", *matrix, frame_ids[parent], 0))
        extension_entries.extend(rw_chunk(3, rw_chunk(0x11E, struct.pack("<iii", 256, tag, 0))
                                         + rw_chunk(0x253F2FE, frame_name.encode() + b"\0")))
    frame_count = len(extensions) + len(SA_EXTRA_BONES)
    new_frames = rw_chunk(1, struct.pack("<I", frame_count) + frame_entries) + extension_entries

    def rebuild(start, finish, vertex_count=0):
        for kind, payload, limit in chunks(data, start, finish):
            if kind == 0x0E:
                yield rw_chunk(kind, new_frames)
            elif kind == 0x0F:
                vertices, = struct.unpack_from("<I", data, payload + 20)
                yield rw_chunk(kind, b"".join(rebuild(payload, limit, vertices)))
            elif kind in (0x1A, 3):
                yield rw_chunk(kind, b"".join(rebuild(payload, limit, vertex_count)))
            elif kind == 0x116:
                yield rw_chunk(kind, adapt_skin(data[payload:limit], vertex_count, old_indices, new_indices, name))
            else:
                yield data[payload - 12:limit]

    return rw_chunk(0x10, b"".join(rebuild(clump, clump_end)))


def build_img(entries):
    sector_size = 2048
    sector = (8 + 32 * len(entries) + sector_size - 1) // sector_size
    directory = bytearray(struct.pack("<4sI", b"VER2", len(entries)))
    contents = bytearray()
    for name, data in sorted(entries.items()):
        encoded = name.encode("ascii")
        if len(encoded) > 23:
            raise ValueError(f"IMG name is too long: {name}")
        count = (len(data) + sector_size - 1) // sector_size
        directory.extend(struct.pack("<IHH24s", sector, count, 0, encoded))
        contents.extend(data)
        contents.extend(bytes(count * sector_size - len(data)))
        sector += count
    directory.extend(bytes((-len(directory)) % sector_size))
    return bytes(directory + contents)
