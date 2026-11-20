"""Extract the USA PS2 vehicle damage factors used by the traffic collision response."""

import argparse
import csv
from pathlib import Path
import struct
import zlib

from import_vcs_frontend import import_sound_bank
from import_vcs_traffic import DEFAULT_OUTPUT, GAME_DTZ, GATG_ROOT, U32, table, verify_file, write_atomic


def export(disc, destination):
    image = zlib.decompress(verify_file(disc, "PS2/GAME.DTZ", GAME_DTZ))
    count, models = struct.unpack_from("<II", image, GATG_ROOT + 6 * 4)
    rows, masses, door_flags, service_cars = [], [], [], []
    for model, (offset,) in enumerate(U32.iter_unpack(table(image, models, count, 4, "Model info pointers"))):
        if offset and image[offset + 0x10] == 6:
            handling, = U32.unpack_from(image, offset + 0x38)
            record = table(image, handling, 1, 0xD4, "Vehicle handling")
            factor, = struct.unpack_from("<f", record, 0xC8)
            if not handling or not 0 < factor < float("inf"):
                raise ValueError(f"Invalid collision damage factor for original model {model}")
            rows.append(f"    [{model}] = {factor:.9g},")
            mass, = struct.unpack_from("<f", record, 0xBC)
            if not 0 < mass < float("inf"):
                raise ValueError(f"Invalid mass for original model {model}")
            masses.append(f"    [{model}] = {mass:.9g},")
            all_flags = U32.unpack_from(record, 0xD0)[0]
            if image[offset + 0x275] != 255:
                label = image[offset + 0x158:offset + 0x160].split(b"\0")[0].decode("ascii")
                assert label.isalnum() or "_" in label, label
                convertible = "true" if all_flags & 0x800 else "false"
                service_cars.append(f'    [{model}] = {{"{label}", {convertible}}},')
            flags = all_flags & 7
            if flags:
                door_flags.append(f"    [{model}] = {flags},")
    lines = ["-- tools/vehicle_impact_import.py, SLUS_215.90 handling + 0xC8.",
             "TrafficCollisionHandling = {", *rows, "}",
             "TrafficVehicleMass = {", *masses, "}",
             "TrafficCarjackHandlingFlags = {", *door_flags, "}",
             "TrafficServiceCars = {", *service_cars, "}", ""]
    write_atomic(destination, "\n".join(lines).encode("ascii"))
    print(f"Exported {len(rows)} vehicle collision damage factors")


def export_service_sound(disc, output):
    files = {}
    import_sound_bank(disc, files, 0, {"service_suspension": [(255, b"SFX_SHAG_SUSPENS")]})
    for name, content in files.items():
        write_atomic(output / name, content)


def export_decisions(pc, destination):
    data = pc / "data"
    families = ("gangmbr", "cop", "R_Norm", "R_Tough", "R_Weak", "fireman")
    lines = ["-- VCS PC Edition decision event 73, player relationship, occupied vehicle.",
             "local responses = {"]
    for index, family in enumerate(families):
        with (data / "decision" / (family + ".ped")).open(encoding="ascii") as source:
            row = next((row for row in csv.reader(source) if row[:1] == ["73"]), [])
        entries = []
        for start in range(2, len(row) - 12, 13):
            task, weight = int(row[start]), float(row[start + 3])
            if task >= 0 and weight > 0 and int(row[start + 5]):
                entries.append(f"{{{task}, {weight:g}}}")
        lines.append(f"    [{index}] = {{" + ", ".join(entries) + "},")
    lines += ["}", "TrafficCrashDecisions = {"]
    for line in (data / "pedstats.dat").read_text(encoding="ascii").splitlines():
        fields = line.partition("#")[0].split()
        if fields and fields[0].startswith("STAT_"):
            family = int(fields[-1])
            if family not in range(len(families)):
                raise ValueError(f"Unknown decision maker for {fields[0]}")
            lines.append(f"    {fields[0]} = responses[{family}],")
    write_atomic(destination, "\n".join([*lines, "}", ""]).encode("ascii"))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT.parents[1] / "traffic_collision_handling.lua")
    parser.add_argument("--vcs-pc-dir", type=Path, help="Also import the PC edition's player collision decisions")
    args = parser.parse_args()
    export(args.disc, args.output)
    export_service_sound(args.disc, args.output.parent)
    if args.vcs_pc_dir:
        export_decisions(args.vcs_pc_dir, args.output.with_name("traffic_crash_decisions.lua"))
