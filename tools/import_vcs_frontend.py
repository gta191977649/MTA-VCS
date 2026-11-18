#!/usr/bin/env python3
"""Import the original SLUS-21590 HUD textures, bitmap fonts, text and sounds."""

import argparse
import hashlib
import io
import json
import mmap
import re
import struct
import wave
import zlib
from pathlib import Path


RESOURCE = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources/[hud]/frontend"
GAME_HASH = "570a7504048e8a0187b04b20fec63fc57c404c74b84e7d3ee19df8daab1a365b"
# Relocatable RslTexDictionary pointers and CSimpleFont records in the USA GAME.DTZ image.
FONT_DICTIONARY = 0x104
HUD_DICTIONARY = 0x287B0
FONTS = {
    "fancytext": (0x4CB948, b"FancyText"),
    "gametext": (0x4CB998, b"GameText"),
    "bigtext": (0x4CBA20, b"BigText"),
    "pagertext": (0x4CBA70, b"PagerText"),
}
WEAPONS = frozenset("ak47 bat beretta bomb brassknuckle camera chnsaw chromegun flame golfclub grenade katana "
                    "knifecur m16 minigun molotov mplng nitestick python rocketla shotgspa skorpion sniper teargas uzi".split())
SOUNDS = {
    # SLUS DrawHelpText event 0xB4 -> frontend audio dispatch 0x1C56D4.
    "help": ((182, b"SFX_FE_INFO_LEFT"), (183, b"SFX_FE_INFO_RIGH")),
    "money": ((209, b"SFX_MONEY_LEFT"), (210, b"SFX_MONEY_RIGHT")),
    # SLUS DrawPager event 0x65 -> frontend audio dispatch 0x1C5794.
    "pager": ((230, b"pagermono"),),
    "timer": ((276, b"Timer"),),
    "radio_click": ((235, b"SFX_RADIO_CLICK."),),
    "radio_dial1": ((236, b"SFX_RADIO_DIAL_1"),),
    "radio_dial2": ((237, b"SFX_RADIO_DIAL_2"),),
    "radio_dial3": ((238, b"SFX_RADIO_DIAL_3"),),
}
MENU_SOUNDS = {
    "back": ((0, b"SFX_FE_BACK"),),
    "error": ((1, b"SFX_FE_ERROR_LEF"), (2, b"SFX_FE_ERROR_RIG")),
    "highlight": ((3, b"SFX_FE_HIGHLIGHT"),),
    "select": ((7, b"SFX_FE_SELECT"),),
}
VAG_FILTERS = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))


def u32(data, offset):
    return struct.unpack_from("<I", data, offset)[0]


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def texture_entries(image, directories=(FONT_DICTIONARY, HUD_DICTIONARY), stop=0x539E0):
    # The four pointer fields precede the 32-byte RslTexture name.
    for offset in range(0x60, min(stop, len(image) - 48), 4):
        dictionary = u32(image, offset + 4)
        if dictionary not in directories:
            continue
        raster = u32(image, offset)
        if not 0x40 <= raster < min(stop, len(image) - 16):
            continue
        texture_format = u32(image, raster + 4) >> 16
        name = image[offset + 16:offset + 48].split(b"\0", 1)[0]
        if texture_format in (0x25, 0x45) and re.fullmatch(rb"[a-zA-Z0-9_]+", name):
            yield name.decode("ascii"), offset, raster, texture_format


def decode_texture(image, raster, texture_format):
    pixels = u32(image, raster + 8)
    flags = u32(image, raster + 12)
    width, height = 1 << (flags & 15), 1 << ((flags >> 6) & 15)
    packed = texture_format == 0x45
    pitch = u32(image, raster + 4) & 0xFFFF
    if pitch != width // (2 if packed else 1) or height > 512:
        raise ValueError(f"Invalid raster dimensions at 0x{raster:X}")
    end = pixels + pitch * height
    colors = 16 if packed else 256
    palette = []
    for index in range(colors):
        # CT32 CLUTs for PSMT8 use GS CSM1 order. PSMT4 is already in index order.
        slot = index if packed else (index & ~24) | ((index & 8) << 1) | ((index & 16) >> 1)
        r, g, b, alpha = image[end + slot * 4:end + slot * 4 + 4]
        palette.append(bytes((r, g, b, min(255, alpha * 255 // 128))))
    indices = (k for byte in image[pixels:end] for k in (byte & 15, byte >> 4)) if packed else image[pixels:end]
    return width, height, b"".join(palette[index] for index in indices), pixels, end


def encode_png(width, height, rgba):
    def chunk(kind, payload):
        return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload))

    stride = width * 4
    rows = b"".join(b"\0" + rgba[y:y + stride] for y in range(0, len(rgba), stride))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows, 9)) + chunk(b"IEND", b""))


def font_table(image, offset, name):
    count, buttons, line_height, cell_height, letters, tokens = struct.unpack_from("<4H2I", image, offset)
    if image[offset + 44:offset + 44 + len(name)] != name:
        raise ValueError(f"Unexpected font record at 0x{offset:X}")

    def table(start, length):
        result = {}
        for index in range(length):
            left, width, right, height, code, u, v = struct.unpack_from("<3h4H", image, start + 14 * index)
            result.setdefault(str(code), [left, width, right, height, u, v])
        return result

    return {"lineHeight": line_height, "cellHeight": cell_height, "glyphs": table(letters, count),
            "buttons": table(tokens, buttons), "recordOffset": offset, "glyphOffset": letters}


def read_gxt(data):
    if data[:4] != b"TABL" or u32(data, 4) % 12:
        raise ValueError("Invalid PS2 GXT table directory")
    tables = {}
    for entry in range(8, 8 + u32(data, 4), 12):
        name = data[entry:entry + 8].split(b"\0", 1)[0].decode("ascii")
        key_table = u32(data, entry + 8) + (0 if name == "MAIN" else 8)
        key_length = u32(data, key_table + 4)
        text_table = key_table + 8 + key_length
        if data[key_table:key_table + 4] != b"TKEY" or data[text_table:text_table + 4] != b"TDAT" or key_length % 12:
            raise ValueError(f"Invalid GXT section {name}")
        text_start, text_end = text_table + 8, text_table + 8 + u32(data, text_table + 4)
        values = {}
        for key in range(key_table + 8, text_table, 12):
            label = data[key + 4:key + 12].split(b"\0", 1)[0].decode("ascii")
            start = text_start + u32(data, key)
            if start >= text_end or start % 2:
                raise ValueError(f"Invalid text offset in {name}:{label}")
            end = start
            while end < text_end and data[end:end + 2] != b"\0\0":
                end += 2
            values[label] = data[start:end].decode("utf-16le")
        tables[name] = values
    return tables


def decode_vag(data):
    samples = []
    previous = older = 0
    for offset in range(0, len(data), 16):
        header, flags = data[offset:offset + 2]
        if flags == 7:
            break
        first, second = VAG_FILTERS[header >> 4]
        for value in data[offset + 2:offset + 16]:
            for nibble in (value & 15, value >> 4):
                signed = (nibble ^ 8) - 8
                sample = ((signed << 12) >> (header & 15)) + ((first * previous + second * older + 32) >> 6)
                sample = max(-32768, min(32767, sample))
                samples.append(sample)
                older, previous = previous, sample
        if flags & 1:
            break
    return samples


def import_sound_bank(disc, files, bank_number, sounds):
    bank = f"AUDIO/SET0/SFX{bank_number}_PS"
    index = (disc / f"{bank}.SDT").read_bytes()
    output = {}
    with (disc / f"{bank}.RAW").open("rb") as raw:
        for name, entries in sounds.items():
            channels, records, rates = [], [], set()
            for ordinal, label in entries:
                offset, size, rate = struct.unpack_from("<III", index, ordinal * 12)
                raw.seek(offset)
                vag = raw.read(size)
                if (len(vag) != size or vag[:4] != b"VAGp" or size % 16
                        or struct.unpack_from(">II", vag, 12) != (size - 48, rate)
                        or vag[32:48].rstrip(b"\0") != label):
                    raise ValueError(f"Unexpected VAG sample {ordinal} in {bank}")
                channels.append(decode_vag(vag[48:]))
                rates.add(rate)
                records.append({"index": ordinal, "offset": offset, "length": size,
                                "label": label.decode(), "sha256": sha256(vag)})
            if len(rates) != 1 or len({len(samples) for samples in channels}) != 1:
                raise ValueError(f"Channel mismatch in {name}")
            pcm = b"".join(struct.pack("<" + "h" * len(channels), *frame) for frame in zip(*channels))
            buffer = io.BytesIO()
            with wave.open(buffer, "wb") as wav:
                wav.setparams((len(channels), 2, rates.pop(), 0, "NONE", "not compressed"))
                wav.writeframes(pcm)
            encoded = buffer.getvalue()
            files[f"sfx_{name}.wav"] = encoded
            output[name] = {"source": bank + ".RAW", "indexSource": bank + ".SDT", "channels": records,
                            "sha256": sha256(encoded)}
    return output


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc_directory", type=Path)
    args = parser.parse_args()
    source = args.disc_directory / "PS2/GAME.DTZ"
    compressed = source.read_bytes()
    if sha256(compressed) != GAME_HASH:
        parser.error("GAME.DTZ is not the verified SLUS-21590 USA v1.00 file")
    image = zlib.decompress(compressed)
    if image[:8] != b"GATG\x01\0\0\0" or u32(image, 8) != len(image):
        parser.error("Invalid GAME.DTZ resource image")

    output = RESOURCE / "ps2"
    files, textures = {}, {}
    def save_texture(data, name, entry, raster, texture_format, source_name, base=0):
        width, height, rgba, pixel_offset, palette_offset = decode_texture(data, raster, texture_format)
        png = encode_png(width, height, rgba)
        if name in textures:
            if files[f"{name}.png"] != png:
                raise ValueError(f"Conflicting HUD texture: {name}")
            return
        files[f"{name}.png"] = png
        textures[name] = {"width": width, "height": height, "source": source_name, "entryOffset": base + entry,
                          "rasterOffset": base + raster, "pixelOffset": base + pixel_offset,
                          "paletteOffset": base + palette_offset, "sha256": sha256(png)}

    font_entries = list(texture_entries(image, (FONT_DICTIONARY,)))
    if {entry[0] for entry in font_entries} != FONTS.keys():
        raise ValueError("The original font dictionary does not match the four CSimpleFont records")
    for name, entry, raster, texture_format in font_entries:
        save_texture(image, name, entry, raster, texture_format, "PS2/GAME.DTZ (inflated)")
    for name, entry, raster, texture_format in texture_entries(image, (HUD_DICTIONARY,)):
        save_texture(image, name, entry, raster, texture_format, "PS2/GAME.DTZ (inflated)")
    with (args.disc_directory / "GTA3PS2.IMG").open("rb") as archive, mmap.mmap(archive.fileno(), 0, access=mmap.ACCESS_READ) as img:
        archive_hash = sha256(img)
        for base in range(0, len(img) - 48, 2048):
            if img[base:base + 4] != b"xet\0":
                continue
            size, end = u32(img, base + 8), u32(img, base + 12)
            if not 0x80 < end <= size <= 0x5000 or base + size > len(img):
                continue
            data = img[base:base + size]
            for name, entry, raster, texture_format in texture_entries(data, (0x20,), end):
                flags = u32(data, raster + 12)
                if name in WEAPONS and (flags & 15, (flags >> 6) & 15) == (6, 6):
                    save_texture(data, "weapon_" + name, entry, raster, texture_format, "GTA3PS2.IMG", base)
                elif re.fullmatch(r"radar\d{2}", name):
                    save_texture(data, name, entry, raster, texture_format, "GTA3PS2.IMG", base)
    required = (set(FONTS) | {"hudnumbers", "fist", "bar_inside1", "bar_inside2", "bar_outline", "radardisc"}
                | {f"weapon_{name}" for name in WEAPONS} | {f"radar{id:02}" for id in range(64)})
    if missing := required - textures.keys():
        raise ValueError(f"Missing textures: {', '.join(sorted(missing))}")
    fonts = {role: font_table(image, offset, name) for role, (offset, name) in FONTS.items()}
    gxt = (args.disc_directory / "AMERICAN.GXT").read_bytes()
    files["gxt.json"] = json.dumps(read_gxt(gxt), ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    sounds = import_sound_bank(args.disc_directory, files, 0, SOUNDS)
    sounds.update(import_sound_bank(args.disc_directory, files, 3, MENU_SOUNDS))
    manifest = {"edition": "SLUS-21590 USA v1.00", "source": "PS2/GAME.DTZ", "sourceSha256": GAME_HASH,
                "textures": textures, "fonts": fonts, "text": {"source": "AMERICAN.GXT", "sha256": sha256(gxt)},
                "archive": {"source": "GTA3PS2.IMG", "sha256": archive_hash}, "sounds": sounds}
    files["manifest.json"] = (json.dumps(manifest, sort_keys=True, separators=(",", ":")) + "\n").encode()
    output.mkdir(parents=True, exist_ok=True)
    for name, content in files.items():
        path = output / name
        temporary = path.with_suffix(".tmp")
        temporary.write_bytes(content)
        temporary.replace(path)
    print(f"Imported {len(textures)} textures, {len(fonts)} font tables and {len(sounds)} sounds into {output}")


if __name__ == "__main__":
    main()
