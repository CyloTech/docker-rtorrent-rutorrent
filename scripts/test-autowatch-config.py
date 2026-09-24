#!/usr/bin/env python3
import importlib.util
from pathlib import Path
import tempfile
import unittest

helper = Path(__file__).parents[1] / "rootfs/usr/local/bin/migrate-autowatch-config.py"
spec = importlib.util.spec_from_file_location("autowatch_migration", helper)
migration = importlib.util.module_from_spec(spec)
spec.loader.exec_module(migration)
stock = (b'directory.watch.added = (cat,(cfg.watch)), load.start\r\n'
         b'schedule2 = untied_directory, 5, 5, (cat,"stop_untied=",(cfg.watch),"*.torrent")\r\n')


class MigrationTest(unittest.TestCase):
    def test_exact_backup_preservation_and_idempotency(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            custom = b"# Customer settings\r\nthrottle.max_uploads.set = 27\r\n"
            original = custom + stock + b"# trailing comment without newline"
            rc.write_bytes(original)
            rc.chmod(0o640)
            self.assertTrue(migration.migrate(rc))
            self.assertEqual(rc.read_bytes(), custom + b"# trailing comment without newline")
            self.assertEqual(rc.stat().st_mode & 0o777, 0o640)
            backups = list(rc.parent.glob(".rtorrent.rc.pre-autowatch-*"))
            self.assertEqual(len(backups), 1)
            self.assertEqual(backups[0].read_bytes(), original)
            self.assertFalse(migration.migrate(rc))
            self.assertEqual(list(rc.parent.glob(".rtorrent.rc.pre-autowatch-*")), backups)

    def test_custom_rules_and_comments_are_untouched(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            original = (b"# " + stock.splitlines()[0] + b"\n" +
                        stock.replace(b"5, 5", b"20, 20").replace(b"cfg.watch", b"cfg.custom_watch"))
            rc.write_bytes(original)
            self.assertFalse(migration.migrate(rc))
            self.assertEqual(rc.read_bytes(), original)
            self.assertFalse(list(rc.parent.glob("*.pre-autowatch-*")))

    def test_conflicting_backup_fails_without_changing_configuration(self):
        with tempfile.TemporaryDirectory() as directory:
            rc = Path(directory) / ".rtorrent.rc"
            rc.write_bytes(stock)
            suffix = migration.hashlib.sha256(stock).hexdigest()[:12]
            rc.with_name(rc.name + ".pre-autowatch-" + suffix).write_bytes(b"different")
            with self.assertRaises(RuntimeError):
                migration.migrate(rc)
            self.assertEqual(rc.read_bytes(), stock)


if __name__ == "__main__":
    unittest.main()
