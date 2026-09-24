#!/usr/bin/env python3
"""Backport the seedingtime hash-done fix to bundled ruTorrent 5.3.14."""
from pathlib import Path
import sys

OLD = '\t$theSettings->getOnHashdoneCommand(array("seedingtimecheck".User::getUser(),\n\t\tgetCmd(\'branch=\').\'$\'.getCmd(\'not=\').\'$\'.getCmd(\'d.get_complete=\').\',,\'.\n\t\tgetCmd(\'d.get_custom\').\'=seedingtime,,"\'.getCmd(\'d.set_custom\').\'=seedingtime,$\'.getCmd(\'d.get_custom\').\'=addtime\'.\'"\')),'
NEW = '\t$theSettings->getOnHashdoneCommand(array("seedingtimecheck".User::getUser(),\n\t\tgetCmd(\'branch=\').getCmd(\'d.get_complete=\').\',"\'.\n\t\tgetCmd(\'branch=\').getCmd(\'d.get_custom\').\'=seedingtime,,\\"\'.\n\t\tgetCmd(\'d.set_custom\').\'=seedingtime,$\'.getCmd(\'d.get_custom\').\'=addtime\\""\')),'


def patch(root):
    target = Path(root) / "plugins/seedingtime/init.php"
    source = target.read_text()
    if source.count(NEW) == 1 and OLD not in source:
        return
    if source.count(OLD) != 1 or NEW in source:
        raise RuntimeError("Unexpected seedingtime hook; refusing to patch")
    target.write_text(source.replace(OLD, NEW, 1))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        raise SystemExit("Usage: patch-rutorrent-seedingtime.py RUTORRENT_ROOT")
    patch(sys.argv[1])
