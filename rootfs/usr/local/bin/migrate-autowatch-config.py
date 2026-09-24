#!/usr/bin/env python3
"""Remove only the two former image defaults that conflict with AutoWatch."""

import hashlib
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile


RULES = {
    b'directory.watch.added=(cat,(cfg.watch)),load.start',
    b'schedule2=untied_directory,5,5,(cat,"stop_untied=",(cfg.watch),"*.torrent")',
}


def migrate(path):
    original = path.read_bytes()
    updated = b"".join(
        line for line in original.splitlines(keepends=True)
        if b"".join(line.split()) not in RULES
    )
    if updated == original:
        return False

    metadata = path.stat()
    backup = path.with_name(path.name + ".pre-autowatch-" + hashlib.sha256(original).hexdigest()[:12])
    if not backup.exists():
        shutil.copy2(path, backup)
        os.chown(backup, metadata.st_uid, metadata.st_gid)
    elif backup.read_bytes() != original:
        raise RuntimeError("Existing AutoWatch migration backup differs")

    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".autowatch-", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            output.write(updated)
            output.flush()
            os.fsync(output.fileno())
        os.chmod(temporary, stat.S_IMODE(metadata.st_mode))
        os.chown(temporary, metadata.st_uid, metadata.st_gid)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print("Removed conflicting default rTorrent watch rules; previous configuration backed up.")
    return True


if __name__ == "__main__":
    migrate(Path(sys.argv[1]))
