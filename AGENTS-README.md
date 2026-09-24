---
description: 
alwaysApply: false
---

# AGENTS.md

Guidance for AI agents working in this repository.

This repo is not a plain upstream mirror. It is an Appbox-oriented fork of
`crazy-max/docker-rtorrent-rutorrent` with compatibility work for existing Appbox
users, additional plugins, and a custom mobile ruTorrent UI.

## Current Image State

- Registry tag: `repo.cylo.net/rutorrent:5.3.14-0.16.23-1`
- Base runtime: `crazymax/alpine-s6:3.24-3.2.3.0`
- rTorrent / libtorrent: `0.16.23`
- ruTorrent: `5.3.14`
- PHP: `8.5`
- Entrypoint: `ENTRYPOINT ["/init"]` through s6-overlay.
- Production architecture: `linux/amd64`.

## Appbox Invariants

Preserve these unless the user explicitly asks for a breaking change:

- Runtime state lives under `/torrents`, not `/data` or `/downloads`.
- Completed downloads: `/torrents/completed`.
- Active downloads: `/torrents/downloading`.
- Watch directory: `/torrents/watch`.
- rTorrent config/session/logs: `/torrents/config/rtorrent`.
- ruTorrent config/user state: `/torrents/config/rutorrent`.
- autodl config: `/torrents/config/autodl`.
- Basic-auth files: `/passwd/rpc.htpasswd`, `/passwd/rutorrent.htpasswd`, `/passwd/webdav.htpasswd`.
- The web UI should be exposed to Appbox through HTTP port `80`; do not add a public HTTP port section to `appbox.yml`.
- `appbox.yml` intentionally relies on store/app-version rows for many runtime details; do not assume missing sections are accidental.

The Dockerfile still has `VOLUME [ "/data", "/downloads", "/passwd" ]` from upstream history,
but the actual Appbox runtime uses `/torrents` and `/passwd`.

## Lifecycle Scripts

The image uses s6-overlay. Do not replace it with a simple bash entrypoint.

Key boot scripts:

- `rootfs/etc/cont-init.d/00-set-passwd.sh` sets initial basic auth from `USERNAME` / `PASSWORD` or `RUTORRENT_USER` / `RUTORRENT_PASSWORD`.
- `rootfs/etc/cont-init.d/03-config.sh` renders nginx, PHP, rTorrent, and ruTorrent config; creates `/torrents` directories; enables/configures plugins; applies autodl compatibility patches on the live plugin tree.
- `rootfs/etc/cont-init.d/05-appbox.sh` handles Appbox upgrade migrations, autodl migration, user settings migration, `irssi` and `rtcheck` services, `filemanager-share`, and the installed callback.
- `rootfs/moduser.sh` is required by Appbox and updates basic auth for ruTorrent, XML-RPC, and WebDAV.
- `rootfs/usr/local/lib/rtorrent-web-auth.sh` is the single shared helper for writing htpasswd files.

If you touch password behavior, update the helper rather than duplicating htpasswd logic.

## Callback Behavior

When `INSTANCE_ID` is set, `05-appbox.sh` posts to:

```text
https://api.cylo.net/v1/apps/installed/${INSTANCE_ID}
```

Supported controls:

- `SKIP_APPBOX_CALLBACK=1` for local tests.
- `CALLBACK_TOKEN` for optional Bearer auth.
- `APPBOX_CALLBACK_BASE` for alternate callback base URLs.

Keep the callback path working; Appbox installs remain in "installing" until it succeeds.

## Bundled Plugins And Patches

The Dockerfile builds or vendors:

- `mobile/` into `/var/www/rutorrent/plugins/mobile`.
- `geoip2-rutorrent/` into `/var/www/rutorrent/plugins/geoip2`.
- `autodl-irssi` into `/home/rtorrent`.
- `autodl-rutorrent` into `/var/www/rutorrent/plugins/autodl-rutorrent`.
- `filemanager`, `filemanager-media`, and `filemanager-share`.
- `appbox` ruTorrent theme into `/var/www/rutorrent/plugins/theme/themes/appbox`.
- `mktorrent` for the ruTorrent `create` plugin.
- DumpTorrent tools for the ruTorrent dump plugin.

`scripts/patch-autodl-rutorrent-html5.py` is applied at build time and by `03-config.sh`
on every boot. This is intentional so persisted custom plugin overrides also get patched.
Do not make autodl fixes only in the generated image tree.

`rootfs/usr/local/bin/patch-rutorrent-dht-port.py` patches the upstream PHP and
JavaScript 0.16 command maps at build time. Keep both maps aligned: ruTorrent's
DHT setter must call `dht.override_port.set`; `dht.port` remains the live getter.
The assigned UDP port is still configured by `RT_DHT_PORT` at startup. New
catalogue versions must import the manifest's zero socket-buffer defaults.

`scripts/patch-rutorrent-cli-arguments.py` replaces the web INI check with a
probe of `Utility::getPHP()` using `php/cli-arguments.php`. PHP 8.5 reports the
directive as off even when CLI arguments work. Keep the web directive off; the
release gate tests plugin initialization, argument handling and failure cases.

## Mobile Plugin

The mobile plugin is a first-class part of this image.

Important files:

- `mobile/mobile.html`
- `mobile/init.js`
- `mobile/mobile.css`
- `mobile/styles/appbox-input.css`
- `mobile/appbox.css`

`mobile/appbox.css` is generated with Tailwind v4:

```bash
cd mobile
npm install
npm run build:css
```

Always rebuild and commit/check in `mobile/appbox.css` after changing Tailwind source,
HTML utility classes, or JS-rendered utility classes.

The mobile plugin depends on ruTorrent `httprpc` and expects `_getdir` for server-side
directory browsing. It explicitly keeps `create` and `_task` enabled so the mobile
create-torrent flow works.

## Web And Network Behavior

nginx config currently provides:

- ruTorrent on `RUTORRENT_PORT`, default `80`.
- XML-RPC at `/RPC2` in the ruTorrent server block.
- separate XML-RPC listener on `XMLRPC_PORT`, default `8000`.
- WebDAV on `WEBDAV_PORT`, default `9000`, rooted at `/torrents/completed`.
- localhost health listeners on `XMLRPC_PORT + 1`, `RUTORRENT_PORT + 1`, and `WEBDAV_PORT + 1`.

Only `80/tcp` is exposed in the Dockerfile for Appbox. Treat XML-RPC/WebDAV listeners as
internal unless the user specifically asks to expose them elsewhere.

## Upgrade Compatibility

`05-appbox.sh` contains compatibility behavior for old Appbox installs. It:

- detects old Appbox rTorrent config.
- backs up old `.rtorrent.rc` files.
- keeps `session` and `.session` paths compatible without moving session data.
- migrates old autodl config into `/torrents/config/autodl`.
- migrates old ruTorrent user settings from `users/` to `share/users/`.
- restores default `theme.dat`, `autotools.dat`, and `WebUISettings.dat` when missing or invalid.

Be very cautious when editing this script. Existing users can have long-lived persisted
state and old session files.

Normal version upgrades preserve the current-layout `.rtorrent.rc` and selected theme,
even though the replacement container has no `/etc/app_configured` marker. Only
configs identified by the existing legacy `Appbox ruTorrent` marker are replaced by
the older layout-conversion path. The 0.16.22 compatibility helper backs up the
retained config before removing the obsolete stock UTF-8 directive.

## Build And Release

Remote builder currently used by the user:

```bash
ssh appbox@builder.tester2.appboxes.co -p12246 \
  -i /Users/rid/.ssh/appbox_ubuntuvps2_webtop \
  -o IdentitiesOnly=yes
```

Typical sync/build/push command:

```bash
tar -C "/Users/rid/Development/Current/docker-rtorrent-rutorrent" \
  --exclude='.git' \
  --exclude='mobile/node_modules' \
  --exclude='rootfs/usr/local/bin/__pycache__' \
  -czf - . | \
ssh appbox@builder.tester2.appboxes.co -p12246 \
  -i /Users/rid/.ssh/appbox_ubuntuvps2_webtop \
  -o IdentitiesOnly=yes \
  "mkdir -p /home/appbox/builds/docker-rtorrent-rutorrent && \
   tar xzf - -C /home/appbox/builds/docker-rtorrent-rutorrent && \
   cd /home/appbox/builds/docker-rtorrent-rutorrent && \
   docker build --platform linux/amd64 -t repo.cylo.net/rutorrent:5.3.14-0.16.23-1 . && \
   docker push repo.cylo.net/rutorrent:5.3.14-0.16.23-1"
```

Only build, push, or commit when the user explicitly asks. Do not force-push or reset.

## Local Smoke Test

```bash
docker run --rm --platform linux/amd64 \
  -e USERNAME=admin \
  -e PASSWORD='TestPass123!' \
  -e INSTANCE_ID=test \
  -e SKIP_APPBOX_CALLBACK=1 \
  -p 8080:80 \
  -v rutorrent-torrents:/torrents \
  -v rutorrent-passwd:/passwd \
  repo.cylo.net/rutorrent:5.3.14-0.16.23-1
```

Open `http://localhost:8080/`. Force mobile mode with `http://localhost:8080/index.html?mobile=1`.

## Before Finishing Changes

- Run `npm run build:css` in `mobile/` when mobile styles changed.
- Rebuild `rootfs/var/www/rutorrent/plugins/theme/themes/appbox/style.css` and
  `style-min.css` when the Appbox theme Tailwind source changes.
- Run `node --check mobile/init.js` when mobile JS changed.
- Use `ReadLints` on changed files after substantive edits.
- Keep edits scoped; do not revert unrelated dirty files.
- Update `README.md` and this file when runtime paths, lifecycle scripts, bundled plugins,
  or build/release steps change.

## Watch-folder compatibility (5.3.12-0.16.10-1)

ruTorrent AutoWatch owns the default /torrents/watch import path. The image no
longer registers a competing native directory watcher or a stop_untied timer.
AutoWatch removes source .torrent files after importing them, so those native
rules could immediately pause the downloads they had loaded.

The default AutoWatch interval is five minutes, so imports can take up to five
minutes to appear.

For containers that are already configured, startup removes only the two former
stock rules from the retained .rtorrent.rc and saves a content-addressed
.pre-autowatch backup before modifying it.
Other rules and settings are left intact by this migration. It does not change
torrent states or remove downloaded data; previously stopped torrents can be
started after updating. Fresh install, restart, configured-state migration and
upgrade checks live in scripts/release-gate.py.
