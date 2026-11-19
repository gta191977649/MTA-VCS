"""Extract freeroam vehicle quotas from the local VCS PC Edition."""

from hashlib import sha256
import re


BOOTSTRAP_SHA256 = "f7c41ae3a2381361df97c83782eaeed0c1b36ccb72345386eff0ef8da0a66289"
BOOTSTRAP = slice(0x1CE21, 0x1D04B)
ZONE_COMMAND = re.compile(rb"([\x67\x6a\x6c])\x07\x09([A-Z0-9\x00]{8})\x04(.)", re.S)
DEFAULT_TYPE = 5
# Default MaxNumberOfCarsInUse at 0x8A5B24, used by 0x43011F.
DEFAULT_CAR_LIMIT = 12


def read_zone_settings(script):
    if sha256(script).hexdigest() != BOOTSTRAP_SHA256:
        raise ValueError("Unrecognized VCS PC main.scm. The population bootstrap must be verified for this build")
    types, dealers, gangs = {}, {}, {}
    bootstrap = script[BOOTSTRAP]
    for command in ZONE_COMMAND.finditer(bootstrap):
        opcode, raw_label, operand = command.groups()
        label = raw_label.rstrip(b"\x00").decode("ascii")
        value = operand[0]
        if opcode == b"\x67":
            types[label] = value
        elif opcode == b"\x6a":
            dealers[label] = value
        else:
            data_type, strength = bootstrap[command.end():command.end() + 2]
            if data_type != 4 or value >= 10:
                raise ValueError(f"Unexpected gang strength operand for {label}")
            gangs.setdefault(label, {})[value] = strength
    if len(types) != 37 or len(gangs) != 4:
        raise ValueError("Incomplete VCS PC population bootstrap")
    return types, dealers, gangs


def read_popcycle(data):
    rows = []
    for line in data.decode("latin-1").splitlines():
        fields = line.split("//", 1)[0].split()
        if fields:
            values = list(map(int, fields))
            if len(values) != 24 or any(not 0 <= value <= 255 for value in values):
                raise ValueError("Invalid VCS PC popcycle row")
            rows.append(values[1:6])
    if len(rows) != 20 * 24:
        raise ValueError("Expected 24 VCS PC popcycle rows for each of 20 population types")
    return rows


def zone_bounds(data):
    for line in data.decode("latin-1").splitlines():
        fields = [field.strip() for field in line.split(",")]
        if len(fields) == 1:
            continue
        if len(fields) != 10:
            raise ValueError(f"Invalid VCS PC zone row {line!r}")
        if int(fields[1]) not in (0, 1):
            continue
        a, b, c, x, y, z = (int(float(value)) for value in fields[2:8])
        yield fields[0].upper(), [min(a, x), min(b, y), min(c, z), max(a, x), max(b, y), max(c, z)]


def traffic_schedule(rows, pop_type, dealer_strength, gang_strength):
    # CPopCycle::UpdatePercentages and GenerateOneRandomCar (0x430138).
    dealers = max(0.10, dealer_strength / 100)
    gangs = min(0.50, sum(gang_strength.values()) / 100)
    cops = max(0.03, 0.30 - gangs) if gangs >= 0.15 else max(0.02, gangs)
    if pop_type in (4, 14, 16):
        cops = max(cops, 0.10)
    elif pop_type == 5:
        cops = max(cops, 0.05)
    elif pop_type in (8, 17):
        cops = 0
    total = max(1, dealers + gangs + cops)
    shares = (dealers / total, gangs / total, cops / total, max(0, 1 - dealers - gangs - cops))
    return [round(cars * sum(multiplier * share for multiplier, share in zip(multipliers, shares)) / 100, 9)
            for cars, *multipliers in rows[pop_type * 24:(pop_type + 1) * 24]]


def import_pc_road_population(root):
    names = ("data/popcycle.dat", "data/info.zon", "data/navig.zon", "data/main.scm")
    popcycle, info, navig, main = sources = [(root / name).read_bytes() for name in names]
    rows = read_popcycle(popcycle)
    types, dealers, gangs = read_zone_settings(main)

    def profile(label):
        pop_type = types.get(label, DEFAULT_TYPE)
        return traffic_schedule(rows, pop_type, dealers.get(label, 0), gangs.get(label, {}))

    regions = list(zone_bounds(info)) + list(zone_bounds(navig))
    if not regions:
        raise ValueError("No VCS PC road population zones found")
    schedules = {label: profile(label) for label in dict.fromkeys(label for label, _ in regions)}
    data = {"cap": DEFAULT_CAR_LIMIT, "fallback": profile(""), "schedules": schedules, "zones": regions}
    manifest = {name: sha256(source).hexdigest() for name, source in zip(names, sources)}
    return data, manifest
