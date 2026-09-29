#!/usr/bin/env python3
"""Require an authenticated, definitive absent release tag before publication."""
import subprocess
import sys

EXPECTED = "repo.cylo.net/rutorrent:5.3.15.2-0.16.24"
PREVIOUS = "repo.cylo.net/rutorrent@sha256:fc8a15f0b42d7368b06cf1dd7d16dcb0b1d20d5a2a096f1a3dbfb9d9573e4644"


def require_absent(image):
    if image != EXPECTED:
        raise RuntimeError("Unexpected image reference")
    # The Docker CLI supplies the builder's registry credentials internally.
    known = subprocess.run(["docker", "manifest", "inspect", PREVIOUS], capture_output=True, text=True, timeout=60)
    if known.returncode:
        raise RuntimeError("Registry read of the current published digest failed; state is indeterminate")
    result = subprocess.run(["docker", "manifest", "inspect", image], capture_output=True, text=True, timeout=60)
    if result.returncode == 0:
        raise RuntimeError("Release tag exists; refusing to replace it")
    if result.stderr.strip() != "no such manifest: " + image:
        raise RuntimeError("Registry did not return definitive MANIFEST_UNKNOWN; refusing publication")
    print("Registry verified: current digest readable; new tag definitively absent", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: registry-check.py IMAGE")
    require_absent(sys.argv[1])
