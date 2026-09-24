#!/usr/bin/env python3
"""
autodl-rutorrent compatibility patch for modern ruTorrent:

- XHTML-style self-closing tags on non-void elements (<div .../>, <select .../>,
  <tbody .../>) break dialog DOM creation in HTML5 parsers.
- UploadMethod.js still calls the old _getdir constructor shape.
- getConf.php still calls the removed global isLocalMode() helper instead of
  User::isLocalMode().
"""
from __future__ import annotations

import pathlib
import re
import sys


def main() -> None:
    base = pathlib.Path(sys.argv[1] if len(sys.argv) > 1 else "/var/www/rutorrent/plugins/autodl-rutorrent")
    js = base / "js"
    tag_re = re.compile(r"<(div|select|tbody)([^>]*)/>")
    for path in js.glob("*.js"):
        content = path.read_text(encoding="utf-8")
        fixed = tag_re.sub(lambda m: f"<{m.group(1)}{m.group(2)}></{m.group(1)}>", content)
        if path.name == "UploadMethod.js":
            fixed = fixed.replace(
                'this.getdirButton1 = new theWebUI.rDirBrowser(idDlg, this.id("watchdir-folder"), this.id("getdir-button"));',
                'this.getdirButton1 = new theWebUI.rDirBrowser(this.id("watchdir-folder"));',
            )
            fixed = fixed.replace(
                'this.getdirButton2 = new theWebUI.rDirBrowser(idDlg, this.id("rtorrent-folder"), this.id("rt-getdir-button"));',
                'this.getdirButton2 = new theWebUI.rDirBrowser(this.id("rtorrent-folder"));',
            )
        if fixed != content:
            path.write_text(fixed, encoding="utf-8")

    get_conf = base / "getConf.php"
    if get_conf.exists():
        content = get_conf.read_text(encoding="utf-8")
        fixed = content.replace("if (!isLocalMode()) {", "if (!User::isLocalMode()) {")
        if fixed != content:
            get_conf.write_text(fixed, encoding="utf-8")


if __name__ == "__main__":
    main()
