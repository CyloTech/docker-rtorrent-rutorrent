#!/usr/bin/env python3
"""Patch ruTorrent stable table progress for Appbox theme geometry."""

import re
from pathlib import Path


STABLE_JS_FILES = [
    Path("/var/www/rutorrent/js/stable.js"),
    Path("/var/www/rutorrent/plugins/theme/themes/club-QuickBox/images/stable.js"),
]
STABLE_CSS = Path("/var/www/rutorrent/css/stable.css")

OLD_TEXT = """<span class='meter-text' style='overflow: visible'>"""
NEW_TEXT = """<span class='meter-text'>"""

OLD_VALUE = """<div class='meter-value' style='float: left; height: 18px !important; margin-top: 4px !important; background-color: """
NEW_VALUE = """<div class='meter-value' style='background-color: """

APPBOX_STABLE_CSS = """

/* Appbox progress meter geometry. Keep after core stable.css rules. */
.stable,
.stable table,
.stable td,
.stable th {
  font-family: var(--appbox-font-sans, Inter, ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif) !important;
  font-size: var(--appbox-text-base, 12px);
  line-height: var(--appbox-leading-base, 1.45);
}
.stable thead td,
.stable th {
  font-size: var(--appbox-text-dense, 11px);
  font-weight: 600;
  line-height: var(--appbox-leading-dense, 1.25);
}
.stable td:has(.meter-value),
.stable td:has(.meter-text),
td[class*="table-"]:has(.meter-value),
td[class*="table-"]:has(.meter-text),
td[class*="t-col-"]:has(.meter-value),
td[class*="t-col-"]:has(.meter-text) {
  background: transparent !important;
  border-radius: 9999px !important;
  height: 16px !important;
  line-height: 16px !important;
  overflow: visible !important;
  padding: 0 !important;
  position: relative !important;
}
.stable td:has(.meter-value)::before,
.stable td:has(.meter-text)::before,
td[class*="table-"]:has(.meter-value)::before,
td[class*="table-"]:has(.meter-text)::before,
td[class*="t-col-"]:has(.meter-value)::before,
td[class*="t-col-"]:has(.meter-text)::before {
  background: rgba(129, 140, 248, 0.08);
  border-radius: 9999px;
  box-shadow: inset 0 0 0 1px rgba(129, 140, 248, 0.38);
  content: "";
  inset: 0;
  position: absolute;
}
.meter-value {
  background: var(--appbox-primary-active, #6366f1) !important;
  border: 0 !important;
  border-radius: 9999px !important;
  bottom: 0;
  box-shadow: none !important;
  clip-path: inset(0 round 9999px);
  display: block !important;
  float: none !important;
  height: 100% !important;
  left: 0;
  margin: 0 !important;
  max-width: 100% !important;
  min-width: 0;
  position: absolute !important;
  top: 0 !important;
  transform: none;
}
.meter-text {
  align-items: center;
  color: var(--appbox-foreground, #e5e7eb) !important;
  display: flex !important;
  float: none !important;
  font-size: var(--appbox-text-dense, 11px) !important;
  font-weight: 600;
  height: 100% !important;
  inset: 0;
  justify-content: center;
  line-height: 1 !important;
  overflow: visible !important;
  pointer-events: none;
  position: absolute !important;
  text-align: center !important;
  text-shadow: none !important;
  top: 0 !important;
  width: 100% !important;
  z-index: 1;
}
"""


def patch_stable_js_file(path: Path) -> bool:
    if not path.exists():
        return False

    content = path.read_text()
    patched = content.replace(OLD_TEXT, NEW_TEXT).replace(OLD_VALUE, NEW_VALUE)
    patched = patched.replace('.addClass("meter-text").css({overflow:"visible"}).text(celldata)', '.addClass("meter-text").text(celldata)')
    patched = re.sub(
        r"const nval = iv\(val\);\s*return \{\s*width: `\$\{nval\}%`,",
        "const nval = Math.max(0, Math.min(100, iv(val)));\n  return {\n    width: `${nval}%`,",
        patched,
    )

    if patched != content:
        path.write_text(patched)
        return True
    return False


def patch_stable_js() -> bool:
    changed = False
    found = False
    for path in STABLE_JS_FILES:
        if path.exists():
            found = True
            changed = patch_stable_js_file(path) or changed

    if not found:
        raise SystemExit("no stable.js files found to patch")

    return changed


def patch_stable_css() -> bool:
    if not STABLE_CSS.exists():
        raise SystemExit(f"{STABLE_CSS} does not exist")

    content = STABLE_CSS.read_text()
    marker = "/* Appbox progress meter geometry."
    if marker in content:
        patched = re.sub(
            r"\n/\* Appbox progress meter geometry\..*?(?=\n/\*|\Z)",
            APPBOX_STABLE_CSS,
            content.rstrip(),
            flags=re.S,
        )
        if patched != content:
            STABLE_CSS.write_text(patched)
            return True
        return False

    STABLE_CSS.write_text(content.rstrip() + APPBOX_STABLE_CSS)
    return True


def main() -> None:
    js_changed = patch_stable_js()
    css_changed = patch_stable_css()
    if js_changed or css_changed:
        print("Patched stable table progress")
    else:
        print("stable table progress already patched")


if __name__ == "__main__":
    main()
