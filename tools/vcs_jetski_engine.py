"""Extract the player's JETSKI engine loop from the VCS US PS2 disc."""
import argparse
import hashlib
import io
from pathlib import Path
import struct
import wave

from import_vcs_frontend import decode_vag
from import_vcs_traffic import write_atomic


def extract(disc, output):
    bank = disc / "AUDIO" / "SET0" / "SFX0_PS"
    offset, size, rate = struct.unpack_from("<III", bank.with_suffix(".SDT").read_bytes(), 16 * 12)
    with bank.with_suffix(".RAW").open("rb") as source:
        source.seek(offset)
        vag = source.read(size)
    if (rate != 2000 or vag[32:48] != b"SFX_BOAT_CRUISER"
            or hashlib.sha256(vag).hexdigest() != "bbbd95123e6c3d0a09f72b48455c337036865fc90e0ead75e9c3b05a5f288c16"):
        raise ValueError("Unexpected SET0 bank 0 sample 16")
    # The first ADPCM frame is silent preroll. SPU loop-start is frame 1
    # and loop-end is frame 266; the idle voice plays this data at 5000 Hz.
    pcm = decode_vag(vag[48:])[28:]
    out = io.BytesIO()
    with wave.open(out, "wb") as wav:
        wav.setparams((1, 2, 5000, 0, "NONE", "not compressed"))
        wav.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
    output.parent.mkdir(parents=True, exist_ok=True)
    write_atomic(output, out.getvalue())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--output", type=Path, default=Path(__file__).resolve().parents[1]
                        / "mods/deathmatch/resources/[model]/vcs_vehicle/audio/jetski_engine.wav")
    args = parser.parse_args()
    extract(args.disc, args.output)
