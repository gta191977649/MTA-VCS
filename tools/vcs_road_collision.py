"""Find traffic turns that cross raised strips in the converted road collision meshes."""

from collections import defaultdict
import math
import re
import struct


CELL_SIZE = 8
ROAD_MODEL = re.compile(r".+_r\d+$", re.IGNORECASE)


def road_instances(map_root):
    for ipl in sorted((map_root / "data/maps").rglob("*")):
        if ipl.suffix.lower() != ".ipl":
            continue
        for line in ipl.read_text(encoding="latin-1").splitlines():
            fields = [field.strip() for field in line.split(",")]
            if len(fields) != 11 or not ROAD_MODEL.fullmatch(fields[1]) or fields[2] != "0":
                continue
            collision = map_root / "resources" / (fields[1] + ".col")
            if collision.is_file():
                yield collision, tuple(map(float, fields[3:10]))


def collision_faces(collision, transform):
    data = collision.read_bytes()
    if data[:4] != b"COL3":
        return
    x, y, z, qx, qy, qz, qw = transform
    norm = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
    qx, qy, qz, qw = -qx / norm, -qy / norm, -qz / norm, qw / norm
    count, = struct.unpack_from("<H", data, 76)
    vertices, faces = struct.unpack_from("<II", data, 96)
    if vertices + 4 > faces + 4 or faces + 4 + count * 8 > len(data):
        raise ValueError(f"Invalid converted road collision {collision}")
    transformed = {}
    for face in range(count):
        indices = struct.unpack_from("<3H", data, faces + 4 + face * 8)
        for index in indices:
            if index in transformed:
                continue
            offset = vertices + 4 + index * 6
            if offset + 6 > faces + 4:
                raise ValueError(f"Invalid converted road vertex {collision}")
            a, b, c = (value / 128 for value in struct.unpack_from("<3h", data, offset))
            tx, ty, tz = 2 * (qy * c - qz * b), 2 * (qz * a - qx * c), 2 * (qx * b - qy * a)
            transformed[index] = (x + a + qw * tx + qy * tz - qz * ty,
                                  y + b + qw * ty + qz * tx - qx * tz,
                                  z + c + qw * tz + qx * ty - qy * tx)
        yield tuple(transformed[index] for index in indices)


def road_surfaces(map_root):
    cells = defaultdict(list)
    models = 0
    for collision, transform in road_instances(map_root):
        models += 1
        for a, b, c in collision_faces(collision, transform):
            ax, ay, az = a
            bx, by, bz = b
            cx, cy, cz = c
            ux, uy, uz, vx, vy, vz = bx - ax, by - ay, bz - az, cx - ax, cy - ay, cz - az
            determinant = ux * vy - uy * vx
            if abs(determinant) < 1e-6:
                continue
            face = (ax, ay, az, vy / determinant, -vx / determinant,
                    -uy / determinant, ux / determinant, uz, vz)
            for i in range(math.floor(min(ax, bx, cx) / CELL_SIZE), math.floor(max(ax, bx, cx) / CELL_SIZE) + 1):
                for j in range(math.floor(min(ay, by, cy) / CELL_SIZE), math.floor(max(ay, by, cy) / CELL_SIZE) + 1):
                    cells[i, j].append(face)
    return cells, models


def ground_height(cells, x, y, nominal):
    nearest, error = None, 2.0
    for ax, ay, az, ua, ub, va, vb, uz, vz in cells.get((math.floor(x / CELL_SIZE), math.floor(y / CELL_SIZE)), ()):
        u, v = (x - ax) * ua + (y - ay) * ub, (x - ax) * va + (y - ay) * vb
        if min(u, v, 1 - u - v) < -1e-6:
            continue
        z = az + u * uz + v * vz
        difference = abs(z - nominal)
        if difference < error:
            nearest, error = z, difference
    return nearest


def lane_centres(nodes, edge):
    start, end = nodes[edge["from"]], nodes[edge["to"]]
    dx, dy = end["x"] - start["x"], end["y"] - start["y"]
    length = math.hypot(dx, dy)
    if not length:
        return []
    x, y, z = tuple((start[axis] + end[axis]) * 0.5 for axis in "xyz")
    if edge["leftLanes"] and edge["rightLanes"]:
        first_offset = 2.5 + max(start["rawWidth"], end["rawWidth"]) / 16
    else:
        first_offset = (1 - edge["lanes"]) * 2.5
    return [(x + dy * (first_offset + lane * 5) / length,
             y - dx * (first_offset + lane * 5) / length, z) for lane in range(edge["lanes"])]


def spline(a, b, c, d, t):
    # SLUS_215.90 0x00318870
    return tuple(q + 0.5 * t * (r - p + t * (2*p - 5*q + 4*r - s + t * (3*q - p - 3*r + s)))
                 for p, q, r, s in zip(a, b, c, d))


def crosses_raised_strip(cells, start, end, curve):
    length = math.dist(start[:2], end[:2])
    if length < 3:
        return False
    first, last = ground_height(cells, *start), ground_height(cells, *end)
    if first is None or last is None or abs(first - last) > 1:
        return False
    steps = math.ceil(length * 5)
    previous, raised_at = first, None
    for step in range(1, steps + 1):
        height = ground_height(cells, *curve(step / steps))
        if height is None:
            return False
        change = height - previous
        # Require both curb steps and a raised span between them. A grade,
        # a single kerb or missing geometry cannot close a transition.
        if 0.10 <= change <= 0.30:
            raised_at = step
        elif raised_at is not None and -0.30 <= change <= -0.10:
            if (step - raised_at) * length / steps >= 2 and abs(height - last) <= 0.08:
                return True
            raised_at = None
        previous = height
    return False


def analyze_road_turns(nodes, links, map_root):
    cells, models = road_surfaces(map_root)
    inbound, outbound, centres = defaultdict(list), defaultdict(list), {}
    for edge in links:
        if edge.get("lanes", 0) and nodes[edge["from"]]["kind"] == "vehicle":
            points = lane_centres(nodes, edge)
            if points:
                inbound[edge["to"]].append(edge)
                outbound[edge["from"]].append(edge)
                centres[edge["id"]] = points
    checked, unresolved, closures = 0, 0, []
    for edge_id, lane_points in centres.items():
        edge = links[edge_id]
        turns = [turn for turn in outbound[edge["to"]] if turn["to"] != edge["from"]]
        if not turns:
            continue
        previous = [point for approach in inbound[edge["from"]] if approach["from"] != edge["to"]
                    for point in centres[approach["id"]]]
        blocked = []
        for turn in turns:
            checked += 1
            following = [point for departure in outbound[turn["to"]] if departure["to"] != turn["from"]
                         for point in centres[departure["id"]]]
            pairs = [(b, c) for b in lane_points for c in centres[turn["id"]]]
            if all(crosses_raised_strip(cells, b, c,
                                      lambda t: tuple(p + t * (q - p) for p, q in zip(b, c)))
                   and all(crosses_raised_strip(cells, b, c, lambda t: spline(a, b, c, d, t))
                           for a in (previous or [b]) for d in (following or [c]))
                   for b, c in pairs):
                blocked.append([edge_id, turn["id"]])
        if len(blocked) < len(turns):
            closures.extend(blocked)
        else:
            unresolved += len(blocked)
    return closures, {"roadCollisionInstances": models, "turnsChecked": checked,
                      "raisedStripClosures": len(closures), "crossingsWithoutAlternate": unresolved}
