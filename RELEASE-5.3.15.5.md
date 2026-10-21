# 5.3.15.5

PHP security release for the PHP 8.5.12 fixes of 21 October 2026
(CVE-2026-109618 / GHSA-w8hw-w9fx-j79w and CVE-2026-109619 /
GHSA-6wmf-4rv5-p3rp, multipart/form-data parsing). ruTorrent's nginx passes
`/no-auth/*.php` to php-fpm without a login (`/no-auth/share.php`), so the
parser is reachable before authentication.

The image is the published 5.3.15.4 image
(`repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`,
built from `f06eb117225f40e69c4d8f23c08cf9a3df22494f`) with only its 16 php85
packages upgraded from 8.5.11-r0 to 8.5.12-r0 (`Dockerfile.php-security`).
rTorrent, libtorrent, ruTorrent, the plugins, rootfs, configuration and all
other Alpine packages are unchanged from 5.3.15.4.

Alpine's v3.24 index still had php85 8.5.11-r0, so the 8.5.12-r0 packages are
our own build of Alpine's community/php85 APKBUILD (aports `0161a10b0614`,
3.24-stable `f169399075e2` plus Alpine MR !110201's test exclusion), signed
with our key `cylo-php85-20261021161817` and published as
`repo.cylo.net/php-artifacts:php85-8.5.12-r0-alpine3.24` =
`sha256:c810e2dbf5e5ff8225acc76d816fc76a00495430e9344ccf14acc632d2ad371d`
(provenance, test results and per-package SHA-256 in
`release/php85-artifact/README.php85-8.5.12-r0-alpine3.24.md`). The build
installs from that repository only, with no network and its own key
directory, so nothing else can change and the key is not added to
`/etc/apk/keys`.

- Image: `repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Build: `docker build --pull --no-cache --platform linux/amd64 -f Dockerfile.php-security -t repo.cylo.net/rutorrent:5.3.15.5-0.16.24 .`
- Gate: `release/verify-image.sh repo.cylo.net/rutorrent:5.3.15.5-0.16.24`
- Bases (pinned by digest): `repo.cylo.net/rutorrent@sha256:d0d5e6f7577aef143f171f4d05995c045122380311396694b430ec758947d5ee`,
  `repo.cylo.net/php-artifacts@sha256:c810e2dbf5e5ff8225acc76d816fc76a00495430e9344ccf14acc632d2ad371d`

Recorded after the push:

- Digest: `sha256:0f967374ba2396278b15a6c00e8330156d7daf6a14475071f88d5d88b3e9783b`
  (OCI index; linux/amd64 manifest `sha256:99bedc30bbf5301139c02179836a21c58460fc9ab12d561a069f911ca82d215f`)
- Platform: `linux/amd64`
- Exact image build commit: `76dd2086fa65539eef720f3698b2cde99aaab77d`
- Build archive SHA-256: `0e870a3e09f8108a1d6b5fbcae952a29a9761371fc84993734f846a24fd24ab1`
- Builder: `builder.grant.appboxes.co` (builder1 was unreachable at build time)
- php85 packages: php85, -bcmath, -common, -ctype, -curl, -dom, -fileinfo,
  -fpm, -mbstring, -openssl, -posix, -session, -simplexml, -sockets, -xml,
  -zip, all `8.5.12-r0` (were `8.5.11-r0`); `php85 -v`: `PHP 8.5.12 (cli)
  (built: Oct 21 2026 16:18:11) (NTS)`

`release/verify-image.sh` passed in release mode before the push: registry tag
definitively absent (MANIFEST_UNKNOWN) before and after the tests; the 5.3.15.4
layers (27) plus one, with entrypoint, healthcheck and environment unchanged;
only the 16 php85 packages changed, each from 8.5.11-r0 to 8.5.12-r0, and all
16 match the artifact APKINDEX checksums; php85 and php-fpm85 8.5.12;
`php85 -m` and `php-fpm85 -m` identical to 5.3.15.4; /etc/php85, /etc/nginx
and /tpls unchanged and no .apk-new files; multipart upload through the php85
CLI server; ruTorrent's PHP tests (11 files, 1,992 assertions); fresh install
(healthy after 423s on the loaded builder) and upgrade from 5.3.15.4 on the
same volumes (healthy after 426s, earlier torrent retained), each with
`nginx -t`, `php-fpm85 -t` as uid 1000, a multipart POST through nginx +
php-fpm (`8.5.12|fpm-fcgi|1|5|0|b`, and 401 without login), a .torrent upload
through `/php/addtorrent.php`, and `/no-auth/share.php` answering from php-fpm
without login.

## Catalogue and rollout (not executed)

cylo-api branch `php-fix-rutorrent-5x`:
`migrations/20261021_rutorrent_5_3_15_5.sql` adds 5.3.15.5 as enabled,
admin-only and not default, copying every resource column and the install
text from 5.3.15.4 (app_versions 1425), and
`migrations/20261021_rutorrent_5_3_15_5_publish.sql` then sets
admin_only=0, moves the default from 1425 and sets apps 66 version/tag to
5.3.15.5 / 5.3.15.5-0.16.24. Both were run twice in a disposable
postgres:16-alpine built from the production column definitions.

farm.cylo.net runs cylo-api `4b6410da` ("Skip ineligible instances in apps
update instead of aborting"), so a stopped instance no longer aborts
`apps update`; per-server splitting is not needed. Always pass both
`--from-version` and `--to-version` (a bare `apps update 66` would also move
the 3.x instances). Run as root on farm; the root shell is fish, so run loops
in `bash`.

1. Apply `20261021_rutorrent_5_3_15_5.sql`; read back the row (changes,
   resources against 1425, enabled=1, admin_only=1, is_default=0).
2. Grant Cylo (11350, cylo13): fresh install of 5.3.15.5; install
   5.2.10-0.15.7 and 5.3.1-0.16.10 and switch both to 5.3.15.5. Check health,
   one install callback, UI login, .torrent upload, XML-RPC and php85 8.5.12.
3. Apply `20261021_rutorrent_5_3_15_5_publish.sql`.
4. Canaries on cylo19 (server 584), one per baseline, then check SQL
   (version 5.3.15.5, state 1, updating 0) and the containers:
   `cyloapi apps update_single` 264142 (5.3.15.4), 160006 (5.3.15.3),
   7936 (5.3.15.2), 181162 (5.3.15.1), 24726 (5.3.14-0.16.23-1),
   16323 (5.3.14-0.16.22-3), 262553 (5.3.12-0.16.10-1),
   102886 (5.3.1-0.16.10), 187702 (5.2.10-0.15.7).
5. Waves, one command per from-version
   (`cyloapi apps update 66 --from-version <v> --to-version 5.3.15.5`),
   checking progress between waves. Counts (not deleting) on 2026-10-21:
   - 5.3.15.x, Alpine 3.24 / php85 8.5.11: 5.3.15.4 (14), 5.3.15.3 (37),
     5.3.15.2 (64), 5.3.15.1 (23)
   - 5.3.14, Alpine 3.24 / php85 8.5.10: 5.3.14-0.16.23-1 (21),
     5.3.14-0.16.23 (8), 5.3.14-0.16.22-3 (8), 5.3.14-0.16.22-2 (1),
     5.3.14-0.16.22-1 (4), 5.3.14-0.16.22 (2)
   - Alpine 3.22 / php84 8.4.16 (largest jump): 5.3.12-0.16.10-1 (12),
     5.3.12-0.16.10 (13), 5.3.1-0.16.10 (36), 5.2.10-0.15.7 (58)
6. Legacy rutorrent4:latest (4.3.6-beta, Alpine 3.19 EOL, php82 8.2.20, no
   app_versions rows), after the 5.2.10 wave and one at a time with
   `cyloapi apps update_single` (target is the default, 5.3.15.5):
   18106 (4.3.6-beta-3, server 571), 141952 (4.3.6-beta-1, server 579),
   153011 (4.3.6-beta, server 583), 189639 (4.3.6-beta, server 580).
   This is a 4.x to 5.x UI change for those customers.
7. Left on old images (skipped by the CLI): stopped on enabled Cylos 51895,
   261220 (5.3.1-0.16.10), 263434, 263944, 264016 (5.3.15.2), 264316
   (5.3.15.3); on disabled Cylos 169148, 262183, 262716, 262770, 262775,
   257586, 261025. Update each with `update_single` when it is started.

Progress: `SELECT version, count(*) FROM appinstance WHERE app_id = 66 AND
deleting IS DISTINCT FROM 1 AND version NOT LIKE '3.%' GROUP BY version` and
`SELECT id, version, server_id, state, updating FROM appinstance WHERE
app_id = 66 AND (updating = 1 OR (version = '5.3.15.5' AND state <> 1))`.
