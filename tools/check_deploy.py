"""Check deployment boundaries and rollback without contacting a server."""

import json
from pathlib import Path
import tarfile
import tempfile
import unittest
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
import deploy


class DeploymentChecks(unittest.TestCase):
    def test_protected_data(self):
        for name in ["mission/save.db", "mission/save.db-wal", "radio/logs/server.log", "[admin]/admin/conf/reports.xml"]:
            self.assertFalse(deploy.managed(name), name)
        self.assertTrue(deploy.managed("[traffic]/npchlc_traffic/traffic_road.lua"))
        self.assertTrue(deploy.managed("[vcs]/radio/audio/radio.bin"))

    def test_path_boundaries(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ["../internal.db", "/etc/passwd", "resource/../../acl.xml", "resource\\..\\acl.xml"]:
                with self.assertRaises(ValueError):
                    deploy.resource_path(root, name)

    def exercise(self, invalid=False, bad_hash=False, failed_start=False):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            resources = root / "data/resources"
            resource = resources / "example"
            resource.mkdir(parents=True)
            (root / "compose.yaml").write_text("services: {}")
            (root / "data/internal.db").write_bytes(b"ACCOUNT DATABASE MUST NOT CHANGE")
            (resource / "main.lua").write_bytes(b"old script")
            (resource / "removed.lua").write_bytes(b"old removed script")
            (resource / "meta.xml").write_text('<meta><script src="main.lua" type="server"/></meta>')
            run = "a" * 32
            stage = root / ".deploy-sync" / run
            stage.mkdir(parents=True)
            (root / "deploy-sync-manifest.json").write_text(json.dumps({"files": {"example/removed.lua": "unused"}}))
            payload = root / "payload"
            payload.mkdir()
            (payload / "main.lua").write_bytes(b"new script")
            (payload / "new.lua").write_bytes(b"new additional script")
            (payload / "meta.xml").write_text("<invalid" if invalid else '<meta><script src="main.lua" type="server"/></meta>')
            files = {"example/" + p.name: deploy.digest(p) for p in payload.iterdir()}
            if bad_hash:
                files["example/main.lua"] = "0" * 64
            (stage / "manifest.json").write_text(json.dumps({"files": files, "run": run}))
            plan = deploy.worker("plan", str(root), run)
            self.assertEqual(plan["deleted"], ["example/removed.lua"])
            with tarfile.open(stage / "changes.tar.gz", "w:gz") as archive:
                for name in plan["changed"]:
                    archive.add(payload / Path(name).name, arcname=name)
            readiness = [RuntimeError("simulated startup failure"), {"health": "healthy"}] if failed_start else None
            with patch.object(deploy, "compose") as compose, patch.object(deploy, "wait_ready", return_value={"health": "healthy"}, side_effect=readiness), patch.object(deploy.os, "chown", create=True):
                if invalid or bad_hash or failed_start:
                    with self.assertRaises((RuntimeError, ValueError)):
                        deploy.worker("apply", str(root), run)
                    self.assertEqual((resource / "main.lua").read_bytes(), b"old script")
                    self.assertEqual((resource / "removed.lua").read_bytes(), b"old removed script")
                    self.assertFalse((resource / "new.lua").exists())
                    if bad_hash:
                        compose.assert_not_called()
                else:
                    result = deploy.worker("apply", str(root), run)
                    self.assertEqual(result["status"], "deployed")
                    self.assertEqual((resource / "main.lua").read_bytes(), b"new script")
                    self.assertFalse((resource / "removed.lua").exists())
                    self.assertEqual((stage / "backup/example/main.lua").read_bytes(), b"old script")
                    deploy.worker("release", str(root), run)
                    next_run = "b" * 32
                    next_stage = root / ".deploy-sync" / next_run
                    next_stage.mkdir()
                    (next_stage / "manifest.json").write_text(json.dumps({"files": files, "run": next_run}))
                    compose.reset_mock()
                    deploy.worker("plan", str(root), next_run)
                    unchanged = deploy.worker("apply", str(root), next_run)
                    self.assertEqual(unchanged["status"], "unchanged")
                    compose.assert_not_called()
                    deploy.worker("release", str(root), next_run)
            self.assertEqual((root / "data/internal.db").read_bytes(), b"ACCOUNT DATABASE MUST NOT CHANGE")

    def test_failed_validation_does_not_stop_server(self):
        self.exercise(bad_hash=True)

    def test_failed_startup_rolls_back_changed_deleted_and_new_files(self):
        self.exercise(invalid=True)

    def test_success_keeps_backup(self):
        self.exercise()

    def test_failed_health_check_restores_previous_version(self):
        self.exercise(failed_start=True)


if __name__ == "__main__":
    unittest.main()
