"""Convert VCS PS2 pedestrian locomotion trees to MTA's ANP3 format."""

import math
import struct
from bisect import bisect_right


GROUP = struct.Struct("<24s20sII")
TREE = struct.Struct("<I24sHxxf")
TRACK = struct.Struct("<HHIHH")
U32 = struct.Struct("<I")
FRAME = (struct.Struct("<5e"), struct.Struct("<8e"))
ANP3_RATE = 60
SECTOR_SIZE = 2048
NATIVE_LOCOMOTION = ("Walk_civi", "run_civi", "sprint_panic", "idle_stance")
EVADE_ASSOCIATIONS = {0x0C: "idle_tired", 0x95: "roadcross", 0x0F: "idle_taxi", 0x84: "getup", 0x87: "getup_front", 0x91: "ev_step",
                      0x92: "ev_dive", 0x9C: "handsup", 0x9D: "handscower"}
BONE_TAGS = {6: 8, 2000: 35, 2001: 25, 2002: 44, 2003: 54}


def u32(data, offset):
    return U32.unpack_from(data, offset)[0]


def name_of(raw):
    return raw.split(b"\0", 1)[0].decode("ascii").lower()


def unit(rotation):
    scale = 1 / math.sqrt(sum(value * value for value in rotation))
    return tuple(value * scale for value in rotation)


def interpolate(left, right, fraction):
    dot = sum(a * b for a, b in zip(left, right))
    if dot < 0:
        right = tuple(-value for value in right)
        dot = -dot
    if dot > 0.9995:
        return unit(tuple(a + (b - a) * fraction for a, b in zip(left, right)))
    angle = math.acos(dot)
    first = math.sin((1 - fraction) * angle) / math.sin(angle)
    second = math.sin(fraction * angle) / math.sin(angle)
    return tuple(first * a + second * b for a, b in zip(left, right))


def multiply(parent, local):
    x, y, z, w = parent
    a, b, c, d = local
    return unit((w*a + x*d + y*c - z*b, w*b - x*c + y*d + z*a,
                 w*c + x*b - y*a + z*d, w*d - x*a - y*b - z*c))


def rotation_sampler(frames):
    ticks = [frame[0] for frame in frames]

    def at(tick):
        index = bisect_right(ticks, tick)
        if not index or index == len(ticks) or ticks[index - 1] == tick:
            return frames[max(index - 1, 0)][1]
        fraction = (tick - ticks[index - 1]) / (ticks[index] - ticks[index - 1])
        return interpolate(frames[index - 1][1], frames[index][1], fraction)

    return at


def read_animation(data, tree, upper_body=False):
    sequence, raw_name, count, duration = TREE.unpack_from(data, tree)
    name = name_of(raw_name)
    end_tick = round(duration * ANP3_RATE)
    tracks = {}
    for index in range(count):
        flags, frame_count, offset, bone, _ = TRACK.unpack_from(data, sequence + index * TRACK.size)
        if not flags & 1 or not frame_count:
            continue
        # VCS stores rotation, elapsed time and optional translation as half
        # floats. Round accumulated seconds to ANP3's 60 Hz absolute ticks.
        layout = FRAME[bool(flags & 2)]
        bone = BONE_TAGS.get(bone, bone)
        seconds = 0
        frames = []
        for frame in layout.iter_unpack(data[offset:offset + frame_count * layout.size]):
            seconds += frame[4]
            tick = round(seconds * ANP3_RATE)
            frames.append((tick, unit(frame[:4]), frame[5:]))
        if not frames or tick > end_tick or bone in tracks:
            raise ValueError(f"{name}: invalid PS2 track for bone {bone}")
        if tick < end_tick:
            frames.append((end_tick, *frames[-1][1:]))
        tracks[bone] = frames

    # The converted DFF attaches the thighs to the pelvis as SA does. Fold
    # the former animated spine parent's rotation into both thigh tracks.
    if upper_body and tracks and tracks.keys().isdisjoint({0, 1, 2, 41, 51}):
        return tracks
    if not {0, 1, 2, 41, 51} <= tracks.keys():
        raise ValueError(f"{name}: incomplete PS2 locomotion hierarchy")
    spine = rotation_sampler(tracks[2])
    for bone in (41, 51):
        frames = tracks[bone]
        if frames[0][2] or tracks[2][0][2]:
            raise ValueError(f"{name}: found translated spine or thigh track")
        thigh = rotation_sampler(frames)
        tracks[bone] = [(tick, multiply(spine(tick), thigh(tick)), ())
                        for tick in range(end_tick + 1)]
    return tracks


def block_trees(image, archive_path, index, offset, embedded_trees):
    _, loaded, first, count = struct.unpack_from("<20sI4xII", image, offset)
    if loaded:
        return image, [embedded_trees + (first + i) * 40 for i in range(count)]

    streaming = u32(image, 0x7C)
    entry = u32(image, streaming + 0xC8) + (u32(image, streaming + 16) + index) * 24
    sector, sectors = struct.unpack_from("<II", image, entry + 16)
    with archive_path.open("rb") as archive:
        archive.seek(sector * SECTOR_SIZE)
        data = archive.read(sectors * SECTOR_SIZE)
    if data[:4] != b"mina":
        raise ValueError(f"Animation block {index} is not a PS2 relocatable chunk")
    return data, struct.unpack_from(f"<{count}I", data, 32)


def write_ifp(animations):
    package = bytearray(struct.pack("<24sI", b"vcs_traffic_locomotion", len(animations)))
    for name, tracks in sorted(animations.items()):
        animation = bytearray()
        frame_bytes = 0
        for bone, frames in sorted(tracks.items()):
            translated = bool(frames[0][2])
            animation.extend(struct.pack("<24s3i", f"bone_{bone}".encode(), 4 if translated else 3,
                                         len(frames), bone))
            start = len(animation)
            previous = None
            for tick, rotation, position in frames:
                if previous and sum(a * b for a, b in zip(previous, rotation)) < 0:
                    rotation = tuple(-value for value in rotation)
                animation.extend(struct.pack("<5h", *(round(value * 4096) for value in rotation), tick))
                if translated:
                    animation.extend(struct.pack("<3h", *(round(value * 1024) for value in position)))
                previous = rotation
            frame_bytes += len(animation) - start
        package.extend(struct.pack("<24s3i", name.encode(), len(tracks), frame_bytes, 1))
        package.extend(animation)
    return struct.pack("<4sI", b"ANP3", len(package)) + package


def convert_locomotion(image, archive_path, model_table, pedestrian_ids, *, street_evades=False):
    # GATG root slot 0x18 points to the PS2 animation manager. Its association
    # arrays precede the embedded animation hierarchy and block pointers.
    manager = u32(image, 0x80)
    associations = manager + 200 * GROUP.size
    tail = associations + 990 * 56
    trees, blocks, _, block_count = struct.unpack_from("<4I", image, tail + 12)
    block_indices = {name_of(image[blocks + index * 48:blocks + index * 48 + 20]): index
                     for index in range(block_count)}
    models = {model: u32(image, u32(image, model_table + model * 4) + 0x30)
              for model in sorted(pedestrian_ids)}
    locations = {}
    groups = {}
    animations = {}

    for group in sorted(set(models.values())):
        _, raw_block, first, count = GROUP.unpack_from(image, manager + group * GROUP.size)
        block = name_of(raw_block)
        # The standard group begins with two jaw animations. Each civilian
        # movement group then uses the same walk/back/run/sprint/idle slots.
        start = first + (2 if group == 0 else 0)
        if start + 5 > first + count:
            raise ValueError(f"Incomplete PS2 locomotion group {group}")
        if block not in locations:
            index = block_indices[block]
            data, addresses = block_trees(image, archive_path, index, blocks + index * 48, trees)
            locations[block] = data, {name_of(data[tree + 4:tree + 28]): tree for tree in addresses}
        data, offsets = locations[block]
        groups[group] = []
        for ordinal in (0, 2, 3, 4):
            address = associations + (start + ordinal) * 56
            name = name_of(image[address + 4:address + 48])
            clip = f"{block}_{name}"
            if len(clip) > 23:
                raise ValueError(f"Animation name is too long: {clip}")
            if clip not in animations:
                animations[clip] = read_animation(data, offsets[name])
            groups[group].append(clip)

    native = ", ".join(f'"{name}"' for name in NATIVE_LOCOMOTION)
    catalog = [f"VCS_TRAFFIC_NATIVE_LOCOMOTION = {{{native}}}",
               "VCS_TRAFFIC_LOCOMOTION_GROUPS = {"]
    for group, clips in groups.items():
        entries = ", ".join(f'"{clip}"' for clip in clips)
        catalog.append(f"    [{group}] = {{{entries}}},")
    catalog.extend(("}", "VCS_TRAFFIC_PEDESTRIAN_GROUPS = {"))
    catalog.extend(f"    [{model}] = {group}," for model, group in models.items())
    catalog.append("}")
    if street_evades:
        index = block_indices["ped"]
        data, addresses = block_trees(image, archive_path, index, blocks + index * 48, trees)
        offsets = {name_of(data[tree + 4:tree + 28]): tree for tree in addresses}
        catalog.append("VCS_TRAFFIC_EVADE_CLIPS = {")
        for ordinal, name in EVADE_ASSOCIATIONS.items():
            address = associations + ordinal * 56
            if u32(image, address) != ordinal or name_of(image[address+4:address+48]) != name:
                raise ValueError(f"Unexpected PS2 pedestrian association at {ordinal:#x}")
            tracks = read_animation(data, offsets[name])
            root = tracks[0]
            duration = round(root[-1][0] * 1000 / ANP3_RATE)
            catalog.append(f"    {name} = {{duration={duration}, motion={{")
            # The syncer can apply full root motion to the entity. Observers
            # already receive its position and need the in-place rendition.
            x0, y0, _ = root[0][2]
            for tick, _, (x, y, _) in root:
                ms = round(tick * 1000 / ANP3_RATE)
                catalog.append(f"        {{{ms}, {x-x0:.6f}, {y-y0:.6f}}},")
            catalog.append("    }},")
            animations[f"{name}_root"] = dict(tracks)
            tracks[0] = [(tick, rotation, (0, 0, z)) for tick, rotation, (_, _, z) in root]
            animations[name] = tracks
            if name in ("handsup", "handscower"):
                # Preserve the original raise, then hold until the longest PS2
                # gunpoint wait. MTA can play this once with freezeLastFrame off.
                animations[f"{name}_wait"] = {
                    bone: [*frames, (6 * ANP3_RATE, *frames[-1][1:])]
                    for bone, frames in tracks.items()
                }
        catalog.append("}")
        for group, ordinal, expected, alias in ((26, 0xDF, "cpr", "service_cpr"), (0, 0x97, "arrestgun", "service_arrest")):
            _, raw_block, first, count = GROUP.unpack_from(image, manager + group * GROUP.size)
            record = next(address for i in range(first, first + count)
                          if u32(image, address := associations + i * 56) == ordinal)
            if name_of(image[record+4:record+48]) != expected:
                raise ValueError(f"Unexpected PS2 service animation {ordinal:#x}")
            idx = block_indices[name_of(raw_block)]
            source, entries = block_trees(image, archive_path, idx, blocks + idx * 48, trees)
            tree = next(t for t in entries if name_of(source[t+4:t+28]) == expected)
            animations[alias] = read_animation(source, tree)
    catalog.append("")
    return write_ifp(animations), "\n".join(catalog).encode("ascii")
