"""Check that a visible world light can reach the native SA entity pre-render pass."""

from math import dist
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

from vcs_model_assets import chunks
from vcs_vehicle_ground import read_archive


WORLD = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[vcs]/vcs"


def light_volumes(dff):
    # Clump / geometry list / geometry / extension / 2DFX plugin.
    spans = [(0, len(dff))]
    for target in (0x10, 0x1A, 0x0F, 3, 0x253F2F8):
        spans = [(a, b) for start, end in spans for kind, a, b in chunks(dff, start, end)
                 if kind == target]
    for p, stop in spans:
        count, = struct.unpack_from("<I", dff, p)
        p += 4
        for _ in range(count):
            x, y, z, kind, size = struct.unpack_from("<3fII", dff, p)
            if p + 20 + size > stop:
                raise ValueError("Truncated 2DFX entry")
            if kind == 0:
                if size not in (76, 80):
                    raise ValueError("Unknown 2DFX light format")
                # Point-light radius, corona size and ground shadow size.
                yield (x, y, z), max(struct.unpack_from("<3f", dff, p + 28))
            p += 20 + size
        if p != stop:
            raise ValueError("Invalid 2DFX record count")


def collision_bounds(archive):
    with archive.open("rb") as stream:
        signature, count = struct.unpack("<4sI", stream.read(8))
        if signature != b"VER2":
            raise ValueError(f"Invalid IMG header in {archive}")
        directory = list(struct.iter_unpack("<IHH24s", stream.read(32 * count)))
        for sector, _, _, name in directory:
            stream.seek(sector * 2048)
            header = stream.read(72)
            if header[:4] != b"COL3":
                raise ValueError(f"Unexpected collision format in {archive}")
            values = struct.unpack_from("<10f", header, 32)
            yield name.rstrip(b"\0").decode().lower(), values


def main():
    imgs = WORLD / "imgs"
    lights = {}
    for archive in sorted(imgs.glob("dff*.img")):
        for name, dff in read_archive(archive).items():
            volumes = list(light_volumes(dff))
            if volumes:
                lights[name] = volumes
    colliders = {}
    for archive in sorted(imgs.glob("col*.img")):
        colliders.update(collision_bounds(archive))
    checked = set()
    for zone in (WORLD / "eagleZones.txt").read_text().split():
        definitions = WORLD / "zones" / zone / (zone + ".definition")
        for model in ET.parse(definitions).getroot():
            mesh, col = model.attrib["dff"].lower() + ".dff", model.attrib["col"].lower() + ".col"
            if mesh not in lights or (mesh, col) in checked:
                continue
            low_x, low_y, low_z, hi_x, hi_y, hi_z, x, y, z, radius = colliders[col]
            for point, reach in lights[mesh]:
                if (dist(point, (x, y, z)) + reach > radius + 0.001
                        or any(p - reach < lo - 0.001 or p + reach > hi + 0.001
                               for p, lo, hi in zip(point, (low_x, low_y, low_z), (hi_x, hi_y, hi_z)))):
                    raise ValueError(f"{zone}/{mesh}: light at {point} exceeds {col}")
            checked.add((mesh, col))
    if len(lights.get("jm_mess.dff", [])) != 24 or ("jm_mess.dff", "jm_mess.col") not in checked:
        raise ValueError("Missing the Fort Baxter mess hall's original 24 lights")
    print(f"Verified {sum(len(lights[m]) for m, _ in checked)} lights across {len(checked)} DFF/COL pairs.")


if __name__ == "__main__":
    main()
