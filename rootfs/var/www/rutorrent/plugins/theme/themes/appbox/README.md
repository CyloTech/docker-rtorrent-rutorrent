# Appbox ruTorrent Theme

ruTorrent theme based on the Appbox dashboard palette and component treatment:

- indigo/purple primary accents
- dark default mode with a built-in light/dark toggle
- dashboard-style sidebar and card surfaces
- visible borders, rounded controls, and soft hover glow
- Tailwind v4 source in `styles/appbox-input.css`

## Typography

Use a compact Appbox dashboard scale everywhere in the theme, including ruTorrent core
dialogs and autodl-irssi interfaces:

- Font family: `Inter`, falling back to system UI sans-serif. Use monospace only for logs,
  consoles, code, hashes, and path-like technical values.
- Base UI text: `12px / 1.45`, normal weight. This is the default for tables, dialogs,
  settings forms, autodl panels, status bars, and secondary text.
- Interactive controls: `13px / 1.35`, medium weight for menus, buttons, toolbar controls,
  tabs, dropdown items, and form inputs.
- Dialog and section titles: `14px / 1.25`, semibold. Keep labels concise and avoid
  uppercase unless a compact badge or status chip needs it.
- Dense metadata: `11px / 1.25`, medium or semibold only when needed for progress meter
  labels, counters, badges, and table microcopy.
- Avoid ad-hoc font sizes in feature-specific CSS. Add or reuse a theme token in
  `styles/appbox-input.css` instead so ruTorrent and autodl-irssi remain visually aligned.

Build the runtime CSS from this directory:

```bash
tmpdir=$(mktemp -d)
cp ./styles/appbox-input.css "$tmpdir/appbox-input.css"
npm install --prefix "$tmpdir" tailwindcss @tailwindcss/cli
"$tmpdir/node_modules/.bin/tailwindcss" -i "$tmpdir/appbox-input.css" -o ./style.css --minify
cp ./style.css ./style-min.css
rm -rf "$tmpdir"
```
