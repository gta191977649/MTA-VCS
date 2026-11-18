"""Build the replay timeline from the USA PS2 MAIN.txt."""
import argparse
import re
from pathlib import Path


def read_replay(script):
    lines = script.splitlines()
    names = {"5425": "phcol", "5427": "gtr1", "5428": "gtr2", "5429": "bmyst"}
    active = False
    audio = 0
    label = ""
    actions = []
    camera = None
    duration = 0
    for line in lines:
        if line == ":RENC7_32746" or line == ":RENC7_34851":
            active = True
        elif line in (":RENC7_34601", ":RENC7_38032"):
            active = False
        if not active:
            continue
        if line.startswith(":"):
            label = line[1:]
        if match := re.search(r"call_func @RENC7_30006 (\d+)", line):
            audio = int(match[1])
            continue
        if line.startswith("02B4:"):
            duration = int(line.split()[-1])
        if line.startswith("00B9:"):
            camera = line.split()[2:5]
        if line.startswith("00BA:"):
            point = line.split()[2:5]
            cut = line.endswith(" 2")
            actions.append((audio, label, "camera", camera + point + [str(0 if cut else duration)]))
            duration = 0
        if match := re.search(r"^(0414|04B4|0523): .*?\$(\d+) (?:value1 |values )(\d+)(?: value2)? (\d+)", line):
            opcode, actor, group, anim = match.groups()
            actions.append((audio, label, "layer" if opcode == "0523" else "animation",
                            [f'"{names[actor]}"', group, anim]))
        if line.startswith("0200:") and "$5425 1" in line:
            actions.append((audio, label, "reveal", []))
        if match := re.search(r"call_func @RENC7_116(64|92) ([^ ]+(?: [^ ]+){0,3})", line):
            actions.append((audio, label, "root" if match[1] == "64" else "layerSeek", match[2].split()))
        if "call_func @RENC7_14371 " in line:
            actions.append((audio, label, "lights", []))
        if line == "$5548 = -1":
            actions.append((audio, label, "holdLights", []))
        if re.fullmatch(r"\$5598 = [01]", line):
            actions.append((audio, label, "spot", [line[-1]]))
        if line.startswith("02A0:"):
            actions.append((audio, label, "fadeAudio", []))
    if audio != 16650000:
        raise ValueError(f"Unexpected replay end {audio}")
    return actions, audio


def build(script):
    actions, audio = read_replay(script)
    output = ["-- Generated from USA PS2 MAIN.txt by tools/timeline.py.",
              "ConcertTimeline = {"]
    for time, label, kind, args in actions:
        values = ", ".join((str(time), f'"{kind}"', *args))
        output.append(f"    {{ {values} }}, -- {label}")
    output.extend(("}", f"ConcertEnd = {audio}", ""))
    return "\n".join(output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("script", type=Path)
    parser.add_argument("output", type=Path)
    options = parser.parse_args()
    options.output.write_text(build(options.script.read_text(encoding="utf-8-sig", errors="replace")),
                              encoding="utf-8")
