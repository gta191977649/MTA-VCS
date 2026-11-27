"""Incrementally deploy this workspace's resources to the existing Docker server."""

import argparse
import base64
import getpass
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import subprocess
import sys
import tarfile
import tempfile
import time
import uuid
import xml.etree.ElementTree as ET


HOST = "64.176.60.176"
ROOT = "/root/mtasa/mta-vcs"
FINGERPRINT = "e+jpcvgbIF9G7ssbZWC0RN8eyj0pJ5sqU6HgmbRjzbg"
EXCLUDED_DIRS = {".git", "__pycache__", "node_modules", "logs", "backups", ".ruff_cache"}


def managed(name):
    path = PurePosixPath(name)
    return (
        not EXCLUDED_DIRS.intersection(path.parts)
        and not path.name.endswith((".log", ".db", ".db-journal", ".db-wal", ".db-shm", ".pyc"))
        and name != "[admin]/admin/conf/reports.xml"
    )


def digest(path):
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def resource_path(root, name):
    relative = PurePosixPath(name)
    if relative.is_absolute() or not relative.parts or ".." in relative.parts or "\\" in name:
        raise ValueError(f"Unsafe resource path: {name}")
    target = root.joinpath(*relative.parts)
    if not target.resolve().is_relative_to(root.resolve()):
        raise ValueError(f"Resource path escapes deployment: {name}")
    return target


def fix_case(resources):
    aliases = []
    try:
        for meta in resources.rglob("meta.xml"):
            for element in ET.parse(meta).getroot():
                source = element.get("src")
                if not source or element.tag not in {"script", "file", "config", "map", "html"} or "*" in source:
                    continue
                current = meta.parent
                for part in source.replace("\\", "/").split("/"):
                    if part in {"", "."}:
                        continue
                    if part == "..":
                        current = current.parent
                        continue
                    requested = current / part
                    if not requested.resolve().is_relative_to(resources.resolve()):
                        raise ValueError(f"External resource reference in {meta}: {source}")
                    if not requested.exists():
                        matches = [p for p in current.iterdir() if p.name.casefold() == part.casefold() and p.exists()]
                        if len(matches) != 1 or requested.is_symlink():
                            raise ValueError(f"Missing resource file in {meta}: {source}")
                        requested.symlink_to(matches[0].name, target_is_directory=matches[0].is_dir())
                        aliases.append(requested)
                    current = requested
    except Exception:
        for path in reversed(aliases):
            path.unlink()
        raise
    return aliases


def compose(root, *args):
    result = subprocess.run(["docker", "compose", *args], cwd=root, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout


def wait_ready(root, offset, timeout=120):
    log = root / "data/logs/server.log"
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if log.exists():
            with log.open("rb") as stream:
                stream.seek(offset)
                text = stream.read().decode(errors="replace")
            if re.search(r"\bERROR:", text):
                raise RuntimeError("New startup errors:\n" + text[-6000:])
            counts = re.search(r"Started (\d+)/(\d+) VCS script resources", text)
            if counts and counts[1] != counts[2]:
                raise RuntimeError("Not all VCS script resources started:\n" + text[-6000:])
            state = json.loads(subprocess.check_output(["docker", "inspect", "mta-vcs"], text=True))[0]["State"]
            if counts and "[npchlc_traffic] Loaded " in text and state.get("Health", {}).get("Status") == "healthy":
                return {"resources": f"{counts[1]}/{counts[2]}", "health": "healthy"}
        time.sleep(2)
    raise RuntimeError("Server did not become ready within 120 seconds. Inspect docker compose logs.")


def worker(action, root, run):
    root = Path(root).resolve()
    if not (root / "compose.yaml").is_file() or not (root / "data/resources").is_dir():
        raise ValueError("Expected an existing MTA-VCS Docker deployment")
    if not re.fullmatch(r"[0-9a-f]{32}", run):
        raise ValueError("Invalid deployment ID")
    stage = root / ".deploy-sync" / run
    lock = root / ".deploy-sync/lock"
    resources = root / "data/resources"
    manifest_path = root / "deploy-sync-manifest.json"
    if action == "release":
        if lock.is_file() and lock.read_text() == run:
            lock.unlink()
        if not (stage / "backup").exists() and not (stage / "changes.tar.gz").exists():
            shutil.rmtree(stage)
        return {}
    if action == "plan":
        try:
            with lock.open("x") as stream:
                stream.write(run)
        except FileExistsError:
            raise RuntimeError(f"Another deployment owns {lock}; inspect it before removing a stale lock")
        try:
            manifest = json.loads((stage / "manifest.json").read_text())
            files = manifest["files"]
            changed = []
            for name, expected in files.items():
                if not managed(name):
                    raise ValueError(f"Attempted to deploy protected data: {name}")
                path = resource_path(resources, name)
                if not path.is_file() or digest(path) != expected:
                    changed.append(name)
            previous = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"files": {}}
            deleted = [name for name in previous["files"] if name not in files and managed(name)]
            for name in deleted:
                resource_path(resources, name)
            plan = {"changed": changed, "deleted": deleted}
            (stage / "plan.json").write_text(json.dumps(plan))
            return plan
        except Exception:
            lock.unlink()
            raise
    if not lock.is_file() or lock.read_text() != run:
        raise RuntimeError("Deployment lock is not owned by this run")
    plan = json.loads((stage / "plan.json").read_text())
    manifest = json.loads((stage / "manifest.json").read_text())
    if not plan["changed"] and not plan["deleted"]:
        manifest_path.write_text(json.dumps(manifest, indent=2))
        return {"status": "unchanged", "restarted": False}
    payload = stage / "payload"
    payload.mkdir()
    with tarfile.open(stage / "changes.tar.gz") as archive:
        members = archive.getmembers()
        if {m.name for m in members} != set(plan["changed"]) or len(members) != len(plan["changed"]):
            raise ValueError("Archive does not match deployment plan")
        for member in members:
            resource_path(payload, member.name)
            if not member.isfile():
                raise ValueError("Only regular files are permitted in deployment archives")
        archive.extractall(payload)
    for name in plan["changed"]:
        if digest(resource_path(payload, name)) != manifest["files"][name]:
            raise ValueError(f"File changed during packaging or upload; retry: {name}")
    backup = stage / "backup"
    saved, absent, aliases = [], [], []
    log = root / "data/logs/server.log"
    compose(root, "stop", "server")
    try:
        for name in plan["changed"] + plan["deleted"]:
            target = resource_path(resources, name)
            if target.exists() or target.is_symlink():
                destination = resource_path(backup, name)
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(target, destination, follow_symlinks=False)
                saved.append(name)
            else:
                absent.append(name)
        for name in plan["deleted"]:
            target = resource_path(resources, name)
            if target.is_file() or target.is_symlink():
                target.unlink()
        for name in plan["changed"]:
            target = resource_path(resources, name)
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(resource_path(payload, name), target)
            os.chown(target, 1000, 1000)
            os.chmod(target, 0o644)
        aliases = fix_case(resources)
        # Newly created directories must also be writable by the game server.
        for name in plan["changed"]:
            parent = resource_path(resources, name).parent
            while parent != resources:
                os.chown(parent, 1000, 1000)
                parent = parent.parent
        offset = log.stat().st_size if log.exists() else 0
        compose(root, "up", "-d", "server")
        result = wait_ready(root, offset)
    except Exception as error:
        compose(root, "stop", "server")
        for path in reversed(aliases):
            if path.is_symlink():
                path.unlink()
        for name in absent:
            path = resource_path(resources, name)
            if path.is_file() or path.is_symlink():
                path.unlink()
        for name in saved:
            target = resource_path(resources, name)
            if target.is_file() or target.is_symlink():
                target.unlink()
            shutil.copy2(resource_path(backup, name), target, follow_symlinks=False)
            os.chown(target, 1000, 1000, follow_symlinks=False)
        offset = log.stat().st_size if log.exists() else 0
        compose(root, "up", "-d", "server")
        wait_ready(root, offset)
        raise RuntimeError(f"Deployment failed; previous resources restored and restarted: {error}") from error
    manifest_path.write_text(json.dumps(manifest, indent=2))
    result.update(status="deployed", changed=len(plan["changed"]), deleted=len(plan["deleted"]), backup=str(backup))
    (stage / "result.json").write_text(json.dumps(result, indent=2))
    last_path = root / ".deploy-sync/last-success.json"
    previous = json.loads(last_path.read_text()) if last_path.exists() else None
    last_path.write_text(json.dumps({"run": run, "backup": str(backup)}))
    if previous and re.fullmatch(r"[0-9a-f]{32}", previous.get("run", "")) and previous["run"] != run:
        shutil.rmtree(root / ".deploy-sync" / previous["run"], ignore_errors=True)
    (stage / "changes.tar.gz").unlink()
    shutil.rmtree(payload)
    return result


def deploy(args):
    try:
        import paramiko
    except ImportError:
        raise SystemExit("Install the SSH dependency first: python -m pip install paramiko")

    class PinnedHostKey(paramiko.MissingHostKeyPolicy):
        def missing_host_key(self, client, hostname, key):
            actual = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("=")
            if actual != args.fingerprint.removeprefix("SHA256:").rstrip("="):
                raise paramiko.SSHException(f"Host key mismatch: SHA256:{actual}")

    source = Path(__file__).resolve().parents[1] / "mods/deathmatch/resources"
    print("Hashing local resources...", flush=True)
    cache_path = source.parents[2] / ".deploy-cache.json"
    try:
        cache = json.loads(cache_path.read_text())
    except (OSError, ValueError):
        cache = {}
    files, next_cache = {}, {}
    for directory, folders, names in os.walk(source):
        folders[:] = [name for name in folders if name not in EXCLUDED_DIRS]
        for name in names:
            path = Path(directory) / name
            relative = path.relative_to(source).as_posix()
            if not managed(relative):
                continue
            info = path.stat()
            signature = [info.st_size, info.st_mtime_ns, info.st_ctime_ns]
            saved = cache.get(relative)
            value = saved["sha256"] if not args.rehash and saved and saved["stat"] == signature else digest(path)
            files[relative] = value
            next_cache[relative] = {"stat": signature, "sha256": value}
            if len(files) % 5000 == 0:
                print(f"Indexed {len(files)} files...", flush=True)
    cache_path.write_text(json.dumps(next_cache))
    if not files:
        raise ValueError("No local resources found")
    client = paramiko.SSHClient()
    client.load_system_host_keys()
    client.set_missing_host_key_policy(PinnedHostKey())
    connection = dict(hostname=args.host, username=args.user, port=args.port, timeout=30, key_filename=args.identity)
    password = os.environ.get("MTA_DEPLOY_PASSWORD")
    try:
        client.connect(**connection, password=password)
    except paramiko.AuthenticationException:
        client.connect(**connection, password=getpass.getpass(f"SSH password for {args.user}@{args.host}: "))
    client.get_transport().set_keepalive(20)
    run = uuid.uuid4().hex
    stage = args.root.rstrip("/") + "/.deploy-sync/" + run
    sftp = client.open_sftp()

    def remote(action):
        command = " ".join(shlex.quote(s) for s in ["python3", stage + "/worker.py", "--worker", action, "--root", args.root, "--run", run])
        _, out, err = client.exec_command(command, timeout=360)
        output = out.read().decode(errors="replace")
        error = err.read().decode(errors="replace")
        if out.channel.recv_exit_status():
            raise RuntimeError(error.strip() or output)
        return json.loads(output)

    prepared = False
    try:
        try:
            sftp.mkdir(args.root.rstrip("/") + "/.deploy-sync")
        except OSError:
            sftp.stat(args.root.rstrip("/") + "/.deploy-sync")
        sftp.mkdir(stage)
        sftp.put(str(Path(__file__).resolve()), stage + "/worker.py")
        prepared = True
        commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip()
        with sftp.open(stage + "/manifest.json", "w") as stream:
            stream.set_pipelined(True)
            stream.write(json.dumps({"files": files, "source_commit": commit, "run": run}))
        print("Comparing server files...", flush=True)
        plan = remote("plan")
        print(f"Changed: {len(plan['changed'])}; removed from previous sync: {len(plan['deleted'])}", flush=True)
        for name in plan["changed"] + plan["deleted"]:
            print("  " + name, flush=True)
        if args.dry_run:
            print("Dry run: resources were not changed; server was not restarted.")
            return
        if plan["changed"] or plan["deleted"]:
            with tempfile.TemporaryDirectory(prefix="mta-vcs-sync-") as temporary:
                archive = Path(temporary) / "changes.tar.gz"
                with tarfile.open(archive, "w:gz", compresslevel=1) as output:
                    for name in plan["changed"]:
                        output.add(source / name, arcname=name, recursive=False)
                print(f"Uploading {archive.stat().st_size / 1024**2:.2f} MiB...", flush=True)
                sftp.put(str(archive), stage + "/changes.tar.gz")
        print("Applying update and checking startup...", flush=True)
        print(json.dumps(remote("apply"), indent=2), flush=True)
    finally:
        try:
            if prepared:
                remote("release")
        finally:
            sftp.close()
            client.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default=HOST)
    parser.add_argument("--port", type=int, default=22)
    parser.add_argument("--user", default="root")
    parser.add_argument("--root", default=ROOT)
    parser.add_argument("--identity", help="SSH private key path; otherwise use SSH agent, standard keys, or a password prompt")
    parser.add_argument("--fingerprint", default=FINGERPRINT, help="Expected SSH host key SHA256 fingerprint")
    parser.add_argument("--dry-run", action="store_true", help="Compare files without changing resources or restarting")
    parser.add_argument("--rehash", action="store_true", help="Rebuild the local hash cache from file contents")
    parser.add_argument("--worker", choices=["plan", "apply", "release"], help=argparse.SUPPRESS)
    parser.add_argument("--run", help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.worker:
        print(json.dumps(worker(args.worker, args.root, args.run)))
    else:
        deploy(args)


if __name__ == "__main__":
    try:
        main()
    except (Exception, KeyboardInterrupt) as error:
        print(f"Deployment error: {error}", file=sys.stderr)
        sys.exit(1)
