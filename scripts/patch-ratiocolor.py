#!/usr/bin/env python3
"""Adapt Gyran's ratiocolor plugin to the Appbox ruTorrent 5 image."""
from pathlib import Path
import sys

MODE_OLD = 'changeWhat = "cell-background";'
# Prior Appbox images coloured the ratio text rather than the cell background.
MODE_NEW = 'changeWhat = "font";'

HOOK_ANCHOR = """               theWebUI.setRatioColors();
            };
"""
# ruTorrent 5 updates visible cells in place through syncDOM() and only
# calls refreshRows() for scrolling, sorting and row changes. Recolour after
# each sync so a ratio that crosses a level updates without a redraw.
HOOK = HOOK_ANCHOR + """            plugin.tempSyncDOM = theWebUI.tables.trt.obj.syncDOM;
            theWebUI.tables.trt.obj.syncDOM = function(){
                plugin.tempSyncDOM.apply(this, arguments);
                theWebUI.setRatioColors();
            };
"""


def main():
    target = Path(sys.argv[1] if len(sys.argv) > 1 else "/var/www/rutorrent/plugins/ratiocolor") / "init.js"
    text = target.read_text()
    if text.count(MODE_OLD) != 1 or text.count(HOOK_ANCHOR) != 1:
        raise SystemExit("ratiocolor init.js does not match the pinned upstream source")
    text = text.replace(MODE_OLD, MODE_NEW).replace(HOOK_ANCHOR, HOOK)
    target.write_text(text)


if __name__ == "__main__":
    main()
