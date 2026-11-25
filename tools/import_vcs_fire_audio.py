"""Extract the original burning, flamethrower and explosion voices from SLUS-21590."""

import argparse
from pathlib import Path
import struct

from import_vcs_frontend import decode_vag, encode_wave
from import_vcs_traffic import verify_file, write_atomic


SAMPLES = {
    "fire": (68, b"SFX_CAR_ON_FIRE.", True),
    "ped_fire": (227, b"SFX_PED_ON_FIRE.", True),
    "extinguish": (188, b"SFXJUMBOTAXI", True),
    "flamethrower": (153, b"flamethrower", True),
    "flamethrower_start": (155, b"SFX_FLAMETHROWER", False),
    "explosion": (137, b"SFX_EXPLOSION_1.", False),
    "molotov": (139, b"SFX_EXPLOSION_3.", False),
    "mine": (246, b"SFX_ROCKET_LEFT.", False),
}


def extract(disc, output):
    index = verify_file(disc, "AUDIO/SET0/SFX0_PS.SDT",
                        "587488483f2ad2792184f8a1ea0287f4e6e545e54e55502225476b70bee68041")
    bank = verify_file(disc, "AUDIO/SET0/SFX0_PS.RAW",
                       "bb5f1e41e7238ca66870190e9535d79bd940a84f7fcbcb8d9703a4a070b0c135")
    output.mkdir(parents=True, exist_ok=True)
    for name, (sample, label, looped) in SAMPLES.items():
        offset, size, rate = struct.unpack_from("<III", index, 12 * sample)
        vag = bank[offset:offset + size]
        if (vag[:4] != b"VAGp" or vag[32:48].rstrip(b"\0") != label
                or struct.unpack_from(">II", vag, 12) != (size - 48, rate)):
            raise ValueError(f"Unexpected VAG header at bank 0 sample {sample}")
        data = vag[48:]
        pcm = decode_vag(data)
        if looped:
            flags = data[1::16]
            start, end = flags.index(6), flags.index(3)
            if start != 1 or len(pcm) != (end + 1) * 28:
                raise ValueError(f"Unexpected SPU loop markers at bank 0 sample {sample}")
            pcm = pcm[start * 28:]
        write_atomic(output / f"{name}.wav", encode_wave([pcm], rate))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]
                        / "mods/deathmatch/resources/[graphic]/skygfx/audio")
    args = parser.parse_args()
    extract(args.disc, args.output)
