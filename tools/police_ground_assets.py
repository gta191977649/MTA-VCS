"""Build the standalone undercover car archive from the converted VCS vehicle IMG."""
import struct
from pathlib import Path

from vcs_model_assets import build_img, build_texture_dictionary, native_textures, vehicle_material_textures


def pack(source):
    names = ("fbicar", "vicechee")
    required = {"vehshare.txd"} | {f"{name}.{ext}" for name in names for ext in ("dff", "txd")}
    entries = {}
    with source.open("rb") as stream:
        signature, count = struct.unpack("<4sI", stream.read(8))
        if signature != b"VER2":
            raise ValueError(f"Invalid IMG header in {source}")
        directory = list(struct.iter_unpack("<IHH24s", stream.read(32 * count)))
        for sector, blocks, _, raw_name in directory:
            name = raw_name.rstrip(b"\0").decode("ascii")
            if name in required:
                stream.seek(sector * 2048)
                data = stream.read(blocks * 2048)
                size = 12 + struct.unpack_from("<I", data, 4)[0]
                if size > len(data):
                    raise ValueError(f"Truncated RenderWare chunk in {name}")
                entries[name] = data[:size]
    if missing := required - entries.keys():
        raise ValueError(f"Rebuild vcs_model/vehicle.img first. Missing {sorted(missing)}")
    shared = native_textures(entries.pop("vehshare.txd"))
    for name in names:
        dictionary = entries[f"{name}.txd"]
        textures = native_textures(dictionary)
        native_lamps = {"vehiclelights128", "vehiclelightson128"}
        for texture in vehicle_material_textures(entries[f"{name}.dff"]) - textures.keys() - native_lamps:
            textures[texture] = shared[texture]
        entries[f"{name}.txd"] = build_texture_dictionary(dict(sorted(textures.items())), dictionary[26:28])
    return build_img(entries)


if __name__ == "__main__":
    resources = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources"
    output = resources / "[traffic]/npchlc_traffic/police_models.img"
    output.write_bytes(pack(resources / "[model]/vcs_model/vehicle.img"))
