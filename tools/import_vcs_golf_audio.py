"""Recover the four DRIVERA positional cues from the US PS2 mission stream."""
import argparse
from pathlib import Path
import struct
import zlib

from import_vcs_frontend import decode_vag, encode_wave

ASSETS = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[mission]/mission/assets"
CUES = {"SX_GFSW": "swing", "SX_GFHT": "strike", "SX_GFIW": "water", "SX_GFHM": "buoy"}


def extract(disc, output):
    audio = disc / "AUDIO"
    lookup = list(struct.iter_unpack("<I", (audio / "M_LOOKUP.BIN").read_bytes()))
    index = (audio / "SET6/SFX67_PS.SDT").read_bytes()
    with (audio / "SET6/SFX67_PS.RAW").open("rb") as bank:
        for key, name in CUES.items():
            sample = lookup.index((zlib.crc32(key.encode("ascii")) ^ 0xFFFFFFFF,))
            offset, size, rate = struct.unpack_from("<III", index, sample * 12)
            bank.seek(offset)
            vag = bank.read(size)
            if vag[:4] != b"VAGp" or struct.unpack_from(">II", vag, 12) != (size - 48, rate):
                raise ValueError(f"Invalid mission sample for {key}")
            (output / f"golf_{name}.wav").write_bytes(encode_wave([decode_vag(vag[48:])], rate))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    extract(parser.parse_args().disc, ASSETS)
