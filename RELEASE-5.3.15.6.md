# 5.3.15.6

Hardening release. Basic auth can no longer be switched off by an empty or
missing password file, and the installed callback token is no longer on
curl's command line.

Upstream `03-config.sh` commented out `auth_basic` in the rendered nginx
config whenever `/passwd/rutorrent.htpasswd`, `rpc.htpasswd` or
`webdav.htpasswd` was empty. An empty `rutorrent.htpasswd` served the whole
port 80 server (the one behind the Appbox HTTPS proxy) without a login,
including `/RPC2`, because the same `sed` also commented out that location's
own `auth_basic`. Appbox always supplies `RUTORRENT_USER` /
`RUTORRENT_PASSWORD` (required install fields) and `025-set-passwd.sh` writes
all three files from them on every start, so this was not a live exposure on
correctly installed instances.

Changes (rootfs; `Dockerfile` and a future full rebuild pick them up too):

- `03-config.sh`: never comments auth out. nginx keeps `auth_basic` for
  ruTorrent (port 80, including `/RPC2`), XML-RPC (port 8000) and WebDAV
  (port 9000). An empty file refuses every login (401) and a missing one
  fails the request (403/500). Each empty or missing file logs
  `ERROR: /passwd/<name>.htpasswd is empty or missing; ...`. The container
  keeps running, so `/moduser.sh <password>` (Appbox password reset) restores
  access at once without a restart, and rTorrent keeps seeding.
  The same rule applies to `rpc.htpasswd` and `webdav.htpasswd`: their ports
  are not published, but other containers on the Cylo network can reach them,
  and a correctly installed instance cannot have them empty at this point
  (025 rewrites all three files from the install fields first).
  `/no-auth/share.php` keeps its explicit `auth_basic off` (public share links).
- `025-set-passwd.sh`: log text no longer says an empty file disables auth.
- `appbox-installed-callback`: the callback URL (which can carry
  `?callback_token=`) and `X-Cylo-Callback-Token` reach curl as a config file
  on stdin (`curl --config -`), not as arguments. Retries, logging and exit
  statuses are unchanged.

The image is the published 5.3.15.5 image
(`repo.cylo.net/rutorrent@sha256:0f967374ba2396278b15a6c00e8330156d7daf6a14475071f88d5d88b3e9783b`)
with only those three files replaced (`Dockerfile.auth-fail-closed`, two
`COPY` layers). rTorrent, libtorrent, ruTorrent, the plugins, PHP 8.5.12 and
every package are unchanged from 5.3.15.5. The 5.3.15.5 image was checked
against this branch before the change: all 140 rootfs files match.

- Image: `repo.cylo.net/rutorrent:5.3.15.6-0.16.24`
- Build: `docker build --pull --no-cache --platform linux/amd64 -f Dockerfile.auth-fail-closed -t repo.cylo.net/rutorrent:5.3.15.6-0.16.24 .`
- Gate: `release/verify-auth-image.sh repo.cylo.net/rutorrent:5.3.15.6-0.16.24`
- Base (pinned by digest): 5.3.15.5 above

`release/verify-auth-image.sh` checks, before pushing:

- registry: release tag definitively absent (MANIFEST_UNKNOWN), before and
  after the tests;
- image: the 5.3.15.5 layers plus two, labels, entrypoint, healthcheck and
  environment unchanged; a full filesystem listing (type, mode, owner, link
  target, SHA-256 of every file) differs from 5.3.15.5 only in the three
  files, each identical to `rootfs/` and 0775 root:root;
- `scripts/test-installed-callback.sh` against the image's helper, and the
  same test against the 5.3.15.5 helper as a control (it must fail only on
  the command-line token);
- ruTorrent's PHP tests (`release/regression/`);
- every container runs with app 66's catalogue environment (test values for
  the templated ones) and dummy `RUTORRENT_USER` / `RUTORRENT_PASSWORD`;
- fresh install, then restart: `release/runtime-checks.py`
  (nginx/php-fpm config tests, multipart through php-fpm, .torrent upload,
  `/no-auth/share.php`, torrent kept across the restart) and
  `release/auth-checks.py login` (no login and a wrong password get 401, the
  right one 200, on `/`, `/index.html`, `/php/getsettings.php`,
  `/php/addtorrent.php`, `/RPC2`, port 8000 and port 9000);
- empty password files (`RUTORRENT_USER` without a password): an error logged per file,
  every protected path refuses every login (`auth-checks.py locked`), the
  same after the files are deleted (`refused`) and after a restart, while
  `/no-auth/share.php` still answers; `/moduser.sh` then restores the login
  without a restart;
- upgrade from 5.3.15.5 on the same `/torrents` and `/passwd` volumes, with
  two torrents and a completed file: `.rtorrent.rc`, the session torrents and
  the completed file unchanged, both torrents still loaded, the same login
  works.

## Catalogue and rollout (not executed)

Migrations are prepared for cylo-api (`<date>_rutorrent_5_3_15_6.sql` adds
5.3.15.6 enabled, admin-only and not default, every resource column copied
from 5.3.15.5, app_versions 1440; `..._publish.sql` then makes it the
default and moves apps 66 to 5.3.15.6 / 5.3.15.6-0.16.24). Existing
instances keep 5.3.15.5 until updated. Update with both versions given, e.g.
`cyloapi apps update 66 --from-version 5.3.15.5 --to-version 5.3.15.6`
(a bare `apps update 66` would also move the 3.x instances).
