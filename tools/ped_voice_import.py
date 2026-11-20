"""Extract original VCS PS2 street and driver reactions from the speech bank. Requires Unicorn 2."""

import argparse
from array import array
from collections import defaultdict
from pathlib import Path
import struct
import sys
import wave
import zlib

from unicorn import Uc, UC_ARCH_MIPS, UC_HOOK_CODE, UC_MODE_LITTLE_ENDIAN, UC_MODE_MIPS64
from unicorn.mips_const import (
    UC_CPU_MIPS64_MIPS64R2_GENERIC, UC_MIPS_REG_8, UC_MIPS_REG_A0, UC_MIPS_REG_A1,
    UC_MIPS_REG_A2, UC_MIPS_REG_A3, UC_MIPS_REG_PC, UC_MIPS_REG_RA, UC_MIPS_REG_SP, UC_MIPS_REG_V0,
)

from import_vcs_frontend import decode_vag
from import_vcs_traffic import DEFAULT_OUTPUT, GAME_DTZ, PS2_EXECUTABLE, verify_file


INDEX_HASH = "65b1bfda1a366779e925247580f478898e08b2bcbaa7decaf96592f0c506c84b"
BANK_HASH = "22aba95a685061f018827323cd7c6623917f31ef3feaca425d5cd3ee603057e0"
EVENTS = {"gunpoint": 0x76, "fear": 0x77, "pain": 0x6A, "impact": 0x8A, "carjack": 0x7A, "evade": 0x8D,
          "reclaim": 0x8E, "crash": 0x8F, "treat": 0x8B, "arrive": 0x8C, "revived": 0x7C,
          "fireScene": 0x96, "arrest": 0x6D, "arrested": 0x6C, "chat": 0x9C, "look": 0x99,
          "mugVictim": 0x7B, "mugger": 0x79, "serviceOffer": 0x93, "serviceAction": 0x7F, "serviceEnd": 0x7E,
          "pursuitGroup": 0x86, "pursuitReply": 0x87}
SELECTOR, RANDOM_RANGE = 0x001C2448, 0x001C87D8
MANAGER, PED, STACK, RETURN = 0x514A90, 0x820000, 0x8F0000, 0x890000
BANK_FIRST = 293


def original_model_ranges(executable, game):
    """Run only the model/event switch and capture the arguments to its sample picker."""
    load, file_start, vaddr, _, file_bytes, _, _, _ = struct.unpack_from(
        "<8I", executable, struct.unpack_from("<I", executable, 28)[0])
    if (load, file_start, vaddr) != (1, 0x1000, 0x100000):
        raise ValueError("Unexpected PS2 ELF segment")
    cpu = Uc(UC_ARCH_MIPS, UC_MODE_MIPS64 | UC_MODE_LITTLE_ENDIAN)
    cpu.ctl_set_cpu_model(UC_CPU_MIPS64_MIPS64R2_GENERIC)
    cpu.mem_map(0x100000, 0x800000)
    cpu.mem_write(vaddr, executable[file_start:file_start + file_bytes])
    cpu.hook_add(UC_HOOK_CODE, lambda uc, addr, size, data: uc.emu_stop(), begin=RANDOM_RANGE, end=RANDOM_RANGE)
    _, models = struct.unpack_from("<II", game, 0x38)
    catalog = {}
    for original_id in range(171):
        offset, = struct.unpack_from("<I", game, models + original_id * 4)
        if not offset or game[offset + 16] != 7:
            continue
        ped_type, = struct.unpack_from("<I", game, offset + 0x34)
        if not ped_type and original_id != 0:
            continue
        cpu.mem_write(PED + 0x56, struct.pack("<H", original_id))
        cpu.mem_write(PED + 0x550, struct.pack("<I", ped_type))
        variants = [{} for _ in range(20)]
        for kind, event in EVENTS.items():
            if kind == "pursuitGroup" and ped_type != 6 or kind == "pursuitReply" and original_id != 0:
                continue
            # The fallback dispatcher selects from 2, 4 or 5 alternate voice packs
            # for certain uniforms. Twenty manager counter values cover every residue.
            for counter in range(20):
                cpu.mem_write(MANAGER + 0x30, struct.pack("<I", counter))
                for reg, value in ((UC_MIPS_REG_SP, STACK), (UC_MIPS_REG_RA, RETURN),
                                   (UC_MIPS_REG_A0, MANAGER), (UC_MIPS_REG_A1, PED), (UC_MIPS_REG_A2, event)):
                    cpu.reg_write(reg, value)
                cpu.emu_start(SELECTOR, RETURN, count=2000)
                if cpu.reg_read(UC_MIPS_REG_PC) == RANDOM_RANGE:
                    first = cpu.reg_read(UC_MIPS_REG_A3) - BANK_FIRST
                    count = cpu.reg_read(UC_MIPS_REG_8)  # PS2 EABI a4
                    if first < 0 or not 0 < count <= 51:
                        raise ValueError(f"Invalid selector range for {original_id}/{kind}")
                    variants[counter][kind] = tuple(range(first, first + count))
                elif cpu.reg_read(UC_MIPS_REG_PC) != RETURN or cpu.reg_read(UC_MIPS_REG_V0) != 0x1752:
                    raise ValueError(f"Unexpected selector return for {original_id}/{kind}")
        for events in variants:
            if events.pop("impact", None) != events.get("pain"):
                raise ValueError(f"Damage speech differs between 0x6A and 0x8A for model {original_id}")
        if any(variants):
            period = next(n for n in (1, 2, 4, 5, 10, 20) if all(
                events == variants[i % n] for i, events in enumerate(variants)))
            catalog[original_id] = variants[:period]
    if catalog[45][0]["fear"] != tuple(range(1269, 1282)) or catalog[46][0]["pain"] != tuple(range(2251, 2302)):
        raise ValueError("PS2 generic male/female speech selectors disagree with bank 2")
    return catalog


def export(disc, output):
    exe = verify_file(disc, "SLUS_215.90", PS2_EXECUTABLE)
    game = zlib.decompress(verify_file(disc, "PS2/GAME.DTZ", GAME_DTZ))
    index = verify_file(disc, "AUDIO/SET0/SFX2_PS.SDT", INDEX_HASH)
    bank = verify_file(disc, "AUDIO/SET0/SFX2_PS.RAW", BANK_HASH)
    catalog = original_model_ranges(exe, game)
    families = sorted({group for variants in catalog.values() for events in variants for group in events.values()})
    samples = sorted({i for group in families for i in group})
    output.mkdir(parents=True, exist_ok=True)
    for sample in samples:
        offset, size, rate = struct.unpack_from("<III", index, sample * 12)
        vag = bank[offset:offset + size]
        if len(vag) != size or size % 16 or vag[:4] != b"VAGp" or struct.unpack_from(">II", vag, 12) != (size-48, rate):
            raise ValueError(f"Invalid VAG sample {sample}")
        pcm = array("h", decode_vag(vag[48:]))
        if sys.byteorder != "little":
            pcm.byteswap()
        if not pcm:
            raise ValueError(f"Empty sample {sample}")
        with wave.open(str(output / f"{sample:04d}.wav"), "wb") as wav:
            wav.setparams((1, 2, rate, 0, "NONE", "not compressed"))
            wav.writeframes(pcm.tobytes())
    lines = ["-- Generated by tools/ped_voice_import.py from the USA PS2 executable and bank 2.",
             "local pools = {"]
    pool_ids = {pool: i for i, pool in enumerate(families, 1)}
    for group in families:
        lines.append("    {")
        for i in range(0, len(group), 5):
            lines.append("        " + ", ".join(f'"ped_voice/{sample:04d}.wav"' for sample in group[i:i+5]) + ",")
        lines.append("    },")
    lines += ["}", "PedVoiceClips = {"]
    for model, variants in catalog.items():
        lines.append(f"    [{model}] = {{")
        for events in variants:
            fields = ", ".join(f"{kind}=pools[{pool_ids[pool]}]" for kind,pool in events.items())
            lines.append("        {" + fields + "},")
        lines.append("    },")
    (output / "catalog.lua").write_bytes("\n".join(lines + ["}", ""]).encode("ascii"))
    counts = defaultdict(set)
    for variants in catalog.values():
        for events in variants:
            for key, samples_for_model in events.items():
                counts[key].update(samples_for_model)
    print(f"{len(catalog)} models, {len(samples)} bank-2 WAVs: " + ", ".join(f"{k} {len(v)}" for k,v in counts.items()))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("disc", type=Path)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT.parents[1] / "ped_voice")
    args = parser.parse_args()
    export(args.disc, args.output)
