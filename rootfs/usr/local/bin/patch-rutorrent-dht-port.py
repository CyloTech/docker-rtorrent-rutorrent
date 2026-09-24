#!/usr/bin/env python3
"""Fix ruTorrent's DHT settings command for rTorrent 0.16.x."""

from pathlib import Path
import sys


ENTRY = '\t"set_dht_port" => array( "name"=>"dht.override_port.set", "prm"=>1 ),'
ANCHOR = "\t// Scheduling\n"
JS_ENTRY = '\t\t\t"set_dht_port"      : { name: "dht.override_port.set", prm: 1 },'
JS_ANCHOR = '\t\t\t"schedule"          : { name: "schedule",                              prm: 1 },\n'


def patch(root: Path) -> bool:
    updates = []
    for filename, entry, anchor in (
        ("php/methods-0.16.0.php", ENTRY, ANCHOR),
        ("js/content.js", JS_ENTRY, JS_ANCHOR),
    ):
        path = root / filename
        original = path.read_text()
        if entry in original:
            continue
        if "dht.override_port.set" in original or original.count(anchor) != 1:
            raise RuntimeError("Unexpected ruTorrent DHT mapping in " + filename)
        # Patch only the 0.16 version map; older daemon mappings stay intact.
        updates.append((path, original.replace(anchor, entry + "\n\n" + anchor, 1)))
    for path, updated in updates:
        path.write_text(updated)
    return bool(updates)


if __name__ == "__main__":
    patch(Path(sys.argv[1]))
