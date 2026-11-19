"""Build Win32 vcsconv from existing local librw and librwgta source trees."""

import argparse
from concurrent.futures import ThreadPoolExecutor
import os
from pathlib import Path
import subprocess
import tempfile


def build(references, compiler, output):
    librw = references / "librw"
    librwgta = references / "librwgta"
    stories = librwgta / "tools/storiesconv"
    target = subprocess.check_output([compiler, "-dumpmachine"], text=True).strip()
    if not target.startswith("i686-") or not ("mingw" in target or target.endswith("-windows-gnu")):
        raise ValueError(f"Expected an i686 MinGW C++ compiler, received {target}")
    groups = {
        "rw": sorted((librw / "src").rglob("*.cpp")),
        "gta": sorted((librwgta / "src").glob("*.cpp")),
        "vcs": sorted(stories.glob("*.cpp")),
    }
    for name, sources in groups.items():
        if not sources:
            raise ValueError(f"Missing {name} sources under {references}")
    flags = [
        "-std=gnu++17", "-DRW_NULL", "-DVCS", "-Wno-narrowing", "-O1",
        "-ffunction-sections", "-fdata-sections",
        *[f"-I{path}" for path in (librw, librw / "src", librwgta / "src", librwgta / "lua", stories)],
    ]
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".vcsconv-", dir=output.parent) as scratch:
        workspace = Path(scratch)
        # The original tool targets older PC games. MTA/SA requires D3D9
        # native rasters. Keep the existing converter's source tree untouched.
        entry = stories / "storiesconv.cpp"
        converter_source = entry.read_text(encoding="utf-8")
        old = "rw::platform = PLATFORM_D3D8;"
        if converter_source.count(old) != 1:
            raise ValueError("Unexpected vcsconv platform declaration")
        adapted_entry = workspace / entry.name
        adapted_entry.write_text(converter_source.replace(old, "rw::platform = PLATFORM_D3D9;"),
                                 encoding="utf-8")
        groups["vcs"] = [adapted_entry if source == entry else source for source in groups["vcs"]]
        jobs = [(source, workspace / f"{name}-{index}.o")
                for name, sources in groups.items() for index, source in enumerate(sources)]

        def compile_one(job):
            source, obj = job
            process = subprocess.run([compiler, *flags, "-c", source, "-o", obj],
                                     text=True, capture_output=True)
            if process.returncode:
                raise ValueError(f"{source.name} failed to compile\n{process.stderr}")
            return obj.name

        with ThreadPoolExecutor(max_workers=min(8, os.cpu_count() or 1)) as workers:
            objects = list(workers.map(compile_one, jobs))
        built = workspace / "vcsconv.exe"
        subprocess.run([compiler, "-static", "-Wl,--gc-sections", *objects, "-o", built],
                       cwd=workspace, check=True)
        os.replace(built, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("references", type=Path, help="Local directory containing librw and librwgta")
    parser.add_argument("compiler", type=Path, help="Path to i686-w64-mingw32-clang++.exe")
    parser.add_argument("output", type=Path, help="Destination for vcsconv.exe")
    args = parser.parse_args()
    try:
        output = args.output.resolve()
        build(args.references.resolve(strict=True), args.compiler.resolve(strict=True), output)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        parser.error(str(error))
    print(output)


if __name__ == "__main__":
    main()
