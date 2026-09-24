#!/usr/bin/env python3
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import unittest

helper = Path(__file__).parents[1] / "rootfs/usr/local/bin/migrate-rtorrent-016-config.py"
spec = importlib.util.spec_from_file_location("compatibility", helper)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)


class CompatibilityTest(unittest.TestCase):
    def test_backup_settings_permissions_and_second_boot(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            kept = b"# encoding.add = UTF-8\r\nthrottle.max_uploads.set = 27\r\n"
            original = b"encoding.add = UTF-8\r\n" + kept
            rc.write_bytes(original)
            rc.chmod(0o640)
            self.assertTrue(migration.migrate(rc))
            self.assertEqual(rc.read_bytes(), kept)
            self.assertEqual(rc.stat().st_mode & 0o777, 0o640)
            backups = list(rc.parent.glob(".rtorrent.rc.pre-01622-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertFalse(migration.migrate(rc))

    def test_custom_encoding_is_not_rewritten(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            original = b"encoding.add = ISO-8859-1\n"
            rc.write_bytes(original)
            self.assertFalse(migration.migrate(rc))
            self.assertEqual(rc.read_bytes(), original)

    def test_conflicting_backup_stops_migration(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            original = b"encoding.add = UTF-8\n"
            rc.write_bytes(original)
            rc.with_name(rc.name + ".pre-01622-" + hashlib.sha256(original).hexdigest()[:12]).write_bytes(b"conflict")
            with self.assertRaises(RuntimeError):
                migration.migrate(rc)
            self.assertEqual(rc.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
