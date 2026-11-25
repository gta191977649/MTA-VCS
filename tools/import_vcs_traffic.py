"""Import verified VCS PS2 navigation data from a local SLUS-21590 USA disc.

The executable addresses cited below refer to the SHA-256 in PS2_EXECUTABLE.
Container offsets are offsets into the inflated GAME.DTZ, before relocation.
"""

import argparse
from collections import Counter, defaultdict
import hashlib
from itertools import accumulate
import json
import math
import os
from pathlib import Path
import re
import struct
import subprocess
import tempfile
import zlib

from vcs_model_assets import (
    adapt_pedestrian, airtrain_models, build_img, build_texture_dictionary, complete_vehicle_textures, native_textures,
    original_vehicle_reflections, vehicle_material_textures, vehicle_native_raster,
)
from vcs_rhino import restore_rhino
from vcs_vehicle_ground import ground_catalog
from vcs_police_materials import POLICE_MODELS, SHARED_SURFACES, source_motorcycle_beacon, source_siren_bar
from vcs_traffic_animations import convert_locomotion
from vcs_road_collision import analyze_road_turns
from vcs_pc_road_population import import_pc_road_population


PS2_EXECUTABLE = "3b43be57d60a29df35e41504d67bbf728d5ce2fc5aab6bbf928cbbc5963fe547"
GAME_DTZ = "570a7504048e8a0187b04b20fec63fc57c404c74b84e7d3ee19df8daab1a365b"
MAIN_SCM = "3cd356b27e6abedbcc59422840d96d31685f9de6911f9b968e544d5ce1ffdb32"
GTA3PS2_IMG = "a4de99ed3e96c4751b5573ab1d5b9680fba587b52b918bd98f993105dd9eb39e"
EDITION = "SLUS-21590 USA v1.00"
SCHEMA_VERSION = 1
GATG_ROOT = 0x20
NODE = struct.Struct("<hhbBhH")
VEHICLE_LINK = struct.Struct("<HH")
U16 = struct.Struct("<H")
U32 = struct.Struct("<I")
FLIGHT_POINT = struct.Struct("<4fI")
FLIGHT_SEGMENT = struct.Struct("<B3x4f")
ZONE = struct.Struct("<8s6f8x2H12x")
POPULATION_RECORD = struct.Struct("<36H")
PED_GROUP = struct.Struct("<16i")
ZONE_COMMANDS = {0x00AF: 12, 0x00B7: 12, 0x01F3: 2, 0x030A: 14}
POPULATION_BOOTSTRAP = ((0xC76A, 0xD49C), (0xD4AF, 0xE7EB))
GRAPH_NAME = "vcs_traffic.json"
MANIFEST_NAME = "vcs_traffic.manifest.json"
DEFAULT_OUTPUT = (
    Path(__file__).resolve().parents[1]
    / "mods/deathmatch/resources/[traffic]/npchlc_traffic/paths/generated"
)
MODEL_RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[model]/model"
ROAD_MAP = DEFAULT_OUTPUT.parents[3] / "[vcs]" / "jconv"
MODEL_TEMPLATES = Path(__file__).resolve().parent / "vcs_model"
CONVERTED_MODEL_RESOURCE = DEFAULT_OUTPUT.parents[3] / "[model]" / "vcs_model"
CONVERTED_MODELS = {8: "cop", 14: "male01", 34: "hmyap", 280: "airtrain"}
# These water models need separate client model IDs. Their server vehicles use
# native boat hulls; in particular the old JETSKI manifest points to a car.
WATER_MODEL_VARIANTS = {
    215: ("speeder", 452), 233: ("jetski", 473), 248: ("marquis", 484),
    249: ("rio", 484), 257: ("squalo", 446), 264: ("scarab", 446),
}
# The nine pairs installed by the initial MAIN.SCM set_gang_ped_models calls.
# The seventh slot starts with PGANG7A/B (89/90).
GANG_MODELS = ((91, 92), (93, 94), (95, 96), (97, 98), (99, 100),
               (101, 102), (89, 90), (105, 106), (107, 108))


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def verify_file(disc_directory, relative_path, expected_hash):
    source = disc_directory / relative_path
    data = source.read_bytes()
    if sha256(data) != expected_hash:
        raise ValueError(f"{source} is not the verified {EDITION} file")
    return data


def require(condition, description):
    if not condition:
        raise ValueError(description)


def table(image, offset, count, stride, name):
    end = offset + count * stride
    require(offset >= GATG_ROOT and end <= len(image), f"{name} exceeds GAME.DTZ bounds")
    return memoryview(image)[offset:end]


def vehicle_details(record, origin, destination):
    anchor = record["anchor"]
    require(anchor == min(origin, destination), "Vehicle link is not anchored at the lower endpoint")
    # 00430290 and 004361a8 select the outbound lane bits by the anchor endpoint.
    outbound = record["leftLanes"] if anchor == origin else record["rightLanes"]
    # 00312ce0 selects the controlled approach using flag 0x40 and the anchor.
    light_on_approach = record["lightGroup"] != 0 and (
        (anchor == origin) == bool(record["flags"] & 0x40)
    )
    return {
        "vehicleLinkId": record["id"],
        "vehicleFlags": record["flags"],
        "leftLanes": record["leftLanes"],
        "rightLanes": record["rightLanes"],
        "lanes": outbound,
        "lightGroup": record["lightGroup"],
        "lightDirection": light_on_approach,
    }


def read_graph(image, spawn_thresholds):
    # 00324a50 returns base+0x20, and 003321f0 stores root[0] into 00487490.
    graph, = U32.unpack_from(image, GATG_ROOT)
    table(image, graph, 1, 0x7BA8, "Path graph header")
    (node_offset, vehicle_offset, vehicle_index_offset, node_count, vehicle_count,
     pedestrian_count) = struct.unpack_from("<6I", image, graph)
    require((node_count, vehicle_count, pedestrian_count) == (8387, 3079, 5308),
            "Unexpected PS2 node partition or count")
    adjacency_offset, weights_offset = struct.unpack_from("<II", image, graph + 0x7BA0)
    declared_adjacency, declared_vehicle_indices = struct.unpack_from("<2H", image, graph + 0x1A)
    declared_vehicle_links, = U32.unpack_from(image, graph + 0x20)
    nodes = []
    adjacency_count = 0
    for index, (raw_x, raw_y, raw_z, width, first, flags) in enumerate(NODE.iter_unpack(
            table(image, node_offset, node_count, NODE.size, "Path nodes"))):
        count = flags & 0xF
        require(first == adjacency_count, f"Noncontiguous adjacency at node {index}")
        adjacency_count += count
        # 0040a418 and 00269228 decode these packed coordinates and width.
        z = raw_z - 100 if raw_z < 0 else raw_z
        water = bool(flags & 0x100)
        kind = "pedestrian" if index >= vehicle_count else "boat" if water else "vehicle"
        require(kind != "pedestrian" or not water, f"Water bit in pedestrian node {index}")
        nodes.append({
            "id": index, "x": raw_x / 8, "y": raw_y / 8, "z": z,
            "rawWidth": width, "width": width / 16, "firstLink": first, "linkCount": count,
            "flags": flags, "water": water, "kind": kind,
            "scene": "underground" if z < -50 else "outdoor",
            "speedClass": (flags >> 10) & 3,
            "spawnThreshold": spawn_thresholds[(flags >> 12) & 3],
        })

    vehicle_links_count = nodes[vehicle_count]["firstLink"]
    require((adjacency_count, vehicle_links_count) == (17652, 6354)
            == (declared_adjacency, declared_vehicle_indices),
            "Unexpected PS2 adjacency counts")
    vehicle_indices = [index for index, in U16.iter_unpack(
        table(image, vehicle_index_offset, vehicle_links_count, 2, "Vehicle adjacency indices"))]
    physical_count = max(vehicle_indices) + 1
    require(physical_count == declared_vehicle_links == 3177,
            "Unexpected PS2 physical vehicle link count")
    require(set(vehicle_indices) == set(range(physical_count)), "Gap in PS2 vehicle records")
    vehicle_links = []
    for index, (anchor_group, flags) in enumerate(VEHICLE_LINK.iter_unpack(
            table(image, vehicle_offset, physical_count, VEHICLE_LINK.size, "Vehicle links"))):
        vehicle_links.append({
            "id": index, "anchor": anchor_group & 0x3FFF, "lightGroup": anchor_group >> 14,
            "flags": flags, "leftLanes": (flags >> 3) & 7, "rightLanes": flags & 7,
        })

    adjacency = table(image, adjacency_offset, adjacency_count, 2, "Adjacency")
    weights = table(image, weights_offset, adjacency_count, 1, "Adjacency weights")
    links = []
    reverse_links = Counter()
    for node in nodes:
        start = node["firstLink"]
        for index in range(start, start + node["linkCount"]):
            word, = U16.unpack_from(adjacency, index * 2)
            target = word & 0x3FFF
            source = node["id"]
            require(target < node_count, f"Invalid target for adjacency {index}")
            require(node["kind"] == nodes[target]["kind"], f"Cross-partition adjacency {index}")
            link = {"id": index, "from": source, "to": target, "flags": word & 0xC000,
                    "weight": weights[index]}
            if index < vehicle_links_count:
                record = vehicle_links[vehicle_indices[index]]
                link.update(vehicle_details(record, source, target))
                # 00435fb8 reads the junction's class before shifting the
                # rail window. The next transition starts at this junction.
                link["speedClass"] = node["speedClass"]
                reverse_links[record["id"], source, target] += 1
            links.append(link)
    require(all(count == 1 and reverse_links[record, target, source] == 1
                for (record, source, target), count in reverse_links.items()),
            "Missing or duplicate reciprocal vehicle adjacency")
    offsets = {"pathGraph": graph, "nodes": node_offset, "vehicleLinks": vehicle_offset,
               "vehicleLinkIndices": vehicle_index_offset, "adjacency": adjacency_offset,
               "adjacencyWeights": weights_offset}
    return nodes, links, vehicle_links, offsets


def read_fake_plane(image):
    # 003321f0 loads root[0x2e] via 0022d088. 0022d1f8 and 0022d418 consume it.
    root, = U32.unpack_from(image, GATG_ROOT + 0x2E * 4)
    table(image, root, 1, 0x48, "Plane route header")
    length, takeoff, landing, duration = struct.unpack_from("<4f", image, root + 0xC)
    require(0 < takeoff < landing < length and 0 < duration < math.inf,
            "Invalid plane route header distances")
    count, point_offset = struct.unpack_from("<II", image, root + 0x40)
    require(count == 260, "Unexpected PS2 ambient aircraft point count")
    points = []
    previous = -1
    for index, (x, y, z, distance, flags) in enumerate(FLIGHT_POINT.iter_unpack(
            table(image, point_offset, count, FLIGHT_POINT.size, "Plane route points"))):
        require(all(math.isfinite(value) for value in (x, y, z, distance)),
                f"Invalid coordinate at plane point {index}")
        require(previous < distance < length, f"Invalid cumulative distance at plane point {index}")
        points.append({"id": index, "x": x, "y": y, "z": z, "distance": distance, "flags": flags})
        previous = distance
    segment_offset = root + 0x48
    rows = [dict(zip(("kind", "start", "distance", "velocity", "acceleration"), record))
            for record in FLIGHT_SEGMENT.iter_unpack(table(image, segment_offset, 6,
                    FLIGHT_SEGMENT.size, "Plane motion segments"))]
    require([row["kind"] for row in rows] == [1, 2, 1, 2, 1, 0],
            "Unexpected PS2 aircraft motion segments")
    require(rows[0]["start"] == points[0]["distance"] == 0 and rows[-1]["start"] == duration,
            "Invalid PS2 aircraft loop endpoints")
    for row, next_row in zip(rows, rows[1:]):
        row["end"] = next_row["start"]
        require(row["start"] < row["end"] and all(math.isfinite(value) for value in row.values()),
                "Invalid PS2 aircraft motion segment")
    route = {
        "id": "fake-plane", "kind": "fixedWing", "usage": "ambient", "originalModelId": 0x118,
        "loop": True, "points": points, "length": length, "takeoffDistance": takeoff,
        "landingDistance": landing, "clockDuration": duration, "motionSegments": rows[:-1],
        "motionEnd": rows[-1], "instances": 3, "clockPeriodMs": 0x80000, "phaseStepMs": 0x2AAAA,
    }
    return route, {"fakePlane": root, "fakePlanePoints": point_offset,
                   "fakePlaneMotion": segment_offset}


def model_name_key(name):
    return zlib.crc32(name.upper().encode("ascii")) ^ 0xFFFFFFFF


def vehicle_text_key(image, model_table, model_id):
    offset, = U32.unpack_from(image, model_table + model_id * 4)
    return image[offset + 0x158:offset + 0x160].split(b"\0")[0].decode("ascii")


def read_vehicle_bindings(image, resource):
    # 003321f0 passes root[6] and root[7] to 001a8198, which installs the model
    # table at 00486518 and recognizes vehicle model infos by byte +0x10 == 6.
    count, models = struct.unpack_from("<II", image, GATG_ROOT + 6 * 4)
    pointers = table(image, models, count, 4, "Model info pointers")
    vehicle_models, traffic_rules = {}, []
    for model_id in range(count):
        offset, = U32.unpack_from(pointers, model_id * 4)
        if not offset:
            continue
        info = table(image, offset, 1, 0x11, "Model info")
        if info[0x10] == 6:
            key, = U32.unpack_from(info, 8)
            require(key not in vehicle_models, "Duplicate PS2 vehicle model key")
            vehicle_models[key] = model_id
            # 003c8cd8 groups by the signed class byte and forwards frequency
            # to 00432e90 when adding a loaded model to the selection tables.
            info = table(image, offset, 1, 0x276, "Vehicle model info")
            frequency, traffic_class = struct.unpack_from("<Hxb", info, 0x272)
            traffic_rules.append({"originalId": model_id, "trafficClass": traffic_class,
                                  "frequency": frequency})
    require(vehicle_models[model_name_key("airtrain")] == 280,
            "Unexpected PS2 AIRTRAIN model key")

    # The existing MTA model resource uses stable server IDs for replacements.
    # Dynamically requested client IDs are deliberately excluded from the binding
    # table, since they are not valid IDs for a server-created vehicle.
    source = resource / "mod.lua"
    if not source.is_file():
        return [], traffic_rules, models
    manifest = source.read_text(encoding="utf-8").split("IMG_VEHICLE = {", 1)[1]
    manifest = re.sub(r"--\[\[.*?\]\]", "", manifest, flags=re.DOTALL)
    assets = {path.relative_to(resource).as_posix().casefold()
              for path in (resource / "src" / "vehicle").glob("*")}
    bindings = {}
    replacement_counts = Counter()
    for entry in re.finditer(r'\["[^"]+"\]\s*=\s*\{([^{}]+)\}', manifest):
        block = entry[1]
        if not re.search(r"\breplace\s*=\s*true\b", block):
            continue
        parent = re.search(r"\bparent\s*=\s*(\d+)", block)
        mesh = re.search(r'\bdff\s*=\s*"([^"]+\.dff)"', block)
        textures = re.search(r'\btxd\s*=\s*"([^"]+\.txd)"', block)
        if not (parent and mesh and textures):
            continue
        if mesh[1].casefold() not in assets or textures[1].casefold() not in assets:
            continue
        model = int(parent[1])
        replacement_counts[model] += 1
        name = Path(mesh[1]).stem.lower()
        model_id = vehicle_models.get(model_name_key(name))
        if model_id is None:
            continue
        require(model_id not in bindings, f"Duplicate local replacement for {name}")
        bindings[model_id] = {"originalId": model_id, "model": model, "name": name}
    stable = [bindings[model_id] for model_id in sorted(bindings)
              if replacement_counts[bindings[model_id]["model"]] == 1]
    return stable, traffic_rules, models


def read_traffic_model_sources(image, models, pedestrian_ids=(), vehicle_bindings=()):
    # 003cb7e0 installs root[0x17], 003c66b0 selects an entry by model ID,
    # 003c7ed8 reads the sector and size then converts each to bytes.
    streaming, = U32.unpack_from(image, GATG_ROOT + 0x17 * 4)
    entries, = U32.unpack_from(image, streaming + 0xC8)
    first_texture, = U32.unpack_from(image, streaming + 8)

    def locate(index):
        entry = table(image, entries + index * 0x18, 1, 0x18, "Model streaming entry")
        sector, sectors = struct.unpack_from("<II", entry, 0x10)
        require(sector < 0x1000000 and sectors > 0, "Invalid PS2 model sector range")
        return {"offset": sector * 2048, "size": sectors * 2048}

    assets = {}
    names = {original_id: f"ped_{original_id}" for original_id in pedestrian_ids}
    vehicles = {entry["originalId"]: entry for entry in vehicle_bindings}
    names.update({original_id: entry["name"].lower() for original_id, entry in vehicles.items()})
    names.update(CONVERTED_MODELS)
    for original_id, name in sorted(names.items()):
        model, = U32.unpack_from(image, models + original_id * 4)
        info = table(image, model, 1, 0x20, "Traffic model info")
        is_vehicle = original_id == 280 or original_id in vehicles
        require(info[0x10] == (6 if is_vehicle else 7),
                f"Unexpected PS2 model type for {name}")
        if original_id in CONVERTED_MODELS:
            key, = U32.unpack_from(info, 8)
            require(key == model_name_key(name), f"Unexpected PS2 model name key for {name}")
        # 003c7498 reads the slot. 003c6710 subtracts the streaming texture base
        # to recover the slot from a texture stream index.
        texture_slot, = struct.unpack_from("<h", info, 0x1E)
        require(texture_slot >= 0, f"Missing PS2 textures for {name}")
        assets[original_id] = {"name": name, "archive": "GTA3PS2.IMG",
                               **locate(original_id), "format": "PS2 MDL",
                               "textures": locate(first_texture + texture_slot),
                               "kind": "vehicle" if is_vehicle else "ped",
                               "base": vehicles[original_id]["model"] if original_id in vehicles
                               else {8: 280, 9: 285, 10: 286, 11: 287, 12: 274, 13: 277,
                                     117: 126, 118: 127, 119: 284, 280: 577}.get(original_id, 7)}
    return assets, entries


def police_helicopter_definition():
    # 003aae58, 002e9d00, 002ea060: a live target drives pursuit, not a waypoint asset.
    return {
        "id": "police-helicopter", "kind": "helicopter", "usage": "wanted",
        "originalModelId": 0x105, "pilotModelId": 8, "target": "wantedPlayer", "originalArea": 0,
        "minWantedLevel": 3, "maxWantedLevel": 6, "maxAircraft": 1,
        "spawnAttemptMs": 15000, "spawnRadius": 250, "spawnAngleStep": 0.02453125,
        "spawnBounds": {"minX": -2400, "maxX": 1600, "minY": -2000, "maxY": 2000},
        "heightAboveTarget": 50, "heightAboveTerrain": 20, "retireDistance": 170,
    }


def zone_commands(scm):
    # Both branches are called in order during the PS2 main-script bootstrap.
    # 00254b90 decodes zero (01), signed immediates (06/07/08), and strings (0A).
    for start, end in POPULATION_BOOTSTRAP:
        offset = start
        while offset < end:
            opcode, = U16.unpack_from(scm, offset)
            require(opcode in ZONE_COMMANDS and scm[offset + 2] == 0xA,
                    f"Unexpected population command at SCM offset {offset:#x}")
            label_end = scm.index(b"\0", offset + 3, offset + 11)
            label = scm[offset + 3:label_end].decode("ascii")
            offset = label_end + 1
            values = []
            for _ in range(ZONE_COMMANDS[opcode]):
                value_type = scm[offset]
                offset += 1
                if value_type == 1:
                    values.append(0)
                    continue
                encoding = {6: "<i", 7: "<b", 8: "<h"}.get(value_type)
                require(encoding is not None, f"Unexpected population value at SCM {offset - 1:#x}")
                value, = struct.unpack_from(encoding, scm, offset)
                values.append(value)
                offset += struct.calcsize(encoding)
            require(values[0] in (0, 1), f"Invalid day/night flag in {label}")
            yield opcode, label, values[0], values[1:]
        require(offset == end, f"Population command crosses SCM boundary {end:#x}")


def apply_zone_command(record, opcode, args):
    # 001cc248 -> 00367e68, 001cc5e0 -> 00367fb8, 001cc700 -> 003681b8,
    # 001cc7d0 -> 00367f28. The game stores cumulative thresholds in u16 slots.
    if opcode == 0x00AF:
        record[0] = args[0]
        record[14:23] = list(accumulate(args[1:10], initial=args[10]))[1:]
        record[23] = args[10]
    elif opcode == 0x00B7:
        record[24] = args[0]
        record[25:34] = list(accumulate(args[1:10], initial=args[10]))[1:]
        record[34] = args[10]
    elif opcode == 0x01F3:
        record[35] = args[0]
    else:
        record[1:14] = accumulate(args)


def read_population(image, scm):
    # 003321f0 sets the zones and pedestrian group pointers. Zone search
    # 00367bb0 is ordered, with index zero reserved as the fallback.
    zone_system, = U32.unpack_from(image, GATG_ROOT + 10 * 4)
    zone_offset, record_offset = struct.unpack_from("<II", image, zone_system + 0x10)
    zone_count, = U16.unpack_from(image, zone_system + 0x1A)
    require(zone_count == 168, "Unexpected number of PS2 population zones")
    zone_names = defaultdict(list)
    zones = []
    for index, (name, min_x, min_y, min_z, max_x, max_y, max_z, day, night) in enumerate(
            ZONE.iter_unpack(table(image, zone_offset, zone_count, ZONE.size, "Population zones"))):
        bounds = (min_x, min_y, min_z, max_x, max_y, max_z)
        require(all(math.isfinite(value) for value in bounds)
                and all(low <= high for low, high in zip(bounds[:3], bounds[3:])),
                f"Invalid bounds at population zone {index}")
        label = name.rstrip(b"\0").decode("ascii")
        zone_names[label].append((day, night))
        zones.append({"id": index, "name": label, "minX": min_x, "minY": min_y, "minZ": min_z,
                      "maxX": max_x, "maxY": max_y, "maxZ": max_z, "day": day, "night": night})
    record_count = 1 + max(max(zone["day"], zone["night"]) for zone in zones)
    require(record_count == 335, "Unexpected number of PS2 population records")
    records = [list(record) for record in POPULATION_RECORD.iter_unpack(
        table(image, record_offset, record_count, POPULATION_RECORD.size, "Population records"))]
    command_counts = Counter()
    skipped_names = set()
    for opcode, label, day, args in zone_commands(scm):
        command_counts[opcode] += 1
        matched = zone_names.get(label)
        if not matched:
            skipped_names.add(label)
            continue
        for day_record, night_record in matched:
            apply_zone_command(records[day_record if day else night_record], opcode, args)
    require(command_counts == {0x00AF: 88, 0x00B7: 88, 0x01F3: 88, 0x030A: 76},
            "Unexpected number of SCM population mutations")
    require(all(len(record) == 36 and all(0 <= word <= 0xFFFF for word in record) for record in records),
            "Invalid population record after SCM bootstrap")
    group_count = 1 + max(record[-1] for record in records)
    require(group_count == 71, "Unexpected number of PS2 pedestrian model groups")
    group_offset, = U32.unpack_from(image, GATG_ROOT + 0x26 * 4)
    ped_groups = list(PED_GROUP.iter_unpack(
        table(image, group_offset, group_count, PED_GROUP.size, "Pedestrian model groups")))
    require(all(-1 <= model <= 170 for group in ped_groups for model in group),
            "Invalid PS2 pedestrian group model ID")
    # 00432788 and 00432800 span rating slots 0..8 for road and 9..12 for water.
    # 00432b38 selects from the corresponding 25-entry rows and size table.
    vehicle_group_offset, vehicle_size_offset = struct.unpack_from("<II", image, GATG_ROOT + 8 * 4)
    sizes = struct.unpack_from("<13I", image, vehicle_size_offset)
    require(all(0 < size <= 25 for size in sizes), "Invalid PS2 vehicle group size")
    vehicle_groups = []
    for index, size in enumerate(sizes):
        group = struct.unpack_from(f"<{size}I", image, vehicle_group_offset + index * 100)
        require(all(171 <= model <= 280 for model in group), "Invalid PS2 vehicle group model ID")
        vehicle_groups.append(group)
    data = {"zones": zones, "records": [{"id": index, "values": row} for index, row in enumerate(records)],
            "pedGroups": ped_groups, "vehicleGroups": vehicle_groups, "gangModels": GANG_MODELS}
    offsets = {"zoneSystem": zone_system, "populationZones": zone_offset,
               "populationRecords": record_offset, "pedestrianGroups": group_offset,
               "vehicleGroups": vehicle_group_offset, "vehicleGroupSizes": vehicle_size_offset}
    script_details = {"populationBootstrapRanges": POPULATION_BOOTSTRAP,
                      "populationCommands": sum(command_counts.values()),
                      "unmatchedZoneLabels": sorted(skipped_names)}
    return data, offsets, script_details


def apply_initial_road_closures(scm, nodes, links):
    # Contiguous road/ped switches ending at the main-script RETURN. Mission
    # bytecode later in MAIN.SCM must not affect the free-roam initial state.
    offset, end = 0xEF77, 0xF38E
    disabled = set()
    while offset < end:
        opcode, = U16.unpack_from(scm, offset)
        require(opcode in (0x122, 0x152), f"Unexpected road setup at {offset:#x}")
        offset += 2
        corners = []
        for _ in range(6):
            size = {3: 1, 4: 2, 5: 3, 9: 4}.get(scm[offset])
            require(size is not None, f"Unexpected SCM road coordinate at {offset:#x}")
            offset += 1
            corners.append(struct.unpack("<f", bytes(4 - size) + scm[offset:offset + size])[0])
            offset += size
        if opcode == 0x152:
            continue
        bounds = list(zip(map(min, corners[:3], corners[3:]), map(max, corners[:3], corners[3:])))
        # 0036C748 -> 0026A388 (inclusive bounds) -> 0026AB80.
        stack = [n for n in nodes if n["kind"] != "pedestrian" and all(
            low <= n[axis] <= high for axis, (low, high) in zip("xyz", bounds))]
        while stack:
            node = stack.pop()
            if node["flags"] & 0x20 or node["id"] in disabled:
                continue
            disabled.add(node["id"])
            if node["linkCount"] < 3:
                for link in links[node["firstLink"]:node["firstLink"] + node["linkCount"]]:
                    target = nodes[link["to"]]
                    if target["linkCount"] < 3:
                        stack.append(target)
    require(offset == end and scm[end:end + 2] == b"\x26\0", "Unexpected road setup terminator")
    for index in disabled:
        nodes[index]["flags"] |= 0x20
    return len(disabled)


def assemble(disc_directory, vcs_pc_directory=None):
    executable = verify_file(disc_directory, "SLUS_215.90", PS2_EXECUTABLE)
    compressed = verify_file(disc_directory, "PS2/GAME.DTZ", GAME_DTZ)
    scm = verify_file(disc_directory, "MAIN.SCM", MAIN_SCM)
    image = zlib.decompress(compressed)
    magic, version, size = struct.unpack_from("<4sII", image)
    require((magic, version, size) == (b"GATG", 1, len(image)), "Invalid GAME.DTZ container")
    # PT_LOAD maps ELF file offset 0x1000 to address 0x00100000. 00430290
    # uses the minimum of these endpoint thresholds against the low random nibble.
    lookup_offset = 0x00487498 - 0x00100000 + 0x1000
    thresholds = tuple(executable[lookup_offset:lookup_offset + 4])
    require(thresholds == (0, 4, 7, 15), "Unexpected PS2 path spawn threshold table")
    nodes, links, vehicle_links, graph_offsets = read_graph(image, thresholds)
    initial_closures = apply_initial_road_closures(scm, nodes, links)
    road_turn_closures, road_collision = analyze_road_turns(nodes, links, ROAD_MAP)
    plane, flight_offsets = read_fake_plane(image)
    bindings, vehicle_model_rules, model_table = read_vehicle_bindings(image, MODEL_RESOURCE)
    model_sources, streaming_table = read_traffic_model_sources(image, model_table)
    plane["modelSource"] = model_sources[280]
    population, population_offsets, script_details = read_population(image, scm)
    script_details["additionalDisabledVehicleNodes"] = initial_closures
    pedestrian_ids = {model for group in population["pedGroups"] for model in group if model >= 0} | {8, 14}
    driver_masks = {}
    for original_id in sorted(pedestrian_ids):
        pointer, = U32.unpack_from(image, model_table + original_id * 4)
        driver_masks[str(original_id)], = U32.unpack_from(image, pointer + 0x3C)
    graph = {"schemaVersion": SCHEMA_VERSION, "edition": EDITION, "nodes": nodes, "links": links,
             "modelProvider": "vcs_model", "fallbackDriverModelId": 14, "vehicleSteeringLimits": {"234": 0.7},
             "vehicleLinks": vehicle_links, "routes": [plane],
             "dynamicRoutes": [police_helicopter_definition()], "population": population,
             "modelBindings": bindings, "vehicleModelRules": vehicle_model_rules,
             "pedestrianDriverMasks": driver_masks, "roadTurnClosures": road_turn_closures}
    manifest = {
        "schemaVersion": SCHEMA_VERSION,
        "edition": EDITION,
        "sources": {"SLUS_215.90": PS2_EXECUTABLE, "PS2/GAME.DTZ": GAME_DTZ, "MAIN.SCM": MAIN_SCM},
        "inflatedOffsets": {**graph_offsets, **flight_offsets, **population_offsets,
                            "modelInfoPointers": model_table, "streamingTable": streaming_table},
        "script": script_details,
        "convertedRoadCollision": road_collision,
        "trafficModelSources": model_sources,
        "counts": {"nodes": dict(Counter(node["kind"] for node in nodes)),
                   "directedLinks": dict(Counter(nodes[link["from"]]["kind"] for link in links)),
                   "physicalVehicleLinks": len(vehicle_links), "ambientPlanePoints": len(plane["points"]),
                   "populationZones": len(population["zones"]),
                   "populationRecords": len(population["records"]),
                   "pedestrianGroups": len(population["pedGroups"]),
                   "vehicleGroups": len(population["vehicleGroups"]),
                   "localVehicleBindings": len(bindings),
                   "vehicleModelRules": len(vehicle_model_rules),
                   "undergroundNodes": sum(node["scene"] == "underground" for node in nodes)},
        "coverage": {"verified": ["road", "pedestrian", "water", "ambientFixedWing", "wantedHelicopter",
                                  "populationBootstrap"],
                     "remaining": ["scriptSpecificRouteCallSites", "scriptPopulationChangesAfterBootstrap"],
                     "scriptRouteHandlers": [
                         {"opcode": "0041", "handler": "0010cb68", "kind": "pedestrian"},
                         {"opcode": "004a", "handler": "003d0910", "kind": "vehicle"},
                         {"opcode": "01b6", "handler": "003d2f80", "kind": "vehicle"},
                         {"opcode": "01bf", "handler": "003d3330", "kind": "boat"},
                         {"opcode": "02da", "handler": "003d5618", "kind": "helicopter"},
                     ]},
        "evidence": {
            "dataRoot": ["003321f0", "00324a50"],
            "nodesAndPartition": ["0042d898", "0040a418", "00269228"],
            "waterAndSpawn": ["00430290", "0043c130"],
            "vehicleLinksAndLights": ["00430290", "004361a8", "0026a2b0", "00312ce0"],
            "roadSpeedAndSpline": ["00435fb8", "0042a818", "00433ae8", "002d13d0", "002d1bc0",
                                    "00318528", "00318870", "0047fcc8"],
            "fixedWing": ["0022d088", "0022d098", "0022d1f8", "0022d418"],
            "modelBindings": ["003321f0", "001a8198", "003cb7e0", "003c66b0", "003c7ed8",
                              "003c7498", "003c6710",
                              "003c8cd8", "00432e90"],
            "wantedHelicopter": ["003aae58", "002e9d00", "002ea060"],
            "population": ["00367bb0", "00367da8", "00368260", "002b35b0", "00432b38"],
            "scriptPopulation": ["001cc248", "001cc5e0", "001cc700", "001cc7d0"],
        },
    }
    if vcs_pc_directory is not None:
        graph["roadPopulation"], manifest["vcsPcRoadPopulationSources"] = import_pc_road_population(vcs_pc_directory)
    return graph, manifest


def encode_json(value, *, readably=False):
    return (json.dumps(value, allow_nan=False, indent=2 if readably else None,
                       separators=None if readably else (",", ":")) + "\n").encode("utf-8")


def write_atomic(target, contents):
    path = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, delete=False) as stream:
            path = Path(stream.name)
            stream.write(contents)
        os.replace(path, target)
    finally:
        if path is not None:
            path.unlink(missing_ok=True)


def validate_pc_texture_dictionary(data, name):
    offset, textures = 12, 0
    while offset < len(data):
        kind, length = struct.unpack_from("<II", data, offset)
        end = offset + 12 + length
        require(end <= len(data), f"Invalid RenderWare chunk size in {name}")
        if kind == 0x15:
            require(length >= 16 and struct.unpack_from("<I", data, offset + 24)[0] == 9,
                    f"{name} requires D3D9 rasters. Build vcsconv with build_vcs_model_converter.py.")
            textures += 1
        offset = end
    require(textures > 0, f"No native textures in {name}")


def export_traffic_models(disc, converter, destination, population, vehicle_bindings, *, street_peds=False):
    executable = converter.resolve(strict=True)
    raw_game = zlib.decompress(verify_file(disc, "PS2/GAME.DTZ", GAME_DTZ))
    model_table, = U32.unpack_from(raw_game, GATG_ROOT + 7 * 4)
    # 003321F0 and 003297A8 install this table. 00329668 reads its RGB triples.
    palette_offset, = U32.unpack_from(raw_game, GATG_ROOT + 0x1C * 4)
    palette = table(raw_game, palette_offset, 0xF0, 3, "Pedestrian RGB palette")
    pedestrian_ids = {model for group in population["pedGroups"] for model in group if model >= 0}
    if street_peds:
        pedestrian_ids.update((9, 10, 11, 12, 13, 117, 118, 119))
        pedestrian_ids.update(model for group in GANG_MODELS for model in group)
    if not street_peds:
        vehicle_bindings = list(vehicle_bindings)
        # The scripted VCPD Maverick has a separate mesh from the patrol Maverick.
        vehicle_bindings.append({"originalId": 279, "model": 497, "name": "chopper"})
        vehicle_bindings = [entry for entry in vehicle_bindings if entry["originalId"] not in POLICE_MODELS]
        for original_id, (name, base) in (WATER_MODEL_VARIANTS | POLICE_MODELS).items():
            pointer, = U32.unpack_from(raw_game, model_table + original_id * 4)
            key, = U32.unpack_from(raw_game, pointer + 8)
            require(key == model_name_key(name), f"Unexpected PS2 vehicle model for {name}")
            vehicle_bindings.append({"originalId": original_id, "model": base, "name": name})
    model_sources, _ = read_traffic_model_sources(raw_game, model_table, pedestrian_ids, vehicle_bindings)
    if street_peds:
        model_sources = {key: value for key, value in model_sources.items() if value["kind"] == "ped"}
    outputs = {"ped": {}, "vehicle": {}}
    if street_peds:
        templates = {"jaw_c.lua": (MODEL_TEMPLATES / "jaw_c.lua").read_bytes()}
    else:
        templates = {name: (MODEL_TEMPLATES / name).read_bytes()
                     for name in ("model_bindings_s.lua", "model_bindings_c.lua", "locomotion_c.lua", "jaw_c.lua",
                                  "vehicle_lamps.fx")}
        for name in ("vehiclelights128.png", "vehiclelightson128.png"):
            templates[name] = (MODEL_RESOURCE / "src" / "generic" / name).read_bytes()
        source_dir = MODEL_RESOURCE / "src" / "vehicle"
        shared_dictionary = (source_dir / "vehshare.txd").read_bytes()
        shared_vehicle_textures = native_textures(shared_dictionary)
        used_common_textures = {}
        for texture, donor in (("cubanbody128c", "CUBAN.txd"), ("ponybits_ca", "PONY.txd"),
                               ("barracks_slats", "BARRACKS.txd"), ("barracksbits", "BARRACKS.txd")):
            shared_vehicle_textures[texture] = native_textures((source_dir / donor).read_bytes())[texture]
        for name, offset in (("xv_vehiclegeneric_sl", 0x55CB0), ("xv_vehiclegrunge_sl", 0x55D10)):
            shared_vehicle_textures[name] = vehicle_native_raster(raw_game, name, offset)
        police_surfaces = {name: (source, vehicle_native_raster(raw_game, source, offset))
                           for name, (source, offset) in SHARED_SURFACES.items()}
    with tempfile.TemporaryDirectory(prefix="vcs-traffic-models-") as temp_dir:
        workspace = Path(temp_dir)
        game_dat = workspace / "game.dat"
        game_dat.write_bytes(raw_game)
        with (disc / "GTA3PS2.IMG").open("rb") as archive:
            digest = hashlib.sha256()
            for block in iter(lambda: archive.read(1024 * 1024), b""):
                digest.update(block)
            require(digest.hexdigest() == GTA3PS2_IMG, "GTA3PS2.IMG is not the verified PS2 archive")
            for original_id, asset in model_sources.items():
                if asset["kind"] == "vehicle" and original_id not in (279, 280):
                    # Reuse the project's SA-ready VCS vehicle conversions. A
                    # direct PS2 mesh conversion misses SA vehicle dummies and
                    # the embedded collision that the native renderer expects.
                    name = asset["name"]
                    for suffix, chunk_id in (("dff", 0x10), ("txd", 0x16)):
                        filename = f'{name}.{suffix}'
                        data = (source_dir / filename).read_bytes()
                        kind, length, _ = struct.unpack_from("<III", data)
                        require(kind == chunk_id and length <= len(data) - 12,
                                f"Invalid existing VCS vehicle asset {filename}")
                        outputs["vehicle"][filename] = data[:length + 12]
                    geometry = outputs["vehicle"][name + ".dff"]
                    dictionary = outputs["vehicle"][name + ".txd"]
                    original_model = workspace / (name + ".mdl")
                    original_dff = workspace / (name + ".dff")
                    archive.seek(asset["offset"])
                    raw = archive.read(asset["size"])
                    require(len(raw) == asset["size"] and raw.startswith(b"ldm\0"),
                            f"Invalid PS2 vehicle source {name}")
                    original_model.write_bytes(raw)
                    result = subprocess.run(
                        [str(executable), "-v", "36003", "-g", str(game_dat),
                         str(original_model), str(original_dff)],
                        cwd=workspace, capture_output=True, text=True, timeout=60,
                    )
                    require(result.returncode == 0 and original_dff.is_file(),
                            f"PS2 material conversion failed for {name}: {result.stderr.strip()}")
                    original_geometry = original_dff.read_bytes()
                    reflections = original_vehicle_reflections(original_geometry)
                    if original_id == 246:
                        geometry, dictionary = restore_rhino(geometry, dictionary, raw_game, model_table, workspace, executable)
                    elif name == "policem":
                        geometry = source_siren_bar(geometry, original_geometry)
                    elif name == "electrap":
                        geometry = source_motorcycle_beacon(geometry, original_geometry)
                    external = {"vehiclelights128", "vehiclelightson128", "tablica", "vortex128x64"}
                    missing = vehicle_material_textures(geometry) - native_textures(dictionary).keys()
                    original = {}
                    if original_id in POLICE_MODELS or missing - shared_vehicle_textures.keys() - external:
                        entry = asset["textures"]
                        archive.seek(entry["offset"])
                        texture_input = workspace / (name + ".tex")
                        texture_output = workspace / (name + ".txd")
                        texture_input.write_bytes(archive.read(entry["size"]))
                        result = subprocess.run(
                            [str(executable), "-v", "36003", "-g", str(game_dat),
                             str(texture_input), str(texture_output)],
                            cwd=workspace, capture_output=True, text=True, timeout=60,
                        )
                        require(result.returncode == 0 and texture_output.is_file(),
                                f"Conversion failed for {texture_input.name}: {result.stderr.strip()}")
                        original_dictionary = texture_output.read_bytes()
                        validate_pc_texture_dictionary(original_dictionary, texture_output.name)
                        original = native_textures(original_dictionary)
                    geometry, dictionary, common = complete_vehicle_textures(
                        geometry, dictionary, shared_vehicle_textures, original, name, reflections,
                        police_surfaces if original_id in POLICE_MODELS else None)
                    used_common_textures.update(common)
                    outputs["vehicle"][name + ".dff"] = geometry
                    outputs["vehicle"][name + ".txd"] = dictionary
                    continue
                for entry, suffix, output_suffix, signature, chunk_id in (
                    (asset, "mdl", "dff", b"ldm\0", 0x10),
                    (asset["textures"], "tex", "txd", b"xet\0", 0x16),
                ):
                    archive.seek(entry["offset"])
                    raw = archive.read(entry["size"])
                    name = asset["name"]
                    require(len(raw) == entry["size"] and raw.startswith(signature),
                            f"Invalid original {name}.{suffix} chunk")
                    source = workspace / f"{name}.{suffix}"
                    output = source.with_suffix(f".{output_suffix}")
                    source.write_bytes(raw)
                    result = subprocess.run(
                        [str(executable), "-v", "36003", "-g", str(game_dat), str(source), str(output)],
                        cwd=workspace, capture_output=True, text=True, timeout=60,
                    )
                    require(result.returncode == 0 and output.is_file(),
                            f"Conversion failed for {source.name}: {result.stderr.strip()}")
                    converted = output.read_bytes()
                    kind, length, version = struct.unpack_from("<III", converted)
                    require((kind, length, version) == (chunk_id, len(converted) - 12, 0x1803FFFF),
                            f"Invalid RenderWare 3.6 output for {output.name}")
                    if chunk_id == 0x16:
                        validate_pc_texture_dictionary(converted, output.name)
                    elif asset["kind"] == "ped":
                        model_offset, = U32.unpack_from(raw_game, model_table + original_id * 4)
                        info = table(raw_game, model_offset, 1, 0xFC, "Pedestrian model info")
                        converted = adapt_pedestrian(converted, output.name, info, palette)
                    outputs[asset["kind"]][output.name] = converted

    if street_peds:
        destination.mkdir(parents=True, exist_ok=True)
        catalog = ["StreetPedModels = {"]
        for model, asset in model_sources.items():
            catalog.append(f'    [{model}] = {{base={asset["base"]}, name="{asset["name"]}"}},')
        catalog.extend(("}", ""))
        animations, groups = convert_locomotion(raw_game, disc / "GTA3PS2.IMG", model_table, model_sources,
                                               street_evades=True)
        officer_files = {f"ped_{model}.{ext}" for model in (9, 10, 11, 117, 118, 119) for ext in ("dff", "txd")}
        officer_image = build_img({name: data for name, data in outputs["ped"].items() if name in officer_files})
        image = build_img({name: data for name, data in outputs["ped"].items() if name not in officer_files})
        for name, data in {"police.img": officer_image, "street.img": image, "street.ifp": animations,
                           "models.lua": "\n".join(catalog).encode("ascii"), "groups.lua": groups,
                           "jaw_c.lua": templates["jaw_c.lua"]}.items():
            write_atomic(destination / name, data)
        return {"models": len(model_sources), "sha256": sha256(image)}

    outputs["vehicle"]["vehshare.txd"] = build_texture_dictionary(used_common_textures, shared_dictionary[26:28])
    catalog = ["VCS_TRAFFIC_MODEL_CATALOG = {"]
    for original_id, asset in model_sources.items():
        kind, base = asset["kind"], asset["base"]
        variant = ", variant = true" if original_id in WATER_MODEL_VARIANTS or original_id in (218, 279) else ""
        label = f', textKey = "{vehicle_text_key(raw_game, model_table, original_id)}"' if kind == "vehicle" else ""
        catalog.append(f'    [{original_id}] = {{kind = "{kind}", base = {base}, name = "{asset["name"]}"{variant}{label}}},')
    catalog.append("}")
    templates["model_catalog.lua"] = ("\n".join(catalog) + "\n").encode("utf-8")
    templates.update(airtrain_models(outputs["vehicle"]["airtrain.dff"]))
    templates["vehicle_ground_catalog.lua"] = ground_catalog(
        {id: asset["name"] for id, asset in model_sources.items() if asset["kind"] == "vehicle"},
        outputs["vehicle"],
    )
    templates["traffic_locomotion.ifp"], templates["locomotion_catalog.lua"] = convert_locomotion(
        raw_game, disc / "GTA3PS2.IMG", model_table,
        {model_id for model_id, asset in model_sources.items() if asset["kind"] == "ped"},
    )
    lines = ["<meta>",
             '    <export function="HasModelLoaded" type="client" />',
             '    <script src="model_catalog.lua" type="shared" />',
             '    <script src="model_bindings_s.lua" type="server" />',
             '    <script src="locomotion_catalog.lua" type="client" />',
             '    <script src="locomotion_c.lua" type="client" />',
             '    <script src="jaw_c.lua" type="client" />',
             '    <script src="vehicle_ground_catalog.lua" type="client" />',
             '    <script src="model_bindings_c.lua" type="client" />',
             '    <min_mta_version client="1.6.0-9.22676" />',
             '    <export function="getVcsVehicleCatalog" type="client" />',
             '    <export function="getVcsModelBase" type="server" />',
             '    <export function="getVcsModelIdByName" type="server" />',
             '    <export function="getVcsVehicleGroundGeometry" type="client" />',
             '    <export function="getVcsVehicleRenderMaterials" type="client" />',
             '    <export function="getTrafficModelBase" type="server" />',
             '    <export function="getTrafficFixedWingLOD" type="client" />',
             '    <file src="airtrain_vlo.dff" />',
             '    <file src="airtrain_lo.dff" />',
             '    <file src="airtrain_hi.dff" />',
             '    <file src="airtrain.col" />',
             '    <export function="getTrafficVehicleGroundGeometry" type="client" />',
             '    <file src="traffic_locomotion.ifp" />',
             '    <file src="vehicle_lamps.fx" />',
             '    <file src="vehiclelights128.png" />',
             '    <file src="vehiclelightson128.png" />',
             '    <file src="ped.img" />',
             '    <file src="vehicle.img" />']
    lines.append("</meta>")
    destination.mkdir(parents=True, exist_ok=True)
    archives = {kind + ".img": build_img(entries) for kind, entries in outputs.items()}
    for name, contents in {**templates, **archives}.items():
        write_atomic(destination / name, contents)
    write_atomic(destination / "meta.xml", ("\n".join(lines) + "\n").encode())
    return {name: {"size": len(data), "sha256": sha256(data), "entries": len(outputs[name[:-4]])}
            for name, data in archives.items()}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc_directory", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--verify-only", action="store_true", help="validate and count without writing")
    parser.add_argument("--convert-models", type=Path, metavar="VCSCONV",
                        help="convert the selected local traffic models using a Win32 vcsconv executable")
    parser.add_argument("--model-output", type=Path, default=CONVERTED_MODEL_RESOURCE)
    parser.add_argument("--street-peds", type=Path, metavar="VCSCONV",
                        help="Convert PS2 street pedestrian skins and locomotion into npchlc_traffic/ped_models")
    local_pc = Path("D:/Game/vcs_pc_edition")
    parser.add_argument("--vcs-pc-dir", type=Path, default=local_pc if local_pc.is_dir() else None,
                        help="Use the locally installed VCS PC Edition for road population density")
    args = parser.parse_args()
    if args.verify_only and (args.convert_models or args.street_peds):
        parser.error("Asset conversion cannot be combined with --verify-only")
    try:
        graph, manifest = assemble(args.disc_directory, args.vcs_pc_dir)
        encoded = encode_json(graph)
        manifest["output"] = {"name": GRAPH_NAME, "sha256": sha256(encoded), "size": len(encoded)}
        if args.convert_models:
            manifest["convertedModels"] = export_traffic_models(
                args.disc_directory, args.convert_models, args.model_output, graph["population"], graph["modelBindings"]
            )
            manifest["sources"]["GTA3PS2.IMG"] = GTA3PS2_IMG
        if args.street_peds:
            manifest["streetPedestrians"] = export_traffic_models(
                args.disc_directory, args.street_peds, DEFAULT_OUTPUT.parents[1] / "ped_models",
                graph["population"], [], street_peds=True)
        if not args.verify_only:
            args.output.mkdir(parents=True, exist_ok=True)
            write_atomic(args.output / GRAPH_NAME, encoded)
            write_atomic(args.output / MANIFEST_NAME, encode_json(manifest, readably=True))
    except (OSError, ValueError, struct.error, zlib.error, subprocess.TimeoutExpired) as error:
        parser.error(str(error))
    print(encode_json(manifest, readably=True).decode("utf-8"), end="")


if __name__ == "__main__":
    main()
