## ruTorrent Mobile (Appbox)

Dashboard-inspired ruTorrent UI for phones and tablets: large touch targets, searchable torrent list, richer detail cards, quick actions, and light/dark theming aligned with the [Appbox](https://appbox.co) dashboard.

Maintained by **CyloTech** as a fork of [xombiemp/rutorrentMobile](https://github.com/xombiemp/rutorrentMobile).

### Requirements

- **httprpc** plugin (required).
- ruTorrent **5.x** / **jQuery 3**–compatible environments are supported (see `init.js` for compatibility shims).

### Installation

Place all plugin files in a directory named **`mobile`** under `rutorrent/plugins/`.

Clone this repository:

```bash
cd rutorrent/plugins
git clone https://github.com/CyloTech/rutorrentMobile.git mobile
```

> **Note:** The directory **must** be named `mobile` so assets and `mobile.css` resolve correctly.

> **Warning:** Not compatible with the **ipad** plugin.

### Highlights

- Dashboard-style header, cards, filters, and bottom action rail
- Inline torrent search for names, labels, and tracker/error text
- Improved add-torrent flow with clearer file-picker affordance
- Better loading / empty / error states for the list and detail tabs
- Dark / light mode toggle with local preference persistence
- ruTorrent 5.x `_getdir`-compatible directory browser flow

### Styling (Tailwind)

- **`appbox.css`** is generated from `styles/appbox-input.css` with the Tailwind v4 CLI.
- After changing markup (`mobile.html`), `init.js` strings that introduce new utility classes, or `styles/appbox-input.css`, rebuild:

```bash
npm install
npm run build:css
```

Commit the updated **`appbox.css`** so servers using the plugin do not need Node.js.

Optional plugins that add behaviour:

- **_getdir** — browse server directories when adding a torrent.
- **erasedata** — delete with data from the delete confirmation flow.
- **seedingtime** — Added / Finished fields in details.
- **ratio** — ratio group selector in details.
- **throttle** — channel selector in details.

### Configuration

Options at the top of **`init.js`**:

| Option | Default | Description |
|--------|---------|-------------|
| `plugin.enableAutodetect` | `true` | Auto-load on detected mobile browsers. |
| `plugin.tabletsDetect` | `true` | Treat tablets as mobile for autodetect. |
| `plugin.eraseWithDataDefault` | `false` | Default “delete with data” when ruTorrent’s delete confirmation is disabled. |
| `plugin.sort` | `'-addtime'` | Default torrent list sort (`name`, `-name`, `size`, …; prefix `-` for descending). |

### Usage

With **`plugin.enableAutodetect`**, the mobile UI loads on supported mobile user agents. On desktop, append **`?mobile=1`** to the ruTorrent URL to force the mobile UI.

Once loaded you can:

- Search the current list from the top search field
- Tap summary cards to jump to common status views
- Use the bottom action rail for start / stop / pause / recheck / delete
- Toggle dark mode from the sun / moon icon

### Troubleshooting

- Ensure **httprpc** is installed and enabled.
- Confirm the plugin path is **`plugins/mobile/`** and that **`appbox.css`** and **`mobile.css`** are present.
- If the mobile UI looks stale after an upgrade, hard refresh the browser (or use a private window) so ruTorrent does not keep cached plugin JS / CSS.
- Remove the **ipad** plugin if scrolling or layout breaks.
- Report issues: [https://github.com/CyloTech/rutorrentMobile/issues](https://github.com/CyloTech/rutorrentMobile/issues) (include device, OS, browser, and web server details).

### License

GPL-3.0 (see `LICENSE`).
