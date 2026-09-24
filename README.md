# rTorrent + ruTorrent for Appbox

Appbox packaging for rTorrent, libtorrent, and ruTorrent based on the upstream
[`crazy-max/docker-rtorrent-rutorrent`](https://github.com/crazy-max/docker-rtorrent-rutorrent)
image, with Appbox lifecycle scripts, persisted `/torrents` layout, autodl support,
file manager plugins, WebDAV, and a refreshed mobile ruTorrent UI.

The current Appbox image tag is:

```bash
repo.cylo.net/rutorrent:5.3.14-0.16.23-1
```

## Current Versions

- Alpine `3.24`
- rTorrent `0.16.23`
- libtorrent `0.16.23`
- ruTorrent `5.3.14`
- c-ares `1.34.8`
- curl `8.22.0`
- mktorrent `1.1`
- DumpTorrent `1.7.0`
- autodl-irssi `2.6.2`
- PHP `8.5`

## What This Fork Adds

- Appbox metadata in `appbox.yml`.
- Appbox password setup and recovery through `/moduser.sh`.
- Appbox installed callback from `rootfs/etc/cont-init.d/05-appbox.sh`.
- Compatibility with the previous Appbox `/torrents` data layout.
- Bundled `mobile/` plugin with Appbox-style light/dark UI, search, details cards, add flow, directory browser, and create-torrent support.
- Bundled `autodl-irssi` and `autodl-rutorrent`, with compatibility patches applied at build time and again on boot.
- Bundled `geoip2`, `filemanager`, `filemanager-media`, and `filemanager-share`.
- WebDAV listener for completed downloads.
- `rtcheck` service restored from the previous Appbox image.
- Appbox dashboard-inspired `appbox` ruTorrent theme, plus the previous `club-QuickBox` theme.

## Runtime Layout

This image intentionally uses the previous Appbox paths:

- `/torrents/config/rtorrent` - rTorrent config, logs, and session data.
- `/torrents/config/rutorrent` - ruTorrent config, plugin config, themes, user settings, and uploaded torrent files.
- `/torrents/config/autodl` - persisted autodl-irssi config.
- `/torrents/completed` - completed downloads.
- `/torrents/downloading` - active downloads.
- `/torrents/watch` - watch directory.
- `/passwd` - `rutorrent.htpasswd`, `rpc.htpasswd`, and `webdav.htpasswd`.

The Dockerfile still declares upstream-style `VOLUME [ "/data", "/downloads", "/passwd" ]`,
but the Appbox runtime and templates use `/torrents` and `/passwd`. Do not switch the
runtime paths back to `/data` or `/downloads` unless you are intentionally breaking
compatibility with existing Appbox installs.

## Ports

Only port `80/tcp` is exposed by the image for Appbox reverse proxying.

Internally nginx also configures:

- ruTorrent HTTP on `RUTORRENT_PORT` default `80`.
- XML-RPC on `/RPC2` in the ruTorrent server block.
- separate XML-RPC listener on `XMLRPC_PORT` default `8000`.
- WebDAV on `WEBDAV_PORT` default `9000`, rooted at `/torrents/completed`.
- localhost health listeners on the next ports: `8001`, `81`, and `9001` by default.

For Appbox, HTTP is reverse-proxied through the platform. Do not publish the web UI as
an explicit public app port in `appbox.yml`.

## Credentials

Initial credentials come from Appbox fields:

- `USERNAME`
- `PASSWORD`

The scripts also accept the upstream-style names:

- `RUTORRENT_USER`
- `RUTORRENT_PASSWORD`

`00-set-passwd.sh`, `025-set-passwd.sh`, and `/moduser.sh` all use
`/usr/local/lib/rtorrent-web-auth.sh`, which writes the same bcrypt htpasswd entry to:

- `/passwd/rutorrent.htpasswd`
- `/passwd/rpc.htpasswd`
- `/passwd/webdav.htpasswd`

Password recovery:

```bash
docker exec <container> /moduser.sh 'NewComplexPassword123!'
```

## Appbox Lifecycle

The image uses s6-overlay and keeps `ENTRYPOINT ["/init"]`.

Boot-time setup is handled by `rootfs/etc/cont-init.d/`:

- `00-set-passwd.sh` writes initial basic-auth files when credentials are provided.
- `03-config.sh` renders PHP, nginx, rTorrent, and ruTorrent config; creates `/torrents` directories; enables the mobile plugin; configures the create plugin; applies custom plugins/themes; patches autodl-rutorrent.
- `05-appbox.sh` handles upgrade compatibility, autodl migration, user settings migration, irssi and rtcheck services, filemanager-share endpoint setup, and Appbox callback.

When `INSTANCE_ID` is set, `05-appbox.sh` posts to:

```text
https://api.cylo.net/v1/apps/installed/${INSTANCE_ID}
```

Set `SKIP_APPBOX_CALLBACK=1` for local smoke tests. `CALLBACK_TOKEN` is supported if
the app record requires callback authentication.

## Bundled Plugins

The image keeps the upstream ruTorrent plugin set and adds or configures:

- `mobile`
- `geoip2`
- `autodl-rutorrent`
- `filemanager`
- `filemanager-media`
- `filemanager-share`
- `theme` with `appbox` as the default and `club-QuickBox` still bundled
- `create` configured to use `/usr/local/bin/mktorrent`

`03-config.sh` changes existing persisted `plugins.ini` files from
`enabled = user-defined` to `enabled = yes` under `[default]` so bundled plugins remain
available after upgrades. It also ensures `[mobile] enabled = yes` exists.

Custom plugins can be placed under:

```text
/torrents/config/rutorrent/plugins/<plugin-name>
```

Custom plugin `conf.php` files can be placed under:

```text
/torrents/config/rutorrent/plugins-conf/<plugin-name>.php
```

Custom themes can be placed under:

```text
/torrents/config/rutorrent/themes/<theme-name>
```

The bundled `appbox` theme lives at:

```text
/var/www/rutorrent/plugins/theme/themes/appbox
```

Its editable Tailwind source is `styles/appbox-input.css`; rebuild the runtime
`style.css` / `style-min.css` files after changing it.

## Mobile Plugin

The mobile UI is vendored in `mobile/` and copied to:

```text
/var/www/rutorrent/plugins/mobile
```

Key features:

- Appbox-style card/header layout.
- Light/dark theme toggle.
- Inline torrent search.
- Floating status, labels, and trackers filters.
- Improved add-torrent and directory browser flows for ruTorrent 5.x.
- Create-torrent page using the ruTorrent `create` plugin.
- Details tabs styled for mobile.

CSS is generated with Tailwind v4:

```bash
cd mobile
npm install
npm run build:css
```

Commit `mobile/appbox.css` after changing `mobile/styles/appbox-input.css`, markup that
uses generated classes, or JS-rendered class names.

## Upgrade Notes

This repo preserves previous Appbox behavior while moving to current rTorrent and
ruTorrent versions.

On old Appbox installs, `05-appbox.sh` detects old config and user setting paths,
creates compatibility symlinks for `session` and `.session`, migrates autodl config to
`/torrents/config/autodl`, and warns that older torrents may need their download
directory reset to `/torrents/completed` followed by a force recheck.

Do not remove the migration logic unless you have explicitly decided to stop supporting
existing Appbox installs.

## Build

Production builds target `linux/amd64`.

Local build:

```bash
docker build --platform linux/amd64 -t repo.cylo.net/rutorrent:5.3.14-0.16.23-1 .
```

Remote builder currently used for release builds:

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

Only push a registry tag when the user explicitly asks for it.

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

Open `http://localhost:8080/` and sign in with the provided credentials. Force mobile
mode with `http://localhost:8080/index.html?mobile=1`.

## Important Files

- `Dockerfile` - upstream build plus Appbox additions.
- `appbox.yml` - Appbox store metadata.
- `mobile/` - vendored mobile plugin.
- `scripts/patch-autodl-rutorrent-html5.py` - autodl-rutorrent compatibility patcher.
- `rootfs/etc/cont-init.d/03-config.sh` - main runtime config renderer.
- `rootfs/etc/cont-init.d/05-appbox.sh` - Appbox lifecycle and migration logic.
- `rootfs/usr/local/lib/rtorrent-web-auth.sh` - shared auth writer.
- `rootfs/moduser.sh` - Appbox password recovery.

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

## Package refresh: 5.3.14-0.16.22

This release packages ruTorrent 5.3.14, rTorrent/libtorrent 0.16.22, Alpine 3.24,
s6-overlay 3.2.3.0, PHP 8.5, curl 8.22.0, c-ares 1.34.8, gosu 1.19,
GeoIP2 3.4.0 and Tailwind 4.3.3. RAR and UnRAR use stable 7.23; the UnRAR
source archive is named 7.2.7. The bundled RAR binary comes from RARLab
`rarlinux-x64-723.tar.gz` (binary SHA-256
`56c3c4fd46faa7a9f52264d30cb96813e19ec7c4587d9f18424d7e909cf78555`).

Normal version upgrades preserve the existing rTorrent config and selected theme.
The former legacy-Appbox layout conversion remains in place.

Startup backs up the retained rTorrent configuration before removing the former
stock `encoding.add = UTF-8` directive, which newer rTorrent no longer supports.
The generated DHT setting uses `dht.override_port.set`; persisted settings,
torrent sessions, authentication and the existing AutoWatch fix remain covered
by the release gate.

Published on 2026-09-14 as catalog version **1316** for app **66** (enabled/default).
The immutable registry reference is recorded in `appbox.yml`.

The dedicated-builder release gate passed fresh install, plugin initialization,
web/watch imports, restart persistence, upgrade from catalog version 1308,
configuration backup and custom-setting/theme retention, authentication,
installation callbacks, package versions, and a 1 MiB private torrent transfer
with SHA-256 verification. Catalog publication does not update existing instances.

## Preallocation correction: 5.3.14-0.16.22-1

The Appbox catalogue now supplies `RT_PREALLOCATE_TYPE=1`. Startup converts the
legacy value `2` to `1`; both enabled the same per-file allocation behavior.
`0` remains disabled, and saved `.rtorrent.rc` overrides are preserved. This does
not reserve the entire torrent immediately. Standalone containers still default
to `0` unless the environment variable is supplied.

Before publishing this release, run on the dedicated builder:

```sh
python3 scripts/preallocation-release-gate.py repo.cylo.net/rutorrent:5.3.14-0.16.22-1
```

## Session persistence: 5.3.14-0.16.22-2

Session snapshots run after the first minute and every five minutes afterwards.
The app-owned `appbox_session_save` timer is separate from custom `session_save`
timers. The former 3,600/10,800-second environment defaults migrate to 300 seconds;
other explicit intervals and saved `.rtorrent.rc` files are preserved.

rTorrent receives SIGINT during an orderly container stop, with up to 25 seconds
for supervised services to exit. A shutdown hook queues the latest session state
before network cleanup. Use a Docker stop timeout of at least 30 seconds.
An external SIGKILL bypasses these hooks and can still lose progress since the last
snapshot; the platform's forced-stop path must also change to prevent that.

The image no longer forces hash checks solely because a torrent has zero completed
pieces at startup. rTorrent's normal resume validation remains enabled.

Release gate on the dedicated builder:

```sh
python3 scripts/session-release-gate.py repo.cylo.net/rutorrent:5.3.14-0.16.22-3
```

## Network compatibility: 5.3.14-0.16.22-3

The image patches both ruTorrent command maps (PHP and JavaScript) so the DHT
port setting uses `dht.override_port.set` on rTorrent 0.16.x. The former
`dht.port.set` command accepts the request but does nothing. The getter remains
`dht.port`, which reports the actual listener. Startup still selects the
platform-assigned UDP port through `RT_DHT_PORT`; changes made in ruTorrent do
not alter Docker's port forwarding or replace that assigned port on restart.

`RT_SEND_BUFFER_SIZE` and `RT_RECEIVE_BUFFER_SIZE` now default to `0` in both
startup and the manifest, allowing kernel TCP autotuning. Explicit nonzero
environment values remain supported. The next catalogue import must include
the manifest's zero values so the former 64M catalogue defaults are replaced.

The managed config uses the current schedule, execution and listening-port
commands. It relies on rTorrent's built-in insertion save handler instead of
the ineffective two-argument `method.set_key` rule. Persistent custom configs
are retained, and the launcher keeps `-D` for their compatibility.

`scripts/network-test-in-container.py` exercises the real authenticated
ruTorrent settings endpoint and checks the kernel UDP listener in disposable
containers. It also checks zero buffer defaults and preservation of synthetic
custom settings/data across upgrade and restart. Do not run its mutating modes
against customer containers.

## PHP compatibility fix: 5.3.14-0.16.23-1

Fixes the misleading `register_argc_argv` warning on PHP 8.5 by testing the PHP
executable used by plugins. Web PHP keeps the directive off. rTorrent and
libtorrent remain at 0.16.23, and ruTorrent remains at 5.3.14.
The DHT port mapping, zero socket-buffer defaults, five-minute session saves,
graceful shutdown and persisted configuration behavior are retained.

Run the exact-image release gate on the dedicated builder before publishing:

```sh
python3 scripts/session-release-gate.py repo.cylo.net/rutorrent:5.3.14-0.16.23-1
```

The upgrade gate starts from the immutable 5.3.14-0.16.22-3 image and verifies
torrent sessions, custom configuration, authentication and data retention.
