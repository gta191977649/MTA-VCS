"""Extract and convert the USA PS2 concert assets using vcsconv and the PS2 map reader."""
import argparse
import math
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
from bisect import bisect_right

from timeline import read_replay

IFP_FPS = 60
SCM_AUDIO_RATE = 44100

MODELS = {
    "phcol": 146, "gtr1": 131, "gtr2": 134, "bmyst": 40,
    "ndc_philstick": 7483, "me_mainlightrig": 7493,
}
ANIMS = {
    "phil": 415, "phil_lipsync": 416, "pc_lead_look": 496, "pc_lead_sm_wail": 497,
    "pc_lead_wail": 498, "pc_lead_play": 499, "pc_bass_play": 500, "pc_bass_wait": 501,
    "pc_key_play": 502, "pc_key_funk": 503, "ren_c7_cut": 504,
}
BONE_NAMES = {
    0: "root", 1: "pelvis", 2: "spine", 3: "spine1", 4: "neck", 5: "head", 8: "jaw",
    21: "bip01_r_clavicle", 22: "r_upperarm", 23: "r_forearm", 24: "r_hand",
    25: "r_finger",
    31: "bip01_l_clavicle", 32: "l_upperarm", 33: "l_forearm", 34: "l_hand",
    35: "l_finger",
    41: "l_thigh", 42: "l_calf", 43: "l_foot", 44: "l_toe0",
    51: "r_thigh", 52: "r_calf", 53: "r_foot", 54: "r_toe0",
}
ACTORS = ("phcol", "gtr1", "gtr2", "bmyst")
# MTA's full-body animation mask is indexed in SA bone order. A partial mask
# uses that order even when the clump has a different HAnim traversal order.
MTA_BONES = (0, 1, 2, 3, 4, 5, 8, 6, 7, 31, 32, 33, 34, 35, 36, 21, 22, 23, 24, 25,
             26, 302, 301, 201, 41, 42, 43, 44, 51, 52, 53, 54, 28, 29, 30, 38, 39,
             40, 303, 304, 305, 306, 307, *range(5001, 5022))


def convert_models(game, archive, converter, output):
    from leeds import dictionary, raster
    from renderware import txd, txd_texture

    with tempfile.TemporaryDirectory(prefix="vcs-concert-") as temporary:
        temp = Path(temporary)
        game_file = temp / "game.dat"
        game_file.write_bytes(game.data)
        for name, model in MODELS.items():
            base = game.model(model)
            slot = struct.unpack_from("<h", game.data, base + 30)[0]
            txd_start, = struct.unpack_from("<I", game.data, game.stream + 8)
            for extension, index, ident in (
                ("dff", model, b"ldm\0"), ("txd", txd_start + slot, b"xet\0"),
            ):
                raw = game.stream_asset(archive, index)
                if not raw.startswith(ident):
                    raise ValueError(f"{name}.{extension}: unexpected stream header {raw[:4]!r}")
                target = output / f"{name}.{extension}"
                if extension == "txd":
                    textures = [txd_texture(key, raster(raw, address, 0)) for key, address in dictionary(raw)]
                    if not textures:
                        continue
                    target.write_bytes(txd(textures))
                else:
                    stream = temp / f"{name}.bin"
                    stream.write_bytes(raw)
                    subprocess.run([converter, "-v", "36003", "-g", game_file, stream, target], check=True)
                print(f"{name}.{extension}: stream {index}, {target.stat().st_size} bytes", flush=True)


def rw_chunks(data):
    offset = 0
    while offset < len(data):
        kind, size, version = struct.unpack_from("<III", data, offset)
        end = offset + 12 + size
        yield kind, data[offset + 12:end], data[offset:end], version
        offset = end


def rotation_quaternion(matrix):
    # RenderWare stores basis vectors as rows. Use the largest component
    # to avoid cancellation near the 180 degree rotations of limb joints.
    a, b, c, d, e, f, g, h, i = matrix
    candidates = (1 + a - e - i, 1 - a + e - i, 1 - a - e + i, 1 + a + e + i)
    axis = max(range(4), key=candidates.__getitem__)
    u = math.sqrt(candidates[axis]) / 2
    v = 0.25 / u
    return (
        (u, (b+d)*v, (c+g)*v, (f-h)*v),
        ((b+d)*v, u, (f+h)*v, (g-c)*v),
        ((c+g)*v, (f+h)*v, u, (b-d)*v),
        ((f-h)*v, (g-c)*v, (b-d)*v, u),
    )[axis]


def adapt_ped_dff(path):
    def offsets(data, start, end):
        while start < end:
            kind, size, _ = struct.unpack_from("<III", data, start)
            payload = start + 12
            start = payload + size
            yield kind, payload, start
        if start != end:
            raise ValueError("Invalid RenderWare chunk bounds")

    data = bytearray(path.read_bytes())
    _, clump, clump_end = next(item for item in offsets(data, 0, len(data)) if item[0] == 0x10)
    _, frames, frames_end = next(item for item in offsets(data, clump, clump_end) if item[0] == 0x0e)
    entries = list(offsets(data, frames, frames_end))
    _, frame_data, _ = entries[0]
    bind = {}
    remap = {}
    hierarchy = None
    for frame, (_, start, end) in enumerate(entries[1:]):
        plugins = {kind: (first, last) for kind, first, last in offsets(data, start, end)}
        if 0x11e not in plugins:
            continue
        first, _ = plugins[0x11e]
        tag, count = struct.unpack_from("<ii", data, first + 4)
        if count:
            hierarchy = first + 20, count
        name_first, name_last = plugins[0x253f2fe]
        name = data[name_first:name_last].split(b"\0", 1)[0].decode("ascii").lower()
        new_tag = {"jaw": 8, "l_finger": 35, "r_finger": 25, "l_toe0": 44, "r_toe0": 54}.get(name, tag)
        if new_tag in bind:
            raise ValueError(f"{path.name}: duplicate bone {new_tag}")
        remap[tag] = new_tag
        struct.pack_into("<i", data, first + 4, new_tag)
        matrix = struct.unpack_from("<9f", data, frame_data + 4 + frame * 56)
        bind[new_tag] = rotation_quaternion(matrix)

    first, count = hierarchy
    for index in range(count):
        offset = first + index * 12
        tag, matrix_index = struct.unpack_from("<ii", data, offset)
        if matrix_index != index:
            raise ValueError(f"{path.name}: unexpected matrix index {matrix_index}")
        struct.pack_into("<i", data, offset, remap[tag])
    if bind.keys() != BONE_NAMES.keys():
        raise ValueError(f"{path.name}: unexpected concert bone table {bind.keys()}")
    path.write_bytes(data)
    return bind


def copy_shared_stage_textures(source, output):
    dictionary_data = next(payload for kind, payload, _, _ in rw_chunks(source.read_bytes()) if kind == 0x16)
    wanted = {b"xc_dr_portacabin_door", b"xc_ndc_empirescorch"}
    selected = []
    for kind, payload, original, version in rw_chunks(dictionary_data):
        if kind != 0x15:
            continue
        info = next(data for entry, data, _, _ in rw_chunks(payload) if entry == 1)
        name = info[8:40].split(b"\0", 1)[0]
        if name in wanted:
            wanted.remove(name)
            selected.append(original)
    if wanted:
        raise ValueError(f"Missing shared VCS textures: {wanted}")
    info = struct.pack("<IIIHH", 1, 4, version, len(selected), 2)
    payload = info + b"".join(selected) + struct.pack("<III", 3, 0, version)
    output.write_bytes(struct.pack("<III", 0x16, len(payload), version) + payload)


def read_animations(data):
    if data[:4] != b"mina":
        raise ValueError("Expected a PS2 relocatable animation chunk")
    anims = {}
    for tree in struct.unpack_from("<11I", data, 32):
        name = data[tree + 4:tree + 28].split(b"\0", 1)[0].decode("ascii").lower()
        sequence, = struct.unpack_from("<I", data, tree)
        count, duration = struct.unpack_from("<If", data, tree + 28)
        tracks = {}
        for index in range(count):
            flags, frames, offset, bone, _ = struct.unpack_from("<HHIHH", data, sequence + 12 * index)
            translated = bool(flags & 2)
            layout = "<8e" if translated else "<5e"
            size = struct.calcsize(layout)
            keyframes = []
            tick = 0
            for x, y, z, w, delta, *position in struct.iter_unpack(layout, data[offset:offset + frames * size]):
                tick += round(delta * 30)
                keyframes.append((tick / 30, (x, y, z, w), position))
            if not keyframes:
                raise ValueError(f"{name} bone {bone}: empty track")
            if keyframes[-1][0] < duration:
                keyframes.append((duration, *keyframes[-1][1:]))
            tracks[bone] = keyframes
        anims[name] = (duration, tracks)
    if anims.keys() != ANIMS.keys():
        raise ValueError(f"Unexpected pc_conc animations: {anims.keys()}")
    return anims


def unit(rotation):
    length = math.sqrt(sum(component * component for component in rotation))
    return tuple(component / length for component in rotation)


def interpolate_rotation(left, right, weight):
    dot = sum(a * b for a, b in zip(left, right))
    if dot < 0:
        right = tuple(-component for component in right)
        dot = -dot
    if dot > 0.9995:
        return unit(tuple(a + (b - a) * weight for a, b in zip(left, right)))
    angle = math.acos(dot)
    scale = math.sin(angle)
    a = math.sin((1 - weight) * angle) / scale
    b = math.sin(weight * angle) / scale
    return tuple(a * x + b * y for x, y in zip(left, right))


def resample(frames, source_times):
    frames = [(time, unit(rotation), position) for time, rotation, position in frames]
    timestamps = [frame[0] for frame in frames]
    for tick, time in enumerate(source_times):
        index = bisect_right(timestamps, time)
        if not index or index == len(frames) or timestamps[index - 1] == time:
            rotation, position = frames[max(0, index - 1)][1:]
        else:
            first, last = frames[index - 1:index + 1]
            weight = (time - first[0]) / (last[0] - first[0])
            rotation = interpolate_rotation(first[1], last[1], weight)
            position = tuple(a + (b - a) * weight for a, b in zip(first[2], last[2]))
        yield tick / IFP_FPS, rotation, position


def bake_phil(anims, replay, end):
    # Combine body and lip seeks on the concert clock so GTA applies the jaw.
    reveal, = (position for position, _, kind, _ in replay if kind == "reveal")
    body_start = reveal / SCM_AUDIO_RATE
    mouth_start, = (position / SCM_AUDIO_RATE for position, _, kind, _ in replay if kind == "layer")
    cues = iter((position, kind, float(args[0])) for position, _, kind, args in replay
                if kind in ("root", "layerSeek"))
    cue = next(cues, None)
    body_times, mouth_times = [], []
    ticks = math.ceil((end - reveal) * IFP_FPS / SCM_AUDIO_RATE)
    for tick in range(ticks + 1):
        sample = reveal + tick * SCM_AUDIO_RATE / IFP_FPS
        seconds = sample / SCM_AUDIO_RATE
        while cue and cue[0] <= sample:
            position, kind, offset = cue
            if kind == "root":
                body_start = position / SCM_AUDIO_RATE - offset
            else:
                mouth_start = position / SCM_AUDIO_RATE - offset
            cue = next(cues, None)
        body_times.append(seconds - body_start)
        mouth_times.append(seconds - mouth_start)

    tracks = {bone: list(resample(frames, body_times)) for bone, frames in anims["phil"][1].items()}
    tracks[6] = list(resample(anims["phil_lipsync"][1][6], mouth_times))
    return ticks / IFP_FPS, tracks


def write_ifp(anims, bind_poses, output):
    # ANP3 preserves HAnim tags explicitly. ANPK's MTA parser infers them from names.
    package = bytearray(struct.pack("<24sI", b"pc_conc", len(anims)))
    for name, (duration, source_tracks) in anims.items():
        tracks = {(8 if bone == 6 else bone): frames for bone, frames in source_tracks.items()}
        if name != "phil":
            for bone, frames in tracks.items():
                if any(frame[1:] != frames[0][1:] for frame in frames[1:]):
                    end_tick = round(frames[-1][0] * IFP_FPS)
                    tracks[bone] = list(resample(frames, (tick / IFP_FPS for tick in range(end_tick + 1))))
        if name != "phil_lipsync":
            actor = ("gtr1" if name.startswith("pc_lead_") else
                     "gtr2" if name.startswith("pc_bass_") else
                     "bmyst" if name.startswith("pc_key_") else "phcol")
            for bone in MTA_BONES:
                quat = bind_poses[actor].get(bone, (0, 0, 0, 1))
                tracks.setdefault(bone, [(0, quat, ()), (duration, quat, ())])
        animation = bytearray()
        frame_bytes = 0
        for bone, frames in tracks.items():
            translated = bool(frames[0][2])
            label = BONE_NAMES.get(bone, f"bone_{bone}")
            animation.extend(struct.pack("<24s3i", label.encode(), 4 if translated else 3,
                                         len(frames), bone))
            keyframes = bytearray()
            previous = None
            for seconds, rotation, position in frames:
                sign = -1 if previous and sum(x*y for x, y in zip(rotation, previous)) < 0 else 1
                scale = sign / math.sqrt(sum(q*q for q in rotation))
                previous = tuple(q*scale for q in rotation)
                keyframes.extend(struct.pack("<5h", *(round(q * 4096) for q in previous), round(seconds * IFP_FPS)))
                if translated:
                    # Phil's root is applied in world space by actor.lua to match SCM resets.
                    xyz = (0, 0, 0) if name == "phil" else position
                    keyframes.extend(struct.pack("<3h", *(round(v * 1024) for v in xyz)))
            frame_bytes += len(keyframes)
            animation.extend(keyframes)
        package.extend(struct.pack("<24s3i", name.encode(), len(tracks), frame_bytes, 1))
        package.extend(animation)
    (output / "pc_conc.ifp").write_bytes(struct.pack("<4sI", b"ANP3", len(package)) + package)


def write_actor_data(anims, phil_root, output):
    lines = ["-- Generated from pc_conc by tools/cast.py.", "ConcertClips = {"]
    for name, (duration, _) in anims.items():
        lines.append(f'    [{ANIMS[name]}] = {{ "{name}", {duration:.6f} }},')
    lines.append("}")
    lines.append("ConcertPhilRoot = {")
    lines.extend("    {" + ", ".join(f"{value:.7g}" for value in (seconds, *position)) + "},"
                 for seconds, _, position in phil_root)
    lines.append("}")
    (output.parent / "actor_data.lua").write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("map_tools", type=Path, help="Local mta_map_tools checkout with the PS2 reader")
    parser.add_argument("vcsconv", type=Path, help="32-bit PS2 VCS build of librwgta storiesconv")
    parser.add_argument("output", type=Path, help="Resource assets directory")
    parser.add_argument("--shared-txd", type=Path, help="Existing converted VCS business.txd")
    options = parser.parse_args()
    sys.path.insert(0, str(options.map_tools))
    from ps2 import GameData

    options.output.mkdir(exist_ok=True, parents=True)
    game = GameData(options.disc)
    with (options.disc / "GTA3PS2.IMG").open("rb") as archive:
        anims = read_animations(game.stream_asset(archive, 8453))
        phil_root = anims["phil"][1][0]
        replay, end = read_replay((options.disc / "MAIN.txt").read_text(encoding="utf-8-sig", errors="replace"))
        anims["phil"] = bake_phil(anims, replay, end)
        convert_models(game, archive, options.vcsconv, options.output)
        bind_poses = {name: adapt_ped_dff(options.output / f"{name}.dff") for name in ACTORS}
        write_ifp(anims, bind_poses, options.output)
        write_actor_data(anims, phil_root, options.output)
    shared = options.shared_txd or options.output.parents[2] / "[vcs]" / "jconv" / "resources" / "business.txd"
    copy_shared_stage_textures(shared, options.output / "stage_props.txd")
