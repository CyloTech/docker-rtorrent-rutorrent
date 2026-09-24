#!/usr/bin/env python3
"""Check the plugin PHP executable rather than the web PHP INI value."""
from pathlib import Path
import sys

OLD = '''\t\t\t$val = strtoupper(ini_get("register_argc_argv"));
\t\t\tif( $val!=='' && $val!='ON' && $val!='1' && $val!='TRUE' )'''
NEW = '''\t\t\trequire_once(__DIR__.'/cli-arguments.php');
\t\t\tif(!ruTorrentPhpCliHasArguments(Utility::getPHP()))'''


def patch(root):
    target = root / 'php/getplugins.php'
    text = target.read_text()
    if text.count(NEW) == 1 and OLD not in text:
        return
    if text.count(OLD) != 1:
        raise RuntimeError('Expected one ruTorrent CLI argument diagnostic')
    if not (root / 'php/cli-arguments.php').is_file():
        raise RuntimeError('CLI argument helper is missing')
    target.write_text(text.replace(OLD, NEW))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: patch-rutorrent-cli-arguments.py RUTORRENT_ROOT')
    patch(Path(sys.argv[1]))
