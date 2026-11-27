# Incremental Docker deployment

Run from the local repository root:

```powershell
python tools/deploy.py
```

The command defaults to `root@64.176.60.176` and `/root/mtasa/mta-vcs`. It syncs the current workspace, including uncommitted resource edits and generated game assets. It does not require a Git commit or upload documentation and development tools.

Install the SSH dependency once if needed:

```powershell
python -m pip install paramiko
```

SSH uses an agent or standard private keys when available; otherwise it prompts for the SSH password. No password is stored in this repository. For a dedicated existing key, use `--identity C:\Users\you\.ssh\your_key`. Noninteractive callers can supply the password through `MTA_DEPLOY_PASSWORD`; use a secret manager rather than putting a password in a saved script or shell history. The server's SSH host key is pinned and a changed host key fails verification.

The local `.deploy-cache.json` caches hashes using file size and nanosecond modification and creation timestamps. Use `--rehash` to force a fresh content scan. The cache is excluded from Git.

Preview the update without changing game files or restarting:

```powershell
python tools/deploy.py --dry-run
```

The tool compares SHA256 hashes and uploads only changed files. When files change, it stages and validates the upload, stops the Docker service, saves the previous versions, applies the update, resolves Linux filename-case differences, and starts the service. It checks the container health, VCS engine startup totals, traffic network load, and new startup errors. A failed apply or startup automatically restores the previous files and restarts the previous version. When nothing changed, it does not restart the server.

The sync excludes the server configuration, ACL, account database, runtime databases, logs, and admin reports. These remain on the server. Files removed locally are deleted remotely only if a previous successful run of this command recorded them as managed files. The first run leaves unrelated remote files alone. Resources are not a wholesale directory mirror.

The existing MTA 1.7 Docker image and Compose settings remain unchanged. Updating the MTA executable or server configuration is a separate operation.

One previous successful update's file backup is kept in `.deploy-sync/<run>/backup` on the server. `deploy-sync-manifest.json` records the last synchronized file hashes. Upload archives and superseded successful backups are removed automatically. A deployment lock prevents two updates from overlapping. If a process is killed, inspect `.deploy-sync/lock` and confirm no deployment is running before removing a stale lock.

Restarting disconnects active players. Run the command when a brief server restart is acceptable.

Check deployment boundary and rollback behavior locally:

```powershell
python tools/check_deploy.py
```

Server operation:

```sh
cd /root/mtasa/mta-vcs
docker compose ps
docker compose logs --tail 100 server
```
