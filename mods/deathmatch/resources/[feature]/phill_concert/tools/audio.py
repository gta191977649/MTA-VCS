"""Convert the USA PS2 PHILCOL.VB stream to an MTA Vorbis asset."""
import argparse
import subprocess
import sys
from array import array
from pathlib import Path

INTERLEAVE = 0x2000
RATE = 32000
COEFFICIENTS = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))


def decode_channel(data, channel):
    output = array("h")
    first = second = 0
    for start in range(channel * INTERLEAVE, len(data), 2 * INTERLEAVE):
        end = min(start + INTERLEAVE, len(data))
        for i in range(start, end, 16):
            header = data[i]
            scale = header & 15
            a, b = COEFFICIENTS[header >> 4]
            for byte in data[i + 2:i + 16]:
                for nibble in (byte & 15, byte >> 4):
                    delta = ((nibble if nibble < 8 else nibble - 16) << 12) >> scale
                    sample = max(-32768, min(32767, delta + ((a * first + b * second + 32) >> 6)))
                    output.append(sample)
                    second, first = first, sample
    return output


def convert(source, output, ffmpeg):
    data = source.read_bytes()
    if len(data) % (2 * INTERLEAVE):
        raise ValueError("Expected complete pairs of PS2 VB blocks")
    left, right = (decode_channel(data, channel) for channel in range(2))
    stereo = array("h", [0]) * (len(left) * 2)
    stereo[::2], stereo[1::2] = left, right
    if sys.byteorder != "little":
        stereo.byteswap()
    subprocess.run([ffmpeg, "-nostdin", "-v", "error", "-y", "-f", "s16le", "-ar", str(RATE),
                    "-ac", "2", "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(output)],
                   input=stereo.tobytes(), check=True)
    print(f"{output}: {len(left) / RATE:.3f} seconds")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--ffmpeg", default="ffmpeg")
    args = parser.parse_args()
    convert(args.disc / "AUDIO" / "MUSIC" / "PHILCOL.VB", args.output, args.ffmpeg)
