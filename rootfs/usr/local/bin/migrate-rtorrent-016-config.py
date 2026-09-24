#!/usr/bin/env python3
"""Remove the former stock UTF-8 directive, removed by rTorrent 0.16.15."""

import hashlib
import os
from pathlib import Path
import shutil
import stat
import sys
import tempfile


def migrate(path):
    original = path.read_bytes()
    updated = b"".join(
        line for line in original.splitlines(keepends=True)
        if b"".join(line.split()) != b"encoding.add=UTF-8"
    )
    if updated == original:
        return False
    metadata = path.stat()
    backup = path.with_name(path.name + ".pre-01622-" + hashlib.sha256(original).hexdigest()[:12])
    if not backup.exists():
        shutil.copy2(path, backup)
        os.chown(backup, metadata.st_uid, metadata.st_gid)
    elif backup.read_bytes() != original:
        raise RuntimeError("Existing rTorrent compatibility backup differs")
    descriptor, temporary = tempfile.mkstemp(prefix=path.name + ".01622-", dir=path.parent)
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
    print("Removed obsolete stock UTF-8 directive; previous configuration backed up.")
    return True


if __name__ == "__main__":
    migrate(Path(sys.argv[1]))
